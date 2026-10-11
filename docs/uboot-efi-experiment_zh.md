# Sheng 的 U-Boot / EFI 实验

> 状态：实验性。本仓库构建的完整 Sheng U-Boot 基线已从独立 EFI ESP 实机引导 NixOS；它不是 release 镜像。

## 已确认的启动边界

稳定系统仍使用：`ABL -> Android boot_b -> Mobile NixOS stage-1 -> stage-2`。
长期目标为：`ABL -> U-Boot -> systemd-boot -> NixOS`，由标准 EFI 启动项管理系统代际。

本次实机诊断得到两条重要结论：

- `fastboot boot` 不是这台设备的有效验证通道：连已知可启动的 Mobile NixOS `boot_b` 镜像也会回到 ABL fastboot，不能据此判断 U-Boot 是否运行；
- `boot_a` 原本是 Android header v4，而 NixOS/U-Boot 使用 Android header v0。把 v0 U-Boot 镜像放入 `boot_a` 会回到 ABL fastboot；这不代表 U-Boot 失败。

有效的验证路径是：备份两个 boot 槽，只临时替换 `boot_b`，设置 B 为活动槽后冷启动，并观察 U-Boot 输出。本仓库的镜像已在该路径上枚举为：

```text
USB: 18d1:4ee0
Manufacturer: U-Boot
Product: USB download gadget
Host node: /dev/ttyACM0
```

本次实测的本仓库镜像 SHA-256 为
`ace4caa74df60600ce9f799ac260743030999a24eca3b8e0bc4d077580167231`；试验后已将已知可启动的
Mobile NixOS boot 镜像（SHA-256
`def3f8d2d3219d64e660f1c848d59e13371ab6102596dd8832ac5b65c7370160`）刷回 `boot_b`。设备重新进入内核
`7.1.8`，且 `sheng-mark-boot-successful.service` 将 B 槽标记成功。

同一基线的只读 fastboot 探针也已完成实机验证。它启动后由主机返回
`version: 0.4` 与 `product: xiaomi-sheng`，证明 U-Boot 的 fastboot 协议可用。探针禁用
`CONFIG_FASTBOOT_FLASH`，不能写任何分区；同时它拒绝 `fastboot reboot bootloader`，因此恢复时必须手动进入
Android ABL fastboot，再刷回已知可启动的 `boot_b` 镜像。

## EFI 存储启动实测

2026-10-11 已完成第一次存储启动验证。`linux-boot` ESP 中的载荷包含标准
`EFI/BOOT/BOOTAA64.EFI`、systemd-boot Type #1 菜单、未压缩的 EFI-stub `Image`、initrd 与 Sheng DTB。
载荷构造在原生 ARM CI 中通过 AA64 PE/COFF、FAT32 文件布局和读回验证；随后又从当前已验证的稳定
`boot_b` 提取同一内核、initrd 与 DTB，在主机独立完成 FAT32 读回，并在设备 ESP 上逐文件 SHA-256 复核。

使用 SHA-256 为 `ace4caa74df60600ce9f799ac260743030999a24eca3b8e0bc4d077580167231` 的实验 U-Boot
`boot_b` 后，设备进入 NixOS stage-2。内核日志确认：

```text
efi: EFI v2.11 by Das U-Boot
Kernel command line: initrd=\EFI\NixOS\sheng-7.1.8\initrd ...
fb0: EFI VGA frame buffer device
```

根目录继续由 `/dev/disk/by-partlabel/linux` 挂载为 ext4，`/sys/firmware/efi` 存在，ESP GPT 与文件
清单均通过校验，`systemctl --failed` 为空，`sheng-mark-boot-successful.service` 为 active。随后普通
`systemctl reboot` 也重新回到 EFI runtime 和 stage-2；重新启动后的正常重启标记已被消费。

这证明目标链 `ABL → U-Boot → systemd-boot → EFI Image → stage-1 → stage-2` 可用。`boot_a`、
Android `userdata`、`super`、基带与其他固件分区没有写入。

## 当前基线

`shengUbootAndroidBootimg` 固定官方 U-Boot `v2026.10-rc5` 的带签名标签提交
`a06e89ab05eaa2b8344d521319399333cd760ae5`，生成 Android boot header v0：

