# Expanding the linux filesystem

[English](linux-partition-resize.md) | [简体中文](linux-partition-resize_zh.md)

The dedicated `linux` partition may be much larger than the ext4 filesystem
inside a flashed rootfs image. NixOS generations need enough free filesystem
space even when the partition table already reserves sufficient space.

Check both sizes from NixOS:

```sh
df -h /
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
```

On the tested device, the `linux` partition was about 77.7 GiB while the ext4
filesystem was about 10 GiB. Online `resize2fs` failed because the filesystem
was mounted.

Current boot images enable Mobile NixOS stage-1 automatic resizing. Before
mounting the root filesystem, stage-1 compares the ext4 filesystem size with
the `linux` partition, runs `e2fsck`, and expands the filesystem when needed.
After flashing a matching boot image and rootfs, the first boot may take
longer while this completes.

Verify after the first boot:

```sh
df -h /
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
```

Use the following rescue procedure only if automatic resizing did not complete.

## TWRP or rescue procedure

Boot TWRP or another rescue environment. Confirm the path before running any
filesystem command:

```sh
ls -l /dev/block/by-name/linux
```

Unmount the filesystem if the rescue environment mounted it, then check and
expand it:

```sh
umount /dev/block/by-name/linux 2>/dev/null || true
e2fsck -f /dev/block/by-name/linux
resize2fs /dev/block/by-name/linux
```

Reboot into NixOS and verify:

```sh
df -h /
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
```

Do not format `linux`, do not modify `userdata`, and do not run `resize2fs` on
an unverified device path. Keep a current rootfs image available for recovery.
