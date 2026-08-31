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
