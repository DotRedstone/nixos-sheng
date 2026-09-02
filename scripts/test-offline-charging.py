#!/usr/bin/env python3

import importlib.util
import subprocess
import sys
import tempfile
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


for width, height in ((3048, 2032), (2032, 3048), (1280, 720)):
    low = decode_commands(module.build_framebuffer_commands(width, height, 20))
    high = decode_commands(module.build_framebuffer_commands(width, height, 80))
    unknown = decode_commands(module.build_framebuffer_commands(width, height, None))
    for operations in (low, high, unknown):
        assert_true(0 < len(operations) < 10000, "invalid rectangle count")
        for x, y, rect_width, rect_height, _, _, _, _ in operations:
            assert_true(x + rect_width <= width, "rectangle exceeds framebuffer width")
            assert_true(y + rect_height <= height, "rectangle exceeds framebuffer height")
    assert_true(
        charged_area(high) > charged_area(low),
        "battery fill does not increase with capacity",
    )

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

print("offline charging detector and renderer tests passed")
