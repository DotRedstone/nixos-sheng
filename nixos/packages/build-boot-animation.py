"""Bake the rounded Sheng boot loop into rectangle-only SFB1 frames."""

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
mint = (130, 214, 184)
white = (229, 236, 233)
muted = (137, 150, 147)
track = (24, 31, 30)
outline = (72, 86, 81)
colors = [black]
for color in (mint, white, muted, track, outline):
    colors.extend(tuple(round(c * level / 8) for c in color) for level in range(1, 9))
palette = Image.new('P', (1, 1))
palette.putpalette([c for color in colors for c in color] + [0] * (768 - 3 * len(colors)))
title_font = ImageFont.truetype(font_path, 42 * supersample)
label_font = ImageFont.truetype(font_path, 21 * supersample)


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


for phase, label in [('prepare', 'Preparing device'), ('start', 'Starting system')]:
    for frame in range(frames):
        canvas = Image.new('RGB', (size * supersample, size * supersample), black)
        draw = ImageDraw.Draw(canvas)

        def rounded(bounds, radius, color):
            draw.rounded_rectangle(tuple(round(v * supersample) for v in bounds),
                                   radius=round(radius * supersample), fill=color)

        # The same restrained shell and soft mint fill as the charging battery.
        # The travelling breath is indeterminate: it never claims boot progress.
        rounded((246, 210, 474, 362), 40, outline)
        rounded((249, 213, 471, 359), 37, black)
        for index in range(4):
            x = 280 + index * 42
            rounded((x, 242, x + 34, 330), 17, track)
            wave = (1 + math.sin(2 * math.pi * frame / frames - index * 0.65)) / 2
            height = 34 + 54 * wave
            rounded((x, 286 - height / 2, x + 34, 286 + height / 2), 17, mint)
        draw.text((360 * supersample, 433 * supersample), 'NixOS Sheng',
                  font=title_font, fill=white, anchor='ms')
        draw.text((360 * supersample, 486 * supersample), label,
                  font=label_font, fill=muted, anchor='ms')
        (output / f'{phase}-{frame:02d}.sfb').write_bytes(encode(canvas))
print(f'{frames * 2} boot frames, {sum(p.stat().st_size for p in output.glob("*.sfb"))} bytes')
