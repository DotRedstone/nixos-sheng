# Sheng 统一引导界面与多系统路线图

> 状态：长期架构目标与实机验收顺序。NixOS 已正常启动，Alpine 与 Debian 已完成短时独立 rootfs 探针；菜单条目不等于完整系统适配。

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

设备由 Android ABL 选择 A/B 槽。A 槽保留 Android 启动分区，B 槽的稳定路径是 Mobile NixOS；实验 U-Boot 可替换 B 槽的 boot 镜像，读取独立的 `linux-boot` ESP，再通过 systemd-boot 选择 NixOS 世代。当前 7.3.0 候选已通过 B 槽持久启动、普通重启、关机插墙充、断开电源冷启动、音量加加电源键进入 TWRP 及刷回稳定镜像的实机验证。插墙充时不再显示 U-Boot 图标或日志，短暂白屏后进入电池画面；当前仍只有 NixOS EFI 条目。

现用 `sheng-uboot.env` 在正常路径先加载 systemd-boot，U-Boot 自带 `bootmenu` 仅在 EFI 启动失败后提供诊断与恢复命令，因此当前还不是一个覆盖所有系统的顶层界面。U-Boot 的 `bootmenu` 使用 ANSI 终端菜单；若最终界面采用图形方式，应先验证本机 EFI 图形输出与实体键输入，再选择或实现统一的 EFI 前端，而不是仅给诊断菜单增加系统名称。[U-Boot bootmenu 说明](https://docs.u-boot.org/en/stable/usage/cmd/bootmenu.html)

Android A 槽有 v4 格式的 `boot_a`、`vendor_boot_a`、`init_boot_a`，以及 `dtbo_a` 和 `vbmeta_a`。2026-10-26 从 B 槽经 ABL fastboot 切至 A 槽后，ADB 报告 Android 16、`_a` 槽、`sys.boot_completed=1`，图形服务运行；随后从 Android ADB 返回 ABL fastboot、切回 B 槽，重新进入非 EFI 的 NixOS 7.3.0。B 槽完整哈希与测试前备份一致，A 槽关键启动分区也与私有备份一致；未刷写 A 槽、`linux` 或 `userdata`。本次证明槽位切换可用，不证明 Android 能从 B 槽 U-Boot 菜单直接启动。

显示交接修复已固定在 `linux-sheng` 提交 `125eb0c`，本仓库内核输入也固定到该提交。组合诊断版连续两次未见白闪；最终干净版一次未见白闪、一次未看清。当前默认 EFI 内核的哈希与干净版测试载荷不同，因此当前设备默认项尚不能作为无白闪发布基线。干净版载荷与 manifest 保存在本机备份中；持久使用前须同时提供匹配的 rootfs 内核模块，并复测正常启动、充电与恢复键路径。

## 系统适配边界

| 目标 | 当前状态 | 下一项可验证结果 |
| --- | --- | --- |
| NixOS 世代 | EFI 菜单、内核 7.3.0 与现用 rootfs 已实机启动 | 保持更新、回退和离线充电路径稳定 |
| Alpine 3.24.3 | 独立 ext4 rootfs 的 `/init` 在平板以 PID 1 运行，随后返回 NixOS | 验证完整服务、交互、设备支持及长期安装 |
| Debian 13 | 官方 arm64 最小用户态的独立 ext4 rootfs 已以 PID 1 运行，随后返回 NixOS | 验证完整服务、交互、设备支持及长期安装 |
| 更多 Linux 发行版 | 尚未实机启动；不能把另一个 NixOS 世代算作独立系统 | 使用单独 rootfs 与适配 Sheng 的内核/DTB/initrd 完成可回退启动 |
| Android A 槽 | Android 16 启动完成，ADB 回到 fastboot 后已切回 B 槽 NixOS | 继续验证可从统一菜单直接选择 Android，且返回机制可靠 |
| Android 统一菜单入口 | RAM 探针已装载 A 槽镜像并到达 `booti` 交接，随后复位回 NixOS；Android 尚未启动 | 取得早期内核或固件日志，定位复位原因，再验证菜单启动与返回机制 |
| Windows on Arm | 未评估这台设备的 Windows 启动与驱动 | 先审计 UEFI 服务、ACPI 表、启动存储和 Arm64 驱动，再考虑 Windows PE 启动探针 |
| 原版 iOS / iPadOS | 不列为 Sheng 可交付系统 | Apple 的启动信任链和系统设计依赖 Apple 硬件；不以菜单图标暗示支持 |

### Android：槽位入口与直接入口

已验证的 Android 入口是 ABL A/B 槽位切换：A 槽进入 Android，B 槽进入 NixOS，实验时也可进入 U-Boot。切到 A 后，ABL 直接启动 Android，B 槽的统一界面不会出现；因此这只是过渡路径。Android 的 A/B 元数据还承担更新与失败回退，`set_active` 会改变成功和重试状态，不能把槽位切换伪装为无副作用的一次性菜单选择。本次已实测 A 槽启动与经 ABL fastboot 返回 B 槽；未验证 Android 启动失败时的自动回退。[Android A/B 实现说明](https://source.android.com/docs/core/ota/ab/ab_implement)

真正一致的每次开机界面需要从 B 槽 U-Boot 直接交接 Android，或证明等价的安全返回机制。该设备的 Android v4 启动链使用独立的 `vendor_boot`、`init_boot`、DTB/DTBO、bootconfig 和 AVB；还要处理恢复模式与 Android 更新后镜像的变化。U-Boot 通用 Android boot image 支持不足以证明这些设备专属输入已正确组合。该路径必须独立实现、先 RAM 验证，再进行有备份的实机验收。[Android 启动分区说明](https://source.android.com/docs/core/architecture/partitions/generic-boot)、[U-Boot Android 启动镜像](https://docs.u-boot.org/en/stable/android/boot-image.html)

2026-11-01 的只读 RAM 探针已从 UFS 读到 A 槽 `boot`、`vendor_boot`、`init_boot` 和 `dtbo`，前两者的头部与备份逐字节一致；U-Boot 完成 DTB 6 与 DTBO 47 的准备，阶段标记到达 `bootm go`。设备随后重新进入 B 槽 NixOS，未观察到 Android 启动完成。对齐内核入口、保留原厂 DTB `/chosen/bootargs` 的两项对照均未改变结果；后者导出的最终 `bootargs` 已确认含原厂 DTB 与 `vendor_boot` 参数。实验没有写入 `boot_b`、A 槽或 `userdata`；`boot_b` 整分区摘要保持不变。当前应检查传给 Android 内核的最终 FDT、ramdisk/bootconfig 和内存布局，不能把 `bootm go` 视为 Android 启动成功。

同日后续探针核对了 v4 镜像的 vendor ramdisk、`init_boot` 通用 ramdisk 与 bootconfig 拼接结果，并发现 ABL 传入的启动参数超过 U-Boot 原有的 512 字节命令缓冲区；实验版已将其增至 4096 字节。一次测试的默认 `bootcmd` 误设为只启动 NixOS，相关回退结果不作为 Android 交接证据。修正后，带 ABL 动态参数的 A 槽启动到达 `booti`，导出的参数含 `init=/init`、`rootwait` 与修正后的 `_a` 槽位；分别使用 A 槽 DTBO 和已保存的原生 Recovery 交接树仍复位回 NixOS。原生 Recovery 树有 `/hypervisor` 节点，B 槽 ABL 交给 U-Boot 的树没有，但目前不能据此断定复位原因。实验只刷写过 `boot_b`，随后已恢复测试前的完整镜像，整分区 SHA-256 与备份一致；A 槽、`linux` 和 `userdata` 未刷写。下一步需要取得早期内核或固件日志，并核对 ABL 在两种启动路径下的交接状态，不能继续仅凭返回 NixOS 推断故障位置。

再将 ABL 动态参数与 `vendor_boot_a` 的 DTB 6、`dtbo_a` 覆盖层 47 组合，由可复现的 Nix RAM 镜像启动，阶段仍到 `booti_go` 后返回 NixOS。`rawdump` 有一份旧 TWRP panic；重跑探针前后其前 1 MiB 哈希相同，不能用作本轮故障日志。B 槽 `vendor_boot_b` 的 v4 头部与 A 槽一致，但将 U-Boot 临时封装成 v4 `boot.img` 后，`fastboot boot` 返回成功而设备停在 ABL fastboot，未到 U-Boot 阶段。ABL UEFI 日志报告 `kernel image does not have appended DTB` 和 `Device Tree blob not found`；直接附加 DTB 6、先补齐 U-Boot ARM64 Image 声明的 `image_size` 再附加，两项对照仍得到同样错误。设备随后重启回 B 槽 NixOS，`boot_b` 整分区哈希仍与备份一致。v4 镜像格式与 ABL 的 DTB 定位规则需要单独分析，不能把 fastboot 的 `Booting OKAY` 视为 U-Boot 已执行。

B 槽 `vendor_boot_b` 与 A 槽完整镜像哈希一致，而原 `dtbo_b` 全为零。备份两处分区后，临时将 A 槽 DTBO 写入 `dtbo_b`，并将 U-Boot 封装为 v4 镜像写入 `boot_b`；该组合已正常启动 NixOS。早期直接交接 Android 的探针到达 `booti_go` 后，ABL 耗尽 B 槽重试并自动切到 A 槽；Android ADB 随后出现只证明原生 A 槽启动。`rawdump` 记录了逐项修复的 Android 第一阶段故障：重复 `androidboot.hardware` 导致 bootconfig 解析失败；去掉重复项后缺少启动设备参数，找不到 `/dev/block/by-name/super`；补齐启动设备后，AVB 状态缺失导致 `/system` 挂载失败。当前探针沿用 ABL 交给 U-Boot 的设备树及 `/hypervisor`，并补入本机的启动设备、分区和验证状态参数。一次自动直启测试中，屏幕进入 Android；随后 Fastboot 报告当前槽仍为 B，未发生此前的 A 槽回退。双系统 U-Boot 菜单已分别进入 NixOS 与可操作的 Android 桌面；菜单直启 Android 后 Fastboot 再次报告 B 槽，排除了 A 槽回退。原厂 `vendor_boot_a` 的 bootconfig 已含 USB 控制器参数；重复传入的对照镜像由 `rawdump` 确认出现 bootconfig 重定义错误，已撤销。U-Boot 的 ARM64 跳转清理不会停止 ACM gadget；在 Android 交接前从所有控制台移除 `usbacm` 后，Android ADB 成功枚举并报告 `sys.boot_completed=1`，远程进入 Fastboot 后活动槽位仍为 B。当前 `boot_b` 为 5 秒菜单、默认 NixOS；重启后 NixOS ADB 正常，分区前缀哈希与构建镜像一致。其他 Android 设备功能、OTA 与长期稳定性仍待核验。`dtbo_b` 和硬编码启动参数均属临时测试配置，不能作为公开刷机包。

近期验收顺序：

1. 从显示交接修复构建内核和匹配模块，建立可回退的持久无白闪基线，并目视复测。
2. 为 RAM 探针取得早期内核或固件日志，并比较原生 A 槽与 B 槽 U-Boot 的交接状态；确认复位点后再修改装载路径。
3. Android 直接进入桌面且下次仍回统一菜单后，再加入正式菜单项；最后回归 NixOS、充电和 TWRP 路径。

### 其他 Linux 与 Windows on Arm

其他 Linux 可复用统一界面的 EFI 入口，但每个系统需要自己的适配 Sheng 的内核、DTB、initrd、模块和固件，规划独立或明确共享的根文件系统，并验证更新及回退。`linux-boot` ESP 目前只承担 EFI 引导载荷；不得把 Android `userdata`、`super` 或固件分区改作 Linux 存储。

社区适配使用[Linux EFI 条目约定](community-linux-efi-entry_zh.md)和只读预检器准备临时条目；长期安装仍须逐发行版验证。

`scripts/sheng-build-alpine-initrd-probe.sh` 将 SHA-256 固定的 [Alpine 3.24.3 aarch64 minirootfs](https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/aarch64/) 打包为临时 RAM 探针。首次实机测试确认 Alpine `/init` 执行，写下版本与内核标记后自动返回 NixOS。随后在现有 `linux` 分区内建立独立的 128 MiB ext4 镜像，用相同的设备内核和 DTB 从 EFI 临时条目启动，`switch_root` 后 Alpine 根文件系统中的 `/init` 以 PID 1 写下 `rootfs=alpine`、`version=3.24.3`、`kernel=7.3.0`，再自动返回 NixOS。ESP 默认项、临时条目与 initrd 已恢复或清理，B 槽哈希未变。此结果证明第二套 Linux 用户态及独立根文件系统的短时启动；还不是 Alpine 桌面或长期安装验收。

Debian 使用 [Debian 13 trixie arm64 官方容器镜像](https://github.com/docker-library/official-images/blob/master/library/debian)导出的最小用户态，镜像摘要为 `sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f`。在同一 EFI 内核、DTB 与临时 initrd 下，独立的 256 MiB ext4 镜像完成挂载与 `switch_root`，Debian `/init` 以 PID 1 写下 `rootfs=debian`、`version=13`、`kernel=7.3.0`，随后自动返回 NixOS。两个探针均通过 RAM 启动 U-Boot；临时 ESP 条目和两个 ext4 测试镜像在保存结果后已清理，默认项恢复为 NixOS，B 槽完整哈希仍与可启动备份相同。Debian 服务、图形、硬件与更新机制尚未验证。

`scripts/sheng-build-linux-rootfs-probe-initrd.sh` 将已校验的 Alpine minirootfs 打包为可复用的独立 rootfs 交接 initrd。参数依次为 Alpine 归档、探针 ID 和输出路径；设备端从现有 `linux` 分区读取 `/var/lib/sheng-multiboot/<探针 ID>.img`，只读挂载 ext4 并执行镜像内的 `/init`。镜像内须有可执行的 `/init` 及 `host`、`dev`、`proc`、`sys` 目录；`/init` 负责记录结果及返回。stage 将进度写入同目录下的 `<探针 ID>.stage`，失败时尝试重启。该脚本只生成 initrd，不安装菜单条目、不切换默认项，也不证明新发行版已经实机启动；首次用于某个新 rootfs 前仍需逐项核对 EFI 内核、DTB、镜像来源和回退路径。

Windows on Arm 对固件的要求超出“能运行一个 EFI 程序”：需检查 UEFI 启动与运行时服务、图形和存储协议、ACPI 描述、启动所需设备和原生 Arm64 驱动。当前 U-Boot/Linux 的 DTB 启动成功不能推出 Windows 可启动。应先做不写分区的固件能力审计，再尝试 Windows PE；完整安装须等启动链和驱动有独立证据。[Microsoft UEFI 要求](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/uefi-requirements-that-apply-to-all-windows-platforms)、[Windows on Arm 设备制造与驱动](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/arm64-device-manufacturing)

### iOS / iPadOS

原版 iOS / iPadOS 的启动链以 Apple SoC 的 Boot ROM 为硬件信任根，并逐级验证 Apple 签名组件；它不是可直接放进这台 Qualcomm 平板 ESP 的通用 EFI 系统。项目不把“在 Sheng 上安装原版 iOS/iPadOS”列为可交付能力，也不在菜单中展示虚假的可启动项。若研究相似的交互体验，应明确使用其他合法可移植系统的名称。[Apple 平台启动安全说明](https://support.apple.com/guide/security/boot-process-for-ipad-and-iphone-devices-secb3000f149/web)、[Apple iOS/iPadOS 软件许可](https://www.apple.com/legal/sla/docs/iOS26_iPadOS26.pdf)

## 开发与验收顺序

1. 维持当前 NixOS EFI 启动、离线充电、冷启动、TWRP 与 `boot_b` 回退路径；定位充电和 EFI 交接时的短暂白屏。
2. 定义统一界面的条目清单和启动适配器边界，实机验证 U-Boot 的图形输出、实体键输入及失败返回；选择或实现一个 EFI 前端。界面仅列已验证条目。
3. 在已完成 Alpine 和 Debian 独立 rootfs 短时启动后，继续验证完整服务、设备支持、更新、断电冷启动及回退，形成可长期使用的跨发行版条目。
4. 保持 B 槽稳定镜像和主机备份可用，在已验证 A 槽 Android 启动与手动返回后，单独开发可从统一界面选择的 Android 交接。
5. 对 Windows on Arm 先做固件/ACPI/驱动差距审计和可回退的 Windows PE 探针，再决定是否有完整安装条件。

每一步分别记录：源码预期、构建结果、设备画面、进入的系统、失败时的实际恢复路径。新系统通过这些检查后才成为默认可见菜单项；任何阶段都不刷 `userdata`。