- `u-boot-nodtb.bin` 用 `gzip -n` 压缩，随后拼接同次构建的 Sheng DTB；
- 使用已验证的偏移和 4 KiB 页：kernel `0x00008000`、ramdisk `0x01000000`、tags `0x01e00000`；
- `CONFIG_TEXT_BASE=0x80000000`，避免 ARM64 Image header 的 text offset 溢出；
- 开启 Sheng UFS、PM8550B eUSB2、USB ACM、EFI、FAT、按键和 ABL framebuffer hand-off；
- 禁用 UEFI capsule 与 U-Boot fastboot 分区写入，固件只读取 EFI 载荷，不会写 Android 槽位或 GPT；
- 构建时核对 Android header、gzip 载荷、DTB、ramdisk、页对齐及 192 MiB `boot_b` 上限。

构建命令：

```bash
nix build ./nixos#shengUbootAndroidBootimg \
  -o out/sheng-u-boot-experimental-boot_b.img
```

离线验收至少应确认：

```bash
file out/sheng-u-boot-experimental-boot_b.img
sha256sum out/sheng-u-boot-experimental-boot_b.img
```

最终 DTB 必须包含：

- SM8550 UFS 与 UniPro 75/150/300 MHz 时钟/分频路径；
- PM8550B eUSB2 repeater 和其生命周期处理；
- USB2 peripheral 模式、`qcom,select-utmi-as-pipe-clk` 与 USB configuration NoC clock；
- 3048x2032、ARGB8888 的 ABL splash framebuffer hand-off；
- USB ACM 恢复控制台、音量按键和 EFI/FAT 启动环境。

## 补丁来源与维护方式

`nixos/patches/u-boot/sheng-baseline/` 是对公开的
[`dianqk/nixos-android-devices`](https://github.com/dianqk/nixos-android-devices)
commit `8f29bfc02bb3a8d03c4545eff1296a9ce6656337` 的可审计基线导入：每个 patch 保留原始作者、
版权、来源链接与本地说明。它们仍以官方 U-Boot 为构建上游，而不是把第三方二进制纳入本仓库。

其中 Linux 衍生的改动保留各自的 Linux 来源和许可证信息；本地 U-Boot 适配继续遵循
GPL-2.0-or-later。后续修改必须保持单一硬件职责，不能把 UFS、USB、显示和 EFI 的新问题混入
同一 patch。

## 实机验证流程

只在 B 槽执行，并始终保留 A 槽 Android recovery 与 B 槽 NixOS 备份：

```bash
# 先记录状态和备份；不要刷 userdata。
fastboot getvar current-slot
fastboot getvar slot-successful:a
fastboot getvar slot-successful:b
fastboot flash boot_b out/sheng-u-boot-experimental-boot_b.img
fastboot set_active b
fastboot reboot
```

验证主机端是否出现 U-Boot USB device 和 `/dev/ttyACM*`。若失败，进入 Android fastboot 后立刻回退：

```bash
fastboot flash boot_b /path/to/known-good-mobile-nixos-boot.img
fastboot set_active b
fastboot reboot
```

`boot_a`、`linux`、GPT 与 `userdata` 不属于当前实验写入范围。关机充电也继续由现有 Mobile NixOS
stage-1 路径负责；在 U-Boot 正常启动、EFI 存储、热重启、恢复键、回退和关机充电均分别验证前，
不得发布或合并此实验分支。

## 下一阶段

独立的 `linux-boot` FAT32 ESP 已在 RAM recovery 中创建并验收，U-Boot 也已从其引导 EFI 载荷。
`uefi_a`、`uefi_b`、`rescue`、`userdata` 与 Android 固件分区仍不可复用，也没有被写入。

下一步是让 NixOS generation 更新以受控方式更新 ESP 中的 Type #1 条目，并单独验证 systemd-boot 菜单交互、
恢复键、关机充电和从 ABL fastboot 回退稳定 `boot_b`。在这些路径分别验证前，实验分支不得合并或发布。
实际分区边界和验收记录见 [存储迁移预案](uboot-efi-storage-plan_zh.md)。
