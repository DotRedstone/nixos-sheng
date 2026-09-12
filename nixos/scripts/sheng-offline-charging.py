#!@python@

import glob
import functools
import os
import re
import select
import struct
import subprocess
import sys
import time


SYSTEMCTL = "@systemctl@"
FRAMEBUFFER_PAINTER = "@framebufferPainter@"
FRAMEBUFFER_COMMAND_PATH = "/run/sheng-offline-charging.fbops"
FONT_PATH = "@chargingFont@"

EVENT = struct.Struct("llHHI")
RECTANGLE = struct.Struct("<HHHHBBBB")
EV_KEY = 1
KEY_POWER = 116
HOLD_SECONDS = 2.0
DISPLAY_SECONDS = 8.0
MINIMUM_BOOT_CAPACITY = 5
POWER_DISCOVERY_GRACE_SECONDS = 30.0
DISCONNECT_SECONDS = 10.0
PREFERRED_POWER_KEY_PATH = (
    "/dev/input/by-path/"
    "platform-c400000.spmi-platform-c400000.spmi:pmic@0:pon@1300:pwrkey-event"
)

BG = (0, 0, 0)
TRACK = (24, 31, 30)
OUTLINE = (229, 236, 233)
ACCENT = (130, 214, 184)
FULL = (130, 214, 184)
LOW = (238, 186, 96)
CRITICAL = (232, 105, 105)
def read_text(path):
    try:
        with open(path, "r", encoding="ascii") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def write_text(path, value):
    try:
        with open(path, "w", encoding="ascii") as handle:
            handle.write(value)
        return True
    except OSError:
        return False


def cmdline_value(cmdline, key):
    prefix = key + "="
    for token in cmdline.split():
        if token.startswith(prefix):
            return token[len(prefix) :].strip('"')
    return ""


def bootconfig_value(bootconfig, key):
    match = re.search(
        rf"^\s*{re.escape(key)}\s*=\s*\"?([^\"\s]+)\"?\s*$",
        bootconfig,
        flags=re.MULTILINE,
    )
    return match.group(1) if match else ""


def parse_power_on_reason(value):
    try:
        return int(value, 0)
    except (TypeError, ValueError):
        return None


def charger_power_on_reason(value):
    reason = parse_power_on_reason(value)
    if reason is None:
        return False
    pon = reason & 0xFF
    usb_charger = bool(pon & (1 << 4))
    power_key = bool(pon & (1 << 7))
    return usb_charger and not power_key


def power_key_power_on_reason(value):
    reason = parse_power_on_reason(value)
    return reason is not None and bool((reason & 0xFF) & (1 << 7))


def detect_charger_boot(cmdline, bootconfig):
    force_normal = cmdline_value(cmdline, "androidboot.force_normal_boot")
    if not force_normal:
        force_normal = bootconfig_value(bootconfig, "androidboot.force_normal_boot")
    if force_normal == "1":
        return ""

    pureason = cmdline_value(cmdline, "bootinfo.pureason")
    if not pureason:
        pureason = bootconfig_value(bootconfig, "bootinfo.pureason")
    if power_key_power_on_reason(pureason):
        return ""

    mode = cmdline_value(cmdline, "androidboot.mode")
    if not mode:
        mode = bootconfig_value(bootconfig, "androidboot.mode")
    if mode.lower() == "charger":
        return "androidboot.mode=charger"

    if charger_power_on_reason(pureason):
        return f"bootinfo.pureason={pureason}"
    return ""


def detect_from_files(cmdline_path="/proc/cmdline", bootconfig_path="/proc/bootconfig"):
    return detect_charger_boot(read_text(cmdline_path), read_text(bootconfig_path))


def battery_capacity():
    for path in glob.glob("/sys/class/power_supply/*"):
        if read_text(os.path.join(path, "type")) != "Battery":
            continue
        value = read_text(os.path.join(path, "capacity"))
        if value.isdigit():
            return max(0, min(100, int(value)))
    return None


