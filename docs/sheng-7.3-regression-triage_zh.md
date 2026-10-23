# Sheng Linux 7.3：分阶段补丁验收与 Wi-Fi / SSC 定位

> 分支：`DotRedstone/nixos-sheng:exp/7.3-ramoops-validation`
>
> 纯净内核：`map220v/sm8550-mainline:sheng-7.3 @ 9ce9cb0e1543980f85f5a44c074e44c569cf793d`
>
> 本轮唯一内核代码变更：`DotRedstone/linux-sheng:contrib/sheng-ramoops-20261022`，在设备树加入 0xa7000000 / 4 MiB ramoops。
>
> **不要把本轮的 ramoops 测试当成 Wi-Fi 或 SSC 已修复。**

## A. 为什么先不乱改 Wi-Fi 和 FastRPC

- Wi-Fi 实测为 `wlp1s0` 枚举成功，但执行 UP 时 WMI 16387 / QMI -110 超时。此日志不足以区分固件模式转换、PCIe/ASPM、电源、驱动回归和设备配置。旧 7.1.8 与上游 7.3 板级 DTS 的 Wi-Fi 供电节点非常相近，不能先验认定是 PCIe 时序问题。
- `no reserved DMA memory for FASTRPC` 是 `drivers/misc/fastrpc.c` 在 `of_reserved_mem_device_init_by_idx()` 失败时打印的 `dev_info`，**旧版 7.1.8 与 7.3 的实现都存在这条信息**。旧版 sheng DTS 同样没有本文所述的专用 FastRPC 内存池。它不等价于 DMA 分配必然失败，因此**禁止未经内存布局核对就随意在 DTS 硬编码一块 CMA/reserved-memory**。
- 报告中“摄像头通过”主要来自节点/管道枚举，不等于真实取帧；“音频通过”主要来自编解码器/功放绑定，不等于六颗扬声器均有声音。人工测试前状态应为“枚举 PASS / 物理输出待验证”。
- `/sys/fs/pstore` 为空不代表 ramoops 初始化失败；没有上一次崩溃时它可以为空。只核验注册、DT reserved-memory、驱动日志，不故意触发 panic。

## B. 当前运行的 7.3 先采证（刷下一版之前）

以下命令在电脑 Linux 端运行，仅采集数据，**不重启、不重置设备、不更改网络管理状态**。请保存原始输出（包括时间戳），必要时在结果公开前脱敏。

```bash
mkdir -p ~/sheng-7.3-validation/logs-regressions
cd ~/sheng-7.3-validation/logs-regressions

adb shell 'uname -a; cat /proc/cmdline; cat /proc/version' > baseline.txt 2>&1
adb shell 'journalctl -b -k --no-pager -o short-monotonic' > kernel-boot.log 2>&1
adb shell 'journalctl -b --no-pager -u NetworkManager -u iio-sensor-proxy' > services.log 2>&1

adb shell 'ip -d link show wlp1s0; iw dev; nmcli -f GENERAL device show wlp1s0' > wifi-state.txt 2>&1
adb shell 'ls -l /sys/bus/pci/devices/0000:01:00.0; cat /sys/bus/pci/devices/0000:01:00.0/power/control; (ethtool -i wlp1s0 || true)' > wifi-pci.txt 2>&1

adb shell 'ls -l /dev/fastrpc* /dev/adsprpc* 2>&1 || true; systemctl status iio-sensor-proxy --no-pager -l; busctl --system list' > ssc-state.txt 2>&1
adb shell 'journalctl -b --no-pager | grep -Ei "fastrpc|adsp|cdsp|ssc|sensor|qmi|glink|smem" | tail -350' > ssc-journal.txt 2>&1

adb shell 'dmesg | grep -Ei "pstore|ramoops|reserved memory"' > ramoops-before.txt 2>&1
```

若 `adb shell` 返回权限不足、工具不存在或服务名不同，应在日志中记录而不是伪造 PASS。

## C. 仅在保存启动日志之后，复现 Wi-Fi 激活故障

此步骤会尝试操作网络接口，可能暂时改变连接状态。让终端 Agent 在确认目前仍通过 USB ADB 连接、且无需依赖 Wi-Fi 远程控制之后再执行。

```bash
adb shell 'date; ip link show wlp1s0; ip link set wlp1s0 up; echo "link_up_exit=$?"; ip link show wlp1s0' > wifi-up-attempt.txt 2>&1
adb shell 'dmesg | tail -350' > wifi-after-attempt.log 2>&1
```

记录是否每次复现、是否仅冷启动失败、固件版本、PCIe runtime PM 状态、接口变为 unmanaged 的时间顺序。**不要为了掩盖超时而盲目增加 sleep 或无限重试。**

## D. Ramoops 专项验收（下一轮 boot）

只有当独立内核 CI 通过、并确认匹配的 rootfs 构建通过后，才刷测试镜像；仍按原项目刷 `boot_b` + `linux` 的方式，保持 Android A 槽不变。本轮不要引入 CS35L43、THP、FPC、Wi-Fi 或 SSC 的其他修改。

```bash
adb shell 'uname -r; ls /lib/modules; cat /proc/iomem | grep -Ei "a7000000|ramoops|reserved"'
adb shell 'dmesg | grep -Ei "ramoops|pstore|persistent ram|reserved memory"'
adb shell 'ls -l /sys/fs/pstore /sys/bus/platform/devices/*ramoops* 2>/dev/null || true'
```

验收标准：系统能启动，保留的 4 MiB 地址无冲突警告，ramoops/pstore 组件正确注册；不能因为 pstore 空目录就判 FAIL，禁止主动制造 panic。

## E. 下一轮诊断闭环

| 子系统 | 当前证据 | 下一步 | 不可据此声称 |
| --- | --- | --- | --- |
| ramoops | DTS 缺 4 MiB 节点，7.1.8 有 | 单补丁构建、启动、注册检查 | 已验证异常重启后的日志持久化 |
| Wi-Fi | WMI/QMI 超时，无法 UP | 保存完整 boot 日志、PCIe 电源/固件、一次受控复现 | 仅凭 timeout 断言是启动时序 |
| SSC | D-Bus 超时、FastRPC 信息日志 | 联合检查 daemon、GLINK、DSP、DMA 分配失败日志 | 仅凭 `no reserved DMA memory` 断言必须预留新物理地址 |
| 音频 | 六颗功放枚举成功 | 人工低音量播放录音 | 六扬声器均正常发声 |
| 摄像头 | CAMSS 和用户态枚举成功 | 实际 RAW 帧/预览取帧 | 摄像头已经可用 |
| 触控笔/指纹 | 旧分支驱动缺失 | 待 Wi-Fi/SSC 确诊后分别移植 | 需要一次性 cherry-pick 全部 7.1.8 历史 |
| MiPPS | 标准充电可用 | 先确认现有用户态服务，再核对最小内核差异 | 自动支持 120W |
