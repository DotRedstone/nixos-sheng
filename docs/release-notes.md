# Xiaomi Pad 6S Pro (sheng) Mobile NixOS v0.1.0

This is the first stable release for the Xiaomi Pad 6S Pro 12.4 (`sheng`).
Read the known issues before flashing.

## Working

- Boot to the minimal GNOME desktop
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
- Reusable `mkShengSystem` and `mkShengMinimalSystem` constructors for private
  downstream dotfiles flakes

## Known issues

- **Fingerprint sensor**: Unsupported (requires proprietary Qualcomm TEE/TrustZone decryption which is unavailable in mainline Linux).
- **5GHz Wi-Fi on Cold Boot**: After a fresh `fastboot` flash (cold boot), 5GHz Wi-Fi networks may not appear due to a modem/firmware initialization race condition. A warm `reboot` resolves this.
- Sensors use SSC plus D-Bus; kernel `/sys/bus/iio/devices/iio:device*` nodes
  are not available.
- Audio playback/recording, Bluetooth pairing/audio, official keyboard/touchpad,
  and desktop camera integration still need broader validation.
- Kernel, DTS, stage-1 initrd, and boot-command-line changes still require a
  separately built and flashed `boot_b` image.

## Flashing

The release contains a boot image, a compressed rootfs image, and
`sha256sums.txt`. Rootfs archives larger than GitHub's 2 GiB per-asset limit
are uploaded as numbered `.part-*` files. Verify the checksums before joining
the parts or flashing.

For first-time dual-boot partitioning and installation, follow
[`install-dualboot.md`](install-dualboot.md).

```sh
sha256sum -c sha256sums.txt
cat sheng-*-rootfs-*.img.zst.part-* > sheng-rootfs.img.zst
zstd -d sheng-rootfs.img.zst
fastboot flash boot_b sheng-*-boot.img
fastboot flash linux sheng-rootfs.img
fastboot reboot
```

If the release contains a single rootfs `.img.zst` instead of `.part-*`
files, use:

```sh
zstd -d sheng-*-rootfs-*.img.zst
fastboot flash boot_b sheng-*-boot.img
fastboot flash linux sheng-*-rootfs-*.img
fastboot reboot
```

Both `boot_b` and `linux` must be flashed for the complete release. Do not
flash `userdata`.

The public image uses the default credentials `luser` / `1` and root
password `123456`. Change them immediately, or build a personalized system
from a private flake using the template in `examples/sheng-dotfiles`.

The rootfs image filesystem may be smaller than the dedicated `linux`
partition. To use the remaining space for NixOS generations, follow
[`linux-partition-resize.md`](linux-partition-resize.md) from TWRP or another
rescue environment after flashing.

## Rollback

Keep the previous boot and rootfs release files. If the new image does not
boot, enter Fastboot or TWRP and flash the previous `boot_b` image. Flashing a
previous `linux` rootfs restores that rootfs but replaces its local NixOS
generations and data, so back up important files first.
