# Sheng 启动世代菜单

[English](boot-generation-menu.md) | [简体中文](boot-generation-menu_zh.md)

Sheng 使用固定的 Android `boot_b` 镜像作为启动基础，并从可写的 `linux`
分区中选择 NixOS stage-2 世代。

普通启动路径仍然不显示菜单。需要从正在运行的系统里打开一次性世代菜单：

```sh
sudo sheng-reboot-generation-menu
```

该命令会把一次性请求写入可写的 `linux` 分区并重启。Stage-1 在显示菜单前
消费这个请求。

无法进入 stage-2 时，也可以等屏幕出现 NixOS 启动文字后，在 2 秒内快速按三次
音量加键。Stage-1 会在正常启动任务间隙非阻塞地监听这个手势；没有按键时不会增加
固定等待时间。只按了一两次时，才会短暂等待本次手势完成：

菜单会在 framebuffer 上显示两层世代信息、当前选择位置、按键图标和自动启动
进度。选中的世代使用高对比色块和方向标记强调，确认后会显示即将交给
stage-2 的世代编号与版本。

- 音量上下键或外接键盘上下方向键用于切换高亮的 stage-2 世代。
- 长按导航键会连续移动选择。
- 音量键采用边沿触发，重绘不会等待延迟的松键事件。
- 电源键或外接键盘 Enter 键确认启动。
- 30 秒无操作后自动启动当前高亮项。
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

按电源键开机时不要同时按住音量键。小米 bootloader 会在 Linux 启动前截获
音量加键并进入 Recovery，或截获音量下键并进入 Fastboot。三击手势必须等到
NixOS 启动文字出现后再操作。

该菜单没有使用 Mobile NixOS 的 LVGL splash，因为之前启用图形 stage-1 路径会
阻止 sheng 进入 stage-2。

构建或修改这个菜单会影响 Android boot image，需要重新刷写 `boot_b`。创建、
选择、切换或回滚 stage-2 世代不需要重新刷机。

## 验证

测试菜单前，先确认至少存在两个世代：

```sh
PAGER=cat nix-env --profile /nix/var/nix/profiles/system --list-generations
```

分别测试 `sudo sheng-reboot-generation-menu` 和 NixOS 启动文字出现后的三击音量
加键入口，选择较旧的世代，并用电源键确认。
启动后检查：

```sh
readlink /nix/var/nix/profiles/system
readlink -f /run/current-system
systemctl --failed --no-pager
```

如果菜单无法出现，回滚方式是刷回上一份确认可用的 `boot_b` 镜像。
