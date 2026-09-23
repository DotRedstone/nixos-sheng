"""Bake blue Nix snowflake loops at two resolutions into SFB1 frames."""

import math
from pathlib import Path
import struct
import sys

from PIL import Image, ImageDraw, ImageFont

font_path, output = sys.argv[1:]
output = Path(output)
output.mkdir(parents=True, exist_ok=True)
size, supersample, frames = 720, 8, 60
record = struct.Struct('<HHHHBBBB')
black = (0, 0, 0)
white = (238, 238, 238)
title_font = ImageFont.truetype(font_path, 34 * supersample)
credit_font = ImageFont.truetype(font_path, 13 * supersample)
deep_blue, light_blue = (82, 119, 195), (126, 186, 228)


def make_palette(tints):
    colors = [(round(255 * level / 63),) * 3 for level in range(64)]
    for tint in tints:
        colors.extend(tuple(round(c * level / 31) for c in tint) for level in range(32))
    palette = Image.new('P', (1, 1))
    palette.putpalette([c for color in colors for c in color] + [0] * (768 - 3 * len(colors)))
    return palette

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


def encode(canvas, extent, palette, clear=True):
    canvas = canvas.resize((extent, extent), Image.Resampling.LANCZOS)
    canvas = canvas.quantize(palette=palette, dither=Image.Dither.NONE).convert('RGB')
    pixels = canvas.load()
    rectangles = [(0, 0, extent, extent, *black, 0)] if clear else []
    left, top, right, bottom = canvas.getbbox()
    active = {}
    for y in range(top, bottom):
        current = {}
        x = left
        while x < right:
            color = pixels[x, y]
            end = x + 1
            while end < right and pixels[end, y] == color:
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


for frame in range(frames):
    canvas = Image.new('RGB', (size * supersample, size * supersample), black)
    draw = ImageDraw.Draw(canvas)

    # Alternate the official blues; restrained moving light keeps the upright
    # mark legible. Both resolutions are downsampled from the same 5760px art.
    time = 2 * math.pi * frame / frames
    breath = (1 - math.cos(time)) / 2
    scale = .43 * (1 + .018 * breath)
    tints = []
    for index in range(6):
        angle = math.radians(index * 60)
        cosine, sine = math.cos(angle), math.sin(angle)
        light = ((1 + math.cos(time - angle)) / 2) ** 3
        tint = tuple(round(c * (.84 + .16 * light))
                     for c in (light_blue if index % 2 else deep_blue))
        tints.append(tint)
        points = [((360 + scale * (x * cosine - y * sine)) * supersample,
                   (300 + scale * (x * sine + y * cosine)) * supersample)
                  for x, y in arm]
        draw.polygon(points, fill=tint)

    draw.text((360 * supersample, 486 * supersample), 'NixOS',
              font=title_font, fill=white, anchor='ms')
    palette = make_palette(tints)
    for suffix, extent in (('', 720), ('-hd', 1440)):
        encoded = encode(canvas, extent, palette)
        for phase in ('prepare', 'start'):
            (output / f'{phase}{suffix}-{frame:02d}.sfb').write_bytes(encoded)

# A separate layer lets the renderer anchor the credit to the actual screen
# corner, independently of the centered logo and the display aspect ratio.
credit = Image.new('RGB', (size * supersample, size * supersample), black)
ImageDraw.Draw(credit).text((692 * supersample, 692 * supersample),
                           'by dotredstone', font=credit_font,
                           fill=(104, 104, 104), anchor='rs')
for suffix, extent in (('', 720), ('-hd', 1440)):
    (output / f'credit{suffix}-00.sfb').write_bytes(
        encode(credit, extent, make_palette([]), clear=False))
print(f'{frames * 4} boot frames + 2 credits, '
      f'{sum(p.stat().st_size for p in output.glob("*.sfb"))} bytes')
