# Xiaomi Pad 6S Pro（sheng）Mobile NixOS v0.1.1

[English](release-notes.md) | [简体中文](release-notes_zh.md)

这个维护版本修复 Xiaomi Pad 6S Pro 12.4（`sheng`）上 GNOME 亮度异常变化的问题。
刷写前请阅读已知问题。

## 相比 v0.1.0 的变化

- 禁用 GNOME 环境光自动亮度调整。
- 禁用 GNOME 空闲变暗。
- 重新启用使用 Zstandard 压缩器的 ZRAM。
- 恢复容器、桌面工具和文件系统常用的内核能力：BPF、io_uring、FUSE、
  OverlayFS、SquashFS、EROFS、NFS 和 CIFS。非特权 BPF 默认仍关闭。
- 澄清刷写、校验和公开发布文档。
- 添加仓库许可证和第三方/专有材料声明。

## 当前可用

- 启动到偏控制台的 minimal 镜像，或可选 GNOME 镜像
- 显示、触摸屏、物理音量键
- **物理电源键**：切换亮屏/息屏，不触发 suspend
- **屏幕键盘**：启用 `gjs-osk` 触控输入
- 四向自动旋转、合盖灭屏、开盖重绘
- Stage-1 世代菜单，支持音量/电源键和外接方向键/回车
- 2.4GHz 与 5GHz Wi-Fi
- 蓝牙控制器枚举
- USB-C role 与 Type-C 枚举
- 通过 SSC 用户态路径提供加速度计、距离传感器、环境光和指南针
- ALSA 声卡与相机 media node 枚举
- Nix、`nixos-rebuild` 与 stage-2 世代框架
- 面向私人 dotfiles flake 的桌面无关 `mkShengSystem` 与显式
  `mkShengGnomeSystem` 构造器

## 已知问题

- **指纹传感器**：不支持。硬件依赖专有 Qualcomm TEE/TrustZone 解密，主线
  Linux 没有可用的开源方案。
- **冷启动后的 5GHz Wi-Fi**：全新 `fastboot` 刷写后的首次冷启动，5GHz
  Wi-Fi 网络可能因为 modem/firmware 初始化竞争而不出现。执行一次热重启即可恢复。
- 传感器使用 SSC + D-Bus；当前没有 kernel `/sys/bus/iio/devices/iio:device*`
  节点。
- 音频播放/录音、蓝牙配对/音频、官方键盘/触控板和桌面相机集成仍需要更多验证。
- kernel、DTS、stage-1 initrd 和 boot command line 更新仍需要单独构建并刷写
  `boot_b` 镜像。

## 刷写

Release 包含一个 boot 镜像，以及 minimal 和 GNOME 两种 rootfs。rootfs 以分卷
ZIP 上传，方便 Windows 用户使用图形解压工具。请下载所选版本的所有分卷，例如
`.z01`、`.z02` 和最后的 `.zip`，然后用 Bandizip、7-Zip、WinRAR 或其他支持
split ZIP 的工具打开 `.zip` 文件。解压得到的 `.img` 可以直接刷写。产物命名包含
`nixos`、版本号和内核版本。

首次分区和双系统安装请参考
[双系统安装指南](https://github.com/DotRedstone/nixos-xiaomi-sheng/blob/sheng/docs/install-dualboot.md)。

```sh
fastboot flash boot_b nixos-sheng-*-boot.img
fastboot flash linux nixos-sheng-*-rootfs-minimal.img
fastboot --set-active=b
fastboot reboot
```

只有想使用仓库自带 GNOME 桌面时才选择 `rootfs-gnome`，否则使用
`rootfs-minimal`。`.img` 文件来自下载的分卷 ZIP 解压结果。

校验是可选但推荐的。请只校验自己下载的版本，避免另一个 rootfs 版本因为未下载而
被报告为缺失：

```sh
grep -E 'boot\.img|rootfs-minimal\.(z[0-9]+|zip)$' sha256sums.txt | sha256sum -c -
```

使用 GNOME 镜像时，将 `rootfs-minimal` 替换为 `rootfs-gnome`。

完整 release 需要同时刷写 `boot_b` 和 `linux`。不要刷写 `userdata`。

项目原创内容采用 MIT 许可证。第三方代码和专有固件保留其各自条款；再分发镜像前请阅读
[THIRD_PARTY_NOTICES.md](https://github.com/DotRedstone/nixos-xiaomi-sheng/blob/sheng/THIRD_PARTY_NOTICES.md)。

权利人可以通过 GitHub 请求复核受影响的文件或 release 产物。本项目与 Xiaomi、
Qualcomm 或其他组件厂商不存在隶属或背书关系。源码、说明、镜像和其他产物均不提供担保。

公开镜像默认用户为 `luser` / `1`，root 密码为 `123456`。请立即修改密码，或使用
`examples/sheng-dotfiles` 中的模板从私人 flake 构建自己的系统。

rootfs 镜像内的文件系统可能小于专用 `linux` 分区。若要把剩余空间用于 NixOS 世代，
请在刷写后参考
[linux 文件系统扩容指南](https://github.com/DotRedstone/nixos-xiaomi-sheng/blob/sheng/docs/linux-partition-resize.md)，
从 TWRP 或其他救援环境扩容。

## 回滚

保留上一版本的 boot 与 rootfs release 文件。如果新镜像无法启动，进入 Fastboot
或 TWRP 并刷回上一版 `boot_b`。刷回旧的 `linux` rootfs 会恢复该 rootfs，但也会
替换其中的本地 NixOS 世代和数据，所以请先备份重要文件。
