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

脚本会脱敏 Android 序列号，不采集 SSID、MAC 地址和 IP 地址，并在同一份报告中保存启动总时间、最慢单元和 `graphical.target` 关键链。公开日志前仍应人工检查一次。

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

### 10. 保留 q6apm 就绪查询，先量化音频超时

基线中 `sheng-audio-modules.service` 用时 3.517 秒，唯一对应异常是 `qcom-apm` 的 `APM_CMD_GET_SPF_STATE` 同步查询超时。驱动通用同步路径允许最多等待 5 秒，而 `q6prm` probe 随后也依赖同一查询结果判断 ADSP 是否可用。Linux 上游当前仍保留这套语义。

本轮不删除、不缩短这个查询：旧系统虽然打印超时，但声卡最终能够枚举；缺少新内核上的重复启动样本时，贸然优化可能把确定的几秒延迟变成偶发无声。基线脚本已经采集 audio unit 与内核告警，刷入后先确认新的 ADSP 启动时序是否自然消除超时，再决定是否需要驱动层修复。

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

1. 刷入后完成三次冷启动和扬声器播放/暂停恢复测试。
2. 在用户在场时执行多轮 deep suspend/resume，记录 wakeup source 和 ADSP/UCSI 恢复。
3. 对比 Android live DT 与 Linux DTS 的 regulator consumer 映射，只合入能确认 rail 的 supply。
4. 为 libcamera 缺少的 `ov02b1b`、`ov32d40` IPA tuning 建立独立校准工作，不用未经标定的“算法参数”冒充画质优化。
5. 在低电量条件下分别测 USB-PD/PPS、MiPPS 与电脑 C-to-C，分清协商上限、线材 E-marker 和充电曲线限制。
