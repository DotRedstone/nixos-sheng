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

脚本会脱敏 Android 序列号，不采集 SSID、MAC 地址和 IP 地址。公开日志前仍应人工检查一次。

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
| 温度 | SoC 约 31–36°C，PMIC 约 37°C，电池约 29.7°C |
| ADSP | `running`，固件为 sheng 原厂 ADSP |
| CDSP | `offline`，按需启动，属于预期状态 |
| USB-C/UCSI | charger PD 约 0.87 秒出现，UCSI 约 3.23 秒注册成功 |
| Wi-Fi | PCIe Gen2 x2，WCN7850/ath12k 正常工作 |
| 音频 | 2 个 playback、1 个 capture，PipeWire 扬声器 EQ 正常接入 |
| 休眠统计 | 尚未做安全的 suspend/resume 循环测试 |

三秒空闲采样中，各 CPU 的深空闲累计驻留时间约 2.96–3.03 秒。这说明现有调速器和 cpuidle 基本可用，不应在没有能耗仪数据时盲目更换 governor 或抬高最低频率。

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

### 有线索，但暂不猜测

- CS35L43 的 `VA`/`VP` dummy regulator：驱动绑定要求供电描述，但原厂 DTBO 也没有给出 regulator phandle。需要先从原理图、PMIC rail 或可验证的原厂 regulator 映射确认，不能把 `vph_pwr`/1.8 V 轨凭经验硬填进去。
- PS5169 的 `dvdd` dummy regulator：原厂节点同样没有 supply 映射，Type-C retimer 当前能正常注册。
- WCN7850 的 `vddio1p2` dummy regulator：主线 power-sequencer 要求该名称，但 SM8550 参考 DTS 与 sheng 一样未提供，且现有 Wi-Fi/蓝牙链路可用。后续应先确认 SM8550 封装是否真的有独立 1.2 V IO rail。
- PCIe 的 `vdda`/`vddpe-3v3` dummy regulator：WCN7850 是板载 endpoint，3.3 V 外设轨是否存在需要硬件依据。
- GPU 的 `vdd`/`vddcx` dummy regulator：GPU 已由 GMU/RPMh 电源域正常拉起，不能简单把旧版驱动的通用 supply 名映射到任意 rail。

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
