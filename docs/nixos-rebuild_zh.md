# 更新已安装的 NixOS 系统

[English](nixos-rebuild.md) | [简体中文](nixos-rebuild_zh.md)

刷入的 Android `boot_b` 镜像是 sheng 固定的启动基础。它包含 kernel、DTB、
Mobile NixOS stage-1 initrd 和 boot 命令行。普通 NixOS 世代只更新可写
`linux` 分区上的 stage-2。

创建多个世代前，先确认 ext4 文件系统已经使用完整 `linux` 分区：

```sh
df -h /
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
```

当前 sheng kernel/文件系统组合不支持在线扩容。请在文件系统未挂载时，从 TWRP
或其他救援环境按 [`linux-partition-resize.md`](linux-partition-resize.md)
执行。

flake 暴露了与可刷 rootfs 镜像相同的 Mobile NixOS 求值：

| Configuration | 桌面 | 对应 rootfs 输出 |
| --- | --- | --- |
| `sheng` | 可选 minimal GNOME | `mobileRootfsImageGnome` |
| `sheng-stage2` | minimal GNOME，不构建 boot 内核 | 设备内 `nixos-rebuild` |
| `sheng-minimal` | 不绑定桌面的 console 平台 | `mobileRootfsImage` |

这很重要，因为单独的普通 `nixosSystem` 求值可能选择不同的 kernel module tree，
或遗漏 sheng 硬件服务。

私有 dotfiles 仓库应使用公开的 Mobile NixOS 构造器：

```nix
nixosConfigurations.sheng =
  nixos-sheng.lib.aarch64-linux.mkShengSystem [
    ./hosts/sheng/configuration.nix
  ];
```

该构造器提供完整、不绑定桌面的 sheng 平台，但不会创建用户、注入凭据、安装
GNOME，或安装本仓库的 Home Manager 配置。用户、凭据和个人配置应放在下游
dotfiles 仓库中。只有明确想使用本仓库 GNOME profile 时才使用
`mkShengGnomeSystem`。

## 第一次安全测试

在平板上克隆仓库并只构建、不激活：

```sh
git clone https://github.com/DotRedstone/nixos-sheng
cd nixos-sheng

sudo nixos-rebuild build --flake ./nixos#sheng-stage2
```

仓库 flake 位于 `nixos/` 子目录中。因此远程 flake URI 必须使用 `dir=nixos`；
推荐先克隆仓库。

Release 分支应包含 `nixos/flake.lock`，避免平板上重新求值并下载大型 inputs。

切换前检查结果：

```sh
readlink -f result
readlink -f /run/current-system
readlink -f result/kernel-modules 2>/dev/null || true
readlink -f /run/current-system/kernel-modules 2>/dev/null || true
```

测试新世代，但不设为启动默认值：

```sh
sudo nixos-rebuild test --flake ./nixos#sheng-stage2
```

确认网络、桌面和硬件服务后，再设为默认 stage-2 世代：

```sh
sudo nixos-rebuild switch --flake ./nixos#sheng-stage2
```

## 世代与回滚

列出已安装系统世代：

```sh
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

回滚默认 profile 并激活选中的 stage-2 世代：

```sh
sudo nix profile rollback --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

这个纯 flake 流程不依赖旧式 NixOS channels 或 `<nixpkgs/nixos>`。sheng 启动世代
菜单也可以在启动时选择 stage-2 世代，但不能选择不同的 kernel 或 stage-1 世代。

通过非交互 ADB shell 检查世代时，关闭 pager：

```sh
PAGER=cat nix-env --profile /nix/var/nix/profiles/system --list-generations
```

## 固定 boot 边界

`sheng-stage2` 不会构建或写入 Android boot 分区，并继续使用 boot 镜像提供、
复制到 `/lib/modules` 的模块。以下内容变化仍需要构建
`mobileAndroidBootimg` 并刷入 `boot_b`：

- kernel 或 kernel configuration
- DTS / DTB
- Mobile NixOS stage-1 initrd
- boot 命令行

不要把 `nixos-rebuild` 成功当成这些 boot 侧修改已经安装的证据。不要刷
`userdata`。

## 配置归属

本仓库负责硬件集成、启动行为、固件、rootfs 布局和平台服务。私有下游 flake
负责用户、凭据、个人系统软件包和可选 Home Manager 配置。

仓库构建的测试镜像仍会通过 `nixos/profiles/default-user.nix` 包含一次性默认用户；
公开构造器不会创建用户。
