# Sheng 图形 Live 镜像

Sheng Live 从独立的 `linux-live` 分区启动到 GNOME。内核、设备树、
initramfs、设备固件和 NixOS 系统都在同一张 ext4 镜像内。桌面使用
`live` 用户自动登录，提供触屏键盘、GNOME Console、文件管理器和
NetworkManager。网络配置、下载和 Nix 构建结果保存在该分区。

## 构建

在 AArch64 Linux 上运行，或为 Nix 配置可用的 AArch64 构建器。

```sh
nix build ./nixos#packages.aarch64-linux.shengLiveImage -o out/sheng-live
stat -Lc '%s bytes' out/sheng-live/sheng-live.img
zstd -T0 -6 -o out/sheng-live.img.zst out/sheng-live/sheng-live.img
sha256sum out/sheng-live.img.zst > out/sheng-live.img.zst.sha256
```

`sheng-live.img` 是刷写文件。`.zst` 用于分发。预留空间按解压后的
镜像大小计算。若平板需要拉取大型包闭包或从源码构建，应另外给
`linux-live` 留出足够的空间。首次启动时会把 ext4 扩容到分区末尾。

## 启动

使用 Sheng U-Boot 仓库的 **`liveBootImage`** 构建目标，按该项目
的 B 槽教程备份和刷入。在内部 UFS 的未分配空间中准备唯一的 GPT
分区 `linux-live`。确认它的实际容量足够，并在 ABL Fastboot 中
核对分区大小后刷入。

```sh
fastboot getvar current-slot
fastboot getvar partition-size:linux-live
fastboot flash linux-live out/sheng-live/sheng-live.img
fastboot reboot
```

在 U-Boot 菜单用音量键选 **Boot Sheng Live**，按电源键确认。
该入口读出 `linux-live` 内的 EFI 内核、initramfs 和 DTB。刷写
目标为 `boot_b` 和 `linux-live`。回退时从 U-Boot 菜单选择原系统，
或按 U-Boot 教程还原原 `boot_b`。

## 平板内联网构建

在 GNOME 的快速设置中连网，打开 **Console**，检查根目录、缓存
和剩余空间。以下示例从你自己的 flake 源码目录开始。

```sh
findmnt /
df -h /nix/store
nix store info --store https://cache.nixos.org
nix build nixpkgs#hello --no-link
nix build .#packages.aarch64-linux.shengLiveImage
```

首版验收包含冷启动进入 GNOME、触屏键盘、Wi-Fi、运行 Nix 构建和重启后
读取构建产物。完成实机验收后再登记对应结果。
