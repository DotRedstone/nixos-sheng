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

实验 EFI 路径不再显示旧的 stage-1 世代菜单；旧 Android boot 镜像保存在主机，供 ABL fastboot 回退。持久启动、音量键短按和长按连续移动、备份镜像刷回、无预写标记的 fastboot 回程、断电冷启动与恢复键均已实机确认。关闭图标的候选已完成关机插墙充、冷启动、恢复键和原镜像刷回实测；充电及系统启动仍短暂白屏。Android 尚未从 EFI 菜单启动，Alpine 和 Debian 仅完成短时独立 rootfs 探针，因此保持实验分支状态。

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

2026-10-27 将关闭 `CONFIG_VIDEO_LOGO` 的候选（SHA-256
`a843e13dae29a0972b97c712d9165a8e051c34a890013817cc1c3a3d3293af73`）写入 B 槽。
写入后读回镜像前 647168 字节哈希一致，设备进入 U-Boot UEFI、systemd-boot 与
NixOS 7.3.0，失败服务仍只有此前已有的两项。关机、断开电脑并插入墙充后，使用者
观察到短暂白屏，然后进入充电电池画面；未看到 U-Boot 图标、文字日志或 EFI 菜单。
拔掉墙充后仅按电源键冷启动，直接出现 EFI 选择界面，随后短暂白屏并进入 NixOS。
白屏的来源及是否可以消除仍需分析。再次远程关机后，使用者确认音量加加电源键进入
TWRP，并从 `Reboot → System` 返回 EFI 选择界面与 NixOS；ADB 随后确认
`Das U-Boot`、systemd-boot 260.1 与 B 槽候选哈希。最后从 ABL fastboot 刷回原
192 MiB `boot_b` 备份，设备从非 EFI 路径进入 NixOS 7.3.0，B 槽完整读回 SHA-256
为 `31e4e8bfaa06fedb2e2fa41531b068274d6baafd3ade0886dc279af2a473ae6a`，
与备份一致。只有此前已有的两个失败服务；A 槽、`linux`、`userdata` 和 Android
固件分区未写入。此候选的充电、冷启动、恢复键与回退路径均已实测，但短暂白屏、
充电功率和长时间稳定性仍未解决或验证。

2026-10-27 将延后视频控制台输出的候选镜像（SHA-256
`0a58f14f1b4ec39af3b1782b17021f045b485200972c5105b4e4dd6934809fdb`）刷入 B 槽。
持久启动进入 U-Boot UEFI、systemd-boot 和 NixOS 7.3.0。真实关机插墙充时，先短暂显示
右上角带 U-Boot 图标的启动画面，随后黑屏并进入充电电池画面；先前可见的多行日志没有再
出现。断开墙充后冷启动显示 U-Boot/EFI 选择界面，短暂白屏后进入 NixOS。恢复键测试后
设备也返回 EFI/NixOS，但这次使用者只回复“没问题”，TWRP 画面及其重启选项尚待明确
复核。最后刷回原 192 MiB `boot_b` 备份，设备从非 EFI 路径进入 NixOS 7.3.0，完整
B 槽读回 SHA-256 为 `31e4e8bfaa06fedb2e2fa41531b068274d6baafd3ade0886dc279af2a473ae6a`，
与备份一致。A 槽、`linux`、`userdata` 和 Android 固件分区未写入。

2026-10-27 再次将关闭图标的候选写入 B 槽，临时运行与
`sheng-reboot-generation-menu` 当前源码相同的 shell 命令。设备已通过 U-Boot UEFI 和
systemd-boot 进入 NixOS 7.3.0；命令在 EFI 路径执行普通重启，设备再次进入同一 EFI
启动链，且未生成旧 stage-1 的 `requested` 标记。测试没有更新 rootfs，因此不能证明
新命令已作为系统包部署。随后从 ABL fastboot 恢复原 192 MiB `boot_b` 备份；设备回到
非 EFI NixOS 7.3.0，完整 B 槽读回 SHA-256 为
`31e4e8bfaa06fedb2e2fa41531b068274d6baafd3ade0886dc279af2a473ae6a`，与备份一致。
屏幕上 EFI 选择界面的显示仍以使用者现场观察为准。

