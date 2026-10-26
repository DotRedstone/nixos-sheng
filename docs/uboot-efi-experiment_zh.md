# Sheng 的 U-Boot / EFI 实验

> 状态：实验性。U-Boot 已从独立 EFI ESP 引导多个 NixOS 世代，并在 B 槽完成持久启动、关机插墙充、冷启动及恢复键验证；它不是 release 镜像。

## 已确认的启动边界

当前实验链路如下。systemd-boot 是运行在 U-Boot 提供的 EFI 环境中的菜单；每个世代条目共用经过校验的内核、DTB 与 stage-1，并通过 `mobile-nixos.generation=` 选择独立的 stage-2 系统闭包。

```text
ABL fastboot / B 槽
    │
    ├── U-Boot → linux-boot ESP → systemd-boot 世代菜单
    │                                  ├── NixOS Generation 97 → stage-1 → stage-2 #97
    │                                  └── NixOS Generation 98 → stage-1 → stage-2 #98
    │
    └── 刷回备份的 Android boot_b → Mobile NixOS stage-1 菜单 → stage-2
```

实验 EFI 路径不再显示旧的 stage-1 世代菜单；旧 Android boot 镜像保存在主机，供 ABL fastboot 回退。持久启动、音量键短按和长按连续移动、备份镜像刷回、无预写标记的 fastboot 回程、断电冷启动与恢复键均已实机确认。关机插墙充仍短暂显示 U-Boot 日志，且 Android 与其他 Linux 未从 EFI 菜单启动，因此保持实验分支状态。

2026-10-11 的实机复验确认，`fastboot boot` 可以作为 RAM-only 验证通道：候选镜像在不写入
`boot_b` 的情况下进入 U-Boot、EFI runtime、stage-1 与 stage-2，且 ADB/USB gadget 正常枚举。此后已备份并刷入 `boot_b`，完成持久启动及从 Linux 热重启复验。`boot_a` 原本是 Android header v4，
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
`def3f8d2d3219d64e660f1c848d59e13371ab6102596dd8832ac5b65c7370160`）保留为 ABL fastboot 回退物；当时 B 槽写入了实验 U-Boot。这条历史记录不代表设备现用镜像。

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

尚未更新 rootfs 时，可在主机直接运行仓库脚本。它会通过 ADB 传送同一段受控代码，随后等待
ABL fastboot 枚举，因此无需手动按住音量键：

```bash
scripts/sheng-adb-reboot-bootloader.sh
```

`adb reboot bootloader` 是 ADB daemon 的普通重启请求，不能稳定映射为 Linux 的
`RESTART2("bootloader")`；主机包装脚本和 rootfs 命令专门补足这个原因传递。
ABL fastboot 的枚举窗口可能很短。临时启动 U-Boot 时使用主机脚本，先让
`fastboot boot` 等待设备，再触发同一 `RESTART2` 请求：

```bash
scripts/sheng-adb-ram-boot.sh out/sheng-u-boot-experimental-boot_b.img
```

该命令只把镜像送入 RAM，不刷写 `boot_b`。
直接调用 `RESTART2` 不经过 systemd 的 `reboot.target`，因此上述命令会先持久化一次性
`force-normal-once` 标记。设备从 ABL fastboot 执行 `fastboot reboot` 后，stage-1 用该标记
优先选择正常启动，stage-2 随后清除标记。更新 rootfs 前应使用仓库中的主机包装脚本。

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

更新后的 EFI initrd 通过 `mobile-nixos.generation=` 接收菜单选择。实机用临时 U-Boot 分别进入
`system-97-link` 和 `system-98-link`，`/run/current-system` 均与命令行参数对应。随后将个人 GNOME
配置构建为第 99 世代，启动后 `sheng-efi-sync-generations.service`、
`sheng-efi-mark-successful.service` 与清单校验均通过，失败服务为空。将同一 U-Boot 镜像写入
`boot_b` 后，`fastboot reboot` 和 Linux `systemctl reboot` 均重新进入 EFI 与第 99 世代。

