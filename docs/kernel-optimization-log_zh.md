# Xiaomi Pad 6S Pro (sheng) 内核与启动链路优化记录

本文记录 sheng 的驱动链路审计、修改依据和前后对比方法。目标不是单纯消除日志，而是在不猜测硬件供电关系的前提下，缩短启动路径、恢复原厂明确使用的硬件策略，并为后续功耗和性能测试保留可复现基线。

## 测试边界

- 设备：Xiaomi Pad 6S Pro 12.4（sheng，SM8550）
- 基线日期：2026-08-12
- 基线内核：`Linux 7.0.0 #1-mobile-nixos SMP PREEMPT`
- 基线系统：NixOS 26.11 pre-release
- 分支：`audit/sheng-hardware-optimization`
- 本轮不刷写设备、不改 Android 分区、不执行 suspend/reboot。
- 采样时电池 96%，正在充电，因此充电功率不适合作为峰值快充基线。

完整采集可在平板本机执行：

```sh
sudo ./scripts/collect-hardware-baseline.sh 10 > sheng-baseline.txt
```

也可以从电脑临时推入 `/tmp`，不会修改系统配置：

```sh
adb push scripts/collect-hardware-baseline.sh /tmp/
adb shell 'chmod 755 /tmp/collect-hardware-baseline.sh && /tmp/collect-hardware-baseline.sh 10'
```

脚本会脱敏 Android 序列号，不采集 SSID、MAC 地址和 IP 地址，并在同一份报告中保存启动总时间、最慢单元、`graphical.target` 关键链、硬件服务重启次数、当次启动 coredump、journal 占用和 pd-mapper 易失固件目录。公开日志前仍应人工检查一次。

## 修改前基线

| 项目 | 结果 |
| --- | --- |
| 内核阶段 | 6.126 秒 |
| 用户态阶段 | 25.791 秒 |
| 总启动时间 | 31.918 秒 |
| `graphical.target` | 用户态 18.964 秒到达 |
| `NetworkManager-wait-online` | 17.926 秒 |
| `iio-sensor-proxy` | 13.301 秒（运行系统仍是旧的长超时配置） |
| systemd 失败单元 | 0 |
| CPU 调速器 | 三个 cluster 均为 `schedutil` |
| CPU 空闲状态 | 8 个 CPU 均能进入 `cpu-sleep-0-0` |
| GPU devfreq | `simple_ondemand`，220–680 MHz，空闲采样为 220 MHz |
| UFS devfreq | `simple_ondemand`，75–300 MHz，空闲采样为 75 MHz |
| UFS I/O scheduler | `mq-deadline`，read-ahead 2048 KiB |
| CAMSS runtime PM | 被现有 workaround 强制为 `on/active`，开机后几乎全程 active |
| CAMSS interconnect | idle 时仍保留 AHB 与 CAMNOC→DDR 各 2097152 kB/s 投票 |
| ftrace | `current_tracer=nop` |
| 温度 | SoC 约 31–36°C，PMIC 约 37°C，电池约 29.7°C |
| ADSP | `running`，固件为 sheng 原厂 ADSP |
| CDSP | `offline`，按需启动，属于预期状态 |
| USB-C/UCSI | charger PD 约 0.87 秒出现，UCSI 约 3.23 秒注册成功 |
| Wi-Fi | PCIe Gen2 x2，WCN7850/ath12k 正常工作 |
| 音频 | 2 个 playback、1 个 capture，PipeWire 扬声器 EQ 正常接入 |
| 持久崩溃日志 | 内核启用了 pstore，但 DTS 缺少 ramoops，`/sys/fs/pstore` 为空 |
| 休眠统计 | 尚未做安全的 suspend/resume 循环测试 |

三秒空闲采样中，各 CPU 的深空闲累计驻留时间约 2.96–3.03 秒。这说明现有调速器和 cpuidle 基本可用，不应在没有能耗仪数据时盲目更换 governor 或抬高最低频率。

GPU 和 UFS 在采样时也都降到了最低 OPP。虽然内核启用了 dynamic ftrace，运行时 tracer 为 `nop`，调用点处于动态 NOP 状态；在驱动仍处于审计阶段时，保留诊断能力比未经基准测试就删掉 ftrace 更合理。

