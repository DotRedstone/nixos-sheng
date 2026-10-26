# Sheng 统一引导界面与多系统路线图

> 状态：长期架构目标与实机验收顺序。当前 U-Boot / EFI 候选只验证了 NixOS 启动；菜单条目不等于操作系统已适配。

## 目标体验

平板每次正常开机先进入一致的引导界面：同一套显示、实体键操作、默认项、倒计时、错误提示和恢复入口，从中选择已经验证可启动的系统。界面负责选择；各系统由独立的启动适配器负责装载和交接。离线充电、恢复键与 ABL fastboot 保留独立的救援路径，不能被界面故障阻断。

```text
Android ABL / B 槽
    └── U-Boot UEFI → 统一界面
                     ├── NixOS 世代 → EFI Linux + DTB + initrd → linux rootfs
                     ├── 其他 Linux → 各自的 EFI 内核/引导器 → 独立 rootfs
                     ├── Android → 待实现的设备专属交接
                     └── Windows on Arm → 待验证的 UEFI/ACPI/驱动栈

音量加 + 电源键 → 设备现有 TWRP；ABL fastboot → 原 boot_b 备份恢复
```

界面只展示已安装且通过预检的条目。每项都要有载荷版本、存储位置、完整性检查、启动失败后的恢复方式和可验证的默认项。不能因发现某个 `.efi` 文件或分区，就宣称其系统可用。菜单项数量可扩展，但实际可用系统仍受存储、固件接口、驱动、更新机制和设备适配限制。

## 现有证据

设备由 Android ABL 选择 A/B 槽。A 槽保留 Android 启动分区，B 槽的稳定路径是 Mobile NixOS；实验 U-Boot 可替换 B 槽的 boot 镜像，读取独立的 `linux-boot` ESP，再通过 systemd-boot 选择 NixOS 世代。当前 7.3.0 候选已通过 B 槽持久启动、普通重启、关机插墙充、断开电源冷启动、音量加加电源键进入 TWRP 及刷回稳定镜像的实机验证。插墙充时先显示 U-Boot 日志，随后进入电池画面；当前仍只有 NixOS EFI 条目。

设备上只读检查表明，Android A 槽有 v4 格式的 `boot_a`、`vendor_boot_a`、`init_boot_a`，以及 `dtbo_a` 和 `vbmeta_a`。A/B 元数据将 A 标记为 bootable、successful，但这不能证明 Android 现状可启动。检查前已将 A 槽关键启动分区与 `misc` 在主机私有目录备份，并逐项比较设备和备份的 SHA-256；未改写 A 槽或 `userdata`。

## 系统适配边界

| 目标 | 当前状态 | 下一项可验证结果 |
| --- | --- | --- |
| NixOS 世代 | EFI 菜单、内核 7.3.0 与现用 rootfs 已实机启动 | 保持更新、回退和离线充电路径稳定 |
| 第二个 Linux | 未安装，不能把另一个 NixOS 世代算作独立系统 | 使用单独 rootfs 与适配 Sheng 的内核/DTB/initrd 完成一次可回退启动 |
| Android A 槽 | 启动镜像和槽位只读检查完成，尚未实际启动 | 在保留 B 槽恢复路径下验证进入 Android、从 Android 返回 B 槽 |
| Android 统一菜单入口 | 未实现 | 单独证明从菜单选择后正确装载 Android v4 启动链，且下次开机仍能返回统一界面 |
| Windows on Arm | 未评估这台设备的 Windows 启动与驱动 | 先审计 UEFI 服务、ACPI 表、启动存储和 Arm64 驱动，再考虑 Windows PE 启动探针 |
| 原版 iOS / iPadOS | 不列为 Sheng 可交付系统 | Apple 的启动信任链和系统设计依赖 Apple 硬件；不以菜单图标暗示支持 |

### Android：槽位入口与直接入口

