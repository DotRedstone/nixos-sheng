# Sheng 性能与内存压力策略

[English](performance-tuning.md)

默认策略的目标是在内存压力下保持桌面可恢复，而不是锁定 CPU、GPU 或 UFS 高频。
现有实机记录表明，`schedutil` 和 devfreq 调速器空闲时已经能降到最低频率，因此在
取得每瓦性能证据前，不调整最低频率和 governor。

## 默认策略

`services.sheng-performance.enable` 默认启用，并应用以下配置：

- 使用单个 zstd zram swap，未压缩容量上限为物理内存的 50%；
- 设置 `vm.swappiness=100`，让匿名页在全局回收长时间停顿前使用 zram；
- 设置 `vm.page-cluster=0`；压缩内存没有寻道开销，避免换入时额外解压未使用页面；
- 让 systemd-oomd 监控用户 slice，在持续桌面内存压力演变为内核全局 OOM
  卡死前进行恢复。

zram 的 50% 是逻辑容量上限，不会预留一半物理内存。实际占用和压缩率应通过
`zramctl` 与 `mm_stat` 判断。

## 采集报告

在仓库中运行只读采集脚本：

```sh
sudo ./scripts/collect-hardware-baseline.sh 10 > sheng-performance.txt
```

报告包含启动耗时、CPU/devfreq 策略、空闲驻留、温度、PSI、MGLRU/THP 状态、
zram 统计、OOMD 状态、存储计数、电源、硬件服务、coredump 和内核告警。脚本不
采集 SSID、IP 地址或 MAC 地址；公开前仍应人工检查内核与服务日志中的设备信息。

有效的 A/B 测试应在修改前后分别完成三次普通启动，并运行相同工作负载。重点比较
启动时间、`memory full` PSI、zram 压缩率、OOMD 动作、应用存活、温度和空闲驻留。
单次跑分不足以支持更换 governor 或锁频。

## 覆盖与回退

下游配置可以调整 zram 上限或关闭策略：

```nix
{
  services.sheng-performance = {
    zramMemoryPercent = 35;
    protectUserSessions = false;
    # enable = false;
  };
}
```

关闭模块会恢复 NixOS 上游默认值，不修改内核、boot 镜像或 Android 分区。

## 2026-08-31 实机验证

修改前运行中的系统为 `vm.swappiness=60`、`vm.page-cluster=3`，且
`oomctl dump` 的 `Memory Pressure Monitored CGroups` 为空。设备内完成 stage-2
重建并普通重启后，sheng 的结果如下：

- `vm.swappiness=100`、`vm.page-cluster=0`；
- `/user.slice` 及其应用子 slice 以 80% 压力、持续 30 秒为门限接受监控；
- systemd 失败单元和 coredump 均为 0；
- ADSP、pd-mapper、sensor PD、iio-sensor-proxy、NetworkManager 和显示管理器
  全部运行，重启计数均为 0；
- 空闲内存 PSI 为 0，重启后没有再次出现构建期间的 GPU 告警。

本次重建不能作为修改前后性能跑分。私人配置中的 Rnote 首次源码构建占据了绝大
部分时间，墙钟耗时 28 分 54 秒，峰值使用 5.7 GiB RAM 和 7.2 GiB swap。新策略
激活前的这段极端负载中出现过一次 Adreno GMU 性能投票超时，重启后未复现。

验证启动总耗时 36.082 秒，但 stage-1 日志表明其中 14.8 秒是挂载 12 次后按计划
触发的 ext4 完整检查。用户态在 11.513 秒到达 `graphical.target`，与旧样本的
11.216 秒接近。后续对比必须保留并单独标记这项用于保护可写根分区、与内存策略
无关的周期检查。