相机链路目前是明显的剩余功耗项。`sheng-camera-modules` 为规避历史上的 CAMSS runtime ICC/RPMh 超时，把 `acb7000.isp` 永久设为 `power/control=on`。实测 Titan Top GDSC 常开，虽然各 IFE 子域和相机时钟能关闭，但空闲时仍向 AHB 和 CAMNOC→DDR 各保留 2097152 kB/s 带宽投票。上游 SM8550 CAMSS 仍使用相同的固定带宽和 runtime suspend 实现，因此不能只改一个数字或直接删除 workaround；后续应在可恢复环境中测试 `auto`、抓取 RPMh/ICC trace，并同时验证 UFS I/O 和相机反复开关。

## 第一批修改

### 1. 恢复六颗 CS35L43 的原厂 standby 策略

Android 原厂 DTBO 对六颗 CS35L43 都设置了 `cirrus,low-pwr-mode-standby = <1>`，当前主线 DTS 漏掉了该属性。内核中的 CS35L43 驱动已经支持这一布尔属性：启用后，播放间隔使用原厂预期的 standby 路径，并跳过 hibernate 切换。

同时将 `cirrus,vpbr-enable = <1>` 改为标准布尔写法 `cirrus,vpbr-enable;`。功能含义不变，但可消除六条 OF 布尔属性格式警告。

预期验证：

- 六颗功放仍全部枚举为 CS35L43 Revision A1。
- 扬声器播放、暂停、再次播放不出现首帧丢失或功放唤醒失败。
- dmesg 不再出现 `Read of boolean property 'cirrus,vpbr-enable' with a value`。
- 对比空闲时功放相关唤醒和温度；standby 是原厂时序兼容策略，不提前宣称一定比 hibernate 更省电。

### 2. 将 WCN7850 供电序列放入内核

基线配置把 `pwrseq_qcom_wcn` 和 `pci_pwrctrl_pwrseq` 编译为模块。PCIe 控制器约 0.22 秒开始探测，但 WCN7850 的供电序列要等到约 7.75 秒由 rootfs/udev 加载，期间根控制器反复延迟探测，并重复创建 OPP/debugfs 项。

本轮将以下选项从模块改为 built-in：

```text
CONFIG_POWER_SEQUENCING_QCOM_WCN=y
CONFIG_PCI_PWRCTRL_PWRSEQ=y
```

这两项只负责 regulator/GPIO/PCI power-control 时序，不依赖 WLAN 固件。`ath12k` 仍保留为模块，降低改动范围。

预期验证：

- `pwrseq_qcom_wcn` 和 `pci_pwrctrl_pwrseq` 不再出现在 `lsmod`，因为已编入内核。
- PCIe 根控制器不再从 0.2 秒到 7.7 秒反复 deferred probe。
- `PCIe Gen.2 x2 link up` 和 WCN7850 枚举时间提前。
- Wi-Fi、蓝牙开关和 5 GHz 扫描行为没有回归。

### 3. 取消无消费者的网络在线等待

基线中 `NetworkManager-wait-online.service` 耗时 17.926 秒。反向依赖检查显示没有 sheng 服务需要 `network-online.target`；桌面、SSH 和硬件守护进程只需要 NetworkManager 异步启动。

因此移除该服务的 `wantedBy`，保留 NetworkManager、wpa_supplicant 和 dispatcher。该改动不会关闭网络，只是不再让无载波/未关联 Wi-Fi 阻塞启动目标。

预期验证：

- `NetworkManager-wait-online.service` 不再参与启动。
- 登录界面无需等待 Wi-Fi 关联。
- 联网、自动重连和 SSH 在网络就绪后照常工作。

### 4. 修正 pd-mapper 的假文件描述符错误

本地 `pd-mapper` 包装曾把 firmware-class 的 sysfs 文件描述符强制替换为 `-1`，以便使用 `/run/pd-mapper-firmware`。上游函数仍会尝试读取和关闭该描述符，因此每次启动都会产生 `Cannot open sysfs path: Success` 和 `Bad file descriptor` 两条误导日志。

设备上的 `/sys/module/firmware_class/parameters/path` 正常存在且当前为空。恢复上游读取逻辑后，它会自然回退到已经替换为 `/run/pd-mapper-firmware` 的默认目录，功能路径不变，也不再伪造一次打开失败。

预期验证：

- `pd-mapper` 仍能发布 service-registry 服务，sensor PD 正常启动。
- 日志不再出现上述两条 sysfs/file-descriptor 假错误。

### 5. 修复 PS5169 解绑时的空指针风险

PS5169 的 `remove()` 通过 `i2c_get_clientdata()` 获取驱动私有结构，但原 `probe()` 没有调用配对的 `i2c_set_clientdata()`。驱动常驻时不一定暴露，一旦通过 sysfs 解绑、重新绑定或设备被移除，remove 路径可能解引用空指针并导致内核崩溃。

