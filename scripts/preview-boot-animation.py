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
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
width, height, stride = 1280, 720, 1280 * 4 + 96
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
                        str(root / 'control'), '60'], check=True, timeout=20)
        images = [Image.frombytes('RGB', (width, height), path.read_bytes(), 'raw', 'BGRX', stride)
                  for path in sorted(frames.glob('*.raw'))]
        images[15].save(args.output / f'{phase}.png')
        images[0].save(args.output / f'{phase}.gif', save_all=True, append_images=images[1:],
                       duration=50, loop=0)
        sequence.extend(images)
        durations.extend([50] * len(images))
        if phase == 'prepare' and args.menu:
            for name, duration in [('initial', 1000), ('countdown-2', 1000), ('countdown', 1000)]:
                image = Image.open(args.menu / f'menu-1280-{name}.png').convert('RGB')
                if image.size != (width, height):
                    raise ValueError('Menu preview must use 1280x720 native pixels')
                sequence.append(image)
                durations.append(duration)
    sequence[0].save(args.output / 'boot-flow.gif', save_all=True,
                     append_images=sequence[1:], duration=durations, loop=0)
print(args.output / 'boot-flow.gif')