针对菜单是否可见的疑问，又用同一候选做了一次 B 槽测试。EFI 系统中执行
`systemctl reboot --boot-loader-menu=10` 报 `Read-only file system`，设备未重启；
因此该设备当前不能从 Linux 通过 EFI 变量请求一次性菜单超时。临时把 ESP 的
`loader.conf` 从 `timeout 3` 改成 `timeout 10` 后执行普通重启，设备再次经过
U-Boot UEFI 和 systemd-boot 进入 NixOS 7.3.0；屏幕菜单是否实际可见仍待现场反馈。
测试结束后，`loader.conf` 的 SHA-256 恢复为
`1414ba8826bbbdc8fa8d828ac94edd467f5e20f4071adb08164b98cbefddc4b8`，
原 192 MiB B 槽镜像完整哈希也与备份一致，设备回到非 EFI NixOS 7.3.0。

为定位 EFI 菜单确认后的单帧白闪，临时给第 1 世代条目加入
`video=efifb:off`。设备仍经 U-Boot EFI 进入 NixOS 7.3.0；内核日志不再注册
`EFI VGA frame buffer`，但使用者仍观察到相同的单帧白闪。因此 Linux 的 efifb
注册不是白闪的充分原因。另一次测试加入 `sheng.boot-ui=0`，确认该参数生效、
启动动画未运行且系统进入 NixOS；该次屏幕观察尚待反馈，不能据此排除动画。
两次测试的 EFI 条目及 3 秒超时均已恢复原哈希。随后按继续使用实验引导的要求，
将关闭图标的 U-Boot 候选重新写入 B 槽并保留；设备端读回前 647168 字节的
SHA-256 为 `a843e13dae29a0972b97c712d9165a8e051c34a890013817cc1c3a3d3293af73`，
`bootctl` 报告 `Das U-Boot`、systemd-boot 260.1，NixOS 7.3.0 与桌面已启动。
原 192 MiB B 槽备份保留在主机，A 槽、`linux`、`userdata` 未写入。

