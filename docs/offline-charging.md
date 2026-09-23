# Offline Charging

[简体中文](offline-charging_zh.md)

Sheng uses the normal production Linux kernel for off-mode charging, like
Android's charger mode. The bootloader still starts `boot_b`, but stage-1 skips
the generation menu and stage-2 selects `sheng-offline-charging.target` instead
of the desktop.

The boot detector writes its override to `generator.early`. That lookup path
precedes NixOS' static `/etc/systemd/system/default.target`, so the graphical
default cannot override charger mode.

## Behaviour

- The first frame is painted before the panel is unblanked, preventing a brief
  flash of boot-console text.
- A rounded horizontal battery and antialiased Inter percentage are drawn
  directly to `/dev/fb0`, with a black background and mint, amber or red fill.
  Both are 50% larger on the native tablet display than the previous layout.
- A gentle highlight travels through the actual filled region while the bolt
  breathes, in a 3.2-second loop capped at 10 fps. Only the battery interior is
  repainted. Full, unknown and unplugged states are static; blanking stops all
  drawing. Pillow and the bundled font are used only when rendering, not during
  boot-mode detection.
- Charger boots hand off directly to the minimal charging target instead of
  waiting in a black stage-1.
- The display turns off after eight seconds to reduce idle power.
- A short power-key press shows the charge UI again.
- Holding the power key for two seconds starts the normal graphical system once
  the battery has reached 5%.
- Disconnecting external power for ten seconds powers the tablet off.
- The minimal target starts the Qualcomm ADSP/PD mapper and MiPPS authentication
  path, but does not pull in GNOME, Wi-Fi, Bluetooth, or sensor userspace.

The charging UI does not wait for the global `systemd-udev-settle` barrier. It
briefly discovers the framebuffer and battery nodes itself, so an unrelated
slow device cannot block the first visible charging feedback. Below 5%, a long
power-key press only redraws the current level instead of starting the desktop,
which avoids the low-battery brownout loop.

Detection follows AOSP's `androidboot.mode=charger` in the kernel command line
or bootconfig. Sheng also accepts a Qualcomm PON reason with the USB charger bit
set. A simultaneous power-key bit and `androidboot.force_normal_boot=1` both
force a normal boot, so starting the tablet intentionally while it is connected
does not enter offline charging.

The system image must not append `androidboot.force_normal_boot=1` permanently.
That flag is suitable only for a one-shot recovery boot because otherwise it
overrides every charger-boot reason supplied by the bootloader.

## Deployment

This feature changes both initramfs stage-1 and NixOS stage-2. Build and flash
the matching `boot_b` image, then activate or flash the matching rootfs/system
generation. A device-side `nixos-rebuild` alone cannot update stage-1.

The larger battery and charging animation only change stage-2. On a device with the charger
boot support already installed, activate the updated system generation; no
additional boot flash is needed. Switching to the previous system generation
restores the previous renderer.

For an off-device PNG preview, run `scripts/preview-offline-charging.py OUTPUT.png`
with Pillow available and `SHENG_CHARGING_FONT` pointing to `Inter.ttc`.
`--capacity`, `--width`, and `--height` select the battery level and framebuffer
size. Add `--animate` to export a GIF/APNG loop. Use
`--painter /path/to/sheng-fb-painter` to run the actual painter against a temporary
file without touching the display. Preview and device use the same SFB1 commands.

The visual hierarchy follows familiar Android battery/percentage displays; the
artwork and animation are implemented here. References:
[Android charging assets](https://android.googlesource.com/platform/system/core/+/344bff4/healthd/images/)
and [Xiaomi charging animation](https://www.mi.com/sa-en/support/faq/details/KA-483284/).

Offscreen regression checks, with Pillow and Inter available:

```sh
SHENG_CHARGING_FONT=/path/to/Inter.ttc python3 scripts/test-offline-charging.py \
  nixos/scripts/sheng-offline-charging.py /path/to/sheng-fb-painter
```

Checks cover landscape/portrait bounds, loops without stale pixels, stationary
text, full/unplugged states and no drawing while blanked. The same tests can run
on the device using temporary files; they do not replace visible panel checks.

## Hardware Validation

1. Boot normally while connected to power and confirm the desktop still starts.
2. Shut the tablet down fully, then insert a charger without pressing power.
3. Confirm that the generation menu and desktop do not appear.
4. Confirm the larger rounded battery and percentage are sharp, with moving
   light and no text flicker. It should blank after eight seconds, return after
   a short power-key press and remain static at full charge.
5. Hold power for two seconds and confirm the normal graphical system starts.
6. Repeat the charger boot, unplug power, and confirm shutdown after ten seconds.
7. Test standard PD and MiPPS separately and inspect battery current and thermal
   state; the displayed percentage alone does not prove fast charging.

Useful diagnostics after entering the normal system:

```sh
cat /proc/cmdline
grep -E 'androidboot.(mode|force_normal_boot)|bootinfo.pureason' /proc/bootconfig
journalctl -b -u sheng-offline-charging.service --no-pager
systemctl status sheng-offline-charging.target --no-pager
```

Keep the exact charger-boot command line if detection fails. Do not broaden the
PON mask without checking that a normal power-key boot remains distinguishable.
