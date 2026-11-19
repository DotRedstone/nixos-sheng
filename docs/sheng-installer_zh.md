# Sheng RAM 安装器（实验性）

适用于已解锁、已有 `linux` 和 `linux-boot` 的 Xiaomi Pad 6S Pro 12.4（`sheng`）。
安装器沿用 RAM 恢复环境，可由 ABL Fastboot 临时启动。电脑通过 ADB 传输文件，平板端无需进入 TWRP。
`plan` 只读。缺少目标分区时会列出未分配空间并停止。本版的写入目标是已有的两个 Linux 分区，
分区表、Android A 槽、`userdata`、`super` 与设备校准分区均受保护。

## 准备同一构建的文件

用 ARM64 构建器从同一 revision 构建 `shengInstallerBootimg`、`mobileRootfsImage`（或 GNOME 版本）
与 `shengUbootEfiEsp`。把安装器 boot 镜像单独保存，并将原始 ext4 `rootfs.img` 与 `esp/`
文件树放入同一目录。在该目录生成 `SHA256SUMS`，或使用发行产物提供的清单：

```sh
sha256sum rootfs.img esp/manifest.sha256 > SHA256SUMS
```

电脑需要 Python 3.11+、ADB、Fastboot、`debugfs`、`dosfstools` 和 `mtools`。
安装器检查清单、ARM64 EFI 文件、DTB 和 rootfs 中的 NixOS 内核闭包。安装包从可信来源获取。

## 预览与安装

替换命令中的设备序列号。`plan` 可在当前 NixOS 或 RAM 恢复环境运行：

```sh
python3 scripts/sheng-installer.py plan ./bundle --adb-serial ADB_SERIAL
```

从已连接的 ABL Fastboot 开始安装：

```sh
python3 scripts/sheng-installer.py install ./bundle \
  --adb-serial ADB_SERIAL --fastboot-serial FASTBOOT_SERIAL \
  --recovery-image ./sheng-installer.img --backup-dir ./sheng-install-backup
```

已进入专用 RAM 环境时可省去两个 Fastboot 参数。已有 ext4 根分区时先另行备份 Linux 数据，再加
`--replace-linux`。安装器要求在电脑终端输入包含目标 PARTUUID 的确认文本。原 ESP 先备份到电脑，
新 EFI 文件合入副本并读回校验，现有 Android 配置和其他 EFI 条目保留。随后先写入并校验 rootfs，
再写入并校验 ESP。发生中断后，重新进入 RAM 安装器检查两分区，保留电脑上的备份。

本版 U-Boot 的安装和启用仍按已适配的 [B 槽流程](uboot-efi-experiment_zh.md) 单独执行。ESP 备份
只恢复 EFI 文件与配置，原 Linux 文件需从独立备份恢复。对其他发行版的扩展沿用
[社区 Linux EFI 条目约定](community-linux-efi-entry_zh.md)。

## 验证范围

```sh
nix build ./nixos#checks.x86_64-linux.shengStorageInstallerHost
```

主机检查覆盖目标布局、挂载保护、安装包校验以及 FAT 镜像内现有 Android 配置和其他条目的保留。
实机还需完成新 RAM 镜像临时启动、写入与读回校验、U-Boot 启动 NixOS 和中断后恢复。
