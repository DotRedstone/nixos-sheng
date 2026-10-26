# Sheng 多系统启动路线图

> 状态：方案与设备基线检查。当前 U-Boot / EFI 候选只验证了 NixOS 启动；Android A 槽和其他 Linux 尚未通过 U-Boot 菜单启动。

## 已有启动路径

设备由 Android ABL 选择 A/B 槽。A 槽保留 Android 启动分区，B 槽的稳定路径是 Mobile NixOS；实验 U-Boot 可替换 B 槽的 boot 镜像，读取独立的 `linux-boot` ESP，再通过 systemd-boot 选择 NixOS 世代。当前 7.3.0 候选已通过 B 槽持久启动、普通重启及刷回稳定镜像的实机验证；关机插线、断电冷启动和恢复键仍待验收。

设备上只读检查表明，Android A 槽有 v4 格式的 `boot_a`、`vendor_boot_a`、`init_boot_a`，以及 `dtbo_a` 和 `vbmeta_a`。A/B 元数据将 A 标记为 bootable、successful，但这不能证明 Android 现状可启动。检查前已将 A 槽关键启动分区与 `misc` 在主机私有目录备份，并逐项比较设备和备份的 SHA-256；未改写 A 槽或 `userdata`。

## 两种 Android 入口

### ABL 槽位切换

先以 A 槽进入 Android，以 B 槽进入 U-Boot 和 NixOS。切到 A 后，ABL 会直接启动 Android，B 槽 U-Boot 菜单不会出现。正式提供这种方式前，必须实测 Android A 槽启动、从 Android 返回 B 槽的方法，以及失败时通过 ABL fastboot 恢复。A/B 标志会被 Android 更新流程使用，不应把槽位切换伪装为一次性菜单选择。

### U-Boot 菜单直接选择 Android

目标是每次由 B 槽 U-Boot 显示菜单，再从 A 槽读取 Android 镜像。该设备的 Android v4 启动链使用独立的 `vendor_boot`、`init_boot`、DTB/DTBO 与启动参数；还需处理 A/B、AVB、bootconfig、恢复模式和 Android 更新后的镜像变化。U-Boot 通用 `bootm` 支持 Android 启动镜像，但不足以证明这些设备专属输入已被正确组合。该路径需要单独实现、RAM 验证和实机回退，不属于当前可发布功能。

## 更多 Linux

现有 systemd-boot 菜单中的多个条目是多个 NixOS 世代。若增加其他 Linux，需为每个系统准备适配 Sheng 的 EFI 内核、DTB、initrd、模块和固件，规划独立或共享根文件系统，并验证更新及回退。单独增加 BLS 菜单项不能证明新系统可启动。`linux-boot` ESP 目前只承担 EFI 引导载荷，不应把 Android 的 `userdata`、`super` 或固件分区改作 Linux 存储。

## 验证顺序

1. 完成当前 U-Boot 候选的关机插线画面、断电冷启动与恢复键验收。
2. 保持 B 槽稳定镜像和主机备份可用，验证 Android A 槽启动及双向返回路径。
3. 先实现可恢复的 ABL A/B 双系统使用流程，再单独开发统一菜单中的 Android 启动入口。
4. 每增加一个 Linux 系统，独立验证其启动、根文件系统、硬件和更新回退。

参考：[Android A/B 更新与槽位](https://source.android.com/docs/core/ota/ab)、[Android boot/vendor_boot/init_boot 分区](https://source.android.com/docs/core/architecture/partitions/generic-boot)、[U-Boot Android 启动镜像](https://docs.u-boot.org/en/stable/android/boot-image.html)。
