#!/usr/bin/env python3
"""Check native menu pixels and optionally export previews from the test commands."""

import argparse
from pathlib import Path
import subprocess
import tempfile

from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("commands", type=Path, help="Base path emitted by the mruby renderer test")
parser.add_argument("painter", type=Path)
parser.add_argument("--output", type=Path, help="Optional preview directory")
args = parser.parse_args()
if args.output:
    args.output.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix="sheng-menu-") as temporary:
    for width, height in ((3048, 2032), (2032, 3048), (1280, 720)):
        for bpp in (16, 24, 32):
            stride = width * (bpp // 8) + 96
            actual = Path(temporary) / "actual.raw"
            expected = Path(temporary) / "expected.raw"
            for path in (actual, expected):
                with path.open("wb") as file:
                    file.truncate(height * stride)

            def paint(path, suffix):
                command = Path(f"{args.commands}.{width}.{suffix}")
                subprocess.run([str(args.painter), "--file", str(path), str(width),
                                str(height), str(stride), str(bpp), str(command)],
                               check=True, timeout=4)

            def preview(suffix):
                if args.output and bpp == 32:
                    image = Image.frombytes("RGB", (width, height), actual.read_bytes(),
                                            "raw", "BGRX", stride)
                    image.save(args.output / f"menu-{width}-{suffix}.png")

            paint(actual, "initial")
            preview("initial")
            for step in range(6):
                paint(actual, f"{step}.partial")
                paint(expected, f"{step}.full")
                assert actual.read_bytes() == expected.read_bytes(), (width, bpp, step)
                if step == 0:
                    preview("selection")
                if step == 2:
                    preview("next-page")
            for state in ("empty", "booting"):
                paint(actual, state)
                preview(state)
            print(f"{width}x{height}, {bpp}bpp: full/partial pixels identical; all states rendered")