2026-10-13 的后续实验将 EFI 载荷更新为 `sheng-7.1.8-117aacafd58af6e7`，并在
`boot_b` 写入 SHA-256 为
`904130c581c7c72b1ba08ccf838f645b65bf0481c837312be9e382ca527020dc` 的 U-Boot 镜像。
该镜像先通过 RAM 引导进入第 99 世代，再通过持久 B 槽重启；两次的失败服务均为 0。
EFI 载荷将动画 VT2 纳入 `fbcon` 映射。实机日志显示动画服务运行约 7 秒，DSI 连接为
`enabled`；该旧载荷的可见画面未单独验收。

新 U-Boot 从 ABL 的 `/chosen/bootargs` 读取 `bootinfo.pureason`，只把启动原因写入临时
`ShengBootReason` EFI 变量。stage-1 在需要时挂载 `efivarfs` 并读取它，继续遵守电源键优先和
正常重启标记。实机 RAM 启动已读取该变量；USB 连接下关机后自动重新上电时，stage-1 读到
`bootinfo.pureason=0x80010`，包含 USB 充电触发位，随后 ADB 断开。使用者随后确认关机充电
的圆角电池画面正常显示；充电功率和长时间稳定性仍需分别验证。电源键长按转入正常系统
已在后续测试中确认。

关机插线时，旧版 EFI 路径会先显示 systemd-boot 世代菜单，等待 `loader.conf` 的 3 秒倒计时，
然后才进入充电目标。新的 U-Boot 候选补丁在 ABL 启动原因的低字节只有 USB 触发位时，
向 systemd-boot 提供仅本次启动有效的 `LoaderConfigTimeout=menu-hidden`。这样充电启动可跳过
世代菜单；普通电源键开机仍按现有配置显示菜单。该变量不写入非易失存储，也不修改 ESP、
`linux` 或 Android 槽位。源码评估、本地交叉构建和 RAM 正常启动进入第 99 世代均已通过；
该次测试尚未确认关机插线的画面顺序；同一功能的后续实测见下文。该次验证时，设备第 99 世代运行旧版
`sheng-reboot-bootloader`，它不会写入正常重启标记；直接用它进入 fastboot 后临时启动，
stage-1 会把混合 USB 原因判为充电启动。手动预写标记后，新候选镜像读取到
`bootinfo.pureason=0x40011`，没有设置隐藏菜单变量，最终进入第 99 世代正常目标；
`systemctl is-system-running` 为 `running`，失败服务为空，标记已消费。此前真实关机插线
读到的原因是 `0x80010`；它的低字节只有 USB 触发位。设备系统下次更新时需同步安装
带标记写入的新版重启脚本。

2026-10-14 的回退测试确认：从 ABL fastboot 将备份 Mobile NixOS 镜像刷回 `boot_b` 后，
设备进入第 99 世代，系统状态为 `running`，失败服务为空；再将实验 U-Boot 刷回 `boot_b`。
这次从旧版主机包装脚本进入 fastboot 后直接 `fastboot reboot`，设备误入关机充电目标，
直到长按电源键才正常启动。原因是包装脚本的直接 `RESTART2` 绕过了 systemd 正常重启标记。
预先写入标记以及使用修订后的包装脚本，两次 `fastboot reboot` 均进入正常系统，标记随之
消费，系统状态为 `running`。

2026-10-15 又从已处于 ABL fastboot 的设备（`current-slot: b`）执行 `fastboot reboot`，
本轮未通过 Linux 重启脚本预写标记。设备进入正常 NixOS stage-2，`/run/sheng-boot-ui.mode` 为 `normal`，
`systemctl is-system-running` 为 `running`，失败服务为空；EFI 变量记录
`bootinfo.pureason=0x800001`。这条无预写标记的 fastboot 回程与上述 Linux `RESTART2` 回程已分别验收。

2026-10-13 将 EFI 动画首帧改为先 blank、绘制后 unblank，并安装
`sheng-7.1.8-2ac6f6483bf104d1` 载荷。它已进入第 99 世代，stage-2 动画服务运行约 7 秒，
GNOME、DSI 和背光状态正常，失败服务为 0。使用者现场确认这次开机动画正常显示。

同日将音量键长按重复补丁加入 U-Boot，按住 400 ms 后以 100 ms 间隔移动。SHA-256 为
`a2039f440da0b879c24bb9117ab90201712bc69a6f03cfaef3beeb08076e3d19` 的 CI 镜像先通过
`fastboot boot` 临时启动并进入第 99 世代；使用者随后确认菜单长按操作正常。将同一镜像写入
`boot_b` 后，设备端读回的镜像前 651264 字节与 CI 产物哈希一致；fastboot 重启再次进入第 99
世代，`systemctl is-system-running` 为 `running` 且失败服务为空。测试期间临时改为 30 秒的
`loader.conf` 超时已按原文件校验值恢复为 3 秒。