def external_power_online():
    battery_is_charging = False
    for path in glob.glob("/sys/class/power_supply/*"):
        if read_text(os.path.join(path, "type")) == "Battery":
            if read_text(os.path.join(path, "status")) in ("Charging", "Full"):
                battery_is_charging = True
            continue
        if read_text(os.path.join(path, "online")) == "1":
            return True
    return battery_is_charging


def framebuffer_geometry():
    value = read_text("/sys/class/graphics/fb0/virtual_size")
    try:
        width, height = (int(part) for part in value.split(",", 1))
    except (TypeError, ValueError):
        return None
    if width <= 0 or height <= 0 or width > 65535 or height > 65535:
        return None
    return width, height


def add_rect(operations, x, y, width, height, color):
    if width <= 0 or height <= 0:
        return
    operations.append((int(x), int(y), int(width), int(height), *color, 0))


def charge_color(capacity):
    if capacity is None:
        return OUTLINE
    if capacity <= 10:
        return CRITICAL
    if capacity <= 25:
        return LOW
    return ACCENT


@functools.lru_cache(maxsize=4)
def build_framebuffer_commands(width, height, capacity):
    # Pillow and the font are only loaded for the screen, never by the boot
    # generator's charger detection path.
    from PIL import Image, ImageDraw, ImageFont

    if capacity is not None:
        capacity = max(0, min(100, capacity))
    scale = min(width / 440, height / 440, 2.0)
    supersample = 2
    size = max(1, round(360 * scale))
    factor = size * supersample / 360
    canvas = Image.new("RGB", (size * supersample, size * supersample), BG)
    draw = ImageDraw.Draw(canvas)

    def box(bounds):
        return tuple(round(value * factor) for value in bounds)

    def rounded(bounds, radius, color):
        draw.rounded_rectangle(box(bounds), radius=round(radius * factor), fill=color)

    # A quiet horizontal battery above the numeric reading. The inner fill is
    # clipped to one rounded mask, keeping its level accurate even near zero.
    rounded((94, 67, 260, 145), 18, (72, 86, 81))
    rounded((97, 70, 257, 142), 15, BG)
    rounded((264, 93, 270, 119), 3, (72, 86, 81))
    rounded((103, 76, 251, 136), 10, TRACK)
    if capacity:
        mask = Image.new("L", canvas.size)
        md = ImageDraw.Draw(mask)
        md.rounded_rectangle(box((103, 76, 251, 136)), radius=round(10 * factor), fill=255)
        if capacity < 100:
            md.rectangle(box((103 + 148 * capacity / 100, 75, 252, 137)), fill=0)
        canvas.paste(charge_color(capacity), (0, 0), mask)
    # The bolt has its own dark backing so it stays legible across the fill edge.
    rounded((163, 84, 195, 128), 10, TRACK)
    draw.polygon(
        [(round(x * factor), round(y * factor)) for x, y in
         ((182, 91), (170, 108), (178, 108), (175, 121), (188, 103), (180, 103))],
        fill=OUTLINE,
    )

    font_path = os.environ.get("SHENG_CHARGING_FONT", FONT_PATH)
    number_font = ImageFont.truetype(font_path, round(72 * factor))
    percent_font = ImageFont.truetype(font_path, round(27 * factor))
    label = "--" if capacity is None else str(capacity)
    number_width = draw.textlength(label, font=number_font)
    percent_width = draw.textlength("%", font=percent_font)
    gap = round(6 * factor)
    left = (canvas.width - number_width - gap - percent_width) / 2
    baseline = round(249 * factor)
    draw.text((left, baseline), label, font=number_font, fill=OUTLINE, anchor="ls")
    draw.text((left + number_width + gap, baseline - round(5 * factor)), "%",
              font=percent_font, fill=(135, 151, 144), anchor="ls")

    canvas = canvas.resize((size, size), Image.Resampling.LANCZOS)
    # Bound edge colors and merge equal vertical runs to stay within SFB1's
    # 10,000-rectangle limit while retaining antialiased curves and type.
    palette_colors = [BG]
    for color in (TRACK, OUTLINE, ACCENT, LOW, CRITICAL, (72, 86, 81), (135, 151, 144)):
        palette_colors.extend(tuple(round(c * level / 8) for c in color)
                              for level in range(1, 9))
    palette = Image.new("P", (1, 1))
    palette.putpalette([c for color in palette_colors for c in color]
                       + [0] * (768 - 3 * len(palette_colors)))
    canvas = canvas.quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
    pixels = canvas.load()
    origin_x, origin_y = (width - size) // 2, (height - size) // 2
    operations = []
    add_rect(operations, 0, 0, width, height, BG)
    active = {}
    for y in range(size):
        current = {}
        x = 0
        while x < size:
            color = pixels[x, y]
            end = x + 1
            while end < size and pixels[end, y] == color:
                end += 1
            if color != BG:
                key = (x, end - x, color)
                current[key] = active.pop(key, (y, 0))
                first, length = current[key]
                current[key] = (first, length + 1)
            x = end
        for (x, length, color), (first, rows) in active.items():
            add_rect(operations, origin_x + x, origin_y + first, length, rows, color)
        active = current
    for (x, length, color), (first, rows) in active.items():
        add_rect(operations, origin_x + x, origin_y + first, length, rows, color)
    if len(operations) > 10000:
        raise ValueError("charging frame exceeds the native painter limit")
    return b"SFB1" + b"".join(RECTANGLE.pack(*op) for op in operations)

