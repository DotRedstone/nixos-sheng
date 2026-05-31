[🇨🇳 简体中文](README_zh.md) | [🇬🇧 English](README.md)

# nixos-xiaomi-sheng

Xiaomi Pad 6S Pro 12.4 (`sheng`, Qualcomm SM8550) 的实验性 Mobile NixOS 移植项目。

本仓库仅提供 NixOS 设备移植。当前维护的刷机路径是基于 Mobile NixOS 的 Android 启动流程：编译一个 `boot.img` 刷入非活动（inactive）的 Android slot，以及一个由 Mobile NixOS 生成的 ext4 rootfs 镜像刷入专门分配的 `linux` 分区。

## 当前状态

这是一个早期的 bring-up 项目。

| 领域 | 状态 | 备注 |
| --- | --- | --- |
| 设备框架 | Mobile NixOS | 设备定义位于 `nixos/devices/xiaomi-sheng` |
| 内核 | Sheng mainline kernel | 通过 Nix 从 `map220v/sm8550-mainline` 构建 |
| 启动镜像 | Bring-up | 面向 `boot_b` 的 Mobile NixOS Android boot image |
| RootFS | Mobile NixOS 生成的 rootfs | 面向 `linux` 分区的 ext4 镜像 |
| 显示/终端 | Bring-up | 在显示正常工作前，Stage-1 暂为无头 (headless) 运行 |
| 调试访问 | Bring-up | Stage-1/stage-2 的 ADB 已通过 Mobile NixOS 启用 |

## 上游项目

- [mobile-nixos/mobile-nixos](https://github.com/mobile-nixos/mobile-nixos)
  提供设备框架、stage-1 initramfs、Android boot image 构建器、生成的 rootfs 支持、USB gadget 设置以及设备移植约定。
- [map220v/sm8550-mainline](https://github.com/map220v/sm8550-mainline)
  提供 Xiaomi Pad 6S Pro 的主线内核支持。

内核源码在 `nixos/flake.nix` 中配置：

```nix
shengKernelSrc.url = "github:map220v/sm8550-mainline/sheng-7.0";
```

## 启动原理

平板仍然像 Android 设备一样启动。

```text
Android bootloader
  -> boot_b / boot.img
       -> sheng kernel
       -> sm8550-xiaomi-sheng.dtb
       -> Mobile NixOS stage-1 initramfs
            -> 挂载 /dev/disk/by-partlabel/linux
            -> 读取 nix-path-registration
            -> 切换到选定的 NixOS 系统闭包

linux 分区
  -> Mobile NixOS 生成的 ext4 rootfs
       -> nix/store
       -> nix-path-registration
```

这里的 rootfs 镜像故意没有采用标准的 PC 风格根目录。对于 Mobile NixOS 生成的 rootfs 而言，顶层只有 `nix/store` 和 `nix-path-registration` 是正常的现象：stage-1 会使用这些注册数据来寻找 NixOS 系统闭包并运行其 `init`。

## 仓库结构

```text
.
|-- .github/workflows/
|   |-- kernel.yml          # 构建 Mobile NixOS Android boot image
|   `-- nixos-rootfs.yml    # 构建 Mobile NixOS rootfs image
|-- nixos/
|   |-- devices/xiaomi-sheng/
|   |   |-- default.nix     # Mobile NixOS 设备定义
|   |   `-- kernel/
|   |       |-- default.nix # 用于 sheng 内核的 Nix kernel builder
|   |       `-- config.aarch64
|   |-- patches/            # 小型 stage-1 bring-up 补丁
|   |-- flake.nix
|   |-- configuration.nix
|   |-- hardware-sheng.nix
|   |-- mobile-profile.nix
|   `-- services/
|-- scripts/
|   `-- inspect-bootimg.sh  # 离线的 boot.img/initrd 检查辅助脚本
`-- build-nixos-rootfs.sh
```

## 使用 GitHub Actions 构建

打开 Actions 标签页并在 `sheng` 分支上运行以下工作流：

- `Build Sheng Kernel`：构建 `boot_sheng_nixos.img`。
- `Build NixOS RootFS`：构建可刷入的 `nixos-sheng-*.img`。

对于测试构建，请保持开启 `Skip GitHub release`，这样工作流就只会上传产物而不会发布 Release。

## 本地构建

本地构建需要一个启用了 Nix flakes 的 aarch64 Linux 环境。

当需要刷新 inputs 时更新 flake lock：

```bash
nix flake lock ./nixos
```

构建 boot image：

```bash
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
```

构建可刷入的 Mobile NixOS rootfs 镜像：

```bash
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
```

将所有面向 fastboot 的 Mobile NixOS 镜像输出到一个目录中：

```bash
nix build ./nixos#mobileFastbootImages -o out/mobile-fastboot
```

构建并将 rootfs 镜像复制到 `out/nixos-sheng-*.img`：

```bash
./build-nixos-rootfs.sh
```

保留了 `fullRootfsImage` 作为旧命令的兼容别名。它与 `mobileRootfsImage` 指向同一个 Mobile NixOS 生成的 rootfs。

## 刷机指南

对于插槽 `b` 的双启动测试，请将 Android 保留在另一个插槽，并仅刷入非活动插槽的 boot 镜像以及专用的 `linux` rootfs 分区：

```bash
fastboot erase dtbo_b
fastboot flash boot_b out/mobile-bootimg
fastboot flash linux out/nixos-sheng-YYYYMMDD_HHMMSS.img
fastboot --set-active=b
fastboot reboot
```

如果您直接使用 `nix build ./nixos#mobileRootfsImage` 构建了 rootfs，需要刷入的文件是生成的 `rootfs.img`：

```bash
fastboot flash linux out/mobile-rootfs/rootfs.img
```

如果 stage-1 代码或 Android 启动配置发生了变化，请重新构建并刷入 `boot_b`。如果只有 NixOS userspace/rootfs 发生了变化，请重新构建并刷入 `linux`。

不要刷入 `userdata`。固件、软件包、systemd 单元、用户和其他 rootfs 内容都位于 `linux` 分区；仅刷入 `boot_b` 并不会更新 `/lib/firmware`。

## 固件、USB-C 与 OTG

sheng 上的 USB-C 主机模式依赖于最终 Mobile NixOS rootfs 中存在的 Qualcomm remoteproc 固件。有关完整的依赖链、离线 rootfs 检查、运行时验证命令以及常见的故障特征，请参阅 [docs/sheng-firmware-and-usbc.md](docs/sheng-firmware-and-usbc.md)。

## 调试

ADB 通过 `mobile.adbd.enable` 启用。在成功的过渡期间，stage-1 的 ADB 可能会在 stage-2 接管 USB gadget 设置时短暂断开。

要离线检查生成的 boot image：

```bash
scripts/inspect-bootimg.sh out/mobile-bootimg
```

该辅助脚本会打印 `/etc/boot/config`、initrd applets 以及关键的启动标志（如 `boot_as_recovery`、`splash.disabled`、rootfs 挂载设置和 USB 特性）。

## 默认登录

当前的 bring-up 镜像保留了简单的凭据：

- 用户名：`luser`
- 密码：`luser`
- root 密码：`123456`

在发布供一般使用的镜像前请更改这些凭据。

## 警告

这是一个底层的设备移植项目。刷入 boot 镜像、更改活动插槽以及写入分区都有可能导致平板变砖或丢失数据。请备份所有内容，并假设每条命令都是危险的，直到在您自己的设备上验证通过。
