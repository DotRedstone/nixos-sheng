# Sheng 启动世代菜单

[English](boot-generation-menu.md) | [简体中文](boot-generation-menu_zh.md)

Sheng 使用固定的 Android `boot_b` 镜像作为启动基础，并从可写的 `linux`
分区中选择 NixOS stage-2 世代。

普通启动路径仍然不显示菜单。需要从正在运行的系统里打开一次性文本世代菜单：

```sh
sudo sheng-reboot-generation-menu
```

该命令会把一次性请求写入可写的 `linux` 分区并重启。Stage-1 在显示菜单前
消费这个请求：

```text
NixOS Sheng - Select stage-2 generation

> NixOS #2 (2026-06-06 - 26.11pre-git)
  NixOS #1 (2026-06-06 - 26.11pre-git)

Volume +/-: select    Power: boot
```

- 音量上下键或外接键盘上下方向键用于切换高亮的 stage-2 世代。
- 长按导航键会连续移动选择。
- 音量键采用边沿触发，重绘不会等待延迟的松键事件。
- 电源键或外接键盘 Enter 键确认启动。
- 30 秒无操作后自动启动当前高亮项。
- 菜单使用 16x32 console 字体，并在可见状态变化时按实际 tty 尺寸重绘整个
  可见区域，使用空格填满每一行，避免残留行、坐标漂移、周期性闪烁和早期
  fbcon 下半屏残影。
- 菜单激活时会关闭 console 输入回显和 VT 键盘翻译，避免实体音量键把转义
  序列打印到菜单上。
- 菜单激活时会临时压制 kernel console 日志，避免异步驱动日志覆盖菜单。
- 每一行 generation 和菜单下方空白区域在重绘前都会被覆盖，避免移动选择后
  留下反色视频残影或旧 framebuffer 内容。
- 菜单始终使用已经刷入 `boot_b` 的 kernel、DTB、stage-1 initrd 和命令行。

开机时不要按住音量下键。小米 bootloader 会在 Linux 启动前截获它并进入
Fastboot 模式。

该菜单没有使用 Mobile NixOS 的 LVGL splash，因为之前启用图形 stage-1 路径会
阻止 sheng 进入 stage-2。

构建或修改这个菜单会影响 Android boot image，需要重新刷写 `boot_b`。创建、
选择、切换或回滚 stage-2 世代不需要重新刷机。

## 验证

测试菜单前，先确认至少存在两个世代：

```sh
PAGER=cat nix-env --profile /nix/var/nix/profiles/system --list-generations
```

执行 `sudo sheng-reboot-generation-menu`，选择较旧的世代，并用电源键确认。
启动后检查：

```sh
readlink /nix/var/nix/profiles/system
readlink -f /run/current-system
systemctl --failed --no-pager
```

如果菜单无法出现，回滚方式是刷回上一份确认可用的 `boot_b` 镜像。
