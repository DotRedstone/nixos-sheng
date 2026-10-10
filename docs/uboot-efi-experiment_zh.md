# Sheng 的 U-Boot / EFI 实验

> 状态：实验性。当前分支只建立可复现的编译预检，**不产生、也不能刷写** U-Boot
> Android boot 镜像。

## 目标与边界

当前稳定路径保持不变：`ABL -> Android boot_b -> Mobile NixOS stage-1 -> stage-2`。
长期目标是将普通启动演进为：`ABL -> U-Boot -> systemd-boot -> NixOS`，使系统代际
可以由标准 EFI 启动项管理。

离线充电不是这条链路的附带功能。当前的圆润电池界面运行在 Mobile NixOS stage-1；
若 U-Boot 接管普通启动，必须为关机充电定义独立的状态机、退出条件和恢复路径后，
才能替换现有路径。

本实验不会修改 `boot_a`、`boot_b`、`linux`、`userdata` 或 GPT，也不会改变发布镜像。

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

## 设备支持必须逐项实现

任何可启动的 Sheng U-Boot 必须在独立提交中实现并审计以下内容：

1. Sheng boot DTS：板级身份、按键、UFS reset GPIO 和 PM8550B USB 接线。
2. SM8550 UFS：UniPro 时钟、分频器和 UFS 依赖链。
3. USB gadget：PM8550B eUSB2 repeater 与 USB2 pipe clock；先验证串口/网络恢复通道。
4. ABL framebuffer：只在 RAM boot 证实图像地址、尺寸和显示生命周期后接入。
5. Android v0 envelope：只有设备 DTS 和恢复路径都验证后才生成；先 `fastboot boot`，
   不直接写入 `boot_b`。
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
| 编译预检 | 上述两个 Nix 构建成功 | 生成或刷写 Android 镜像 |
| RAM boot | USB 恢复通道、串口、UFS 探测和按键可重复验证 | 写入 `boot_b` |
| EFI 原型 | 标准 ESP 上能加载一个已知 EFI 程序并回到 recovery | 改动现有 `linux` 数据 |
| 持久化候选 | 多次冷启动、普通重启、恢复键和关机充电均可回退 | 覆盖 `boot_a` 或刷写 `userdata` |
