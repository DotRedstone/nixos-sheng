# Sheng dual-boot installation guide

[English](install-dualboot_en.md) | [简体中文](install-dualboot.md)

This guide installs Mobile NixOS on Xiaomi Pad 6S Pro 12.4 (`sheng`) while
keeping Android on the other slot. NixOS uses slot `b` plus a dedicated
`linux` partition.

Back up your data before touching partitions. Creating the `linux` partition
requires deleting and recreating `userdata`, which erases Android user data.
Do not flash `userdata` during later system updates.

## Requirements

- Unlocked bootloader
- Working TWRP or another rescue environment
- Matching boot and rootfs images from the same release
- `adb` and `fastboot` installed on the computer
- Android user data and important files backed up

## Create the linux partition

This section follows the dual-boot flow from
[`sheng-pmos-builds`](https://github.com/alghiffaryfa19/sheng-pmos-builds#dual-boot).
That project provides a TWRP-compatible
[`parted`](https://github.com/alghiffaryfa19/sheng-pmos-builds/blob/10c023a01fbeb8ac3ccb83e48eb4b58b6bad6dac/parted)
binary in its repository root.

Download the tool on your computer, then push it into TWRP:

```sh
curl -L -o parted \
  https://raw.githubusercontent.com/alghiffaryfa19/sheng-pmos-builds/10c023a01fbeb8ac3ccb83e48eb4b58b6bad6dac/parted
adb reboot recovery
adb push parted /sdcard/parted
```

The following steps delete and recreate `userdata`. Confirm your Android data
backup again before continuing. Enter the TWRP shell and verify that `sda`
really contains `userdata`:

```sh
adb shell
readlink -f /dev/block/by-name/userdata
ls -l /dev/block/sda
chmod +x /sdcard/parted
/sdcard/parted /dev/block/sda
```

The `readlink` result must point to a partition under `/dev/block/sda`, for
example `/dev/block/sda29`. If it points to another disk, stop and use the
actual disk path.

Inside the `parted` prompt, switch to GB and print the full layout plus free
space:

```text
unit GB
print free
```

Record the original `userdata` partition number, start, and end. On common
sheng layouts, `userdata` is partition 29 and the new `linux` partition becomes
partition 30, but this may differ across capacities or previously modified
devices. Do not blindly copy partition numbers or offsets.

The following is only an example for a 256GB device. Adjust the split point for
your capacity and the Android space you want to keep. The example keeps the
original `userdata` start at `12.7GB` and splits at `180GB`:

```text
rm 29
mkpart userdata ext4 12.7GB 180GB
mkpart linux ext4 180GB -0MB
print free
quit
```

Confirm that:

- `userdata` starts at the original recorded start position.
- `linux` uses the remaining space.
- The two partitions do not overlap and there is no unexpected large free area.
- You did not modify `boot`, `super`, `persist`, or other unrelated partitions.

After leaving `parted`, confirm TWRP created the `linux` partition node. If the
node is missing, reboot TWRP once and check again before flashing:

```sh
ls -l /dev/block/by-name/userdata
ls -l /dev/block/by-name/linux
exit
adb reboot bootloader
```

Recreating `userdata` erases Android user data and may require formatting
`userdata` in TWRP before Android can boot again. Do not format the new
`linux` partition; flashing the rootfs image overwrites it.

## Flash a release

Release rootfs images are provided as split ZIP archives for Windows-friendly
extraction. Download every volume for one variant. For example:

```text
nixos-sheng-v0.1.2-kernel-7.0.0-rootfs-minimal.z01
nixos-sheng-v0.1.2-kernel-7.0.0-rootfs-minimal.z02
nixos-sheng-v0.1.2-kernel-7.0.0-rootfs-minimal.zip
```

Put all volumes in the same folder, then open the final `.zip` file with
Bandizip, 7-Zip, WinRAR, or another split-ZIP compatible tool. Extract the
`.img` file and flash it:

```sh
fastboot erase dtbo_b
fastboot flash boot_b nixos-sheng-*-boot.img
fastboot flash linux nixos-sheng-*-rootfs-minimal.img
fastboot --set-active=b
fastboot reboot
```

Use `rootfs-gnome` instead of `rootfs-minimal` only when you want the
repository-provided GNOME desktop. The extracted `.img` is the file passed to
`fastboot flash linux`.

Checksum verification is optional. If you verify, only check the files you
downloaded so the other rootfs variant is not reported as missing:

```sh
grep -E 'boot\.img|rootfs-minimal\.(z[0-9]+|zip)$' sha256sums.txt | sha256sum -c -
```

On Windows, you may instead right-click extract first and optionally compare
individual downloaded files with PowerShell:

```powershell
Get-FileHash .\nixos-sheng-*-rootfs-minimal.zip -Algorithm SHA256
```

Replace `rootfs-minimal` with `rootfs-gnome` when using the GNOME image.

Do not flash `boot_a`; it is kept for Android. Do not flash `userdata`.

## Expand the rootfs filesystem

The ext4 filesystem inside the rootfs image can be smaller than the dedicated
`linux` partition. A matching boot image expands it automatically from Mobile
NixOS stage-1 before the first rootfs mount, so the first boot may take longer.

After booting, check:

```sh
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
df -h /
```

If the filesystem is still much smaller than the `linux` partition, automatic
expansion did not complete. Do not repeatedly run `resize2fs` on the mounted
root filesystem. Enter TWRP and run it while `linux` is unmounted:

```sh
adb shell
ls -l /dev/block/by-name/linux
umount /dev/block/by-name/linux 2>/dev/null || true
e2fsck -f /dev/block/by-name/linux
resize2fs /dev/block/by-name/linux
reboot
```

See [`linux-partition-resize.md`](linux-partition-resize.md) for details and
risk boundaries.

## Updates and rollback

Ordinary stage-2 NixOS configuration can create, switch, and roll back
generations with `nixos-rebuild`. Kernel, DTS, stage-1 initrd, and boot
command-line updates still require flashing a new `boot_b`.

Keep the previous boot and rootfs images. If the new system does not boot,
enter Fastboot or TWRP and flash the previous `boot_b`. Flashing an older
rootfs replaces local NixOS generations and data inside the `linux` partition,
so back up important files first.
