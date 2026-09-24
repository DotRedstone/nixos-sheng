#!/usr/bin/env python3
"""Exercise the real native animation renderer without opening a display."""
import hashlib
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

painter, assets = (Path(argument).resolve() for argument in sys.argv[1:3])

asset_paths = sorted(assets.glob('*.sfb'))
assert len(asset_paths) == 243, 'Expected two resolutions of both boot phases, credits and menu logo'
for asset in asset_paths:
    data = asset.read_bytes()
    assert data[:4] == b'SFB1' and (len(data) - 4) % 12 == 0, f'Invalid frame: {asset}'
    for offset in range(4, len(data), 12):
        red, green, blue = data[offset + 8:offset + 11]
        assert red <= green <= blue, f'Color outside the blue/neutral palette in {asset}'
for suffix in ('', '-hd'):
    for index in range(60):
        assert (assets / f'prepare{suffix}-{index:02d}.sfb').read_bytes() == \
            (assets / f'start{suffix}-{index:02d}.sfb').read_bytes(), 'Boot phase changes visual style'


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

    for width, height in [(3048, 2032), (2032, 3048), (1600, 1600), (1280, 720), (480, 800)]:
        for bpp in (16, 24, 32):
            stride = width * (bpp // 8) + 96
            raw.write_bytes(b'\xa5' * (stride * height))
            subprocess.run(command(width, height, bpp), check=True, timeout=5)
            data = raw.read_bytes()
            for row in range(height):
                assert data[row * stride + stride - 96:(row + 1) * stride] == b'\xa5' * 96
            assert data[:bpp // 8] == b'\0' * (bpp // 8), 'Old content was not cleared'
            row_bytes = width * (bpp // 8)
            assert any(any(data[row * stride:row * stride + row_bytes])
                       for row in range(height)), 'Blank splash'
            if bpp == 32:
                # A real corner credit must survive frame updates and must be
                # anchored to the display, rather than the central square.
                corner = [data[y * stride + x * 4:y * stride + x * 4 + 3]
                          for y in range(height - min(130, height // 4), height)
                          for x in range(width - min(330, width // 2), width)]
                assert any(pixel[0] for pixel in corner), 'Corner credit is missing'
                assert all(pixel[0] == pixel[1] == pixel[2] for pixel in corner), 'Credit is not neutral'
                assert max(pixel[0] for pixel in corner) < 150, 'Credit overpowers the logo'
                assert (frames / '000.raw').read_bytes()[-stride * 130:] == data[-stride * 130:], \
                    'Corner credit flickers between frames'
                # Count colored columns around the logo to catch accidental
                # reuse of the 720px asset on a high-resolution display.
                row = data[(height // 2 - (120 if min(width, height) >= 1600 else 60)) * stride:]
                colored = [x for x in range(width) if row[x * 4] > row[x * 4 + 2] + 15]
                assert colored, 'Blue snowflake missing'
                if min(width, height) >= 1600:
                    assert max(colored) - min(colored) > 350, 'HD logo rendered at low resolution'
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

    # Real cross-process takeover: load first, retire old writer, publish the
    # new PID. Readiness from the outgoing process must not satisfy the service.
    process = subprocess.Popen(command(count=2400, output='-'))
    incoming = None
    try:
        wait_ready(process, control)
        assert Path(str(control) + '.ready').read_text().strip() == str(process.pid)
        takeover = command(count=2400, output='-')
        takeover[1] = '--animate-file-handoff'
        incoming = subprocess.Popen(takeover)
        assert process.wait(timeout=4) == 0
        wait_ready(incoming, control)
        assert Path(str(control) + '.ready').read_text().strip() == str(incoming.pid)
        subprocess.run([str(painter), '--stop', str(control)], check=True, timeout=4)
        assert incoming.wait(timeout=2) == 0
    finally:
        for child in (process, incoming):
            if child is not None and child.poll() is None:
                child.kill(); child.wait()

    # Python's charging monitor uses the same POSIX lock, unlike an unrelated
    # flock. A battery owner must exclude the native boot animation entirely.
    import fcntl
    with open(str(control) + '.lock', 'r+') as lock:
        fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = raw.read_bytes()
        assert subprocess.run(command(count=1), timeout=4).returncode == 75
        assert raw.read_bytes() == before

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

    process = subprocess.Popen(command(count=2400, output='-'))
    try:
        wait_ready(process, control)
        takeover = command(directory=broken)
        takeover[1] = '--animate-file-handoff'
        assert subprocess.run(takeover, timeout=4).returncode != 0
        assert process.poll() is None, 'Bad incoming assets stopped the old animation'
        assert Path(str(control) + '.ready').read_text().strip() == str(process.pid)
        subprocess.run([str(painter), '--stop', str(control)], check=True, timeout=4)
        process.wait(timeout=2)
    finally:
        if process.poll() is None:
            process.kill(); process.wait()
    before = raw.read_bytes()

    # The separate credit must also be validated before acquiring the display.
    (broken / 'start-30.sfb').unlink()
    (broken / 'start-30.sfb').symlink_to(assets / 'start-30.sfb')
    (broken / 'credit-00.sfb').unlink()
    (broken / 'credit-00.sfb').write_bytes(b'SFB1broken')
    failure = subprocess.run(command(directory=broken), timeout=4)
    assert failure.returncode != 0, 'Malformed credit was accepted'
    assert raw.read_bytes() == before, 'Failed credit preparation touched the display'

print('blue/neutral assets, HD sizing, corner credit, loop, ownership, stop and failure tests passed')
