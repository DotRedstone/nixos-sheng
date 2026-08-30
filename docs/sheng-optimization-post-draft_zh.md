# 把一台 Android 平板变成可回滚的 NixOS 设备

> 发布前草稿，数据采集于 2026-08-30。菜单交接补丁已通过实机验收；正式发布时仍应
> 把单次健康启动替换为合并提交的三次冷启动中位数，并附对应提交与校验和。

## 项目做了什么

`nixos-sheng` 是 Xiaomi Pad 6S Pro 12.4（`sheng`，Snapdragon 8 Gen 2 / SM8550）
的 Mobile NixOS 移植。它保留 Android bootloader 和 A/B slot：NixOS kernel、DTB 与
stage-1 initramfs 放在非活动 `boot` slot，可写 NixOS 系统放在独立 ext4 `linux`
分区。Android 分区不需要被改成可写。

真正有价值的不只是“Linux 能开机”，而是把 NixOS 的系统世代带到移动设备：普通
用户态更新可以直接在平板内 `nixos-rebuild`，失败时从 stage-1 framebuffer 菜单选择
旧世代；只有 kernel、DTS、stage-1 和 boot cmdline 变化才需要重刷 boot image。

当前实机已经覆盖：GNOME、触控、四向旋转、屏幕键盘、2.4/5 GHz Wi-Fi、USB-C
role/OTG、Qualcomm SSC 传感器、前后摄 RAW10、标准 PD、小米 MiPPS 认证、
NT36532E THP 触控笔，以及 FPC1553 指纹录入和验证。

## 三个故障其实是一条时序链

最初的现象是：initramfs 停久后传感器消失、快充偶尔不恢复，登录桌面又可能出现
下游错误。它们并不是完全独立：

```text
ADSP remoteproc
  -> FastRPC / pd-mapper
  -> sensor_pd / charger_pd
  -> SSC / UCSI / PD-PPS
  -> iio-sensor-proxy / MiPPS / desktop session
```

用户态服务过去只检查进程或设备节点是否出现，没有确认 SSC 能否真实查询；MiPPS 也
可能在 Type-C、SVID 和 PDO 尚未稳定时过早放弃。修复后，`sensorspd` 必须通过一次
真实 SSC 查询才能完成启动，失败由 systemd 重启整条 sensor PD daemon；MiPPS 在握手
前等待 PD/PPS、Xiaomi SVID 和 PDO，并对早期临时状态重试。

发布审计又找到更隐蔽的一层：一次启动中 `e2fsck -p` 只用了约 0.18 秒，真正的
29 秒停留发生在世代菜单。该样本随后稳定复现 `SSC QMI Service not found`，
`adsprpcd-sensorspd` 重启超过 18 次。普通重启则恢复为两个传感器服务
`NRestarts=0`。

最终方案没有删掉菜单，也没有继续给用户态叠加 sleep：3 秒无操作仍直接启动；用户
手动选择后，stage-1 原子保存目标世代并快速重启，下一次启动一次性消费选择并跳过
菜单。用户可以慢慢挑世代，硬件仍得到一次干净、短时序的启动。

## 从“能跑”到“可恢复”

- 根分区每次挂载前执行 `e2fsck -p`，自动修复失败才回退到 `-fy`；不再因一次硬重启
  无条件全盘 `-f` 扫描。
- rootfs 只由 stage-1 在离线状态按需扩到 `linux` 分区；stage-2 不再对 Android GPT
  运行 `growpart`，也不再做同尺寸在线 resize。
- ext4 以 `errors=remount-ro` 保护数据；运行时检测到实际只读后同步并请求正常重启，
  让下一次 stage-1 离线修复，而不是强行 remount 继续写。
- 低电量 charger-mode 留在黑屏低功耗 stage-1 充到 5% 再进桌面，避免“进系统耗电
  -> brownout -> USB 再拉起”的循环。
- ramoops 按原厂 DTBO 恢复 4 MiB 持久区，异常重启后终于能留下 kernel console/pmsg。

