# Sheng 社区 Linux EFI 条目约定（实验性）

Sheng 的 B 槽 U-Boot 提供 UEFI 环境，当前由 `systemd-boot` 展示菜单。Linux 发行版按 [Boot Loader Specification Type #1](https://uapi-group.org/specifications/specs/boot_loader_specification/) 提供条目；不要求每个发行版修改 U-Boot。U-Boot 仍须解决 Sheng 的 UFS、显示、按键、充电和 EFI 交接问题。发行版负责内核、initrd、rootfs、固件和服务的适配与更新。

## 提交给测试的文件

在**主机上的暂存 ESP 目录**准备 `loader/entries/<发行版>-<版本>.conf` 和它引用的文件。Linux EFI-stub 条目使用 `architecture aa64`，并包含 `title`、`version`、`options`、`linux`、`initrd` 和 `devicetree`。载荷路径必须在同一个 ESP 内，采用规范化的绝对路径；建议每个发行版使用自己的目录，避免覆盖 NixOS 文件。例如：

```text
title Example Linux (Sheng test)
version 1
sort-key example-linux
architecture aa64
options console=tty0 root=PARTUUID=<测试分区的 UUID> ro
linux /EFI/ExampleLinux/1/linux
initrd /EFI/ExampleLinux/1/initrd
devicetree /EFI/ExampleLinux/1/sm8550-xiaomi-sheng.dtb
```

这是条目格式示例，不是可启动配置。实际 rootfs 位置、内核命令行、驱动模块和固件应由该发行版的 Sheng 适配明确给出。若借用本项目内核，必须同时核对内核、DTB、模块和 rootfs 的版本一致性。不能把通用 arm64 用户态启动当作触摸、Wi-Fi、充电、桌面等硬件能力已适配。

在主机上运行：

```sh
python3 scripts/sheng-check-linux-efi-entry.py /path/to/staged-esp example-linux-1.conf
```

预检只读文件，检查条目、AA64 PE 内核、DTB 头、所引用 initrd 的存在性、同一 ESP 路径和符号链接，并打印载荷 SHA-256。它不核验来源签名、内核与 rootfs 的运行时兼容性，也不写设备。首次实机测试应保留 B 槽可启动备份，使用可回退的临时入口，记录屏幕、内核日志、`/etc/os-release`、PID 1、rootfs 挂载和返回 NixOS 的结果。预检通过后也不自动加入日常默认菜单。

Android 的 ABL/v4 启动链与 Linux Type #1 不同，不能套用这份条目约定。其他 EFI 系统须先分别证明固件接口和设备驱动可用，再定义对应适配器。
