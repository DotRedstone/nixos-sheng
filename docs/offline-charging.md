# Offline Charging

[简体中文](offline-charging_zh.md)

Sheng uses the normal production Linux kernel for off-mode charging, like
Android's charger mode. The bootloader still starts `boot_b`, but stage-1 skips
the generation menu and stage-2 selects `sheng-offline-charging.target` instead
of the desktop.

## Behaviour

- A battery icon and percentage are drawn directly to `/dev/fb0`.
- The display turns off after eight seconds to reduce idle power.
- A short power-key press shows the charge UI again.
- Holding the power key for two seconds starts the normal graphical system.
- Disconnecting external power for ten seconds powers the tablet off.
- The minimal target starts the Qualcomm ADSP/PD mapper and MiPPS authentication
  path, but does not pull in GNOME, Wi-Fi, Bluetooth, or sensor userspace.

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

## Hardware Validation

1. Boot normally while connected to power and confirm the desktop still starts.
2. Shut the tablet down fully, then insert a charger without pressing power.
3. Confirm that the generation menu and desktop do not appear.
4. Confirm that the battery UI appears, blanks after eight seconds, and returns
   after a short power-key press.
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