本轮在 probe 中保存私有结构。该修改不改变寄存器配置、Type-C 状态机和电源时序，只修复生命周期管理。

预期验证：

- 正常启动和 USB-C 正反插、device/host role 切换无回归。
- 在用户在场、没有数据传输时单独测试 PS5169 unbind/bind，不再出现 kernel oops。

### 6. 补齐 Novatek 固件复位后的 ReK 等待

长时运行约 89 分钟后，NT36532E 触控固件曾触发一次 WDT 自恢复。驱动成功重新下载固件，但紧接着发送 `0xBF` 自定义命令时连续失败。对照正常 resume 路径后发现，WDT 和 boot update 路径都少了 `RESET_STATE_REK` 等待，可能在固件尚未完成基线重建时过早发送 idle/doze 配置。

本轮让这两条恢复路径与正常 resume 保持一致：固件下载失败或未进入 ReK 状态时停止发送后续模式命令，成功时才恢复 idle baseline 和 doze 配置。没有改变触控坐标、SPI 频率或手势参数。

预期验证：

- 长时间亮屏、熄屏/唤醒后触控保持正常。
- 若固件再次发生 WDT 复位，日志不再紧跟 `send cmd failed, buf[1] = 0xBF`。
- 复位失败时保留明确错误，便于区分固件下载失败和 ReK 超时。

### 7. 提供传感器 DSP 需要的 ODM 配置别名

原厂 ADSP 固件启动时会通过 FastRPC 连续枚举 `/odm/etc/sensors/config`。NixOS 已经提供内容对应的 `/etc/sensors/config`，但缺少 Android 的 ODM 路径，因此每次启动出现十次 `failed to opendir`，随后才继续读取主配置目录。

本轮只在 `adsprpcd` 和 `adsprpcd-sensorspd` 的 systemd mount namespace 内，把 `/etc/sensors/config` 只读映射为 `/odm/etc/sensors/config`。不在全局根目录创建 Android 路径，不复制配置、不改变 ADSP library path，也不让 Android persist 分区可写。

预期验证：

- `adsprpcd` 不再报告 `/odm/etc/sensors/config` 不存在。
- SSC 传感器枚举数量与方向、光线、距离数据不回归。

### 8. 限制开发期持久日志占用

基线设备的 persistent journal 已占用约 891 MiB。默认上限会随 77 GiB 根分区增长，对会产生大量驱动 bring-up 日志的移动设备过于宽松。本轮保留跨重启日志，但设置 `SystemMaxUse=512M` 和最长 14 天保留期；不关闭压缩，也不通过激进 rate limit 隐藏硬件错误。

预期验证：

- `journalctl --disk-usage` 在日志轮转后稳定在 512 MiB 以内。
- `journalctl --list-boots` 仍保留足够的近期冷启动记录用于回归分析。

### 9. 缩小 pd-mapper 的启动解压集

旧系统在每次启动时把 `qcom/sm8550/sheng` 下全部 zstd 固件解压到 `/run/pd-mapper-firmware`，实测占用约 46 MiB tmpfs，其中 37 MiB 是已经由 remoteproc 从 `/lib/firmware` 加载过的 `adsp.mbn`，其余大项还有 CDSP 和 VPU 镜像。

固定版本的 pd-mapper 源码只枚举 `.jsn` 和 `.jsn.xz` 服务映射。设备上的 `xiaomi_devauth` 二进制还明确包含 `%s/%s.mbn` 路径并加载 `devauth`，因此本轮保留所有 `*.jsn.zst` 和 `devauth.mbn.zst`，不再复制其余 remoteproc/GPU/VPU/IPA 镜像。用设备当前固件在 `/tmp` 复现同一解压逻辑后，易失目录从约 46 MiB 降到 180 KiB。

预期验证：

- `pd-mapper` 正常发布服务，`sensor_pd` 和 `charger_pd` 映射不回归。
- `sheng-devauth` 保持运行，Nanosic 键盘认证正常。
- `/run/pd-mapper-firmware` 只包含五个 `.jsn` 与 `devauth.mbn`。
- 开机日志不再出现对 ADSP/CDSP/VPU 大镜像的重复解压。

### 10. 修正 q6apm 就绪查询的错误语义

