# 关机充电

[English](offline-charging.md)

sheng 和 Android 一样使用正常的 Linux 内核完成关机充电。插入充电器后 bootloader
仍会启动 `boot_b`，但 stage-1 会跳过世代菜单，stage-2 选择
`sheng-offline-charging.target`，而不是启动桌面。

## 行为

- 直接在 `/dev/fb0` 绘制电池图标和电量百分比；
- 显示 8 秒后自动熄屏，降低待机功耗；
- 短按电源键可再次显示充电界面；
- 长按电源键 2 秒进入正常图形系统；
- 外部电源断开 10 秒后自动关机；
- 最小充电目标只启动 Qualcomm ADSP、PD mapper 与 MiPPS 认证链，不拉起
  GNOME、Wi-Fi、蓝牙或传感器用户态服务。

启动模式优先识别 AOSP 标准的 cmdline/bootconfig
`androidboot.mode=charger`，同时兼容 sheng 的 Qualcomm PON USB 充电位。
如果 PON 原因中同时存在电源键位，或者设置了
`androidboot.force_normal_boot=1`，则强制按正常开机处理，避免插着充电器主动开机时
误入关机充电。

## 部署

本功能同时修改 initramfs stage-1 和 NixOS stage-2。需要构建并刷入匹配的
`boot_b`，随后激活或刷入匹配的 rootfs/系统世代。仅在设备内执行
`nixos-rebuild` 无法更新 stage-1。

## 实机验收

1. 插着电源正常开机，确认仍能进入桌面；
2. 完全关机，不按电源键，直接插入充电器；
3. 确认不出现世代菜单，也不进入桌面；
4. 确认电池界面出现，8 秒后熄灭，短按电源键能够再次唤醒；
5. 长按电源键 2 秒，确认进入正常图形系统；
6. 再次进入关机充电后拔线，确认 10 秒后关机；
7. 分别使用标准 PD 和 MiPPS 充电器检查电流与温度；只显示电量不能证明快充成功。

进入正常系统后可检查：

```sh
cat /proc/cmdline
grep -E 'androidboot.(mode|force_normal_boot)|bootinfo.pureason' /proc/bootconfig
journalctl -b -u sheng-offline-charging.service --no-pager
systemctl status sheng-offline-charging.target --no-pager
```

如果模式没有被识别，应保留该次插电启动的完整 cmdline。没有确认正常电源键启动仍可
区分前，不应继续扩大 PON 位掩码。
