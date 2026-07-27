# ---
# Module: Sheng Offline Charging
# Description: Low-power userspace target for bootloader charger mode
# Scope: System
# ---

{ lib, pkgs, ... }:

let
  offlineChargingGenerator = pkgs.writeShellScript "sheng-offline-charging-generator" ''
    set -eu

    output_dir="$1"
    charger_mode=false
    if ${pkgs.gnugrep}/bin/grep -qw 'androidboot.mode=charger' /proc/cmdline; then
      charger_mode=true
    elif [ -r /proc/bootconfig ] && \
      ${pkgs.gnugrep}/bin/grep -Eq \
        '^[[:space:]]*androidboot\.mode[[:space:]]*=[[:space:]]*"?charger"?[[:space:]]*$' \
        /proc/bootconfig; then
      charger_mode=true
    fi

    if [ "$charger_mode" != true ]; then
      exit 0
    fi

    ${pkgs.coreutils}/bin/mkdir -p "$output_dir"
    ${pkgs.coreutils}/bin/ln -sfn \
      /etc/systemd/system/sheng-offline-charging.target \
      "$output_dir/default.target"
  '';

  offlineChargingMonitor = pkgs.writeScript "sheng-offline-charging-monitor" ''
    #!${pkgs.python3}/bin/python3
    import glob
    import os
    import select
    import struct
    import subprocess
    import time

    EVENT = struct.Struct("llHHI")
    EV_KEY = 1
    KEY_POWER = 116
    HOLD_SECONDS = 1.5
    PREFERRED_POWER_KEY_PATH = (
        "/dev/input/by-path/"
        "platform-c400000.spmi-platform-c400000.spmi:pmic@0:pon@1300:pwrkey-event"
    )

    saved_backlights = {}

    def read_text(path):
        try:
            with open(path, "r", encoding="ascii") as handle:
                return handle.read().strip()
        except OSError:
            return ""

    def write_text(path, value):
        try:
            with open(path, "w", encoding="ascii") as handle:
                handle.write(value)
        except OSError:
            pass

    def battery_capacity():
        for path in glob.glob("/sys/class/power_supply/*"):
            if read_text(os.path.join(path, "type")) != "Battery":
                continue
            value = read_text(os.path.join(path, "capacity"))
            if value.isdigit():
                return int(value)
        return None

    def external_power_online():
        battery_is_charging = False
        for path in glob.glob("/sys/class/power_supply/*"):
            if read_text(os.path.join(path, "type")) == "Battery":
                if read_text(os.path.join(path, "status")) in ("Charging", "Full"):
                    battery_is_charging = True
                continue
            if read_text(os.path.join(path, "online")) == "1":
                return True
        return battery_is_charging

    def blank_display():
        for path in glob.glob("/sys/class/backlight/*/brightness"):
            if path not in saved_backlights:
                saved_backlights[path] = read_text(path)
            write_text(path, "0\n")
        for path in glob.glob("/sys/class/graphics/fb*/blank"):
            write_text(path, "1\n")

    def restore_display():
        for path, value in saved_backlights.items():
            if value:
                write_text(path, value + "\n")
        for path in glob.glob("/sys/class/graphics/fb*/blank"):
            write_text(path, "0\n")

    def open_power_key():
        candidates = [PREFERRED_POWER_KEY_PATH]
        candidates.extend(glob.glob("/dev/input/by-path/*pwrkey-event"))
        for path in dict.fromkeys(candidates):
            try:
                return os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            except OSError:
                pass
        return None

    def start_normal_boot():
        print("Offline charging: power key held; starting the normal system.", flush=True)
        restore_display()
        result = subprocess.run(
            ["${pkgs.systemd}/bin/systemctl", "--no-block", "isolate", "graphical.target"],
            check=False,
        )
        if result.returncode != 0:
            print("Offline charging: failed to start the normal system.", flush=True)
            blank_display()
            return False
        return True

    print("Offline charging mode is active. Hold the power key to boot normally.", flush=True)
    blank_display()
    power_key = None
    pressed_at = None
    offline_since = None
    last_report = 0.0

    while True:
        if power_key is None:
            power_key = open_power_key()

        now = time.monotonic()
        if now - last_report >= 30:
            print(
                f"Offline charging: capacity={battery_capacity()}% "
                f"external_power={external_power_online()}",
                flush=True,
            )
            last_report = now

        if external_power_online():
            offline_since = None
        elif offline_since is None:
            offline_since = now
        elif now - offline_since >= 10:
            print("Offline charging: charger disconnected; powering off.", flush=True)
            subprocess.run(
                ["${pkgs.systemd}/bin/systemctl", "poweroff"],
                check=False,
            )
            time.sleep(60)

        if power_key is not None:
            readable, _, _ = select.select([power_key], [], [], 0.1)
            if readable:
                try:
                    data = os.read(power_key, EVENT.size * 16)
                except OSError:
                    os.close(power_key)
                    power_key = None
                    data = b""

                for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
                    _, _, event_type, code, value = EVENT.unpack_from(data, offset)
                    if event_type != EV_KEY or code != KEY_POWER:
                        continue
                    if value == 1:
                        pressed_at = time.monotonic()
                    elif value == 0:
                        pressed_at = None
        else:
            time.sleep(0.1)

        if pressed_at is not None and time.monotonic() - pressed_at >= HOLD_SECONDS:
            if start_normal_boot():
                break
            pressed_at = None
  '';
in
{
  systemd.generators.sheng-offline-charging = offlineChargingGenerator;

  systemd.targets.sheng-offline-charging = {
    description = "Sheng Offline Charging";
    requires = [
      "basic.target"
      "systemd-udev-settle.service"
    ];
    wants = [
      "pd-mapper.service"
      "xiaomi-mipps-auth.service"
    ];
    after = [
      "basic.target"
      "systemd-udev-settle.service"
      "pd-mapper.service"
    ];
    unitConfig = {
      AllowIsolate = true;
      Conflicts = "shutdown.target";
    };
  };

  systemd.services.sheng-offline-charging = {
    description = "Monitor sheng offline charging mode";
    wantedBy = [ "sheng-offline-charging.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = offlineChargingMonitor;
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.services.xiaomi-mipps-auth.after = lib.mkAfter [ "pd-mapper.service" ];
}