基线中 `sheng-audio-modules.service` 用时 3.517 秒，唯一对应异常是 `qcom-apm` 的 `APM_CMD_GET_SPF_STATE` 同步查询超时。进一步审计发现 `q6apm_get_apm_state()` 丢弃了同步发送的返回值：`-ENOMEM` 或 `-ETIMEDOUT` 最终经 `bool` 转换会变成 true，错误放行 `q6prm`。同时 `apm_probe()` 还执行一次结果完全不用的重复查询。

内核提交 `8475fee16` 现在正确传播查询错误，以 `> 0` 明确判断 ready，并移除 probe 中不参与任何门禁的第一次查询。`q6prm` 自己的同步查询及 `-EPROBE_DEFER` 保持不变，所有图管理命令共享的 5 秒超时也没有缩短。刷入后需要确认声卡始终枚举，并比较 audio unit 用时与 `CMD timeout` 次数。

### 11. 让 FastRPC 精确等待真正接管启动门禁

旧配置同时使用 `ConditionPathExists=/dev/fastrpc-adsp` 和 `ExecStartPre=wait-for-adsp-fastrpc`。systemd 在执行等待脚本之前先评估 condition；节点若恰好稍晚出现，`adsprpcd` 会被直接跳过，60 秒的 remoteproc/FastRPC 稳定检测反而永远没有机会运行。这正是启动时序偶发变化时最不希望出现的行为。

本轮移除 `adsprpcd`、`adsprpcd-sensorspd` 的早期 path condition，以及正常启动链中冗余的 `systemd-udev-settle` 依赖。设备基线表明 settle 单元从未实际执行；root daemon 已有连续三次稳定检查，sensor PD 又严格依赖 root daemon、pd-mapper 与 devauth，因此具体设备状态检查比等待全局 udev 队列更准确。底层永久失败时，现有非零退出与 systemd restart 仍会负责恢复。

### 12. 隔离 WirePlumber 的 BlueZ MIDI 崩溃路径

历史日志没有 kernel panic、watchdog、UFS/ext4 I/O 错误或 remoteproc crash，但上一轮启动保留了两次 WirePlumber `SIGSEGV`。两次崩溃前都出现 BlueZ MIDI 对 `GattManager1.RegisterApplication()` 的重复失败，core 映射和调用栈也落在 PipeWire D-Bus SPA 路径。用户目录没有自定义 WirePlumber/PipeWire 配置，当前 ALSA 声卡本身正常，因此这更符合用户态 BLE MIDI monitor 的异常，而不是音频 codec 驱动掉线。

WirePlumber 把普通 BlueZ 音频与 BlueZ MIDI 定义为独立 monitor。本轮仅禁用 `monitor.bluez-midi`，保留 `monitor.bluez`，所以 A2DP、HFP 与 LE Audio 不受影响。sheng 没有内置 MIDI 硬件；若用户确实需要外接 BLE MIDI，可以在个人配置中重新启用并继续向 PipeWire/WirePlumber 上游定位。

预期验证：

- 重复开关蓝牙、登录/退出桌面后 WirePlumber 不再产生 coredump。
- 蓝牙耳机的 A2DP 播放与 HFP 输入仍正常。
- 日志不再出现 `spa.bluez5.midi` 的 GATT 注册重试。

### 13. 恢复原厂 ramoops 持久崩溃区

保留的 20 次启动日志中没有 kernel panic、watchdog、remoteproc crash 或 UFS/ext4 I/O 错误，但 `/sys/fs/pstore` 始终为空。配置已经启用 `CONFIG_PSTORE_RAM`、console 和 pmsg，真正缺少的是设备树中的保留内存；因此过去的突发重启即使由内核崩溃触发，也无法跨重启留下最后现场。

原厂 sheng DTBO 在所有相关变体中都把 `0xa7000000` 起始的 4 MiB 声明为 ramoops，console 与 pmsg 各 2 MiB。该区域位于 ADSP carveout 结束位置与 `0xa8000000` 内核加载地址之间，当前 `/proc/iomem` 在缺少声明时把它误并入普通 System RAM。内核提交 `1ebcb435f0f8` 按原厂地址和分区恢复该节点，固定牺牲 4 MiB 内存，换取重启后可读取的内核 console/pmsg；不引入 mtdoops 私有驱动，也不会主动制造 panic 做测试。

预期验证：

- 启动日志出现 ramoops/pstore 注册信息，`/proc/iomem` 单独保留 `0xa7000000-0xa73fffff`。
- 正常重启不会生成虚假 crash 记录。
- 若未来再次异常重启，第一时间保存 `/sys/fs/pstore/*` 后再做其他操作。

