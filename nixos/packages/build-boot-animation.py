"""Bake the monochrome Sheng boot loop into rectangle-only SFB1 frames."""

import math
from pathlib import Path
import struct
import sys

from PIL import Image, ImageDraw, ImageFont

font_path, output = sys.argv[1:]
output = Path(output)
output.mkdir(parents=True, exist_ok=True)
size, supersample, frames = 720, 2, 60
record = struct.Struct('<HHHHBBBB')
black = (0, 0, 0)
white = (238, 238, 238)
colors = [(round(255 * level / 31),) * 3 for level in range(32)]
palette = Image.new('P', (1, 1))
palette.putpalette([c for color in colors for c in color] + [0] * (768 - 3 * len(colors)))
title_font = ImageFont.truetype(font_path, 34 * supersample)

# Nix snowflake by Simon Frankau and Tim Cuthbertson, CC BY 4.0.
# Geometry adapted from NixOS/nixos-artwork/logo/nix-snowflake-colours.svg:
# preserve the six interlocking lambda silhouettes; animate only light/spacing.
arm_steps = (
    (122.19683, 211.67512), (-56.15706, .5268), (-32.6236, -56.8692),
    (-32.85645, 56.5653), (-27.90237, -.011), (-14.29086, -24.6896),
    (46.81047, -80.4901), (-33.22946, -57.8257),
)
arm = [(309.54892 - 407.3, -710.38827 + 715.8)]
for dx, dy in arm_steps:
    x, y = arm[-1]
    arm.append((x + dx, y + dy))


def encode(canvas):
    canvas = canvas.resize((size, size), Image.Resampling.LANCZOS)
    canvas = canvas.quantize(palette=palette, dither=Image.Dither.NONE).convert('RGB')
    pixels = canvas.load()
    rectangles = [(0, 0, size, size, *black, 0)]
    active = {}
    for y in range(size):
        current = {}
        x = 0
        while x < size:
            color = pixels[x, y]
            end = x + 1
            while end < size and pixels[end, y] == color:
                end += 1
            if color != black:
                key = (x, end - x, color)
                first, rows = active.pop(key, (y, 0))
                current[key] = (first, rows + 1)
            x = end
        for (x, width, color), (y0, height) in active.items():
            rectangles.append((x, y0, width, height, *color, 0))
        active = current
    for (x, width, color), (y0, height) in active.items():
        rectangles.append((x, y0, width, height, *color, 0))
    if len(rectangles) > 10000:
        raise ValueError(f'Boot frame exceeds painter budget: {len(rectangles)}')
    return b'SFB1' + b''.join(record.pack(*rectangle) for rectangle in rectangles)


for phase in ('prepare', 'start'):
    for frame in range(frames):
        canvas = Image.new('RGB', (size * supersample, size * supersample), black)
        draw = ImageDraw.Draw(canvas)

        # The mark stays upright. Light travels through its six arms, with a
        # tiny shared expansion: no spinning badge or fictional progress bar.
        time = 2 * math.pi * frame / frames
        breath = (1 - math.cos(time)) / 2
        scale = .43 * (1 + .018 * breath)
        for index in range(6):
            angle = math.radians(index * 60)
            cosine, sine = math.cos(angle), math.sin(angle)
            light = ((1 + math.cos(time - angle)) / 2) ** 3
            level = round(166 + 80 * light + 8 * breath)
            points = [((360 + scale * (x * cosine - y * sine)) * supersample,
                       (300 + scale * (x * sine + y * cosine)) * supersample)
                      for x, y in arm]
            draw.polygon(points, fill=(level,) * 3)

        draw.text((360 * supersample, 486 * supersample), 'NixOS',
                  font=title_font, fill=white, anchor='ms')
        (output / f'{phase}-{frame:02d}.sfb').write_bytes(encode(canvas))
print(f'{frames * 2} boot frames, {sum(p.stat().st_size for p in output.glob("*.sfb"))} bytes')
