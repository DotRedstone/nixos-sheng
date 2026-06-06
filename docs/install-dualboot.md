# Sheng 双系统安装指南

本文适用于在 Xiaomi Pad 6S Pro 12.4（`sheng`）上保留 Android，并将
Mobile NixOS 安装到槽位 `b` 和独立 `linux` 分区。

操作分区前必须备份数据。创建 `linux` 分区需要删除并重建 `userdata`，
会清空 Android 用户数据。后续刷写和系统更新不要刷 `userdata`。

## 前置条件

- bootloader 已解锁
- 已安装可用的 TWRP 或其他救援环境
- 已下载本项目同一版本的 boot 与 rootfs 镜像
- 电脑已安装 `adb`、`fastboot` 和 `zstd`
- 已备份 Android 用户数据和重要文件

## 创建 linux 分区

进入 TWRP，并将可用的 `parted` 推送到设备：

```sh
adb reboot recovery
adb push parted /sdcard/parted
adb shell
chmod +x /sdcard/parted
/sdcard/parted /dev/block/sda
```

先使用 `print` 确认 `userdata` 的编号和起止位置。sheng 常见布局中
`userdata` 是分区 29，新建的 `linux` 是分区 30，但不要未经确认直接照抄编号。

下面只是 256GB 设备的布局示例。分界位置应根据设备容量和希望保留给 Android
的空间调整：

```text
print
rm 29
mkpart userdata ext4 12.7GB 180GB
mkpart linux ext4 180GB -0MB
print
quit
```

确认新布局中：

- `userdata` 保留正确的起始位置
- `linux` 使用剩余空间
- 没有修改 boot、super、persist 或其他分区

退出 shell 并进入 bootloader：

```sh
exit
adb reboot bootloader
```

## 刷写 release

校验并解压 release 文件：

```sh
sha256sum -c sha256sums.txt
zstd -d sheng-*-rootfs-*.img.zst
```

刷写槽位 `b` 和 `linux`：

```sh
fastboot erase dtbo_b
fastboot flash boot_b sheng-*-boot.img
fastboot flash linux sheng-*-rootfs-*.img
fastboot --set-active=b
fastboot reboot
```

不要刷 `boot_a`，它用于保留 Android。不要刷 `userdata`。

## 扩展 rootfs 文件系统

rootfs 镜像中的 ext4 文件系统小于 `linux` 分区。首次启动后先检查：

```sh
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
df -h /
```

可以先尝试在线扩容：

```sh
sudo resize2fs /dev/sda30
```

如果命令成功，再使用 `df -h /` 确认容量。如果出现下面的错误，不要反复执行：

```text
reserved block ... not at offset ...
Invalid argument While trying to add group
```

当前候选镜像在实机上触发了该 ext4 在线扩容错误。此时进入 TWRP，在 `linux`
未挂载时执行：

```sh
adb shell
ls -l /dev/block/by-name/linux
umount /dev/block/by-name/linux 2>/dev/null || true
e2fsck -f /dev/block/by-name/linux
resize2fs /dev/block/by-name/linux
reboot
```

详细说明与风险边界见
[`linux-partition-resize.md`](linux-partition-resize.md)。

## 更新与回滚

普通 stage-2 NixOS 配置可以在系统内使用 `nixos-rebuild` 创建、切换和回滚世代。
kernel、DTS、stage-1 initrd 和 boot cmdline 更新仍需重新刷写 `boot_b`。

保留上一版本的 boot 和 rootfs 镜像。无法启动时可进入 Fastboot/TWRP，重新刷入
上一版本的 `boot_b`；恢复旧 rootfs 会覆盖 `linux` 分区中的本地系统世代和数据。
