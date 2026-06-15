# Xiaomi Pad 6S Pro (sheng) Mobile NixOS v0.1.0

This is the first stable release for the Xiaomi Pad 6S Pro 12.4 (`sheng`).
Read the known issues before flashing.

## Working

- Boot to the console-oriented minimal image or the optional GNOME image
- Display, touchscreen, physical volume keys
- **Physical power key** (toggles screen on/off without triggering suspend)
- **On-screen keyboard** (`gjs-osk`) enabled for touch input
- Four-way automatic rotation, cover-close blanking, and cover-open redraw
- Stage-1 generation menu with volume/power keys and external arrow/Enter keys
- 2.4 GHz and 5 GHz Wi-Fi
- Bluetooth controller enumeration
- USB-C role and Type-C enumeration
- Accelerometer, proximity, ambient light, and compass through SSC user space
- ALSA card and camera media-node enumeration
- Nix, `nixos-rebuild`, and the stage-2 generation framework
- Desktop-neutral `mkShengSystem` and explicit `mkShengGnomeSystem`
  constructors for private downstream dotfiles flakes

## Known issues

- **Fingerprint sensor**: Unsupported (requires proprietary Qualcomm TEE/TrustZone decryption which is unavailable in mainline Linux).
- **5GHz Wi-Fi on Cold Boot**: After a fresh `fastboot` flash (cold boot), 5GHz Wi-Fi networks may not appear due to a modem/firmware initialization race condition. A warm `reboot` resolves this.
- Sensors use SSC plus D-Bus; kernel `/sys/bus/iio/devices/iio:device*` nodes
  are not available.
- The v0.1.0 GNOME image may change brightness unexpectedly because automatic
  ambient-light adjustment and idle dimming are enabled. This is fixed on the
  `sheng` branch but is not included in the v0.1.0 image.
- Audio playback/recording, Bluetooth pairing/audio, official keyboard/touchpad,
  and desktop camera integration still need broader validation.
- Kernel, DTS, stage-1 initrd, and boot-command-line changes still require a
  separately built and flashed `boot_b` image.

## Flashing

The release contains one boot image plus minimal and GNOME rootfs variants.
Images smaller than GitHub's 2 GiB per-asset limit are uploaded as directly
flashable `.img` files. Larger raw images are uploaded as numbered
`.img.part-*` files and only need to be joined before flashing. Asset names
include `nixos`, the release version, and the kernel version.

For first-time dual-boot partitioning and installation, follow
the [dual-boot installation guide](https://github.com/DotRedstone/nixos-xiaomi-sheng/blob/sheng/docs/install-dualboot.md).

```sh
cat nixos-sheng-*-rootfs-minimal.img.part-* > nixos-sheng-rootfs.img
fastboot flash boot_b nixos-sheng-*-boot.img
fastboot flash linux nixos-sheng-rootfs.img
fastboot --set-active=b
fastboot reboot
```

Choose `rootfs-gnome` instead of `rootfs-minimal` only when you want the
repository-provided GNOME desktop. If a variant is provided as a single
`.img`, flash that file directly without the `cat` command.

Checksum verification is optional but recommended. Filter the checksum list to
the variant you downloaded so missing files from the other variant are not
reported as failures:

```sh
grep -E 'boot\.img|rootfs-minimal\.img\.part-' sha256sums.txt | sha256sum -c -
```

Replace `rootfs-minimal` with `rootfs-gnome` when using the GNOME image.

Both `boot_b` and `linux` must be flashed for the complete release. Do not
flash `userdata`.

The public image uses the default credentials `luser` / `1` and root
password `123456`. Change them immediately, or build a personalized system
from a private flake using the template in `examples/sheng-dotfiles`.

The rootfs image filesystem may be smaller than the dedicated `linux`
partition. To use the remaining space for NixOS generations, follow
the [linux filesystem resize guide](https://github.com/DotRedstone/nixos-xiaomi-sheng/blob/sheng/docs/linux-partition-resize.md)
from TWRP or another rescue environment after flashing.

## Rollback

Keep the previous boot and rootfs release files. If the new image does not
boot, enter Fastboot or TWRP and flash the previous `boot_b` image. Flashing a
previous `linux` rootfs restores that rootfs but replaces its local NixOS
generations and data, so back up important files first.
