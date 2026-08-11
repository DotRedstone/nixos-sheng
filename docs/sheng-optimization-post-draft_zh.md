# 把一台 Android 平板的 NixOS 启动链重新理顺

> 状态：草稿。文中“修改后”数据必须在刷入新 boot、rebuild 新系统后实测填写，不能用预期值代替结果。

## 问题不是三个孤立故障

Xiaomi Pad 6S Pro（sheng）上的传感器、MiPPS 快充和桌面登录异常，最初看起来互不相关。沿启动时间线检查后，三者都经过 Qualcomm 的远端处理器和用户态服务链：

```text
ADSP remoteproc
  -> FastRPC / pd-mapper
  -> sensor_pd / charger_pd
  -> iio-sensor-proxy / UCSI / MiPPS
  -> GNOME 会话
```

stage-1 菜单曾在正常启动时无条件等待，后面的服务又普遍假设底层已经就绪。于是上游多等几十秒，传感器和快充就可能在错误时间开始一次性初始化。修复思路不是给每个症状分别加睡眠，而是先消除无意义等待，再让每一层只在依赖真正可用时继续，并在暂时失败时可恢复。

## 先测，再改

基线内核为 `Linux 7.0.0`，一次启动结果如下：

| 指标 | 修改前 | 修改后（三次中位数） |
| --- | ---: | ---: |
| 内核阶段 | 6.126 s | 待测 |
| 用户态阶段 | 25.791 s | 待测 |
| 总启动时间 | 31.918 s | 待测 |
| graphical.target | 18.964 s | 待测 |
| NetworkManager-wait-online | 17.926 s | 不再进入启动事务 |
| PCIe Gen2 x2 link up | 8.162 s | 待测 |
| systemd 失败单元 | 0 | 待测 |

CPU 三个 cluster 已经使用 `schedutil`，GPU 和 UFS 空闲时也能降到最低 OPP，8 个 CPU 都能进入深空闲。因此本轮没有换 governor、锁大核或抬最低频率。那些改法容易让短跑分变好，却会直接损害平板的温度和续航。

仓库中的 `scripts/collect-hardware-baseline.sh` 会一次保存启动关键链、频率、cpuidle、温度、UFS、充电、ADSP、USB-C、相机 runtime PM、硬件服务重启次数、当次启动 coredump 和内核告警，并脱敏 Android 序列号。

## 第一批实际修改

### 启动路径

- 只有用户明确请求，或确实需要选择多个 generation 时才显示 stage-1 菜单。
- 移除没有消费者的 `NetworkManager-wait-online`，网络继续异步连接。
- 把 WCN7850 power-sequencer 和 PCI power-control 编进内核，避免 PCIe 从约 0.2 秒开始反复 deferred probe，直到 rootfs 在约 7.7 秒加载模块。
- 恢复 pd-mapper 正常读取 firmware-class 路径，不再用无效文件描述符制造两条假错误。
- 将 pd-mapper 的启动解压集从整个 sheng 固件目录收窄到服务映射 JSON 和 `devauth.mbn`。旧系统每次启动在 tmpfs 生成约 46 MiB 重复固件；用设备当前固件复现后，新集合只占 180 KiB。源码审计和二进制字符串确认其余 ADSP/CDSP/VPU 镜像既不由 pd-mapper 读取，也不参与 devauth FastRPC 加载。

### 恢复能力

- SSC 未可查询时让 `iio-sensor-proxy` 启动失败并由 systemd 重试，不再带着半初始化状态进入桌面。
- MiPPS 在握手前检查 Type-C、PD/PPS、SVID 和 PDO，暂时未就绪时继续重试。
- FastRPC 服务私有映射 `/odm/etc/sensors/config`，兼容原厂 ADSP 路径，但不污染根目录，也不把 Android persist 分区改为可写。
- 移除 FastRPC 服务过早执行的 `ConditionPathExists`。现在节点稍晚出现时会进入明确的 remoteproc/FastRPC 稳定等待，而不是在等待脚本运行前就被 systemd 永久跳过。
- Novatek 触控固件 WDT 自恢复后先等待 ReK 基线状态，再发送 idle/doze 命令。这个缺口在一次约 89 分钟后的真实固件复位中表现为连续 `0xBF` 命令失败。
- 按原厂 DTBO 恢复 `0xa7000000` 的 4 MiB ramoops 区域。此前内核虽启用 pstore，DTS 却没有后端，异常重启后 `/sys/fs/pstore` 永远为空；以后可以跨重启保存最后的 kernel console/pmsg。