### 14. 撤销不存在的 HV haptics 设备

早期移植把 PM8550B 的通用 HV haptics 节点直接设为 `okay`，因此 Linux 能注册一个 force-feedback 输入设备，但注册成功并不等于机身内存在执行器。实机反复触发没有触感，驱动校准结果稳定为 `lra_impedance=Open circuit`。重新反编译 sheng 原厂 DTBO 后还确认：PM8550B HV haptics 与 SoundWire haptics 两套候选节点都保持 `status = "disabled"`，没有任何产品 overlay 将其启用。

因此本轮删除 sheng DTS 中臆造的 haptics 节点，撤销 probe 阶段强制打开模块的改动，并停止自动加载 `qcom-hv-haptics`。这避免 PMIC 持续驱动开路输出，也避免桌面把一个不可用的 FF 设备误认为震动马达。若以后拆机或原理图证明存在独立执行器，应按真实总线、供电和校准数据新增驱动，不能继续用 PM8550B 通用节点猜测。

验证标准：

- 启动日志不再注册 `qcom-hv-haptics`，也不再出现 LRA 开路校准。
- `/sys/class/input` 不再暴露虚假的 haptics/vibrator 设备。
- 充电、PMIC 和待机链路不因该节点出现新的错误。

### 15. 接入 FPC1553 指纹安全链路

原厂 DTS 和 FPC 平台驱动表明，sheng 的侧边指纹使用 L9B 3.3 V 供电、GPIO41 复位和 GPIO40 上升沿中断。内核侧只负责这些电气资源；录入、匹配和模板管理全部在 Qualcomm TEE 中由 `fpcsheng` trusted application 完成，不能用普通 SPI libfprint 驱动替代。

