# TODO

[English](TODO.md) | [简体中文](TODO_zh.md)

本文只跟踪 Xiaomi Pad 6S Pro 12.4（`sheng`）NixOS 移植当前仍有意义的事项。
勾选代表已经在实机验证，不代表“内核配置里打开了选项”。

## 图例

- `[x]` 已在 sheng 实机验证
- `[~]` 已接入，但仍需扩大场景或延长测试
- `[ ]` 尚未完成
- `[-]` 当前阶段明确不做

## 已验证平台能力

- [x] 使用非活动 `boot` slot 和独立 ext4 `linux` 分区的 Mobile NixOS
  Android 启动流程。
- [x] 可写 rootfs、stage-1 离线检查/扩容、ext4 健康监控，以及设备内
  `nixos-rebuild` 世代切换。
- [x] 桌面无关公开 flake 构造器、可选 GNOME 构造器和私人 dotfiles 下游接入。
- [x] Stage-1 framebuffer 世代菜单：默认 3 秒启动、分页、音量键/方向键导航、
  长按连续移动、电源键/Enter 确认。
- [x] GNOME、gjs-osk、四向旋转、盖板处理、触控和电源键亮灭屏控制。
- [x] 2.4 GHz/5 GHz Wi-Fi、USB-C role/OTG、标准 USB-PD 与小米 MiPPS 认证。
- [x] Qualcomm SSC 加速度计、距离、光感和指南针，经
  `iio-sensor-proxy` D-Bus 提供给桌面。
- [x] 前后摄通过 V4L2/CAMSS 抓取 RAW10 实际画面。
- [x] NT36532E THP 多点触控，以及 Xiaomi Focus Pen 的压感、倾斜、悬停和按键事件。
- [x] FPC1553 指纹设备发现、图形化录入和验证，使用基于 QTEE 的私有
  libfprint 驱动。

## 仍需扩大验证

- [~] 蓝牙控制器启动和 Focus Pen HID 重连可用；普通扫描、配对、蓝牙音频和
  suspend/resume 仍需更多设备验证。
- [~] ALSA 播放/录音设备已枚举，音频用户态已接入；发布镜像仍需重复播放、录音
  和受控音质对比。
- [~] 小米 120W MiPPS 已能解锁，但持续功率受电量、温度、充电器和线材影响；
  宣传时只给实测曲线，不承诺固定瓦数。
- [~] 电脑 C-to-C 充电遵循 USB 数据口电流限制；没有主机和 charger firmware
  允许更高档位的证据前，不强推电流。
- [~] RAW 相机可用，但 libcamera、自动曝光和完整桌面相机应用尚未完成。
- [~] 触控笔防误触和按键映射需要覆盖更多绘画软件。
- [~] 指纹熄屏唤醒解锁还需多轮熄屏和 suspend/resume 测试。

## 发版阻断项

- [x] 已实机验证“手动选世代后的快速重启交接”：菜单停留约 24 秒后手动确认，
  下一次启动跳过菜单，且 SSC/IIO 均为 `NRestarts=0`。
- [x] 已通过 PR #1 将 `DotRedstone/linux-sheng:feat/stylus-thp` 合并到维护中的
  7.1.8 分支，并把 `shengKernelSrc` 锁定到该维护分支。
- [ ] 通过经过审查的 PR 把当前 audit 分支合并进默认 `sheng` 分支；不要直接从
  audit 分支发布。
- [ ] boot、minimal rootfs、GNOME rootfs 必须来自同一个合并提交；发布前核对
  workflow `headSha`、校验和、boot 分区大小、内核模块版本和 ext4 特性。
- [~] 已完成 1 次故意长时间停留菜单的交接回归；合并提交候选版仍需做 3 次普通
  启动并保留
  `systemd-analyze`、失败单元、coredump、SSC、充电、rootfs 和内核告警证据。
- [ ] 每次发布都复核闭源固件和二进制的再分发权限；能获取源码或文件不等于
  获得再分发许可。

## 后续工作

- [ ] 接入 libcamera 调校/IPA 和完整桌面相机路径。
- [ ] 验证蓝牙音频 profile 与长时间 suspend/resume。
- [ ] 在同一 PipeWire/WirePlumber 状态下做可重复的扬声器和麦克风 A/B 测试，
  同时公开测试方法。
- [ ] 使用外置功率计扩大充电器、线材、电量和温度覆盖。
- [ ] 解码剩余的 Xiaomi proximity payload 告警；只有应用确实需要时再单独暴露 gyro。
- [ ] 完善恢复文档，并自动生成脱敏的候选版健康检查包。
- [-] 当前 SSC + D-Bus 已满足桌面，不为“看起来更原生”单独编写 kernel IIO
  bridge；只有软件严格依赖 IIO sysfs 时再评估。
