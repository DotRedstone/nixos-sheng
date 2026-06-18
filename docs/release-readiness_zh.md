# Release 准备状态

[English](release-readiness.md) | [简体中文](release-readiness_zh.md)

本文记录最新 release candidate 的验证状态。它不替代 `TODO.md`；这里只列出
release 阻塞项和高信号结果。

## 截至 2026-06-12 已验证

- Kernel 7.0.0 可启动进入 GNOME rootfs。
- Display manager、NetworkManager、NTP、Bluetooth、sensors、Type-C、ALSA
  和 camera media nodes 均已按文档 active 或枚举。
- 加速度计、光感、距离传感器和指南针通过 SSC 与 `iio-sensor-proxy` 更新数值。
- `/sys/bus/iio/devices` 仍为空。当前工作的传感器路径是 SSC 用户态 + D-Bus，
  不是 kernel IIO sysfs。
- `switch-to-configuration test` 可成功激活当前 NixOS 系统。
- Nix、`nixos-rebuild`、Home Manager CLI、system profile 和可写 Nix store
  均存在。
- 5GHz NetworkManager 扫描和连接已在 5180 MHz、80 MHz 下验证，联网正常。
- Battery、USB power-supply、DRM、Type-C、ALSA 和 camera media nodes 均可枚举。
- 后摄 S5KJN1 和前摄 OV32D40 RAW10 抓图已按预期帧大小
  15,618,240 字节和 9,987,840 字节重新验证。
- Bluetooth discovery 可发现附近设备。配对、重连和蓝牙音频仍未验证。
- 一次性启动世代菜单可出现，实体音量键导航可用。
- 世代菜单支持长按重复和外接键盘方向键/Enter。
- 四向自动旋转和旋转后的触摸坐标已验证。
- 霍尔盖板合盖/开盖可息屏和重绘，且不会把 `SW_LID` 暴露给 GNOME。
- 私有下游 flake 已通过公开 `mkShengSystem` 构造器成功求值并激活。
- 已创建并激活第二个合成 stage-2 世代，随后回滚并激活 system profile。
  合成世代已在验证后删除。

## v0.1.0 发布

- `v0.1.0` 从 release commit `2e54371` 发布。
- Public flake checks、boot image 构建、minimal 和 GNOME rootfs 构建均从该
  commit 成功完成。
- 发布后已验证 release tag、带版本和 kernel 的产物命名、boot image、当时的
  minimal/GNOME rootfs artifact 格式、可选校验、刷机说明、已知问题和回滚说明。

## v0.1.1 release candidate

- GNOME 光感自动亮度和 idle dimming 已禁用，避免亮度异常波动。
- ZRAM 已启用 Zstandard 压缩。
- 恢复常用 BPF、io_uring、FUSE、OverlayFS、SquashFS、EROFS、NFS 和 CIFS
  kernel 能力。默认禁用 unprivileged BPF。
- 仓库许可证、第三方声明和 release 附件说明已记录。
- 公开刷机和校验说明已修正。
- 发布前必须从同一个 v0.1.1 release commit 重新构建 boot、minimal rootfs
  和 GNOME rootfs。
- Rootfs release 产物必须以 Windows 友好的分卷 ZIP 上传，并对每个上传分卷
  生成 checksum。

## v0.1.2 release candidate

- Xiaomi MiPPS 快充认证现在会重试，并在充电设备节点未就绪时避免阻塞。
- `pd-mapper` 现在只把 `qcom/sm8550/sheng` 固件解压到 `/run`。2026-06-19
  实机验证显示 `/run/pd-mapper-firmware` 从约 576 MiB 降到约 46-58 MiB，
  GNOME 镜像空闲内存从约 2.0 GiB 降到约 1.4-1.6 GiB。
- v0.1.2 release 正文已说明 Windows 解压工具可用的分卷 ZIP rootfs 归档，并
  保持 checksum 验证为可选。
- 公开 Markdown 文档已按默认英文、`_zh` 简体中文的规则整理，并互相链接。
- 发布前必须从同一个 v0.1.2 release commit 重新构建 boot、minimal rootfs
  和 GNOME rootfs。

## 后续改进

- 离线扩展 ext4 文件系统到完整 `linux` 分区，然后验证完整的设备端
  `nixos-rebuild --flake`。
- 构建并激活一次仓库 Home Manager 配置。当前刷入镜像包含 CLI，但没有 Home
  Manager generation。
- 通过启动世代菜单验证真实 stage-2 世代之间的选择和回滚。
- 如果严格需要 kernel `iio:device*` 节点，再实现 kernel IIO。当前工作的传感器
  路径是 SSC 用户态 + D-Bus。

## 已知问题

- 第一次激活已保存的 5GHz 连接可能提示找不到网络。先刷新完整
  NetworkManager 扫描再激活可用。当前 ath12k 栈下，按频率定向的
  `iw scan freq ...` 不是可靠健康检查。
- 6GHz Wi-Fi 仍禁用且未测试。
- Kernel、DTS、stage-1 initrd 和 boot 命令行更新仍需要单独刷写 `boot_b`。
- 音频播放/录音、蓝牙配对/音频、官方键盘/触控板和桌面相机集成仍需要更广泛的
  用户侧验证。
