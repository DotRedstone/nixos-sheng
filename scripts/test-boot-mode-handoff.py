#!/usr/bin/env python3
"""Run the real Ruby stage-1 decision and shell generator across a /run move."""
from pathlib import Path
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

guard, generator, detector = map(Path, sys.argv[1:4])
menu = Path(sys.argv[4])
spec = importlib.util.spec_from_file_location("charging", detector)
charging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(charging)

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    persistent = root / "var/lib/sheng-offline-charging"
    persistent.mkdir(parents=True)
    marker = persistent / "force-normal-once"
    cmdline = root / "cmdline"
    bootconfig = root / "bootconfig"
    bootconfig.write_text("")

    def generate(run, reason="bootinfo.pureason=0x10"):
        cmdline.write_text(reason)
        script = generator.read_text().replace("/run/", str(run) + "/")
        script = script.replace("/var/lib/sheng-offline-charging/", str(persistent) + "/")
        script = script.replace("@detect@ detect", f"{sys.executable} {detector.resolve()} detect {cmdline} {bootconfig}")
        for name in ("mv", "mkdir", "ln"):
            script = script.replace(f"@{name}@", shutil.which(name))
        output = run / "generator.early"
        # systemd discards generator output and reruns it on daemon-reload.
        if output.exists():
            shutil.rmtree(output)
        output.mkdir()
        subprocess.run(["sh", "-eu", "-c", script, "generator", str(run), str(output)], check=True)
        return (output / "default.target").is_symlink()

    def stage1(run):
        subprocess.run(["ruby", "-e", '''
require "logger"
$logger = Logger.new(File::NULL)
Configuration = {}
module System
  def self.cmdline; ["bootinfo.pureason=0x10"]; end
end
load ARGV[0]
ShengEarlyChargeGuard.define_singleton_method(:normal_reboot_marker_path) { ARGV[1] }
ShengEarlyChargeGuard.define_singleton_method(:boot_mode_path) { ARGV[2] }
mode = ShengEarlyChargeGuard.charger_mode? ? "charger" : "normal"
ShengEarlyChargeGuard.commit_boot_mode(mode)
# A second decision cannot reverse this boot, and an I/O failure must surface.
begin
  ShengEarlyChargeGuard.commit_boot_mode(mode == "normal" ? "charger" : "normal")
  abort "committed boot decision changed"
rescue RuntimeError
end
''', str(guard), str(marker), str(run / "sheng-boot-ui.mode")], check=True)

    for normal in (True, False):
        run = root / "initrd-run"
        run.mkdir()
        if normal:
            marker.write_text("normal-reboot\n")
        stage1(run)
        moved = root / "stage2-run"
        run.rename(moved)
        assert generate(moved) == (not normal)
        marker.unlink(missing_ok=True)  # basic.target cleanup
        assert generate(moved) == (not normal), "daemon-reload reversed stage-1 decision"
        charging.BOOT_MODE_PATH = str(moved / "sheng-boot-ui.mode")
        assert charging.charger_selected() == (not normal)
        shutil.rmtree(moved)

    # Run the real SwitchRoot selection method: a saved manual choice must
    # override USB-only PON even when a legacy reboot omitted the marker.
    for pending in (True, False):
        run = root / "selection-run"
        run.mkdir()
        subprocess.run(["ruby", "-e", '''
require "logger"
$logger = Logger.new(File::NULL)
Configuration = {}
module System
  def self.cmdline; ["bootinfo.pureason=0x10"]; end
end
module Tasks
  class SwitchRoot
    NixOSGeneration = Struct.new(:path)
    def default_selection_path; "default"; end
    def will_kexec?; false; end
  end
  class Splash
    def self.instance; new; end
    def quit(*args); end
  end
end
module ShengBootAnimation
  def self.stop; end
  def self.start(*args); $animation = true; end
end
module ShengHeadlessGenerationMenu
  def self.consume_pending_selection(root); ARGV[4] == "yes" ? :chosen : nil; end
  def self.choose(*args); abort "unexpected menu"; end
end
load ARGV[0]
ShengEarlyChargeGuard.define_singleton_method(:normal_reboot_marker_path) { ARGV[1] }
ShengEarlyChargeGuard.define_singleton_method(:boot_mode_path) { ARGV[2] }
ShengEarlyChargeGuard.define_singleton_method(:wait_if_critical) {}
ShengEarlyChargeGuard.define_singleton_method(:prepare_offline_charging_handoff) { $handoff = true }
source = File.read(ARGV[3])
eval(source[source.rindex("class Tasks::SwitchRoot")..-1], TOPLEVEL_BINDING, ARGV[3])
selection = Tasks::SwitchRoot.new.selected_generation
if ARGV[4] == "yes"
  abort "saved choice entered charging" unless selection == :chosen && $animation && !$handoff
else
  abort "charger played boot animation" unless selection.path == "default" && $handoff && !$animation
end
''', str(guard), str(marker), str(run / "sheng-boot-ui.mode"), str(menu),
                        "yes" if pending else "no"], check=True)
        assert generate(run) == (not pending)
        shutil.rmtree(run)

    # Old initrd / generator fallback: override consumption must not cause a
    # later daemon-reload or system switch to choose charger mode.
    for override in ("marker", "normal", "done", "power-key", "none"):
        run = root / "fallback-run"
        run.mkdir()
        if override == "marker":
            marker.write_text("normal-reboot\n")
        elif override in ("normal", "done"):
            (run / f"sheng-boot-ui.{override}").touch()
        reason = "bootinfo.pureason=0x90" if override == "power-key" else "bootinfo.pureason=0x10"
        expected = override == "none"
        assert generate(run, reason) == expected
        marker.unlink(missing_ok=True)
        assert generate(run) == expected
        shutil.rmtree(run)

    # A diagnostic request winning the lock between the initial check and
    # acquisition must not have its console replaced by the battery monitor.
    charging.BOOT_CONTROL = str(root / "ownership")
    charging.BOOT_MODE_PATH = str(root / "charger.mode")
    Path(charging.BOOT_MODE_PATH).write_text("charger\n")
    original_lockf = charging.fcntl.lockf
    original_open = charging.os.open

    def diagnostic_wins(*args):
        original_lockf(*args)
        Path(charging.BOOT_CONTROL + ".disabled").touch()

    def no_display_open(path, *args):
        assert path != "/dev/tty2", "charging stole the diagnostic console"
        return original_open(path, *args)

    with patch.object(charging.fcntl, "lockf", diagnostic_wins), patch.object(charging.os, "open", no_display_open):
        assert charging.monitor() == 0
    Path(charging.BOOT_CONTROL + ".disabled").unlink()

    # A monitor accidentally started in a normal boot must leave the display alone.
    charging.BOOT_MODE_PATH = str(root / "normal.mode")
    Path(charging.BOOT_MODE_PATH).write_text("normal\n")
    charging.charging_display_owner = lambda: (_ for _ in ()).throw(AssertionError("opened display"))
    assert charging.monitor() == 0

print("stage-1 -> moved /run -> stage-2 -> daemon-reload boot-mode tests passed")
