#!/usr/bin/env python3
"""Export boot GIFs from the native painter, optionally including the actual menu."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('painter', type=Path)
parser.add_argument('assets', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--menu', type=Path, help='Native menu preview directory (1280x720)')
parser.add_argument('--width', type=int, default=1280, help='Native framebuffer width')
parser.add_argument('--height', type=int, default=720, help='Native framebuffer height')
parser.add_argument('--animation-max-size', type=int, default=1536,
                    help='Animated preview maximum edge; 0 keeps native resolution')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
width, height = args.width, args.height
if width <= 0 or height <= 0:
    parser.error('Framebuffer dimensions must be positive')
if args.animation_max_size < 0:
    parser.error('Animation maximum size must not be negative')
stride = width * 4 + 96
sequence = []
durations = []
with tempfile.TemporaryDirectory(prefix='sheng-boot-preview-') as temporary:
    root = Path(temporary)
    for phase in ('prepare', 'start'):
        frames = root / phase
        frames.mkdir()
        raw = root / 'frame.raw'
        raw.write_bytes(bytes(stride * height))
        subprocess.run([str(args.painter), '--animate-file', str(raw), str(width), str(height),
                        str(stride), '32', str(frames), str(args.assets), phase,
                        str(root / 'control'), '60'], check=True, timeout=60)
        images = []
        for index, path in enumerate(sorted(frames.glob('*.raw'))):
            image = Image.frombytes('RGB', (width, height), path.read_bytes(), 'raw', 'BGRX', stride)
            if index == 15:
                image.save(args.output / f'{phase}.png')
            # Keep the still at native resolution; cap animations by default
            # because a native tablet sequence needs several gigabytes of RAM.
            if args.animation_max_size:
                image.thumbnail((args.animation_max_size,) * 2, Image.Resampling.LANCZOS)
            images.append(image)
            path.unlink()
        images[0].save(args.output / f'{phase}.gif', save_all=True, append_images=images[1:],
                       duration=50, loop=0)
        images[0].save(args.output / f'{phase}.apng', format='PNG', save_all=True,
                       append_images=images[1:], duration=50, loop=0)
        sequence.extend(images)
        durations.extend([50] * len(images))
        if phase == 'prepare' and args.menu:
            for name, duration in [('initial', 1000), ('countdown-2', 1000), ('countdown', 1000)]:
                image = Image.open(args.menu / f'menu-1280-{name}.png').convert('RGB')
                if image.size != (width, height):
                    raise ValueError('Menu preview must match framebuffer dimensions')
                if args.animation_max_size:
                    image.thumbnail((args.animation_max_size,) * 2, Image.Resampling.LANCZOS)
                sequence.append(image)
                durations.append(duration)
    sequence[0].save(args.output / 'boot-flow.gif', save_all=True,
                     append_images=sequence[1:], duration=durations, loop=0)
print(args.output / 'boot-flow.gif')
