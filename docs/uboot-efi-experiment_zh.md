# Sheng 的 U-Boot / EFI 实验

> 状态：实验性。本仓库构建的完整 Sheng U-Boot 基线已从独立 EFI ESP 实机引导 NixOS；它不是 release 镜像。

## 已确认的启动边界

当前验证中的 B 槽使用：`ABL -> U-Boot -> systemd-boot -> EFI Image -> Mobile NixOS stage-1 -> stage-2`。
稳定回退路径仍是：`ABL -> Android boot_b -> Mobile NixOS stage-1 -> stage-2`。EFI 的 Type #1 条目管理固定的内核、DTB 与 stage-1；普通 NixOS stage-2 代际继续由现有 generation 菜单管理。

2026-10-11 的实机复验确认，`fastboot boot` 可以作为 RAM-only 验证通道：当前候选在不写入
`boot_b` 的情况下进入 U-Boot、EFI runtime、stage-1 与 stage-2，且 ADB/USB gadget 正常枚举。持久
启动验收仍须在备份后刷入 `boot_b` 并进行冷启动、回退和关机充电测试。`boot_a` 原本是 Android header v4，
而 NixOS/U-Boot 使用 Android header v0；不要将该 v0 镜像刷入 `boot_a`。

本仓库的镜像在 U-Boot 阶段枚举为：

```text
USB: 18d1:4ee0
Manufacturer: U-Boot
Product: USB download gadget
Host node: /dev/ttyACM0
```

本次实测的本仓库镜像 SHA-256 为
`ace4caa74df60600ce9f799ac260743030999a24eca3b8e0bc4d077580167231`；试验后已将已知可启动的
Mobile NixOS boot 镜像（SHA-256
`def3f8d2d3219d64e660f1c848d59e13371ab6102596dd8832ac5b65c7370160`）保留为 ABL fastboot 回退物。

同一基线的只读 fastboot 探针也已完成实机验证。它启动后由主机返回
`version: 0.4` 与 `product: xiaomi-sheng`，证明 U-Boot 的 fastboot 协议可用。探针禁用
`CONFIG_FASTBOOT_FLASH`，不能写任何分区；同时它拒绝 `fastboot reboot bootloader`，因此恢复时必须手动进入
Android ABL fastboot，再刷回已知可启动的 `boot_b` 镜像。

## 从 Linux 进入 ABL fastboot

内核的 `nvmem-reboot-mode` 已声明 `bootloader` 重启原因，但普通 `reboot`、`systemctl reboot` 和
`adb reboot bootloader` 不会可靠传递该原因。rootfs 提供下列命令，它通过 Linux
`RESTART2("bootloader")` 直接触发 Qualcomm reboot-mode 驱动：

```bash
sudo sheng-reboot-bootloader
```

该命令立即重启到 ABL fastboot，不会写入 `boot_a`、`boot_b`、`linux`、GPT、`userdata`、基带或其他
Android 固件分区。实机已确认执行后主机直接枚举 fastboot 设备。

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

## 已接入的 EFI 载荷更新路径

`services.sheng-uboot-efi` 现在向 rootfs 安装 `sheng-efi` 工具和
`sheng-efi-mark-successful.service`。它与普通 `nixos-rebuild` 明确隔离：
后者只切换 stage-2 generation，绝不改变 ESP 上的内核、DTB、stage-1 initrd 或默认 EFI 条目。

构建新的、不可变的 ESP 文件树后，使用 root 身份显式安装：

```bash
nix build ./nixos#shengUbootEfiEsp -o result/sheng-efi-esp
sudo sheng-efi install "$PWD/result/sheng-efi-esp/esp"
sudo sheng-efi status
```

安装器只接受含完整 `manifest.sha256` 的 `shengUbootEfiEsp/esp` 树，并确认 `/boot` 是
PARTLABEL 为 `linux-boot` 的 FAT ESP。它先把新的版本化目录
`EFI/NixOS/sheng-<kernel-version>-<payload-hash>/`、BLS 条目和 systemd-boot 写入临时目录，再逐文件校验；
新载荷全部存在后才用重命名切换 `loader.conf` 的默认项。旧 BLS 条目和旧内核/initrd/DTB 不会被删除，
旧 `loader.conf` 会保存在 `/var/lib/sheng-efi/previous-loader.conf`。

如果还没有重启，或者在仍可进入 stage-2 时决定撤销默认项：

```bash
sudo sheng-efi rollback
sudo sheng-efi status
```

成功到达 `multi-user.target` 后，`sheng-efi-mark-successful.service` 会记录当时配置的 EFI 默认项和时间。
它是运行时健康记录，不能单独证明用户没有从 systemd-boot 菜单手动选择旧条目；它不会自动清理旧载荷，也不会修改 Android 分区。

`uefi_a`、`uefi_b`、`rescue`、`userdata` 与 Android 固件分区仍不可复用，也没有被写入。接下来仍需单独验证
systemd-boot 菜单交互、恢复键、关机充电和从 ABL fastboot 回退稳定 `boot_b`；在这些路径分别验证前，实验分支不得合并或发布。
实际分区边界和验收记录见 [存储迁移预案](uboot-efi-storage-plan_zh.md)。
