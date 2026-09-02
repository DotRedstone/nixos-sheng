#!@python@

import glob
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

EVENT = struct.Struct("llHHI")
RECTANGLE = struct.Struct("<HHHHBBBB")
EV_KEY = 1
KEY_POWER = 116
HOLD_SECONDS = 2.0
DISPLAY_SECONDS = 8.0
POWER_DISCOVERY_GRACE_SECONDS = 30.0
DISCONNECT_SECONDS = 10.0
PREFERRED_POWER_KEY_PATH = (
    "/dev/input/by-path/"
    "platform-c400000.spmi-platform-c400000.spmi:pmic@0:pon@1300:pwrkey-event"
)

BG = (8, 10, 11)
TRACK = (35, 40, 41)
OUTLINE = (207, 214, 212)
ACCENT = (115, 210, 199)
FULL = (121, 218, 158)
LOW = (238, 186, 96)
CRITICAL = (232, 105, 105)

DIGITS = {
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "10000", "11110", "00001", "00001", "11110"),
    "6": ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
    "%": ("11001", "11010", "00100", "01000", "10110", "00110", "00000"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
}

BOLT = (
    "00110",
    "01100",
    "01100",
    "11000",
    "11110",
    "00110",
    "00110",
    "00100",
    "01000",
)


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


def draw_text(operations, text, center_x, top, scale, color):
    glyph_width = 5 * scale
    gap = scale * 2
    text_width = len(text) * glyph_width + max(0, len(text) - 1) * gap
    x = center_x - text_width // 2
    for character in text:
        glyph = DIGITS.get(character, DIGITS["-"])
        for row, pattern in enumerate(glyph):
            for column, pixel in enumerate(pattern):
                if pixel == "1":
                    add_rect(
                        operations,
                        x + column * scale,
                        top + row * scale,
                        scale,
                        scale,
                        color,
                    )
        x += glyph_width + gap


def charge_color(capacity):
    if capacity is None or capacity <= 10:
        return CRITICAL
    if capacity <= 25:
        return LOW
    if capacity >= 95:
        return FULL
    return ACCENT


def build_framebuffer_commands(width, height, capacity):
    operations = []
    add_rect(operations, 0, 0, width, height, BG)

    body_height = max(260, min(int(height * 0.42), 680))
    body_width = max(150, int(body_height * 0.46))
    border = max(8, body_width // 18)
    terminal_width = body_width // 3
    terminal_height = max(12, border * 2)
    body_x = (width - body_width) // 2
    body_y = max(60, (height - body_height) // 2 - height // 16)
    terminal_x = body_x + (body_width - terminal_width) // 2
    terminal_y = body_y - terminal_height

    add_rect(operations, terminal_x, terminal_y, terminal_width, terminal_height, OUTLINE)
    add_rect(operations, body_x, body_y, body_width, border, OUTLINE)
    add_rect(operations, body_x, body_y + body_height - border, body_width, border, OUTLINE)
    add_rect(operations, body_x, body_y, border, body_height, OUTLINE)
    add_rect(operations, body_x + body_width - border, body_y, border, body_height, OUTLINE)

    inner_x = body_x + border * 2
    inner_y = body_y + border * 2
    inner_width = body_width - border * 4
    inner_height = body_height - border * 4
    add_rect(operations, inner_x, inner_y, inner_width, inner_height, TRACK)

    shown_capacity = 0 if capacity is None else capacity
    fill_height = max(border, inner_height * shown_capacity // 100) if shown_capacity else 0
    if fill_height:
        add_rect(
            operations,
            inner_x,
            inner_y + inner_height - fill_height,
            inner_width,
            fill_height,
            charge_color(capacity),
        )

    bolt_color = BG if shown_capacity >= 45 else OUTLINE
    bolt_scale = max(8, body_width // 24)
    bolt_x = width // 2 - (len(BOLT[0]) * bolt_scale) // 2
    bolt_y = body_y + body_height // 2 - (len(BOLT) * bolt_scale) // 2
    for row, pattern in enumerate(BOLT):
        for column, pixel in enumerate(pattern):
            if pixel == "1":
                add_rect(
                    operations,
                    bolt_x + column * bolt_scale,
                    bolt_y + row * bolt_scale,
                    bolt_scale,
                    bolt_scale,
                    bolt_color,
                )

    label = "--%" if capacity is None else f"{capacity}%"
    text_scale = max(7, min(width, height) // 105)
    draw_text(
        operations,
        label,
        width // 2,
        body_y + body_height + max(55, height // 24),
        text_scale,
        OUTLINE,
    )

    data = bytearray(b"SFB1")
    for operation in operations:
        data.extend(RECTANGLE.pack(*operation))
    return bytes(data)


class Display:
    def __init__(self):
        self.saved_backlights = {}

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

    def blank(self):
        self.capture_backlights()
        for path in glob.glob("/sys/class/backlight/*/brightness"):
            write_text(path, "0\n")
        for path in glob.glob("/sys/class/graphics/fb*/blank"):
            write_text(path, "1\n")

    def render(self, capacity):
        geometry = framebuffer_geometry()
        if geometry is None or not os.path.exists("/dev/fb0"):
            return False
        self.unblank()
        commands = build_framebuffer_commands(*geometry, capacity)
        try:
            with open(FRAMEBUFFER_COMMAND_PATH, "wb") as handle:
                handle.write(commands)
            result = subprocess.run(
                [FRAMEBUFFER_PAINTER, FRAMEBUFFER_COMMAND_PATH],
                check=False,
                timeout=5,
            )
            return result.returncode == 0
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


def start_normal_boot(display):
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

        if (
            capacity != last_capacity
            and visible_until is not None
            and now < visible_until
        ):
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