本轮新增精简的 `fpc1552` 资源驱动，提供原厂用户态需要的 `device_prepare`、`hw_reset`、`irq`、`fingerdown_wait` 和 `wakeup_enable` 接口；用户态采用已在 sheng 上完成录入、列举、删除和验证测试的 [ianchb/xiaomi-sheng-fingerprint](https://github.com/ianchb/xiaomi-sheng-fingerprint)，以私有 libfprint 方式接入 fprintd，同时启动 QTEE supplicant、文件系统和 RPMB listeners。`fpcsheng.elf` 固定 SHA-256 为 `269b403b81392c93036dfab37b2408570d98f7d900a0ab29799005b1a7ca08c4`，避免远端固件静默变化。

实机联调还发现 FPC trusted application 会先用一个很短的 IRQ 表示 `FINGER_DOWN_SETUP` 命令完成，它并不代表手指已经按下。内核侧增加一次性 IRQ pending 锁存，避免用户态轮询错过这个边沿；用户态随后以 20 ms 退避查询 TA 的触摸资格状态，确认真实触摸后使用立即采集模式。修正前空闲录入会持续产生 `enroll-retry-scan`，修正后每次真实触摸只推进一个样本，空闲时不再触发采集或占满 CPU。

刷入包含新 DTS/内建驱动的 boot 并更新 NixOS generation 后验证：

```sh
dmesg | grep -Ei 'fpc1552|fingerprint|qtee|tee0|rpmb'
systemctl status qteesupplicant fprintd --no-pager
ls -l /sys/bus/platform/devices/fingerprint_fpc
fprintd-enroll
fprintd-verify
```

在实机完成录入和验证前，状态保持“联调中”，不把构建成功写成硬件已经可用。

## 已确认健康的链路

```text
ADSP remoteproc
  -> charger_pd / sensor_pd PDR
  -> adsprpcd / pd-mapper / sensorspd
  -> iio-sensor-proxy
```

```text
WCN7850 PMU power sequence
  -> PCI power control
  -> SM8550 PCIe Gen2 x2
  -> ath12k Wi-Fi 7
```

```text
charger_pd
  -> PMIC GLINK
  -> UCSI registration
  -> Type-C role and PD/PPS state
```

本次基线里三条链均能到达最终节点。现阶段优化重点是启动顺序和恢复能力，不是重写已经工作的核心驱动。

## 告警分级

### 已处理

- 六颗 CS35L43 的 `vpbr-enable` 布尔属性格式告警。
- WCN power-sequencer 模块加载过晚导致的 PCIe 重复探测窗口。
- Novatek 固件恢复路径缺少 ReK 等待。
- ADSP 预期的 `/odm/etc/sensors/config` 兼容路径缺失。

### 有线索，但暂不猜测

- CS35L43 的 `VA`/`VP` dummy regulator：驱动绑定要求供电描述，但原厂 DTBO 也没有给出 regulator phandle。需要先从原理图、PMIC rail 或可验证的原厂 regulator 映射确认，不能把 `vph_pwr`/1.8 V 轨凭经验硬填进去。
- PS5169 的 `dvdd` dummy regulator：原厂节点同样没有 supply 映射，Type-C retimer 当前能正常注册。
- WCN7850 的 `vddio1p2` dummy regulator：主线 power-sequencer 要求该名称，但 SM8550 参考 DTS 与 sheng 一样未提供，且现有 Wi-Fi/蓝牙链路可用。后续应先确认 SM8550 封装是否真的有独立 1.2 V IO rail。
- PCIe 的 `vdda`/`vddpe-3v3` dummy regulator：WCN7850 是板载 endpoint，3.3 V 外设轨是否存在需要硬件依据。
- GPU 的 `vdd`/`vddcx` dummy regulator：GPU 已由 GMU/RPMh 电源域正常拉起，不能简单把旧版驱动的通用 supply 名映射到任意 rail。
- `/mnt/vendor/persist/sensors/cam_registry_dump.txt` 只读告警：persist 是 Android 校准分区，当前刻意以只读方式挂载。该文件是可选调试输出，不能为了消除日志把整个校准分区改为可写；如以后确实需要，应只给该路径提供独立的易失性覆盖层。

### 上游描述或日志差异

- `qcom,dmic-sample-rate` 缺失：该属性在绑定中是可选项，驱动缺失时使用默认 divider；原厂 DT 也未提供明确值。录音设备已正常枚举，因此暂不猜 600 kHz 或 4.8 MHz。
- SoundWire TX 报 `dout-ports (0) mismatch with controller (1)`：SM8550 DTS 明确描述 0 个 TX-side DOUT，硬件寄存器报告 1。直接改为 1 会让端口数与现有四组配置数组不一致。录音链路正常，先保留并继续跟踪上游。
- `Kernel image misaligned at boot`：Android boot 参数当前使用传统 `offset_kernel = 0x8000`。直接改为 2 MiB 对齐可能与 ramdisk 布局重叠或触发 bootloader 兼容问题，必须通过单独的临时启动镜像验证，不能在稳定 boot 上试错。

## 刷入后的对比清单

刷入新 boot、rebuild 新 rootfs 后，保持相近电量、充电状态和室温，至少进行三次冷启动：

```sh
systemd-analyze time
systemd-analyze blame --no-pager | head -30
dmesg | grep -E 'pwrseq|qcom-pcie|PCIe Gen|wcn7850|vpbr-enable|cs35l43'
dmesg | grep -Ei 'fpc1552|fingerprint|qtee|tee0|rpmb|pstore|ramoops'
test ! -e /sys/bus/platform/drivers/qcom-hv-haptics
lsmod | grep -E 'pwrseq_qcom_wcn|pci_pwrctrl_pwrseq'
systemctl --failed
```

建议文章使用中位数，不使用最好的一次：

| 指标 | 修改前 | 修改后 | 变化 |
| --- | ---: | ---: | ---: |
| 总启动时间 | 31.918 s | 待测 | 待测 |
| 用户态启动 | 25.791 s | 待测 | 待测 |
| graphical.target | 18.964 s | 待测 | 待测 |
| PCIe link up | 8.162 s | 待测 | 待测 |
| UCSI 注册 | 3.235 s | 待测 | 待测 |
| systemd 失败单元 | 0 | 待测 | 待测 |

音质、快充峰值和续航不能只用启动日志下结论：音质至少要做相同 PipeWire/EQ 配置下的 AB 测试；快充需要低电量、同一充电器和线材；续航需要固定亮度、网络状态和 30 分钟以上的稳定工作负载。

## 后续方向

1. 刷入后完成三次冷启动、指纹录入/验证和扬声器播放/暂停恢复测试。
2. 在用户在场时执行多轮 deep suspend/resume，记录 wakeup source 和 ADSP/UCSI 恢复。
3. 对比 Android live DT 与 Linux DTS 的 regulator consumer 映射，只合入能确认 rail 的 supply。
4. 为 libcamera 缺少的 `ov02b1b`、`ov32d40` IPA tuning 建立独立校准工作，不用未经标定的“算法参数”冒充画质优化。
5. 在低电量条件下分别测 USB-PD/PPS、MiPPS 与电脑 C-to-C，分清协商上限、线材 E-marker 和充电曲线限制。