这证明目标链 `ABL → U-Boot → systemd-boot → EFI Image → stage-1 → stage-2` 可用。`boot_a`、
Android `userdata`、`super`、基带与其他固件分区没有写入。

2026-10-25 以 PR #51 的 ARM boot 候选（提交 `5acd5a5`，镜像 SHA-256
`5424227afacf8e9d219430ca8985cc409ff594fce5e45b53e54c2c53e7c1099e`）执行
`fastboot boot` 临时启动。主机依次观察到 U-Boot USB gadget、Mobile NixOS stage-1 和
stage-2 ADB；运行内核为 7.1.8，EFI runtime 存在，启动目标为旧 ESP 菜单中的第 99 世代。
设备现用 rootfs 已转为 7.3.0，系统 profile 只有第 1 世代，`/lib/modules` 也只有 7.3.0；
因此该旧 EFI 内核无法加载 vfat 等模块，`/boot` 挂载及多个服务失败。测试后设备已重启回
原有 7.3.0 `boot_b`，分区完整 SHA-256 与测试前备份相同；未安装候选 ESP，也未写入
`boot_b`。该次测试使用的 EFI 载荷仍由 7.1.8 内核构建。

2026-10-26 的 7.3.0 EFI 候选已通过 ARM boot、ESP 和完整 minimal stage-2 CI 构建。
ESP 构建所用内核的 Nix store 路径与设备现用 7.3.0 系统内核不同；相同的版本号不能证明
模块 ABI 或设备树一致。下载的 ESP artifact 已通过 manifest 校验，EFI `Image` 与设备现用
`Image.gz` 解压后逐字节相同；反编译 DTB 后发现设备现用版本比候选多六处
`cirrus,low-pwr-mode-standby` 属性，模块闭包也尚未核对。安装器会在写入 ESP 前拒绝这组
不匹配的载荷，因此它尚未安装到设备，也未用于持久启动。应使用同一构建的 rootfs 与
EFI 载荷配对，或取得内核、设备树和模块的完整等价证据，再继续关机充电画面顺序、
冷启动及恢复键验收。

现用 rootfs 的原始 CI 构建固定 `linux-sheng` 修订 `024eda3`：它以 `9ce9cb0` 为父提交，
只增加上述六处 DTS 属性。实验分支已改用相同的锁定内核来源与构建定义；新的 ESP
候选在本地 Nix 求值中得到与设备完全一致的内核和模块闭包路径。提交 `c69921d` 的
ARM boot、ESP 与完整 minimal stage-2 构建成功；ESP artifact 的 manifest、内核路径、
解压后的 `Image` 和 DTB 均已与设备逐项核对。

同日将该 ESP 载荷安装到 `linux-boot`，并以同提交的 U-Boot 镜像执行 `fastboot boot`
临时启动。随后用 `scripts/sheng-adb-ram-boot.sh` 重复通过同一路径。`bootctl` 报告
`Das U-Boot`、systemd-boot 260.1 和第 1 世代；运行内核为
7.3.0，`/boot` 以 vfat 挂载，stage-2 已进入现用系统。失败服务只有测试前已存在的
`home-manager-luser.service` 与 `logrotate-checkconf.service`。普通重启后设备从原有 B 槽
进入非 EFI 启动链，`boot_b` 完整 SHA-256 与测试前备份相同。ESP 新载荷仍保留供后续
验证；未刷写 `boot_b`、`boot_a`、`linux` 或 `userdata`。

2026-10-26 将最终提交 `9a69964` 的 U-Boot 镜像（SHA-256
`5424227afacf8e9d219430ca8985cc409ff594fce5e45b53e7c1099e`）写入 B 槽。
设备端读回的前 655360 字节与 CI 镜像完全一致。设备从 B 槽持久进入
`Das U-Boot → systemd-boot → EFI Linux 7.3.0 →` 第 1 世代 stage-2；随后一次普通重启
再次进入同一 EFI 链，`/boot` 均以 vfat 挂载。两次启动没有新增失败服务，仍只有测试前
已有的 `home-manager-luser.service` 和 `logrotate-checkconf.service`。之后从 ABL fastboot
刷回原 192 MiB `boot_b` 备份，设备进入非 EFI 的现用 7.3.0 系统；完整 B 槽 SHA-256
恢复为备份值。A 槽、`linux`、`userdata` 和 Android 固件分区没有写入。当前设备保留原
B 槽镜像。该段记录截至首次刷回；同一候选随后再次刷入并完成下述实机验收。

