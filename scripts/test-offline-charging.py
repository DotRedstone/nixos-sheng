#!/usr/bin/env python3

import importlib.util
import subprocess
import sys
import tempfile
import types
from pathlib import Path


def assert_true(condition, message):
    if not condition:
        raise AssertionError(message)


source = Path(sys.argv[1] if len(sys.argv) > 1 else "nixos/scripts/sheng-offline-charging.py")
painter = Path(sys.argv[2]) if len(sys.argv) > 2 else None
spec = importlib.util.spec_from_file_location("sheng_offline_charging", source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

assert_true(
    module.detect_charger_boot("androidboot.mode=charger", "")
    == "androidboot.mode=charger",
    "cmdline charger mode was not detected",
)
assert_true(
    module.detect_charger_boot("", 'androidboot.mode = "charger"')
    == "androidboot.mode=charger",
    "bootconfig charger mode was not detected",
)
assert_true(
    module.detect_charger_boot(
        "androidboot.mode=charger androidboot.force_normal_boot=1", ""
    )
    == "",
    "force-normal boot did not override charger mode",
)
assert_true(
    module.detect_charger_boot("bootinfo.pureason=0x800011", "")
    == "bootinfo.pureason=0x800011",
    "sheng USB charger PON reason was not detected",
)
assert_true(
    module.detect_charger_boot("bootinfo.pureason=0x800091", "") == "",
    "power-key boot while connected was misdetected as charger mode",
)
assert_true(
    module.detect_charger_boot(
        "androidboot.mode=charger bootinfo.pureason=0x800091", ""
    )
    == "",
    "power-key PON reason did not override a stale charger mode",
)
assert_true(
    module.detect_charger_boot("bootinfo.pureason=broken", "") == "",
    "malformed PON reason was accepted",
)
assert_true(
    not module.normal_boot_allowed(None),
    "normal boot was allowed without a battery reading",
)
assert_true(
    not module.normal_boot_allowed(module.MINIMUM_BOOT_CAPACITY - 1),
    "normal boot was allowed below the safe charge threshold",
)
assert_true(
    module.normal_boot_allowed(module.MINIMUM_BOOT_CAPACITY),
    "normal boot was rejected at the safe charge threshold",
)

with tempfile.TemporaryDirectory() as directory:
    marker = Path(directory) / "force-normal-once"
    assert_true(
        module.request_normal_reboot(str(marker)),
        "normal reboot marker could not be written",
    )
    assert_true(
        marker.read_text(encoding="ascii") == "normal-reboot\n",
        "normal reboot marker content is invalid",
    )

events = []
original_capacity = module.battery_capacity
original_request = module.request_normal_reboot
original_run = module.subprocess.run
module.battery_capacity = lambda: module.MINIMUM_BOOT_CAPACITY
module.request_normal_reboot = lambda: events.append("marker") or True
module.subprocess.run = lambda command, **kwargs: (
    events.append(command) or types.SimpleNamespace(returncode=0)
)
display = types.SimpleNamespace(unblank=lambda: events.append("unblank"), blank=lambda: events.append("blank"))
try:
    assert_true(module.start_normal_boot(display), "normal reboot request failed")
    assert_true(
        events == [
            "marker",
            "unblank",
            [module.SYSTEMCTL, "--no-block", "reboot", "--force"],
        ],
        "charger power hold bypassed the stage-1 normal reboot path",
    )
finally:
    module.battery_capacity = original_capacity
    module.request_normal_reboot = original_request
    module.subprocess.run = original_run

with tempfile.TemporaryDirectory() as directory:
    cmdline = Path(directory) / "cmdline"
    bootconfig = Path(directory) / "bootconfig"
    cmdline.write_text("bootinfo.pureason=0x10\n", encoding="ascii")
    bootconfig.write_text("", encoding="ascii")
    assert_true(
        module.detect_from_files(str(cmdline), str(bootconfig)),
        "file-based detector rejected USB charger mode",
    )


def decode_commands(data):
    assert_true(data[:4] == b"SFB1", "framebuffer command magic is invalid")
    payload = data[4:]
    assert_true(
        len(payload) % module.RECTANGLE.size == 0,
        "framebuffer command payload is misaligned",
    )
    return [
        module.RECTANGLE.unpack_from(payload, offset)
        for offset in range(0, len(payload), module.RECTANGLE.size)
    ]


def charged_area(operations):
    colors = {module.ACCENT, module.FULL, module.LOW, module.CRITICAL}
    return sum(
        width * height
        for _, _, width, height, red, green, blue, _ in operations
        if (red, green, blue) in colors
    )


for width, height in ((3048, 2032), (2032, 3048), (1280, 720), (480, 800)):
    low = decode_commands(module.build_framebuffer_commands(width, height, 20))
    high = decode_commands(module.build_framebuffer_commands(width, height, 80))
    unknown = decode_commands(module.build_framebuffer_commands(width, height, None))
    extremes = [decode_commands(module.build_framebuffer_commands(width, height, capacity))
                for capacity in (0, 1, 5, 100)]
    for operations in (low, high, unknown, *extremes):
        assert_true(0 < len(operations) < 10000, "invalid rectangle count")
        for x, y, rect_width, rect_height, _, _, _, _ in operations:
            assert_true(x + rect_width <= width, "rectangle exceeds framebuffer width")
            assert_true(y + rect_height <= height, "rectangle exceeds framebuffer height")
    assert_true(
        charged_area(high) > charged_area(low),
        "battery fill does not increase with capacity",
    )
    assert_true(charged_area(extremes[0]) == 0, "empty battery has a colored fill")
    assert_true(charged_area(extremes[1]) > 0, "one-percent battery fill disappeared")
    for capacity in (0, 100, None):
        assert_true(not module.build_animation_commands(width, height, capacity, 0),
                    "empty, full or unknown battery should be static")
    frame0 = module.build_animation_commands(width, height, 67, 0)
    assert_true(frame0 != module.build_animation_commands(width, height, 67, 12),
                "charging animation is static")
    assert_true(frame0 == module.build_animation_commands(width, height, 67, module.ANIMATION_FRAMES),
                "charging loop has a seam")
    for frame in range(module.ANIMATION_FRAMES):
        ops = decode_commands(module.build_animation_commands(width, height, 67, frame))
        assert_true(0 < len(ops) < 10000, "animation exceeds rectangle budget")
        assert_true(all(0 < x < x + w <= width and 0 < y < y + h <= height
                        for x, y, w, h, *_ in ops), "animation clears the screen or escapes it")

with tempfile.TemporaryDirectory() as directory:
    events = []
    original_command_path = module.FRAMEBUFFER_COMMAND_PATH
    original_geometry = module.framebuffer_geometry
    original_exists = module.os.path.exists
    original_run = module.subprocess.run
    module.FRAMEBUFFER_COMMAND_PATH = str(Path(directory) / "display-order.fbops")
    module.framebuffer_geometry = lambda: (1280, 720)
    module.os.path.exists = lambda path: path == "/dev/fb0" or original_exists(path)
    module.subprocess.run = lambda *args, **kwargs: (
        events.append("paint") or types.SimpleNamespace(returncode=0)
    )
    display = module.Display()

    def fake_blank():
        events.append("blank")
        display.visible = False

    def fake_unblank():
        events.append("unblank")
        display.visible = True

    display.blank = fake_blank
    display.unblank = fake_unblank
    try:
        assert_true(display.render(100), "initial charging frame failed")
        assert_true(
            events == ["blank", "paint", "unblank"],
            "panel was unblanked before the first frame was painted",
        )
        events.clear()
        assert_true(display.render(100), "visible charging frame refresh failed")
        assert_true(
            events == ["paint"],
            "visible frame refresh unnecessarily blanked the panel",
        )
        events.clear()
        assert_true(display.animate(67, True, 10.0), "visible battery did not animate")
        assert_true(not display.animate(67, True, 10.01), "animation ignored its rate limit")
        assert_true(events == ["paint"], "animation toggled the backlight")
        events.clear()
        assert_true(display.animate(67, False, 10.2), "unplug did not restore the static frame")
        assert_true(not display.animation_active, "animation remained active without power")
        assert_true(events == ["paint"], "unplug unexpectedly blanked the display")
        display.animate(67, True, 11.0)
        events.clear()
        assert_true(display.animate(100, True, 11.2), "full battery did not restore its static frame")
        assert_true(not display.animate(100, True, 11.4), "full battery kept animating")
        assert_true(events == ["paint"], "full battery triggered more than one static repaint")
        display.blank()
        events.clear()
        assert_true(not display.animate(67, True, 12.0), "animation woke the sleeping display")
        assert_true(not events, "animation wrote pixels while the panel was asleep")
    finally:
        module.FRAMEBUFFER_COMMAND_PATH = original_command_path
        module.framebuffer_geometry = original_geometry
        module.os.path.exists = original_exists
        module.subprocess.run = original_run

if painter is not None:
    with tempfile.TemporaryDirectory() as directory:
        width, height = 3048, 2032
        commands = Path(directory) / "offline-charging.fbops"
        framebuffer = Path(directory) / "offline-charging.raw"
        commands.write_bytes(module.build_framebuffer_commands(width, height, 67))
        framebuffer.write_bytes(bytes(width * height * 4))
        subprocess.run(
            [
                str(painter),
                "--file",
                str(framebuffer),
                str(width),
                str(height),
                str(width * 4),
                "32",
                str(commands),
            ],
            check=True,
            timeout=4,
        )
        assert_true(
            any(framebuffer.read_bytes()),
            "native framebuffer painter produced a blank charging UI",
        )
        base = framebuffer.read_bytes()
        first = None
        for frame in (0, 8, 16, 31, 0):
            commands.write_bytes(module.build_animation_commands(width, height, 67, frame))
            subprocess.run([str(painter), "--file", str(framebuffer), str(width), str(height),
                            str(width * 4), "32", str(commands)], check=True, timeout=4)
            data = framebuffer.read_bytes()
            # Only the battery interior moves; text and the surrounding black
            # canvas must survive each partial native paint without flicker.
            size = round(360 * min(width / 440, height / 440, 3))
            bottom = (height - size) // 2 + round(145 * size / 360)
            assert_true(data[bottom * width * 4:] == base[bottom * width * 4:],
                        "charging animation changed the percentage or lower background")
            assert_true(data != base, "native charging animation did not change any pixels")
            if frame == 0:
                if first is not None:
                    assert_true(data == first, "partial animation retained stale pixels after a loop")
                first = data

print("offline charging detector and renderer tests passed")
