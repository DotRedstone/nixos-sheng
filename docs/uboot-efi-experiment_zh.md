# Sheng 的 U-Boot / EFI 实验

> 状态：实验性。当前分支提供一个经过离线结构校验的 Android v0 **RAM-boot 候选**；
> 它不是稳定刷机包，必须先用 `fastboot boot` 在设备上证明 ABL 能加载它。

## 目标与边界

当前稳定路径保持不变：`ABL -> Android boot_b -> Mobile NixOS stage-1 -> stage-2`。
长期目标是将普通启动演进为：`ABL -> U-Boot -> systemd-boot -> NixOS`，使系统代际
可以由标准 EFI 启动项管理。

离线充电不是这条链路的附带功能。当前的圆润电池界面运行在 Mobile NixOS stage-1；
若 U-Boot 接管普通启动，必须为关机充电定义独立的状态机、退出条件和恢复路径后，
才能替换现有路径。

本实验不会自动修改 `boot_a`、`boot_b`、`linux`、`userdata` 或 GPT，也不会改变发布镜像。
所有持久化刷写都留给设备验证通过后的明确操作；本仓库当前只生成候选文件。

## 第一阶段：上游编译预检

`shengUbootEfiPreflight` 固定到官方 U-Boot `v2026.10-rc5` 的带签名标签提交
`a06e89ab05eaa2b8344d521319399333cd760ae5`。它使用 `qcom_defconfig` 和
`board/qualcomm/qcom-phone.config`，并确认如下 EFI 能力进入最终配置：

- `CONFIG_EFI_LOADER`
- `CONFIG_CMD_BOOTEFI`
- `CONFIG_CMD_PART`
- `CONFIG_CMD_FAT`
- `CONFIG_FS_FAT`

构建命令：

```bash
# 在常见 x86_64 开发机上交叉编译 AArch64 固件。
nix build ./nixos#packages.x86_64-linux.shengUbootEfiPreflight --no-link
nix build ./nixos#checks.x86_64-linux.shengUbootEfiPreflight --no-link

# 在 AArch64 构建机上可使用项目的原生发布属性。
nix build ./nixos#packages.aarch64-linux.shengUbootEfiPreflight --no-link
```

结果中只有 `README.md` 和 `NOT_FLASHABLE`。二进制留在内部依赖中，以免被误当成
fastboot 目标。这个预检只证明工具链和上游 EFI 配置可构建，**不证明 Sheng 能启动**。

第二个预检会在上游树上应用本仓库的最小 Sheng DTS，确认最终 DTB 选择了
`qcom/sm8550-xiaomi-sheng`、正确声明了设备身份并保留 ABL splash 内存：

```bash
nix build ./nixos#packages.x86_64-linux.shengUbootEfiShengDtsPreflight --no-link
```

它同样只输出 `NOT_FLASHABLE`。该预检还会编译 SM8550 UFS UniPro 的 75/150/300 MHz
时钟路径；寄存器、频率和分频值独立来自本项目固定 Linux 内核的 `gcc-sm8550.c`，补丁中
保留来源。它证明源代码可编译，**不确认 UFS、USB 或显示能在设备上工作**。

## 第二阶段：Android boot RAM-boot 候选

`shengUbootAndroidBootimg` 将已审计的 Sheng U-Boot 组合为 Android boot header v0：

- `u-boot-nodtb.bin` 使用可重复的 `gzip -n` 压缩，随后拼接同一构建产出的原始 Sheng DTB；
- 空 gzip ramdisk 仅用于满足 Android boot 容器；它不含 NixOS rootfs、initrd 或用户数据；
- 使用当前稳定 Sheng Android boot 的偏移和 4 KiB 页大小：kernel `0x00008000`、ramdisk
  `0x01000000`、tags `0x01e00000`；
- 将 U-Boot `CONFIG_TEXT_BASE` 固定为 `0x80000000`，避免从 Android envelope 进入时 ARM64
  text offset 溢出；
- 在构建中解析 header，逐字节核对 gzip U-Boot、紧随其后的 DTB、ramdisk、地址、页大小和
  `boot_b` 的 192 MiB 上限。

在常见 x86_64 构建机上生成候选：

```bash
nix build ./nixos#packages.x86_64-linux.shengUbootAndroidBootimg \
  -o out/sheng-u-boot-experimental-boot_b.img
file out/sheng-u-boot-experimental-boot_b.img
sha256sum out/sheng-u-boot-experimental-boot_b.img
```

候选首先只能进行非持久化验证：

```bash
fastboot boot out/sheng-u-boot-experimental-boot_b.img
```

