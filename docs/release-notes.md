# Xiaomi Pad 6S Pro (sheng) Mobile NixOS

This is an early bring-up image for the Xiaomi Pad 6S Pro 12.4 (`sheng`).
Read the known issues before flashing.

## Working

- Boot to the minimal GNOME desktop
- Display, touchscreen, physical power and volume keys
- 2.4 GHz and 5 GHz Wi-Fi
- Bluetooth controller enumeration
- USB-C role and Type-C enumeration
- Accelerometer, proximity, ambient light, and compass through SSC user space
- ALSA card and camera media-node enumeration
- Nix, `nixos-rebuild`, and the stage-2 generation framework

## Known issues

- Sensors use SSC plus D-Bus; kernel `/sys/bus/iio/devices/iio:device*` nodes
  are not available.
- 6 GHz Wi-Fi is untested. A full NetworkManager rescan may be needed before
  the first 5 GHz activation.
- Audio playback/recording, Bluetooth pairing/audio, four-way rotation, and
  desktop camera integration still need broader validation.
- Kernel, DTS, stage-1 initrd, and boot-command-line changes still require a
  separately built and flashed `boot_b` image.
- This bring-up image uses the documented test credentials. Change them after
  first boot before using the tablet on an untrusted network.

## Flashing

The release contains a boot image, a compressed rootfs image, and
`sha256sums.txt`. Verify the checksums before flashing.

```sh
sha256sum -c sha256sums.txt
zstd -d sheng-*-rootfs-*.img.zst
fastboot flash boot_b sheng-*-boot.img
fastboot flash linux sheng-*-rootfs-*.img
fastboot reboot
```

Both `boot_b` and `linux` must be flashed for the complete release. Do not
flash `userdata`.

The rootfs image filesystem may be smaller than the dedicated `linux`
partition. To use the remaining space for NixOS generations, follow
[`linux-partition-resize.md`](linux-partition-resize.md) from TWRP or another
rescue environment after flashing.

## Rollback

Keep the previous boot and rootfs release files. If the new image does not
boot, enter Fastboot or TWRP and flash the previous `boot_b` image. Flashing a
previous `linux` rootfs restores that rootfs but replaces its local NixOS
generations and data, so back up important files first.
