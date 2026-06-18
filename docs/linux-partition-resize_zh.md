# 扩展 linux 文件系统

[English](linux-partition-resize.md) | [简体中文](linux-partition-resize_zh.md)

专用 `linux` 分区可能远大于刷入 rootfs 镜像中的 ext4 文件系统。即使分区表
已经预留了足够空间，NixOS 世代仍然需要文件系统本身有足够可用空间。

在 NixOS 中同时检查文件系统和分区大小：

```sh
df -h /
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
```

在已测试设备上，`linux` 分区约 77.7 GiB，而 ext4 文件系统约 10 GiB。
由于文件系统已挂载，在线 `resize2fs` 会失败。

当前 boot image 已启用 Mobile NixOS stage-1 自动扩容。在挂载根文件系统前，
stage-1 会比较 ext4 文件系统大小和 `linux` 分区大小，运行 `e2fsck`，并在
需要时扩展文件系统。刷入匹配的 boot image 和 rootfs 后，首次启动可能会因为
扩容而更久。

首次启动后验证：

```sh
df -h /
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
```

只有在自动扩容没有完成时，才使用下面的救援流程。

## TWRP 或救援环境流程

启动 TWRP 或其他救援环境。执行任何文件系统命令前，先确认路径：

```sh
ls -l /dev/block/by-name/linux
```

如果救援环境已经挂载该文件系统，先卸载，然后检查并扩容：

```sh
umount /dev/block/by-name/linux 2>/dev/null || true
e2fsck -f /dev/block/by-name/linux
resize2fs /dev/block/by-name/linux
```

重启进入 NixOS 后验证：

```sh
df -h /
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
```

不要格式化 `linux`，不要修改 `userdata`，不要在未确认的设备路径上运行
`resize2fs`。请保留当前 rootfs 镜像以便恢复。
