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
white = (246, 246, 246)
track = (34, 34, 34)
colors = [(round(255 * level / 31),) * 3 for level in range(32)]
palette = Image.new('P', (1, 1))
palette.putpalette([c for color in colors for c in color] + [0] * (768 - 3 * len(colors)))
title_font = ImageFont.truetype(font_path, 42 * supersample)


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

        # A single white arc turns over a quiet gray track. Rounded caps and a
        # breathing center dot keep the motion soft without implying progress.
        center_x, center_y, radius = 360, 286, 74
        bounds = tuple(round(value * supersample) for value in (
            center_x - radius, center_y - radius,
            center_x + radius, center_y + radius,
        ))
        draw.ellipse(bounds, outline=track, width=5 * supersample)

        end_angle = -90 + 360 * frame / frames
        start_angle = end_angle - 112
        stroke_width = 8
        draw.arc(bounds, start=start_angle, end=end_angle, fill=white,
                 width=stroke_width * supersample)
        cap_radius = stroke_width / 2
        for angle in (start_angle, end_angle):
            radians = math.radians(angle)
            x = center_x + radius * math.cos(radians)
            y = center_y + radius * math.sin(radians)
            draw.ellipse(tuple(round(value * supersample) for value in (
                x - cap_radius, y - cap_radius, x + cap_radius, y + cap_radius,
            )), fill=white)

        breath = (1 - math.cos(2 * math.pi * frame / frames)) / 2
        core_radius = 8 + 3 * breath
        draw.ellipse(tuple(round(value * supersample) for value in (
            center_x - core_radius, center_y - core_radius,
            center_x + core_radius, center_y + core_radius,
        )), fill=white)
        draw.text((360 * supersample, 432 * supersample), 'NixOS',
                  font=title_font, fill=white, anchor='ms')
        (output / f'{phase}-{frame:02d}.sfb').write_bytes(encode(canvas))
print(f'{frames * 2} boot frames, {sum(p.stat().st_size for p in output.glob("*.sfb"))} bytes')