2026-10-26 对同一 boot 镜像再次刷入 B 槽。真实关机、拔掉电脑线并插入墙充后，使用者
现场观察到先显示一段 U-Boot 日志，接着黑屏，最后进入充电电池画面；没有看到 EFI 世代
菜单。拔掉墙充并等待屏幕熄灭后，只按电源键冷启动，出现 EFI 菜单并进入 NixOS。接回
电脑后，`bootctl` 报告 U-Boot UEFI、systemd-boot 260.1 与
`nixos-sheng-generation-1.conf`，内核为 7.3.0。再次关机并用音量加加电源键启动，进入设备
安装的第三方 TWRP；从 TWRP 选择 `Reboot → System` 后返回 EFI/NixOS 第 1 世代。
两次返回 NixOS 后只有测试前已有的两个失败服务。最后从 ABL fastboot 刷回原 192 MiB
`boot_b` 备份，`current-slot: b`，设备从非 EFI 路径进入 7.3.0，完整 B 槽读回 SHA-256 为
`31e4e8bfaa06fedb2e2fa41531b068274d6baafd3ade0886dc279af2a473ae6a`，与备份一致。
这些观察证明本次充电、冷启动与恢复键路径可达；充电启动的 U-Boot 日志仍是可见问题，
充电功率和长时间稳定性没有因此得到证明。

当前 rootfs 只有第 1 世代，旧 7.1.8 EFI 载荷不能作为 7.3.0 的可启动回退项。
`sheng-efi rollback` 已增加写入前的版本/闭包核对，会拒绝这种跨内核回退。新载荷验证
失败时，应使用原有 `boot_b` 返回现用系统，再从备份恢复 ESP 元数据；
不要把旧 EFI 菜单中的第 99 世代视作可用的 rootfs 回滚。

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

`boot_a`、`linux`、GPT 与 `userdata` 不属于当前实验写入范围。关机充电由 Mobile NixOS
stage-1 判定，再交给 stage-2 充电目标。备份 `boot_b` 的刷回与恢复、手动 fastboot 回程均已实测；
断电冷启动和恢复键仍需分别验收。在这些路径验证前，不得发布或合并此实验分支。

## 已接入的 EFI 载荷更新路径

`services.sheng-uboot-efi` 向 rootfs 安装 `sheng-efi`，并通过
`sheng-efi-sync-generations.path` 监听系统 profile 的世代变化。普通 `nixos-rebuild` 只增加或切换 stage-2 世代；同步服务在 ESP 上为现存且内核闭包与 EFI 载荷一致的 `system-N-link` 生成 Type #1 条目，把匹配的 `system` profile 条目设为默认。不匹配的默认世代会使同步失败，已有菜单保持不变。它不会覆盖固定的 EFI 内核、DTB 或 stage-1 initrd。

手动核对或同步菜单：

```bash
sudo sheng-efi sync-generations
bootctl --esp-path=/boot list
sudo sheng-efi status
```

旧版本设备系统尚无该命令时，可以从仓库执行
`sudo bash nixos/scripts/sheng-efi-generations.sh /boot`。同步脚本只接受
PARTLABEL 为 `linux-boot` 的 FAT ESP，先写入世代条目并校验它们引用的载荷，最后才替换
`loader.conf` 默认项和 manifest。不可变的旧 EFI 载荷条目保持可选，失效或已被清理的
NixOS profile 条目会从 ESP 菜单移除。

构建新的、不可变的 ESP 文件树后，使用 root 身份显式安装：

```bash
nix build ./nixos#shengUbootEfiEsp -o result/sheng-efi-esp
sudo sheng-efi install "$PWD/result/sheng-efi-esp/esp"
sudo sheng-efi status
```