这一步需要观察 U-Boot 是否能稳定显示或通过 USB 恢复，并确认它能枚举 UFS。当前上游
Qualcomm phone environment 会先 `scsi scan`，再执行标准 `bootefi bootmgr`；真正进入
NixOS 还需要一个独立规划的 GPT FAT ESP，提供 `EFI/BOOT/BOOTAA64.EFI`。现有 `linux`
rootfs 分区不是这个 ESP，本实验不会创建或修改 GPT。

**禁止在 RAM boot 尚未成功前执行 `fastboot flash boot_b`。** Android header 与字节结构
正确只说明该文件可交给 fastboot/ABL 测试，不能证明 ABL 接受压缩 U-Boot、UFS 可用、EFI
可启动，或关机充电与回退链路安全。

## 设备支持必须逐项实现

任何可启动的 Sheng U-Boot 必须在独立提交中实现并审计以下内容：

1. Sheng boot DTS：板级身份、按键、UFS reset GPIO 和 PM8550B USB 接线。
2. SM8550 UFS：UniPro 时钟、分频器和 UFS 依赖链。
3. USB gadget：PM8550B eUSB2 repeater 与 USB2 pipe clock；先验证串口/网络恢复通道。
4. ABL framebuffer：只在 RAM boot 证实图像地址、尺寸和显示生命周期后接入。
5. Android v0 envelope：本分支已生成并离线校验候选；仍须先 `fastboot boot`，不直接写入
   `boot_b`。
6. EFI 存储：规划一个标准 GPT FAT ESP（例如 `linux-boot`）并让 EFI 加载
   `EFI/BOOT/BOOTAA64.EFI`。这一步会改分区表，必须在单独的、获明确授权的操作中执行。
7. 持久化：保留 `boot_a` 和独立 Android 格式 RAM recovery；确认反复冷启动、普通重启、
   按键恢复和关机充电后，才考虑写入 `boot_b`。

## 来源与许可证

本分支使用官方 U-Boot 源码（GPL-2.0-or-later）作为基础。它不复制
`dianqk/nixos-android-devices` 的补丁或打包逻辑。后续若研究该项目公开补丁，只能把它们
当作线索；每一项都要回溯到上游 Linux/U-Boot 或自行实现，保留作者、来源、许可证和
本地改动说明。任何来自 U-Boot 或 Linux 的衍生修改都应按其 GPL 要求公开相应源码。

## 验收顺序

| 阶段 | 通过条件 | 禁止事项 |
| --- | --- | --- |
| 编译预检 | 上述两个 Nix 构建成功 | 声称设备可启动 |
| Android 候选 | header、载荷和分区上限在构建中逐项通过 | 直接写入 `boot_b` |
| RAM boot | USB 恢复通道、串口、UFS 探测和按键可重复验证 | 写入 `boot_b` |
| EFI 原型 | 标准 ESP 上能加载一个已知 EFI 程序并回到 recovery | 改动现有 `linux` 数据 |
| 持久化候选 | 多次冷启动、普通重启、恢复键和关机充电均可回退 | 覆盖 `boot_a` 或刷写 `userdata` |

## Sheng 启动 DTS 的来源映射

预检确认上游 U-Boot 有 SM8550 的通用参考板，却没有 Sheng。下一阶段的 DTS 必须从
本项目锁定的内核树逐项裁剪，而不是复制完整 Linux 板级 DTS：

- 内核来源：`DotRedstone/linux-sheng` 的
  `c4b27e2cec1371e166f443877812639d4d0d33da`，文件
  `arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dts`。
- 板级身份：`model = "Xiaomi Pad 6S Pro 12.4"` 和
  `compatible = "xiaomi,sheng", "qcom,sm8550"`。
- 恢复按键：PM8550 GPIO 6 的音量上键。U-Boot 只需要这个明确的恢复输入；不携带
  Hall、触摸、相机、音频或桌面硬件节点。
- UFS：`ufs_mem_hc` 的 reset GPIO 210，以及 `vcc`、`vccq`、`vdd-hba` 供电引用；
  相应 UniPro 时钟和分频器仍须在 U-Boot 驱动中单独实现。
- USB gadget：`pm8550b_eusb2_repeater` 的 L15B 1.8 V / L5B 3.1 V 供电，以及
  `usb_1_hsphy` 到 repeater 的连接。完整 USB-C、DP、PMIC GLINK 策略不在首个
  RAM boot 范围内。

该 Linux DTS 文件标注为 `BSD-3-Clause`。后续若移植其中的节点，补丁头会记录此来源、
原作者和被保留的最小节点；U-Boot 驱动侧的新增或改写仍遵循 U-Boot 的 GPL-2.0-or-later
要求。每个驱动链路（UFS、USB、framebuffer）各自独立提交与测试。
