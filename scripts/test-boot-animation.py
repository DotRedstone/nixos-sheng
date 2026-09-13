#!/usr/bin/env python3
"""Exercise the real native animation renderer without opening a display."""
import hashlib
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

painter, assets = map(Path, sys.argv[1:3])


def wait_ready(process, control):
    deadline = time.monotonic() + 4
    while not Path(str(control) + '.ready').exists():
        if process.poll() is not None:
            raise AssertionError(f'Animation exited before ready: {process.returncode}')
        if time.monotonic() > deadline:
            process.kill()
            raise AssertionError('Animation did not become ready')
        time.sleep(.01)


with tempfile.TemporaryDirectory(prefix='sheng-boot-test-') as temporary:
    root = Path(temporary)
    raw, control, frames = root / 'frame.raw', root / 'control', root / 'frames'
    frames.mkdir()

    def command(width=720, height=720, bpp=32, count=3, output=frames, directory=assets, phase='start'):
        stride = width * (bpp // 8) + 96
        return [str(painter), '--animate-file', str(raw), str(width), str(height),
                str(stride), str(bpp), str(output), str(directory), phase, str(control), str(count)]

    for width, height in [(3048, 2032), (2032, 3048), (1280, 720), (480, 800)]:
        for bpp in (16, 24, 32):
            stride = width * (bpp // 8) + 96
            raw.write_bytes(b'\xa5' * (stride * height))
            subprocess.run(command(width, height, bpp), check=True, timeout=5)
            data = raw.read_bytes()
            for row in range(height):
                assert data[row * stride + stride - 96:(row + 1) * stride] == b'\xa5' * 96
            assert data[:bpp // 8] == b'\0' * (bpp // 8), 'Old content was not cleared'
            assert any(data[height // 2 * stride:height // 2 * stride + stride - 96]), 'Blank splash'
        print(f'{width}x{height}: 16/24/32bpp, padded stride preserved')

    raw.write_bytes(bytes((720 * 4 + 96) * 720))
    subprocess.run(command(count=61), check=True, timeout=15)
    assert (frames / '000.raw').read_bytes() == (frames / '060.raw').read_bytes(), 'Loop seam changes pixels'
    assert (frames / '000.raw').read_bytes() != (frames / '015.raw').read_bytes(), 'Animation is static'

    # A second writer must not erase the first writer's ready marker or pixels.
    process = subprocess.Popen(command(count=2400, output='-'))
    try:
        wait_ready(process, control)
        second = subprocess.run(command(count=1), timeout=4)
        assert second.returncode == 75, 'Two writers acquired the same display'
        assert Path(str(control) + '.ready').exists(), 'Rejected writer removed ready marker'
        subprocess.run([str(painter), '--stop', str(control)], check=True, timeout=4)
        assert process.wait(timeout=2) == 0
        digest = hashlib.sha256(raw.read_bytes()).digest()
        time.sleep(.1)
        assert hashlib.sha256(raw.read_bytes()).digest() == digest, 'Pixels changed after stop acknowledged'
    finally:
        if process.poll() is None:
            process.kill(); process.wait()

    process = subprocess.Popen(command(count=2400, output='-'))
    try:
        wait_ready(process, control)
        process.send_signal(signal.SIGTERM)
        assert process.wait(timeout=2) == 0
        assert not Path(str(control) + '.disabled').exists(), 'Normal stop disabled future UI'
    finally:
        if process.poll() is None:
            process.kill(); process.wait()

    # Moving /run during switch_root must not disconnect the old process from
    # stage-2's stop request or leave a stale ready marker in the moved mount.
    state_directory = root / 'state'
    state_directory.mkdir()
    control = state_directory / 'control'
    process = subprocess.Popen(command(count=2400, output='-'))
    try:
        wait_ready(process, control)
        moved = root / 'moved-state'
        state_directory.rename(moved)
        control = moved / 'control'
        subprocess.run([str(painter), '--stop', str(control)], check=True, timeout=4)
        assert process.wait(timeout=2) == 0
        assert not Path(str(control) + '.ready').exists(), 'Switch-root handoff left stale readiness'
    finally:
        if process.poll() is None:
            process.kill(); process.wait()

    # The test mode must never switch a host VT, even for the diagnostics path.
    process = subprocess.Popen(command(count=2400, output='-'))
    try:
        wait_ready(process, control)
        control.write_text('details')
        assert process.wait(timeout=2) == 0
        assert Path(str(control) + '.disabled').exists()
        before = raw.read_bytes()
        subprocess.run(command(), check=True, timeout=4)
        assert raw.read_bytes() == before, 'Disabled boot UI painted over diagnostics'
    finally:
        if process.poll() is None:
            process.kill(); process.wait()
    Path(str(control) + '.disabled').unlink()

    broken = root / 'broken'
    broken.mkdir()
    for path in assets.glob('*.sfb'):
        (broken / path.name).symlink_to(path)
    (broken / 'start-30.sfb').unlink()
    (broken / 'start-30.sfb').write_bytes(b'SFB1broken')
    before = raw.read_bytes()
    failure = subprocess.run(command(directory=broken), timeout=4)
    assert failure.returncode != 0, 'Malformed assets were accepted'
    assert raw.read_bytes() == before, 'Failed preparation touched the display'

print('boot animation pixels, loop, exclusive ownership, stop, diagnostics and failure tests passed')