## 驱动和功耗审计

- WCN7850 power sequencer 与 PCI power control 改为 built-in，缩短 PCIe deferred
  probe 窗口；ath12k 仍保持模块化。
- 六颗 CS35L43 恢复原厂 standby 策略，并修正 DT 布尔属性写法；音质结论仍必须用
  同一 PipeWire/EQ 状态做 A/B，不拿主观记忆当算法测试。
- PS5169 补齐 I2C client data，修复 unbind/remove 的空指针风险。
- Novatek WDT 恢复路径删除会阻止状态机推进的错误 ReK 前置等待。
- CAMSS 在 7.1.8 上完成 120 次 runtime-PM 循环后恢复 `auto`；空闲时 AHB 与
  CAMNOC->DDR 投票降为 0，Titan Top GDSC 能进入 off。
- pd-mapper 易失固件集从约 46 MiB 收窄到约 180 KiB，只保留服务映射和 devauth。
- WirePlumber 只隔离曾触发崩溃的 BlueZ MIDI monitor，普通蓝牙音频 monitor 保留。

没有硬件证据的 regulator 没有被随意映射。CS35L43、PS5169、WCN7850、PCIe 和 GPU
仍可能报告 dummy regulator；原厂 DT 也未给出相应 rail 时，保留可解释告警比把一个
“电压看起来差不多”的 PMIC 输出硬接上更安全。

## 当前数据

| 指标 | 旧基线 | 当前候选单次健康启动 |
| --- | ---: | ---: |
| Kernel | 6.126 s | 9.075 s |
| Userspace | 25.791 s | 11.990 s |
| 总启动 | 31.918 s | 21.066 s |
| `graphical.target` | 18.964 s | 11.006 s |
| 失败单元 | 0 | 0 |
| `adsprpcd-sensorspd` / `iio-sensor-proxy` 重启 | 未记录 | 0 / 0 |

旧基线和当前内核版本不同，因此这张表只能说明整个系统候选版的结果，不能把差值全部
归因于某一条内核提交。正式帖子应补三次相近电量、室温和供电状态的冷启动中位数。
故意停留旧菜单产生的 58.880 秒失败样本也应保留，它证明了为什么需要手动选择交接。

菜单修复的针对性回归使用提交 `86c2b22` 的 boot image：先在菜单停留约 24 秒，手动
确认后只发生一次快速重启；第二次启动跳过菜单并删除一次性标记，总计 18.075 秒，
`graphical.target` 在 userspace 11.216 秒到达。SSC/IIO 均 active 且重启次数为 0，
root 为可写 ext4、`errors_count=0`。这组数据用于证明时序修复有效，不与冷启动基线
混作同一个性能样本。

## 仍然不承诺什么

- MiPPS 能解锁不等于持续 120 W；功率受电池电量、温度、线材、充电器和充电曲线限制。
- 电脑 C-to-C 数据口受 USB 枚举与 charger firmware 电流限制，不能把 Type-C source
  通告直接当作平板实际可取电流。
- 相机已抓到前后摄 RAW10，不等于 libcamera、自动曝光、HDR 和厂商画质算法已经完成。
- ALSA 设备枚举不等于音质已调完；蓝牙控制器存在不等于所有音频 profile 已验证。
- 触控笔和指纹已经可用，但仍需要更多绘画软件、熄屏唤醒和 suspend/resume 覆盖。
- 闭源 firmware、TA 和二进制的获取不自动授予镜像再分发权限。

## 发帖建议素材

建议正文展示四类证据：stage-1 世代菜单实拍；`systemd-analyze` 与服务
`NRestarts=0`；触控笔压感/倾斜和指纹录入；低电量、MiPPS、电脑 C-to-C 三种充电
场景的分开记录。附上仓库、准确 commit、release 校验和以及
[`release-readiness_zh.md`](release-readiness_zh.md)，比只写“基本完美”更有说服力。