### 驱动正确性

- 六颗 CS35L43 恢复原厂 DTBO 明确使用的 standby 策略，并修正布尔属性写法。
- PS5169 probe 保存 I2C 私有数据，避免 unbind/remove 路径取到空指针。
- 触觉驱动不再套用 185--215 Hz 的通用 LRA 窗口。sheng 原厂 DTBO 明确给出 6667 us，约为 150 Hz，小米公开的 `sheng-u-oss` 驱动也不会在启动时把它强制改成 205 Hz。这里保留精简后的 Linux FF 接口，只删除与本机执行器冲突的机型专用 workaround。

这些修改都刻意避开了没有硬件依据的 regulator 映射。CS35L43、PS5169、WCN7850、PCIe 和 GPU 仍有 dummy regulator 告警，但原厂 DT 也没有给出对应 rail；随手指向一个“看起来电压差不多”的 PMIC 输出，比保留告警危险得多。

## 意外发现的续航大项

当前系统为规避历史 CAMSS/RPMh 超时，把相机子系统永久设为 runtime active。实测 Titan Top GDSC 常开，空闲时 AHB 与 CAMNOC→DDR 仍各保留 2097152 kB/s 带宽投票。各 IFE 子域和相机时钟虽然已经关闭，这个固定投票仍可能抬高片上互连和内存功耗。

这项暂时没有直接删除：旧备注指出切回 `auto` 曾连带阻塞共享的 UFS 互连。正确验证需要在可恢复环境里同时抓 RPMh/ICC trace、循环开关相机并做 UFS I/O，不能在无人看管时拿系统盘试错。它会是下一批最值得量化的功耗优化。

音频模块还有一个值得继续追踪的延迟：`q6apm` 首次查询 `APM_CMD_GET_SPF_STATE` 时等待 DSP 回包并超时，旧系统因此让 `sheng-audio-modules` 用时 3.517 秒。审计还发现查询错误被丢弃后，负 errno 会经 `bool` 转换反而表示“ADSP 已就绪”。本轮已修正错误传播并删除 probe 中结果无人使用的重复查询，但保留 `q6prm` 真正的同步就绪门禁；所有图管理命令共享的 5 秒超时没有被激进缩短。

历史日志还保留了两次 WirePlumber `SIGSEGV`。它们都发生在 BlueZ MIDI 反复注册 GATT 服务失败之后，core 栈也经过 PipeWire 的 D-Bus SPA 层。系统现在只关闭独立的 BLE MIDI monitor，普通蓝牙音频 monitor、ALSA 声卡和 libcamera monitor 均保持启用。这解释了“音频设备突然消失但重启用户态又恢复”的一部分现象，也避免把用户态会话管理器崩溃误归因于 codec 驱动。

## 刷入后的验证方式

1. 在相近电量、充电状态和室温下做至少三次冷启动，文章只使用中位数。
2. 检查传感器方向、光线、距离和触觉短振/长振，重复登录 GNOME，确认没有 failed unit 和 coredump。
3. 做扬声器播放、暂停、再次播放，确认六颗功放恢复无首帧丢失；音质使用同一 PipeWire/EQ 配置做 AB，不用主观记忆跨版本比较。
4. 低电量下用同一充电器和线材分别测试 USB-PD/PPS、MiPPS 与电脑 C-to-C，记录协商档位和电池端功率。
5. 用户在场时再做多轮 deep suspend/resume、PS5169 unbind/bind 和 CAMSS runtime-PM 实验。

## 当前结论

这轮工作的重点不是把 dmesg 变得干净，也不是堆“性能参数”，而是把启动依赖、错误恢复和原厂硬件时序变成可解释、可复现的系统。代码已经在 `audit/sheng-hardware-optimization` 分支完成首批修改；启动速度、稳定性和续航的最终结论，要等新 boot 与 rootfs 上机后用同一套脚本补完数据。