class Display:
    def __init__(self):
        self.saved_backlights = {}
        self.visible = False

    def capture_backlights(self):
        for path in glob.glob("/sys/class/backlight/*/brightness"):
            if path in self.saved_backlights:
                continue
            value = read_text(path)
            maximum = read_text(os.path.join(os.path.dirname(path), "max_brightness"))
            try:
                brightness = int(value)
                max_brightness = int(maximum)
            except ValueError:
                continue
            if brightness <= 0:
                brightness = max(1, max_brightness // 4)
            self.saved_backlights[path] = str(brightness)

    def unblank(self):
        self.capture_backlights()
        for path in glob.glob("/sys/class/graphics/fb*/blank"):
            write_text(path, "0\n")
        for path, value in self.saved_backlights.items():
            write_text(path, value + "\n")
        self.visible = True

    def blank(self):
        self.capture_backlights()
        for path in glob.glob("/sys/class/backlight/*/brightness"):
            write_text(path, "0\n")
        for path in glob.glob("/sys/class/graphics/fb*/blank"):
            write_text(path, "1\n")
        self.visible = False

    def render(self, capacity):
        geometry = framebuffer_geometry()
        if geometry is None or not os.path.exists("/dev/fb0"):
            return False
        was_visible = self.visible
        if not was_visible:
            # Paint the first frame while the panel is still blank. Unblanking
            # before the painter ran exposed one frame of the boot console.
            self.blank()
        commands = build_framebuffer_commands(*geometry, capacity)
        try:
            with open(FRAMEBUFFER_COMMAND_PATH, "wb") as handle:
                handle.write(commands)
            result = subprocess.run(
                [FRAMEBUFFER_PAINTER, FRAMEBUFFER_COMMAND_PATH],
                check=False,
                timeout=5,
            )
            if result.returncode != 0:
                return False
            if not was_visible:
                self.unblank()
            return True
        except (OSError, subprocess.TimeoutExpired):
            return False


def open_power_key():
    candidates = [PREFERRED_POWER_KEY_PATH]
    candidates.extend(glob.glob("/dev/input/by-path/*pwrkey-event"))
    for name_path in glob.glob("/sys/class/input/event*/device/name"):
        name = read_text(name_path).lower()
        if "pwrkey" not in name and "power key" not in name:
            continue
        event = os.path.basename(os.path.dirname(os.path.dirname(name_path)))
        candidates.append(os.path.join("/dev/input", event))
    for path in dict.fromkeys(candidates):
        try:
            return os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            pass
    return None


def normal_boot_allowed(capacity):
    return capacity is not None and capacity >= MINIMUM_BOOT_CAPACITY


def start_normal_boot(display):
    capacity = battery_capacity()
    if not normal_boot_allowed(capacity):
        shown_capacity = "unknown" if capacity is None else f"{capacity}%"
        print(
            "Offline charging: normal boot deferred at "
            f"{shown_capacity}; {MINIMUM_BOOT_CAPACITY}% is required.",
            flush=True,
        )
        return False

    print("Offline charging: power key held; starting the normal system.", flush=True)
    display.unblank()
    result = subprocess.run(
        [SYSTEMCTL, "--no-block", "isolate", "graphical.target"],
        check=False,
    )
    if result.returncode == 0:
        return True
    print("Offline charging: failed to start the normal system.", flush=True)
    display.blank()
    return False


def monitor():
    reason = detect_from_files()
    print(f"Offline charging mode is active ({reason or 'generator-selected'}).", flush=True)
    print("Short-press power to show charge; hold power to boot normally.", flush=True)

    display = Display()
    power_key = None
    pressed_at = None
    offline_since = None
    ever_online = False
    last_report = 0.0
    last_capacity = None
    visible_until = time.monotonic() + DISPLAY_SECONDS
    started_at = time.monotonic()

    for _ in range(100):
        if framebuffer_geometry() is not None and battery_capacity() is not None:
            break
        time.sleep(0.1)
    last_capacity = battery_capacity()
    display.render(last_capacity)

    while True:
        if power_key is None:
            power_key = open_power_key()

        now = time.monotonic()
        capacity = battery_capacity()
        online = external_power_online()
        if online:
            ever_online = True
            offline_since = None
        elif ever_online or now - started_at >= POWER_DISCOVERY_GRACE_SECONDS:
            if offline_since is None:
                offline_since = now
            elif now - offline_since >= DISCONNECT_SECONDS:
                print("Offline charging: charger disconnected; powering off.", flush=True)
                display.blank()
                subprocess.run([SYSTEMCTL, "poweroff"], check=False)
                time.sleep(60)

        if now - last_report >= 30:
            print(
                f"Offline charging: capacity={capacity}% external_power={online}",
                flush=True,
            )
            last_report = now

        if visible_until is not None and now < visible_until:
            if capacity != last_capacity:
                display.render(capacity)
                last_capacity = capacity
        elif visible_until is not None and now >= visible_until:
            display.blank()
            visible_until = None

        if power_key is not None:
            readable, _, _ = select.select([power_key], [], [], 0.1)
            if readable:
                try:
                    data = os.read(power_key, EVENT.size * 16)
                except OSError:
                    os.close(power_key)
                    power_key = None
                    data = b""

                for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
                    _, _, event_type, code, value = EVENT.unpack_from(data, offset)
                    if event_type != EV_KEY or code != KEY_POWER:
                        continue
                    if value == 1:
                        pressed_at = time.monotonic()
                    elif value == 0 and pressed_at is not None:
                        held_for = time.monotonic() - pressed_at
                        pressed_at = None
                        if held_for >= HOLD_SECONDS:
                            if start_normal_boot(display):
                                return 0
                            last_capacity = battery_capacity()
                            display.render(last_capacity)
                            visible_until = time.monotonic() + DISPLAY_SECONDS
                        else:
                            last_capacity = battery_capacity()
                            display.render(last_capacity)
                            visible_until = time.monotonic() + DISPLAY_SECONDS
        else:
            time.sleep(0.1)

        if pressed_at is not None and time.monotonic() - pressed_at >= HOLD_SECONDS:
            if start_normal_boot(display):
                return 0
            pressed_at = None
            last_capacity = battery_capacity()
            display.render(last_capacity)
            visible_until = time.monotonic() + DISPLAY_SECONDS


def main(argv):
    if len(argv) >= 2 and argv[1] == "detect":
        cmdline_path = argv[2] if len(argv) >= 3 else "/proc/cmdline"
        bootconfig_path = argv[3] if len(argv) >= 4 else "/proc/bootconfig"
        reason = detect_from_files(cmdline_path, bootconfig_path)
        if reason:
            print(reason)
            return 0
        return 1
    if len(argv) == 1 or (len(argv) == 2 and argv[1] == "monitor"):
        return monitor()
    print(f"usage: {argv[0]} [detect [CMDLINE BOOTCONFIG] | monitor]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
