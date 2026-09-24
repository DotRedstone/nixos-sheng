# 关机充电

[English](offline-charging.md)

sheng 和 Android 一样使用正常的 Linux 内核完成关机充电。插入充电器后 bootloader
仍会启动 `boot_b`，但 stage-1 会跳过世代菜单，stage-2 选择
`sheng-offline-charging.target`，而不是启动桌面。

启动检测 generator 把覆盖链接写入 `generator.early`。该目录的优先级高于
NixOS 固定在 `/etc/systemd/system/default.target` 的桌面目标，确保充电启动不会
被 GNOME 默认目标覆盖。

## 行为

- 在黑屏状态完成首帧绘制后再点亮面板，避免短暂露出启动命令；
- 直接在 `/dev/fb0` 绘制圆角横向电池与抗锯齿 Inter 电量数字，黑底搭配薄荷绿，
  低电量使用琥珀色或红色。在原生屏幕上，电池与数字比上一版放大 50%；
- 充电时在真实电量填充区域内播放 3.2 秒一轮的柔光，闪电轻轻呼吸；最多每秒
  10 帧，只重绘电池内部。满电、电量未知或拔线后静止，熄屏后停止绘制；
  Pillow 与随包字体只在绘图时加载，不参与开机模式判断；
- charger 启动会立即进入最小充电 target，不在黑屏的 stage-1 中等待电量；
- 显示 8 秒后自动熄屏，降低待机功耗；
- 短按电源键可再次显示充电界面；
- 电量达到 5% 后，长按电源键 2 秒进入正常图形系统；
- 外部电源断开 10 秒后自动关机；
- 最小充电目标只启动 Qualcomm ADSP、PD mapper 与 MiPPS 认证链，不拉起
  GNOME、Wi-Fi、蓝牙或传感器用户态服务。

充电界面不等待全局 `systemd-udev-settle`；脚本会自行短暂等待 framebuffer 与电池
节点出现。这样慢速或异常的无关设备不会阻塞最先需要显示的充电反馈。电量低于 5%
时长按电源键只会重新显示当前电量，不会拉起完整桌面，从而避免 brownout 重启循环。

启动模式优先识别 AOSP 标准的 cmdline/bootconfig
`androidboot.mode=charger`，同时兼容 sheng 的 Qualcomm PON USB 充电位。
如果 PON 原因中同时存在电源键位，或者设置了
`androidboot.force_normal_boot=1`，则强制按正常开机处理，避免插着充电器主动开机时
误入关机充电。

系统镜像不能把 `androidboot.force_normal_boot=1` 固定写入内核参数；该参数只适合
一次性的救援启动，否则 bootloader 提供的充电启动原因会被永久覆盖。

启动决定保存在 `/run/sheng-boot-ui.mode`，一次开机内只允许确定为 `normal` 或 `charger`。
充电服务只能在明确的 `charger` 决定下绘制；不能自行根据残留的 USB PON 位抢占屏幕。
generator 重跑、正常重启标记清理、切换系统配置均不应改变该决定。有效的待启动世代选择
也代表一次明确的正常开机请求。

电池画面和 NixOS 动画共享 POSIX 绘制锁；充电服务随充电 target 停止，并与桌面、
动画及诊断服务互斥。失去 VT2 或切入诊断后监控退出。minimal 的早期文本控制台切换
只在正常启动执行，不能打断充电画面。

## 部署

本功能同时修改 initramfs stage-1 和 NixOS stage-2。需要构建并刷入匹配的
`boot_b`，随后激活或刷入匹配的 rootfs/系统世代。仅在设备内执行
`nixos-rebuild` 无法更新 stage-1。

电池放大与充电动画只涉及 stage-2。已经安装关机充电启动支持的设备，激活新版系统
世代即可，无须再次刷 boot；切换回上一系统世代即可恢复原界面。

离机预览可运行 `scripts/preview-offline-charging.py OUTPUT.png`，需要 Pillow，
并将 `SHENG_CHARGING_FONT` 指向 `Inter.ttc`。通过 `--capacity`、`--width` 和
`--height` 选择电量与屏幕尺寸。加 `--animate` 导出 GIF/APNG 循环；
`--painter /path/to/sheng-fb-painter` 使用真实绘制程序输出到临时文件，不操作屏幕。
预览与实机使用同一组 SFB1 指令。

设计参考安卓常见的电池与电量层次，动画和图形由本项目绘制：
[Android 充电素材](https://android.googlesource.com/platform/system/core/+/344bff4/healthd/images/)、
[小米充电动画说明](https://www.mi.com/sa-en/support/faq/details/KA-483284/)。

离机回归验证（需要 Pillow 和 Inter 字体）：

```sh
SHENG_CHARGING_FONT=/path/to/Inter.ttc python3 scripts/test-offline-charging.py \
  nixos/scripts/sheng-offline-charging.py /path/to/sheng-fb-painter
```

验证覆盖横竖屏边界、循环无残影、数字静止、拔线及满电停止、熄屏不重绘。
设备上同样可运行该测试，绘制目标是临时文件；它不能替代面板上的动画验收。

## 实机验收

1. 插着电源正常开机，确认仍能进入桌面；
2. 完全关机，不按电源键，直接插入充电器；
3. 确认不出现世代菜单，也不进入桌面；
4. 确认放大的圆角电池与数字清晰，柔光流动时数字不闪烁；8 秒后熄灭，短按
   电源键能够再次唤醒，满电时静止；
5. 长按电源键 2 秒，确认进入正常图形系统；
6. 再次进入关机充电后拔线，确认 10 秒后关机；
7. 分别使用标准 PD 和 MiPPS 充电器检查电流与温度；只显示电量不能证明快充成功。

进入正常系统后可检查：

```sh
cat /proc/cmdline
grep -E 'androidboot.(mode|force_normal_boot)|bootinfo.pureason' /proc/bootconfig
journalctl -b -u sheng-offline-charging.service --no-pager
systemctl status sheng-offline-charging.target --no-pager
cat /run/sheng-boot-ui.mode
systemctl daemon-reload
cat /run/sheng-boot-ui.mode
systemctl is-active sheng-offline-charging.service display-manager.service
```

正常启动的 mode 两次均应为 `normal`，充电服务应不活动；充电启动两次均应为
`charger`，桌面应不活动。还需分别验证插电主动重启、手动世代选择、充电长按开机、
诊断切换及 minimal。离机测试覆盖这些状态交接和显示锁，但不能证明设备已经能稳定启动。

如果模式没有被识别，应保留该次插电启动的完整 cmdline。没有确认正常电源键启动仍可
区分前，不应继续扩大 PON 位掩码。
