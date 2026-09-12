"""Bake Inter coverage masks and matching mruby metrics into the native painter."""

import sys
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

font_path, header_path, metrics_path = sys.argv[1:]
names = TTFont(font_path, fontNumber=0)["name"]
license_text = "\n".join(filter(None, (names.getDebugName(i) for i in (0, 13, 14))))
pixels = bytearray()
glyphs = []
metrics = []
for scale in (3, 4, 6):
    font = ImageFont.truetype(font_path, scale * 7)
    widths = []
    for code in range(32, 127):
        char = chr(code)
        width = max(1, round(font.getlength(char)))
        height = scale * 9
        mask = Image.new("L", (width, height))
        ImageDraw.Draw(mask).text((0, scale * 7), char, font=font, fill=255, anchor="ls")
        glyphs.append((len(pixels), width, height))
        widths.append(width)
        pixels.extend(mask.tobytes())
    metrics.append(f"    {scale} => [{','.join(map(str, widths))}]")

Path(header_path).write_text(
    "/* Generated Inter glyph coverage; no font engine is needed at boot. */\n"
    + "static const char menu_font_license[] = " + json.dumps(license_text) + ";\n"
    + "struct menu_glyph { unsigned int offset, width, height; };\n"
    "static const struct menu_glyph menu_glyphs[] = {\n"
    + ",\n".join("{%d,%d,%d}" % glyph for glyph in glyphs)
    + "\n};\nstatic const unsigned char menu_coverage[] = {\n"
    + ",\n".join(",".join(map(str, pixels[i:i + 32])) for i in range(0, len(pixels), 32))
    + "\n};\n"
)
Path(metrics_path).write_text(
    "module ShengHeadlessGenerationMenu\n  FONT_WIDTHS = {\n"
    + ",\n".join(metrics)
    + "\n  }\nend\n"
)
