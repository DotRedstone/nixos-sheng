# Sheng 双系统安装指南

[English](install-dualboot.md) | [简体中文](install-dualboot_zh.md)

本文适用于在 Xiaomi Pad 6S Pro 12.4（`sheng`）上保留 Android，并将
Mobile NixOS 安装到槽位 `b` 和独立 `linux` 分区。

操作分区前必须备份数据。创建 `linux` 分区需要删除并重建 `userdata`，
会清空 Android 用户数据。后续刷写和系统更新不要刷 `userdata`。

## 前置条件

- bootloader 已解锁
- 已安装可用的 TWRP 或其他救援环境
- 已下载本项目同一版本的 boot 与 rootfs 镜像
- 电脑已安装 `adb` 和 `fastboot`
- 已备份 Android 用户数据和重要文件

## 创建 linux 分区

本节参考
[`sheng-pmos-builds` 的 Dual Boot 安装流程](https://github.com/alghiffaryfa19/sheng-pmos-builds#dual-boot)。
该项目在仓库根目录提供了可在 TWRP 中运行的
[`parted`](https://github.com/alghiffaryfa19/sheng-pmos-builds/blob/10c023a01fbeb8ac3ccb83e48eb4b58b6bad6dac/parted)。

在电脑上下载该工具，然后进入 TWRP 并推送到设备：

```sh
curl -L -o parted \
  https://raw.githubusercontent.com/alghiffaryfa19/sheng-pmos-builds/10c023a01fbeb8ac3ccb83e48eb4b58b6bad6dac/parted
adb reboot recovery
adb push parted /sdcard/parted
```

以下操作会删除并重建 `userdata`。继续前再次确认 Android 用户数据已经备份。
进入 TWRP shell，先确认 `sda` 确实是包含 `userdata` 的磁盘：

```sh
adb shell
readlink -f /dev/block/by-name/userdata
ls -l /dev/block/sda
chmod +x /sdcard/parted
/sdcard/parted /dev/block/sda
```

`readlink` 的结果必须指向 `/dev/block/sda` 上的某个分区，例如常见的
`/dev/block/sda29`。如果指向其他磁盘，停止操作并使用实际磁盘路径。

在 `parted` 交互界面中切换为 GB，并打印完整布局和空闲空间：

```text
unit GB
print free
```

必须记录 `userdata` 的分区编号、起点和终点。sheng 常见布局中
`userdata` 是分区 29，新建的 `linux` 是分区 30，但不同容量或已有改动的设备
可能不同。不要未经确认直接照抄编号或起点。

下面只是 256GB 设备的布局示例。分界位置应根据设备容量和希望保留给 Android
的空间调整。示例保留 `userdata` 原本的 `12.7GB` 起点，在 `180GB` 处分界：

```text
rm 29
mkpart userdata ext4 12.7GB 180GB
mkpart linux ext4 180GB -0MB
print free
quit
```

确认新布局中：

- `userdata` 使用原本记录的起始位置
- `linux` 使用剩余空间
- 两个分区没有重叠，末尾没有意外的大块未分配空间
- 没有修改 boot、super、persist 或其他分区

退出 `parted` 后，确认 TWRP 已建立 `linux` 分区设备节点。若节点未出现，先重启
一次 TWRP 再检查，不要继续刷写：

```sh
ls -l /dev/block/by-name/userdata
ls -l /dev/block/by-name/linux
exit
adb reboot bootloader
```

重新创建 `userdata` 会清空 Android 用户数据，并且可能需要在 TWRP 中格式化
`userdata` 后才能重新进入 Android。不要格式化新建的 `linux` 分区；刷写 rootfs
镜像会覆盖它。

## 刷写 release

Release rootfs 会以分卷 ZIP 发布，方便 Windows 用户直接使用 Bandizip、
7-Zip、WinRAR 等图形解压工具。请下载同一个 rootfs 版本的所有分卷，例如：

```text
nixos-sheng-v0.1.2-kernel-7.0.0-rootfs-minimal.z01
nixos-sheng-v0.1.2-kernel-7.0.0-rootfs-minimal.z02
nixos-sheng-v0.1.2-kernel-7.0.0-rootfs-minimal.zip
```

把所有分卷放在同一个文件夹，打开最后的 `.zip` 文件并解压，得到可直接刷入的
`.img`。然后刷写槽位 `b` 和 `linux`：

```sh
fastboot erase dtbo_b
fastboot flash boot_b nixos-sheng-*-boot.img
fastboot flash linux nixos-sheng-*-rootfs-minimal.img
fastboot --set-active=b
fastboot reboot
```

GNOME 镜像将命令中的 `rootfs-minimal` 换成 `rootfs-gnome`。解压得到的
`.img` 才是传给 `fastboot flash linux` 的文件。

可选：刷写前下载 `sha256sums.txt`。请仅筛选并校验已下载的 boot 与 rootfs
版本，避免未下载的另一个 rootfs 版本被报告为文件缺失：

```sh
grep -E 'boot\.img|rootfs-minimal\.(z[0-9]+|zip)$' sha256sums.txt | sha256sum -c -
```

Windows 用户也可以先直接右键解压；如果想单独校验某个下载文件，可用 PowerShell：

```powershell
Get-FileHash .\nixos-sheng-*-rootfs-minimal.zip -Algorithm SHA256
```

使用 GNOME 镜像时，将命令中的 `rootfs-minimal` 替换为 `rootfs-gnome`。

校验可以发现下载损坏，但不是刷写命令的必需步骤。

不要刷 `boot_a`，它用于保留 Android。不要刷 `userdata`。

## 扩展 rootfs 文件系统

rootfs 镜像中的 ext4 文件系统小于 `linux` 分区。匹配的 boot 镜像会在首次挂载
rootfs 前通过 Mobile NixOS stage-1 自动扩展 ext4 文件系统，因此首次启动可能
耗时更长。

启动后检查：

```sh
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
df -h /
```

如果文件系统仍明显小于 `linux` 分区，说明自动扩容未完成。不要在已挂载的根
文件系统上反复运行 `resize2fs`；请进入 TWRP，在 `linux` 未挂载时执行：

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
