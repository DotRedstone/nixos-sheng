#!/usr/bin/env python3
"""Render SFB1 charging stills or loops without accessing hardware."""

import argparse
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image, ImageDraw

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
parser.add_argument("--width", type=int, default=3048)
parser.add_argument("--height", type=int, default=2032)
parser.add_argument("--capacity", type=int, default=67)
parser.add_argument("--animate", action="store_true", help="Export one charging loop as GIF or APNG")
parser.add_argument("--painter", type=Path, help="Render with the actual native painter into a file")
args = parser.parse_args()
source = Path(__file__).resolve().parents[1] / "nixos/scripts/sheng-offline-charging.py"
spec = importlib.util.spec_from_file_location("charging", source)
charging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(charging)
started = time.monotonic()
commands = charging.build_framebuffer_commands(args.width, args.height, args.capacity)
elapsed = time.monotonic() - started
args.output.parent.mkdir(parents=True, exist_ok=True)
preview = Image.new("RGB", (args.width, args.height))
with tempfile.TemporaryDirectory(prefix="sheng-charge-preview-") as directory:
    raw = Path(directory) / "frame.raw"
    fbops = Path(directory) / "frame.sfb"
    stride = args.width * 4 + 96
    if args.painter:
        raw.write_bytes(bytes(stride * args.height))

    def paint(data):
        if args.painter:
            fbops.write_bytes(data)
            subprocess.run([str(args.painter), "--file", str(raw), str(args.width),
                            str(args.height), str(stride), "32", str(fbops)], check=True, timeout=5)
            return Image.frombytes("RGB", (args.width, args.height), raw.read_bytes(), "raw", "BGRX", stride)
        draw = ImageDraw.Draw(preview)
        for offset in range(4, len(data), charging.RECTANGLE.size):
            x, y, width, height, r, g, b, _ = charging.RECTANGLE.unpack_from(data, offset)
            draw.rectangle((x, y, x + width - 1, y + height - 1), fill=(r, g, b))
        return preview.copy()

    still = paint(commands)
    if args.animate:
        images = []
        for frame in range(charging.ANIMATION_FRAMES):
            data = charging.build_animation_commands(args.width, args.height, args.capacity, frame)
            image = paint(data) if data else still.copy()
            image.thumbnail((1536, 1536), Image.Resampling.LANCZOS)
            images.append(image)
        images[0].save(args.output, format="GIF" if args.output.suffix == ".gif" else "PNG",
                       save_all=True, append_images=images[1:], duration=1000 // charging.ANIMATION_FPS,
                       loop=0)
    else:
        still.save(args.output)
print(f"{args.output}: {(len(commands) - 4) // charging.RECTANGLE.size} rectangles, {elapsed:.3f}s")