安装器只接受含完整 `manifest.sha256` 的 `shengUbootEfiEsp/esp` 树，并确认 `/boot` 是
PARTLABEL 为 `linux-boot` 的 FAT ESP。它先把新的版本化目录
`EFI/NixOS/sheng-<kernel-version>-<payload-hash>/`、BLS 条目和 systemd-boot 写入临时目录，再逐文件校验；
新载荷全部存在后才用重命名切换 `loader.conf` 的默认项，再同步世代条目。安装前还会核对载荷记录的内核 store 路径与当前系统内核闭包完全一致，并确认运行内核版本相同；不满足时拒绝写入 ESP。旧 BLS 条目和旧内核/initrd/DTB 保留在 ESP；旧 `loader.conf` 和 `BOOTAA64.EFI` 备份在 `/var/lib/sheng-efi/`，供 `sheng-efi rollback` 使用。早期安装只在 ESP 留有 `BOOTAA64.EFI.previous` 时，回退器会使用这份备份。

如果还没有重启，或者在仍可进入 stage-2 时决定撤销默认项：

```bash
sudo sheng-efi rollback
sudo sheng-efi status
```

回退先校验旧 boot manager 备份，再恢复 `BOOTAA64.EFI` 和旧默认项；如果备份缺失，命令会在切换默认项前报错。ESP 的 FAT 文件替换不具备跨文件事务能力，回退完成后仍需执行 `sheng-efi status` 核对清单与默认项。若设备已无法进入 stage-2，须从 ABL fastboot 将已知可启动的 Mobile NixOS 镜像刷回 `boot_b`，不能依赖设备内的回退命令。

boot 镜像和 ESP 载荷由两个独立 workflow 构建。准备同一发布候选时，应从同一实验分支提交分别手动触发两项 workflow，核对两份 artifact 内的 `*.source-revision` 完全相同，且等于审查的分支提交；再分别校验 boot 镜像 SHA-256 和 ESP 的 `manifest.sha256`。PR 自动构建采用 GitHub 临时合并提交，`source-revision` 不等于 PR 分支提交，不能直接与分支手动构建产物配对。内核版本、U-Boot 版本或 workflow 均成功不能代替提交一致性检查。

下载两份 artifact 并分别解压到独立目录后，可以在刷写前运行只读预检：

```bash
scripts/sheng-verify-efi-artifacts.sh \
  /path/to/boot-artifact /path/to/esp-artifact \
  0000000000000000000000000000000000000000
```

将示例提交号替换为要审查的 40 位分支提交 SHA。脚本检查两份来源记录、boot 镜像
SHA-256、ESP manifest 和所有列入 manifest 的文件、默认 EFI 条目及内核闭包标识。
它不会写入设备；通过预检也不能代替实机启动或 rootfs 配对验证。

同一候选的最短设备验收顺序是：确认 B 槽及已知可启动的 `boot_b` 备份，安装对应 ESP 载荷，临时启动或刷入对应 U-Boot 镜像；验证普通启动、真实关机插线的画面顺序及有无世代菜单、断电后的冷启动、恢复键进入可用恢复路径；最后从 ABL fastboot 刷回备份 `boot_b` 并再次启动稳定系统。每次记录屏幕画面和实际启动目标，且运行 `systemctl is-system-running`、`systemctl --failed`。当前候选已完成这组实机检查，但充电启动仍显示 U-Boot 日志，应在任何 release 声明中列为已知问题。

成功到达 `multi-user.target` 后，`sheng-efi-mark-successful.service` 会记录当时配置的 EFI 默认项和时间。
它是运行时健康记录，不能单独证明用户没有从 systemd-boot 菜单手动选择旧条目；它不会自动清理旧载荷，也不会修改 Android 分区。

`uefi_a`、`uefi_b`、`rescue`、`userdata` 与 Android 固件分区仍不可复用，也没有被写入。
当前候选的 B 槽持久启动、普通重启、关机插墙充、断电冷启动、TWRP 恢复键和稳定镜像刷回
已实测。充电启动仍显示 U-Boot 日志；Android 与其他 Linux 尚未在本菜单启动。实验分支
不得当作已完成多系统适配或正式 release 宣传。
实际分区边界和验收记录见 [存储迁移预案](uboot-efi-storage-plan_zh.md)。
Android A 槽与更多 Linux 的可行性及验收边界见[多系统路线图](uboot-multiboot-roadmap_zh.md)。
