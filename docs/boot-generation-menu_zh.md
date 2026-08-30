# Sheng 启动世代菜单

[English](boot-generation-menu.md) | [简体中文](boot-generation-menu_zh.md)

Sheng 使用固定的 Android `boot_b` 镜像作为启动基础，并从可写的 `linux`
分区中选择 NixOS stage-2 世代。

每次启动都会显示世代菜单，并在 3 秒无操作后自动进入最新世代。需要更多选择
时间时，按一下导航键即可暂停倒计时。从正在运行的系统也可以直接重启到菜单：

```sh
sudo sheng-reboot-generation-menu
```

该命令会重启设备；菜单本身不再依赖需要卡时机完成的三击手势。

菜单会在 framebuffer 上显示两层世代信息、当前选择位置、按键图标和自动启动
进度。选中的世代使用高对比色块和方向标记强调。

- 音量上下键或外接键盘上下方向键用于切换高亮的 stage-2 世代。
- 高亮会在当前页内逐行移动；越过本页最后一项时才切换到下一页。
- 长按导航键会连续移动选择。
- 音量键采用边沿触发，重绘不会等待延迟的松键事件。
- 电源键或外接键盘 Enter 键确认启动。
- 3 秒无操作后自动启动当前高亮项；移动选择会暂停倒计时。
- 菜单直接绘制到 framebuffer，并根据屏幕尺寸调整面板和可见行数。
- 世代编号与日期、版本分层显示，长版本信息不会挤占主标题。
- 倒计时使用状态文字和进度条共同表达；手动移动选择后会显示暂停状态。
- framebuffer 不可用时会自动回退到 tty 文本菜单，避免只有输入却没有画面。
- 只有选择变化、滚动窗口变化或倒计时变化时才重绘对应区域，避免周期性
  闪烁和无意义的整屏写入。
- 菜单激活时会关闭 console 输入回显和 VT 键盘翻译，避免实体音量键把转义
  序列打印到菜单上。
- 菜单激活时会临时压制 kernel console 日志，避免异步驱动日志覆盖菜单。
- 每一行 generation 在重绘前都会清空，避免移动选择后留下显示残影。
- 菜单始终使用已经刷入 `boot_b` 的 kernel、DTB、stage-1 initrd 和命令行。

## 手动选择交接

Qualcomm SSC 服务存在启动注册窗口。如果用户在 stage-1 慢慢翻阅世代，直接从这次
长启动进入 stage-2 可能让 `sensor_pd` 暂时不可用，即使所选 NixOS 世代本身没有问题。

因此，3 秒无操作的自动启动仍然直接进入系统；任何手动确认则使用两次启动交接：

1. Stage-1 将所选世代的精确路径写入
   `/var/lib/sheng-boot-menu/pending-generation`，同步已挂载的 rootfs，然后快速重启。
2. 下一次 stage-1 检查该路径仍对应一个现存世代，在使用前删除标记，跳过菜单并立即
   进入所选世代。

标记只消费一次，过期或非法路径会被忽略，因此不会形成持续重启循环。额外重启只在
用户手动操作后发生，普通自动启动仍然只有一次。

按电源键开机时不要同时按住音量键。小米 bootloader 会在 Linux 启动前截获
音量加键并进入 Recovery，或截获音量下键并进入 Fastboot。等世代菜单出现后
再使用音量键。

该菜单没有使用 Mobile NixOS 的 LVGL splash，因为之前启用图形 stage-1 路径会
阻止 sheng 进入 stage-2。

构建或修改这个菜单会影响 Android boot image，需要重新刷写 `boot_b`。创建、
选择、切换或回滚 stage-2 世代不需要重新刷机。

## 验证

测试菜单前，先确认至少存在两个世代：

```sh
PAGER=cat nix-env --profile /nix/var/nix/profiles/system --list-generations
```

测试普通开机和 `sudo sheng-reboot-generation-menu`。在菜单里停留至少 15 秒，选择
较旧世代并用电源键确认；应只快速重启一次，随后跳过菜单进入所选世代。也要连接
USB 键盘验证上下方向键与 Enter。
启动后检查：

```sh
readlink /nix/var/nix/profiles/system
readlink -f /run/current-system
systemctl --failed --no-pager
systemctl show adsprpcd-sensorspd iio-sensor-proxy \
  -p Id -p ActiveState -p NRestarts
test ! -e /var/lib/sheng-boot-menu/pending-generation
```

如果菜单无法出现，回滚方式是刷回上一份确认可用的 `boot_b` 镜像。
