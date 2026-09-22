# 圆润启动动画

[English](boot-animation.md)

正常启动采用克制的纯黑背景与灰白动效：

1. Linux framebuffer 可用后，白色圆弧沿低亮灰色圆环连续旋转，中心圆点轻微呼吸；
2. 进入大圆角世代菜单，保留 3 秒自动启动和音量键选择；
3. 选定世代后恢复同一套无缝动画，跨越 stage-1 到 stage-2 的交接；
4. 显示管理器启动前先停止绘制，保留最后一帧，再交给桌面。

动画为 20fps、3 秒循环，没有虚构启动百分比，也不会为了播完动画延迟进入桌面。
画面只使用灰阶颜色，文字仅保留 `NixOS`，不再显示阶段提示或彩色电量形态。
手动选择世代仍会快速重启一次；下一次启动消费选择标记并直接进入所选世代。
关机充电继续使用原有静态电池界面，不播放正常开机动画。

## 日志与故障诊断

日志没有被删除。VT1 留给桌面，VT2 用于动画和世代菜单，VT3–6 用于文本控制台。
`fbcon=vc:3-6` 避免 bootloader 追加 `loglevel=6` 后再次把内核日志画到启动界面。
内核与服务消息仍可在 `dmesg`、`journalctl -b`、`/run/log/stage-1.log` 查看。

- 动画期间按外接键盘 **Esc** 可切到 VT3，本次开机不再显示动画；
- 在系统或 ADB shell 中执行 `sudo sheng-boot-details` 也可进入诊断控制台；
- stage-1 的故障处理、救援/紧急目标、显示管理器失败会尝试切到 VT3；
- 动画进程最长运行 120 秒，超时退出并显示诊断控制台；
- 一次性启动参数 `sheng.boot-ui=0` 禁用动画并使用文本菜单；
- 无显示管理器的 minimal 系统在 stage-2 完成早期激活后回到文本控制台。

动画开始前的厂商 Logo、解锁警告属于 Android bootloader，不由本实现控制。
内核早期崩溃、显示驱动不可用时不能保证设备面板能显示诊断信息，仍需串口或 ADB。

## 实现与交接

使用现有 `sheng-fb-painter` 的 SFB1 绘制路径，未重新启用曾阻塞启动的 LVGL 路径。
帧在构建期由 Pillow 与 Inter 生成，运行时使用 C，stage-1 不加载 Python 或字体引擎。
每帧只更新中央 720px 区域，小屏自动缩放；首次接管才清理整屏。

动画通过文件锁保证同一控制路径只有一个绘制进程，菜单开始前等待旧进程停止。
stage-1 进入 switch_root 前等待动画准备好，原进程持有打开的控制目录、控制文件和
VT 句柄，因此 `/run`、`/dev` 移动后仍能收到 stage-2 的停止请求。
stage-2 先结束原进程以释放 initrd 映射，再启动本世代的绘制程序；显示管理器接管前
等待停止确认，不继续往 compositor 的画面写入。
stage-2 服务在首帧准备好后才允许显示管理器启动，避免启动与停止请求交错。
桌面接管时记录本次启动已完成，后续系统切换不会重新播放启动动画。

早期动画只读取 `/proc` 中的启动原因，不提前读取或缓存尚未挂载 rootfs 上的
正常重启标记；否则插着 USB 主动重启可能被误判为关机充电。

## 构建与预览

本次涉及 cmdline、stage-1、共享 painter 和 stage-2 服务，需要匹配的 boot 与 rootfs：

```sh
nix build ./nixos#checks.aarch64-linux.bootAnimation --no-link
nix build ./nixos#checks.aarch64-linux.generationMenuRenderer --no-link
nix build ./nixos#checks.aarch64-linux.offlineCharging --no-link
nix build ./nixos#packages.aarch64-linux.mobileAndroidBootimg -o out/mobile-bootimg
nix build ./nixos#packages.aarch64-linux.mobileRootfsImage -o out/mobile-rootfs
```

设备部署需要更新 `boot_b`，并激活匹配的系统世代或更新 `linux/rootfs`。
只更新其中一边不能保证整段动画与桌面的交接。回滚需恢复上一份 boot_b 和系统世代。

本机预览使用按本机架构构建的 painter 与动画资源包：

```sh
python3 scripts/preview-boot-animation.py "$PAINTER/bin/sheng-fb-painter" \
  "$ANIMATION" out/boot-animation-preview --menu out/rounded-generation-menu-preview
```

菜单目录可由 `scripts/preview-generation-menu.py` 生成。预览 GIF 来自原生 painter
写出的 framebuffer 像素，不是另一套效果图；`--animate-file` 测试模式不访问真实显示。

检查覆盖 16/24/32bpp、带行填充的横竖屏和小屏、动画循环、互斥绘制、停止确认、
移动控制目录后的交接、诊断标记、错误帧拒绝、充电隔离与重启标记。
本机检查通过不代替真实 boot 镜像的实机验收。

## 实机验收

在安装匹配的 boot/rootfs 后分别检查：

- 完整关机再开机；插 USB 主动重启；手动选择旧世代；
- 动画、菜单、桌面交接没有文本闪现，没有两个绘制进程同时接管屏幕；
- 菜单音量键与确认仍可用，自动启动仍按 3 秒计时；
- 完全关机后只插充电器，仍显示原有静态电池，8 秒熄屏与按键唤醒正常；
- Esc、一次性禁用参数和 `sheng-boot-details` 能进入诊断控制台；
- 桌面启动后动画进程已退出，传感器服务与显示管理器正常。

```sh
systemctl status sheng-boot-splash display-manager --no-pager
journalctl -b -u sheng-boot-splash --no-pager
pgrep -af 'sheng-fb-painter.*--animate'
systemctl --failed --no-pager
cat /sys/class/tty/tty0/active
```
