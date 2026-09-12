#!/usr/bin/env python3
"""Render the actual SFB1 charging frame to PNG without accessing hardware."""

import argparse
import importlib.util
from pathlib import Path
import time

from PIL import Image, ImageDraw

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--width", type=int, default=3048)
parser.add_argument("--height", type=int, default=2032)
parser.add_argument("--capacity", type=int, default=67)
args = parser.parse_args()
source = Path(__file__).resolve().parents[1] / "nixos/scripts/sheng-offline-charging.py"
spec = importlib.util.spec_from_file_location("charging", source)
charging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(charging)
started = time.monotonic()
commands = charging.build_framebuffer_commands(args.width, args.height, args.capacity)
elapsed = time.monotonic() - started
preview = Image.new("RGB", (args.width, args.height))
draw = ImageDraw.Draw(preview)
for offset in range(4, len(commands), charging.RECTANGLE.size):
    x, y, width, height, r, g, b, _ = charging.RECTANGLE.unpack_from(commands, offset)
    draw.rectangle((x, y, x + width - 1, y + height - 1), fill=(r, g, b))
preview.save(args.output)
print(f"{args.output}: {(len(commands) - 4) // charging.RECTANGLE.size} rectangles, {elapsed:.3f}s")