继续排查白闪时，发现锁定内核的 KTZ8866 驱动在 probe 中以默认亮度立即打开
LED，而 DRM 面板随后才完成复位和初始化。内核实验提交
[`f8fe49b`](https://github.com/DotRedstone/linux-sheng/commit/f8fe49bc2236c7ca07fc98129eef61526ffa3e46)
改为先保持背光关闭，由 `drm_panel_enable()` 在面板准备后打开；该改动记录在
已关闭的 [`linux-sheng` PR #6](https://github.com/DotRedstone/linux-sheng/pull/6)。
当前 EFI 内核位于独立的
`linux-boot` 分区，`boot_b` 中是 U-Boot，`linux` 中是 rootfs；只写后两者
无法替换 EFI 内核。未获该分区的写入范围确认前，不在设备上安装实验 EFI 载荷。
ARM [EFI 载荷构建](https://github.com/DotRedstone/nixos-sheng/actions/runs/40374499919)
已成功；下载产物的内部 manifest 和外层摘要均通过。对应的
[普通 boot image 工作流](https://github.com/DotRedstone/nixos-sheng/actions/runs/40374773651)
完成镜像构建后，在后续模块打包门禁因本实验内核缺少 FPC1552 驱动而失败，
没有上传镜像。该失败不证明背光补丁编译失败，也不能代替实机验证。
[B 槽诊断作业](https://github.com/DotRedstone/nixos-sheng/actions/runs/40380595505)
随后在模块门禁前上传镜像；镜像 SHA-256 为
`645539d4c9c123ef74c7aeaa456e9a86d978174bacad5712f2c4c29c700d2444`。
离线检查确认 Android boot v0、镜像小于 192 MiB，内核、DTB、initrd 与上述
EFI 载荷逐字节一致。临时刷入 `boot_b` 后，设备经普通 Mobile NixOS 路径进入
NixOS 7.3.0，桌面与背光正常；设备端读回镜像 SHA-256 相同。随后将关闭图标的
U-Boot 候选刷回 `boot_b`，再次经 U-Boot EFI 进入 NixOS；读回前 647168 字节
SHA-256 为 `a843e13dae29a0972b97c712d9165a8e051c34a890013817cc1c3a3d3293af73`。
未写 A 槽、`linux`、`linux-boot` 或 `userdata`。使用者随后确认：这次带背光
补丁的普通 `boot_b` 启动仍有单帧白闪，因此延后 KTZ8866 初次点亮没有消除
该路径上的现象。实验内核已从本分支的 flake 输入撤下，恢复与现用 rootfs
匹配的 `024eda3`。EFI 交接路径没有使用新内核实机测试，不能据此判断
EFI 交接时白闪的具体原因；该实验补丁也不应作为已验证修复合入稳定内核。

另一处可能的时序点是 NT36532E 面板在 `prepare()` 中发送 DCS `Set Display On`，
而 DRM 显示启用尚未完成。独立的
已关闭的 [`linux-sheng` PR #7](https://github.com/DotRedstone/linux-sheng/pull/7)
将该命令移到 `enable()`，基于现用 rootfs 对应的 `024eda3`，不包含已失败的
KTZ8866 实验。`codex/exp-nt36532e-display-test` 单独锁定该内核用于 ARM
镜像构建和短时 B 槽对照，不影响本分支当前 EFI pin。
该实验分支的 [ARM boot image 作业](https://github.com/DotRedstone/nixos-sheng/actions/runs/40445887989)
完成镜像构建与诊断附件上传，后续模块门禁仍因缺少 FPC1552 失败。附件 ZIP
校验通过，boot image 大小为 57,618,432 字节、SHA-256 为
`c7929cd78451de1022c83e60067c537932f3190da1b674ce9f8aaa044b75a87f`。
短时写入 `boot_b` 后，设备端镜像读回哈希一致；普通路径进入 NixOS 7.3.0，
DRM 背光与 GNOME 正常启动。首次测试缺少屏幕观察；再次刷入同一镜像并目视
复测时，使用者确认单帧白闪仍在，且正常进入桌面。因此将面板 `Set Display On`
移到 `enable()` 未消除普通启动路径上的白闪，PR #7 不作为修复合入。
随后刷回测试前的整块 192 MiB B 槽备份，设备端完整 SHA-256 与备份一致；
设备再次经 U-Boot、systemd-boot 进入 NixOS，GNOME 正常启动。
未写 `linux`、`linux-boot`、A 槽或 `userdata`。

随后把 KTZ8866 首次点亮延后和 NT36532E `Set Display On` 延后两项改动合并到
内核实验修订 `3946593`，由 NixOS 实验分支 `codex/exp-panel-backlight-handoff`
锁定。对应的 [ARM boot image 作业](https://github.com/DotRedstone/nixos-sheng/actions/runs/40487750612)
完成镜像构建和诊断附件上传，后续模块打包仍因缺少 `CONFIG_INPUT_FPC1552=y`
失败。附件摘要及 ZIP CRC 校验通过；Android boot v0 镜像为 57,618,432 字节，
SHA-256 为 `8e7e21dd9b376f290b63577aa522c25eee85139ff1764c5ff8a8b0cb1aec1ef4`。
临时写入 `boot_b` 后，设备端整分区哈希与“镜像前缀加原分区尾部”一致。
使用者目视确认：从 fastboot 启动及随后普通重启，两次均无单帧白闪且进入
NixOS 7.3.0 桌面。恢复测试前的整块 192 MiB U-Boot 备份后，设备端 SHA-256
为 `b9024c1599b6b06795ae4c59c990940573e924b6e1374988f157b603d198eea5`，
与备份一致；EFI 选择界面再次出现，选择后白闪仍在，NixOS 桌面正常。
这组对照同时改变了启动路径和运行内核，不能单独归因为 U-Boot 或面板驱动，
也不能证明组合内核已修复 EFI 交接。未写 `linux`、`linux-boot`、A 槽或 `userdata`。

为隔离启动路径，用同一组合内核构建
[EFI 载荷](https://github.com/DotRedstone/nixos-sheng/actions/runs/40515526254)。
作业中的 EFI 载荷构建及附件上传成功，完整 stage-2 构建未启用；下载后校验了
附件摘要、ZIP CRC 和内部 manifest。写入前备份整块 `linux-boot` ESP，备份
SHA-256 为 `e657a9350b7d3d4f9cdc371bce8feac000fa28bc4949caa501167e2cdb23d3c7`。
只新增版本目录 `sheng-7.3.0-9a2dc19773856d69` 的四个载荷文件及一个手动
测试条目，逐文件在设备端核对哈希。由于 U-Boot 提供的 EFI 变量在 Linux 中
只读，`bootctl set-oneshot` 失败；临时改动 `loader.conf` 默认项后，
`bootctl` 确认实际启动的是 `nixos-sheng-panel-backlight-test.conf`。
使用者目视确认：该 EFI 路径仍有单帧白闪，最终进入 NixOS 桌面。
因此这两处面板与背光时序改动没有消除 EFI 路径的白闪；其原因仍需在
U-Boot、systemd-boot 与 Linux 显示交接中进一步定位。测试后将 `loader.conf`
逐字节恢复，删除新增条目和四个载荷文件；`boot_b` 整分区哈希仍与 U-Boot
备份一致，随后从原第 1 世代条目正常启动。此测试不构成新内核与现用 rootfs
闭包兼容性的完整验收；未写 `linux`、A 槽、`userdata` 或设备校准分区。

又将 U-Boot 视频控制台恢复为 EFI 初始化前全程启用，构建诊断镜像
SHA-256 为 `086a6875ee3da0999acffcff7a04d274c85293318a35e32f3e6d7d0a7f6a987b`。
临时刷入 `boot_b` 后，`bootctl` 确认仍经 U-Boot EFI 启动原第 1 世代；使用者确认
菜单出现，选 NixOS 后仍有单帧白闪并进入桌面。仅调整控制台启用时机未消除
现象。随后刷回测试前整块 192 MiB U-Boot 备份，设备端 SHA-256 为
`b9024c1599b6b06795ae4c59c990940573e924b6e1374988f157b603d198eea5`，
原第 1 世代重新启动。仓库源码已撤销该失败实验的配置改动。

systemd-boot 260.1 在菜单确认后调用 `ClearScreen()`。为隔离这一步，
[ARM 诊断构建](https://github.com/DotRedstone/nixos-sheng/actions/runs/40530622455)
只删除该调用，产出 AA64 `BOOTAA64.EFI`，SHA-256 为
`f15f2436c54856708afadc313995707786fc09e06190ff1b0e472d627b849c4e`。
单文件写入 `linux-boot` ESP 后，`bootctl` 确认从 U-Boot EFI 启动原第 1 世代，
使用者目视确认仍有单帧白闪并进入桌面。原 EFI 文件已逐字节恢复，其 SHA-256 为
`9f685a6593cd1c1ad5d8c9caf295dcd11d6e041345a6f5e664c12d27d18ccaf6`；
`boot_b` 仍与 U-Boot 整分区备份一致。因此菜单退出清屏不是白闪的充分原因，
诊断补丁不得作为修复部署。

再测试 U-Boot GOP `SetMode(0)`：诊断镜像跳过该函数对继承帧缓冲的整屏填充，
镜像 SHA-256 为 `f5ba2885ee9d22494cf1b1d872145f66bb4a04235c4f0a35e084a18b9c2cc882`。
仅写入 B 槽后，设备从 U-Boot EFI 启动原第 1 世代；使用者确认仍有单帧白闪，
并正常进入桌面。随后刷回原 192 MiB B 槽备份，整分区 SHA-256 恢复为
`b9024c1599b6b06795ae4c59c990940573e924b6e1374988f157b603d198eea5`；
EFI 管理器文件保持原哈希。内核 EFI stub 在未指定显示模式时不会调用 GOP `SetMode`，
本次测试不能证明该函数在实际启动中被执行，因此只记录为未消除白闪的对照。

另一诊断版在 U-Boot `ExitBootServices()` 处把帧缓冲写黑并等待 50 毫秒，
镜像 SHA-256 为 `1b17d0d49e9315e06346f8ee7aa8cc98b4fc5a27f9a5663104dc42e6bf79a906`。
仅写入 B 槽后，EFI 第 1 世代正常进入桌面，但使用者仍观察到白闪。
本次目视反馈没有确定白闪与黑帧的先后关系，因此不能定位它发生在
`ExitBootServices()` 前或后。已恢复原 B 槽整分区备份并核对哈希；
该诊断补丁不应保留为默认行为。

为定位白闪顺序，在 U-Boot `ExitBootServices()` 有效入口、EFI 事件通知结束和
设备清理结束后依次写入绿色、洋红色与黄色帧，每色停留约 2 秒。早期每色仅
300 毫秒的版本无法辨清，延时版本中使用者确认白闪发生在洋红色结束之后；
增加第 3 色后，使用者确认黄色可见，白闪仍发生在三色全部结束之后。
第 3 色镜像 SHA-256 为
`0a73f03528b54cf3080c3f1423dd5ef37f31e6ab6a361555c7f46a40d751469b`，
ADB 确认设备从 EFI 第 1 世代进入 NixOS。由此排除 EFI 事件通知和 U-Boot 设备清理本身
直接产生可见白闪；仍需区分剩余的 U-Boot EFI 返回、Linux EFI stub 与内核显示接管。
彩色阶段标记仅为诊断，不应发布为默认引导体验。

普通 `boot_b` 对照镜像与 EFI 载荷的解压后 Linux 内核 SHA-256 同为
`0e071fa9c865eee1887206027d765fef90d80d3173069d1ad9f5195bec9b5837`，
设备树 SHA-256 同为
`adbc0899ff0f3b2eb67e2a4b882e5106caab306d4c1379f26650c3ce9aa1a691`。
普通启动两次未见白闪，EFI 路径多次可见白闪；这支持继续检查引导协议及
进入内核时的显示状态，不能单独断定某个驱动有错。

另将最初导入 U-Boot 启动基线的提交 `69a6aa1` 原样构建，镜像 SHA-256 为
`ace4caa74df60600ce9f799ac260743030999a24eca3b8e0bc4d077580167231`。
只写入 B 槽并使用当前同一份 EFI/NixOS 载荷，ADB 确认设备进入第 1 世代，
使用者仍观察到白闪；菜单是否出现未明确反馈。随后恢复原 B 槽整分区备份，
SHA-256 为 `b9024c1599b6b06795ae4c59c990940573e924b6e1374988f157b603d198eea5`，
ESP 的 EFI 管理器文件哈希保持不变。此对照不支持把白闪归因于基线导入后的
U-Boot 环境或菜单改动。

内核实验提交 `71211ed` 在 EFI 启动时保留面板复位 GPIO 的原状态，跳过首次
`nt36532e_prepare()` 中的硬复位，后续 prepare 仍按原流程复位。固定该提交的
[ARM EFI 载荷作业](https://github.com/DotRedstone/nixos-sheng/actions/runs/40538815768)
成功；附件 ZIP SHA-256 为
`c3e24e31ea411ccd9454e9592e9281de992d248743eb65ca9ba419172363733e`，
内部 manifest、ZIP CRC 和设备端四个载荷文件哈希均通过。只在 ESP 增加临时
载荷目录与条目后，`bootctl` 确认启动该测试项，内核日志确认跳过首次复位，
使用者仍观察到白闪并进入桌面。因此单独去掉首次面板复位不能修复该现象。
已恢复原 `loader.conf` 并删除新增条目与载荷；此内核改动仍为诊断分支，
不得作为已验证的面板修复。

随后依据 [Linux fbcon 文档](https://docs.kernel.org/fb/fbcon.html) 中关于
framebuffer 内容保留和 `fbcon=map:` 的说明，用原 EFI 内核及载荷只增加
`fbcon=map:1` 启动参数。设备端确认参数生效、`vtconsole` 只剩 dummy 设备，
使用者仍观察到白闪并进入桌面；已恢复原默认项并删除测试条目。此对照不支持
将白闪归因于 fbcon 抢先清屏。当前内核的
`CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER` 未启用，但单独启用该选项也
不能从这组负结果推定为修复。

研究 Qualcomm DPU 交接时发现，[上游讨论](https://lkml.iu.edu/hypermail/linux/kernel/2202.1/09164.html)
记录了 bootloader 旧扫描路径与 Linux 新路径并存时，IOMMU 配置变化可使旧路径
输出 underflow color；讨论也说明真正无闪烁交接需要继承时钟、电源和显示配置。
该补丁针对另一类接口，[后续评审](https://lists.openwall.net/linux-kernel/2022/02/17/30)
指出其 `CTL_START` 用法与 DSI 视频模式并不直接对应，不能原样套用到 sheng。
本机 EFI 启动后 `efifb` 在约 0.12 秒注册、msm DRM 在约 0.62 秒初始化；
`/proc/iomem` 将 ABL framebuffer 的 `0xb8000000` 区域列为 reserved。
运行后的 DSI encoder underrun 计数为零，但这不能排除 IRQ 注册前的瞬时异常。
随后用同一诊断内核（`70cef9e`）分别从 EFI 与普通 `boot_b` 启动，记录
DPU 资源管理器初始化前后的六组 CTL 和两组 DSI 寄存器。两条路径的采样值相同：
CTL active/START 均为零，DSI status 为零、config 为 `0x00800000`；两次均
进入 NixOS。EFI 载荷与普通 boot 镜像的解压后内核、initrd 哈希分别一致。
这排除了采样时仍有 EFI 专属旧 CTL 扫描的情况，但采样前的瞬时状态仍未知。
两次白闪的现场目视反馈均为“没看清”，不能据此比较这两个诊断镜像的显示结果。
目前不应直接清除全部 CTL 或改变面板时序。

两项测试结束后，原 `boot_b` 整分区 SHA-256 为
`b9024c1599b6b06795ae4c59c990940573e924b6e1374988f157b603d198eea5`，
ESP 的 `loader.conf` 与 EFI 管理器 SHA-256 分别恢复为
`1414ba8826bbbdc8fa8d828ac94edd467f5e20f4071adb08164b98cbefddc4b8`、
`9f685a6593cd1c1ad5d8c9caf295dcd11d6e041345a6f5e664c12d27d18ccaf6`；
第 1 世代重新启动，两个临时条目及新载荷均已删除。未写 `linux`、A 槽、
`userdata` 或设备校准分区。

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
stage-1 判定，再交给 stage-2 充电目标。备份 `boot_b` 的刷回与恢复、手动 fastboot 回程、
断电冷启动和恢复键均已实测。统一菜单中的 Android 启动和长期可用的其他 Linux 条目
仍未验收；本实验分支不得作为完整多系统支持合并或发布刷机镜像。

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

同一候选的最短设备验收顺序是：确认 B 槽及已知可启动的 `boot_b` 备份，安装对应 ESP 载荷，临时启动或刷入对应 U-Boot 镜像；验证普通启动、真实关机插线的画面顺序及有无世代菜单、断电后的冷启动、恢复键进入可用恢复路径；最后从 ABL fastboot 刷回备份 `boot_b` 并再次启动稳定系统。每次记录屏幕画面和实际启动目标，且运行 `systemctl is-system-running`、`systemctl --failed`。关闭图标的候选已完成这组实机检查，充电与冷启动仍出现短暂白屏。

成功到达 `multi-user.target` 后，`sheng-efi-mark-successful.service` 会记录当时配置的 EFI 默认项和时间。
它是运行时健康记录，不能单独证明用户没有从 systemd-boot 菜单手动选择旧条目；它不会自动清理旧载荷，也不会修改 Android 分区。

`uefi_a`、`uefi_b`、`rescue`、`userdata` 与 Android 固件分区仍不可复用，也没有被写入。
早期候选的 B 槽持久启动、普通重启、关机插墙充、断电冷启动、TWRP 恢复键和稳定镜像刷回
已实测。关闭图标的候选在充电与冷启动时仍短暂白屏；Android 尚未在本菜单启动，Alpine 和 Debian
仅完成短时独立 rootfs 探针。实验分支不得当作已完成多系统适配或正式 release 宣传。

后续 U-Boot 候选将正常路径的 `stdout`、`stderr` 先导向串口和 USB ACM，在读取 ESP
并准备交接 EFI 菜单时恢复视频控制台；EFI 失败的救援菜单也恢复视频输出。
关闭 `CONFIG_VIDEO_LOGO` 的候选已构建并通过 `fastboot boot` 临时进入 U-Boot UEFI、
systemd-boot 与 NixOS 7.3.0；随后刷入 B 槽，完成真实充电与冷启动的现场观察。
恢复键、原镜像刷回及完整 B 槽哈希核对也已完成。

2026-10-26 单独验证了 ABL A/B 槽位路径：切至 A 槽后 Android 16 报告启动完成，
`sys.boot_completed=1` 且图形服务运行；通过 Android ADB 返回 fastboot 并切回 B 槽，
NixOS 7.3.0 再次启动。B 槽完整哈希与原始备份一致，A 槽关键启动分区未变。
这不是从 U-Boot / EFI 菜单启动 Android 的验证。

同日验证了另一个 Linux 用户态：官方 Alpine 3.24.3 aarch64 minirootfs 首先作为
独立 initrd 从 EFI 菜单短时启动，`/init` 写下 Alpine 版本和内核 7.3.0 标记。
随后 Alpine 被放入现有 `linux` 分区内的独立 ext4 镜像；EFI 内核经临时 initrd
挂载该镜像并 `switch_root`，Alpine 根文件系统中的 `/init` 以 PID 1 写下结果标记，
之后自动重启回非 EFI NixOS。两次均只以 `fastboot boot` 临时启动 U-Boot；ESP
默认项和临时载荷已恢复或清理，完整 `boot_b` 哈希未变。尚未验证 Alpine 的完整
服务启动、图形界面、硬件驱动和更新机制，不能称为可供日常使用的发行版移植。

同一方法还短时启动了 Debian 13 arm64 的独立 ext4 根文件系统：临时 EFI 条目
经已验证的 7.3.0 内核与 Sheng DTB 进入 Debian `/init`，设备记录其 PID 为 1，
版本为 13，然后自动返回 B 槽 NixOS。Alpine 和 Debian 测试镜像及临时 ESP
条目均已清理，ESP 默认项和 B 槽完整哈希与测试前一致。两者均只完成启动探针，
尚未具备可日常使用的桌面、服务与更新支持。
实际分区边界和验收记录见 [存储迁移预案](uboot-efi-storage-plan_zh.md)。
Android A 槽与更多 Linux 的可行性及验收边界见[多系统路线图](uboot-multiboot-roadmap_zh.md)。