最早可验证的 Android 入口是 ABL A/B 槽位切换：A 槽进入 Android，B 槽进入 U-Boot 和 NixOS。切到 A 后，ABL 直接启动 Android，B 槽的统一界面不会出现；因此这只能是过渡阶段。Android 的 A/B 元数据还承担更新与失败回退，`set_active` 会改变成功和重试状态，不能把槽位切换伪装为无副作用的一次性菜单选择。正式提供此方式前，必须实测 A 槽启动、从 Android 返回 B 槽，以及失败时通过 ABL fastboot 恢复。[Android A/B 实现说明](https://source.android.com/docs/core/ota/ab/ab_implement)

真正一致的每次开机界面需要从 B 槽 U-Boot 直接交接 Android，或证明等价的安全返回机制。该设备的 Android v4 启动链使用独立的 `vendor_boot`、`init_boot`、DTB/DTBO、bootconfig 和 AVB；还要处理恢复模式与 Android 更新后镜像的变化。U-Boot 通用 Android boot image 支持不足以证明这些设备专属输入已正确组合。该路径必须独立实现、先 RAM 验证，再进行有备份的实机验收。[Android 启动分区说明](https://source.android.com/docs/core/architecture/partitions/generic-boot)、[U-Boot Android 启动镜像](https://docs.u-boot.org/en/stable/android/boot-image.html)

### 其他 Linux 与 Windows on Arm

其他 Linux 可复用统一界面的 EFI 入口，但每个系统需要自己的适配 Sheng 的内核、DTB、initrd、模块和固件，规划独立或明确共享的根文件系统，并验证更新及回退。`linux-boot` ESP 目前只承担 EFI 引导载荷；不得把 Android `userdata`、`super` 或固件分区改作 Linux 存储。

Windows on Arm 对固件的要求超出“能运行一个 EFI 程序”：需检查 UEFI 启动与运行时服务、图形和存储协议、ACPI 描述、启动所需设备和原生 Arm64 驱动。当前 U-Boot/Linux 的 DTB 启动成功不能推出 Windows 可启动。应先做不写分区的固件能力审计，再尝试 Windows PE；完整安装须等启动链和驱动有独立证据。[Microsoft UEFI 要求](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/uefi-requirements-that-apply-to-all-windows-platforms)、[Windows on Arm 设备制造与驱动](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/arm64-device-manufacturing)

### iOS / iPadOS

原版 iOS / iPadOS 的启动链以 Apple SoC 的 Boot ROM 为硬件信任根，并逐级验证 Apple 签名组件；它不是可直接放进这台 Qualcomm 平板 ESP 的通用 EFI 系统。项目不把“在 Sheng 上安装原版 iOS/iPadOS”列为可交付能力，也不在菜单中展示虚假的可启动项。若研究相似的交互体验，应明确使用其他合法可移植系统的名称。[Apple 平台启动安全说明](https://support.apple.com/guide/security/boot-process-for-ipad-and-iphone-devices-secb3000f149/web)、[Apple iOS/iPadOS 软件许可](https://www.apple.com/legal/sla/docs/iOS26_iPadOS26.pdf)

## 开发与验收顺序

1. 维持当前 NixOS EFI 启动、离线充电、冷启动、TWRP 与 `boot_b` 回退路径；改进插墙充时可见的 U-Boot 日志。
2. 定义统一界面的条目清单和启动适配器边界，实机验证 U-Boot 的图形输出、实体键输入及失败返回；选择或实现一个 EFI 前端。界面仅列已验证条目。
3. 准备第二个 Linux 的独立 rootfs 和完整载荷，先临时启动，再验证更新、断电冷启动及回退。这是首个真正跨发行版的统一界面验收。
4. 保持 B 槽稳定镜像和主机备份可用，验证 Android A 槽实际启动及双向返回；之后单独开发可从统一界面选择的 Android 交接。
5. 对 Windows on Arm 先做固件/ACPI/驱动差距审计和可回退的 Windows PE 探针，再决定是否有完整安装条件。

每一步分别记录：源码预期、构建结果、设备画面、进入的系统、失败时的实际恢复路径。新系统通过这些检查后才成为默认可见菜单项；任何阶段都不刷 `userdata`。
