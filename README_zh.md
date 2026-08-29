[🇬🇧 English](README.md) | [🇨🇳 简体中文](README_zh.md)

# nixos-sheng

Xiaomi Pad 6S Pro 12.4 (`sheng`, Qualcomm SM8550) 的 Mobile NixOS 移植项目。

![设备](https://img.shields.io/badge/device-Xiaomi%20Pad%206S%20Pro%2012.4-blue)
![内核](https://img.shields.io/badge/kernel-sheng--7.0-blueviolet)
![NixOS](https://img.shields.io/badge/NixOS-Mobile%20NixOS-5277c3)
![许可证](https://img.shields.io/badge/license-MIT%20%2B%20third--party%20terms-orange)

本仓库仅提供 NixOS 设备移植。当前维护的刷机路径是基于 Mobile NixOS 的 Android 启动流程：编译一个 `boot.img` 刷入非活动（inactive）的 Android slot，以及一个由 Mobile NixOS 生成的 ext4 rootfs 镜像刷入专门分配的 `linux` 分区。

如果这个项目帮到了你，或者你只是想看到 NixOS 在移动设备上变得更真实，
欢迎给仓库点一个 star。它能帮助更多 sheng 用户找到这个移植项目，也能让深夜
调试 boot image 的人稍微感受到一点人间温度。

## 项目亮点

- 面向 Xiaomi Pad 6S Pro 12.4 (`sheng`) 的 Mobile NixOS 启动流程
- 可刷入 Android `boot_b` 的 boot 镜像，以及专用 `linux` 分区 rootfs 镜像
- 面向私人 dotfiles 仓库的桌面无关公开 flake 构造器
- 可选 GNOME 镜像，集成触屏键盘、自动旋转和盖板开合处理
- 可通过音量键和电源键操作的 stage-1 NixOS 世代菜单
- Wi-Fi、USB-C role/OTG、SSC 传感器、RAW 相机抓取与 MiPPS 快充认证已可用

## 当前状态

首个公开版本可从
[GitHub Releases](https://github.com/DotRedstone/nixos-sheng/releases/latest)
下载。部分硬件仍未完全支持，刷写前请阅读下方状态表和已知问题。

| 领域 | 状态 | 备注 |
| --- | --- | --- |
| 设备框架 | Mobile NixOS | 设备定义位于 `nixos/hardware/xiaomi-sheng` |
| 内核 | Sheng 设备内核 | 通过 Nix 从 `DotRedstone/linux-sheng` 构建 |
| 启动镜像 | Bring-up | 面向 `boot_b` 的 Mobile NixOS Android boot image |
| RootFS | Mobile NixOS 生成的 rootfs | 面向 `linux` 分区的 ext4 镜像 |
| 显示/桌面 | 可用 | 3048x2032 面板、GNOME shell、gjs-osk 屏幕键盘、物理电源键息屏唤醒、四向旋转与盖板开合亮灭屏均可用 |
| 调试访问 | Bring-up | Stage-1/stage-2 的 ADB 已通过 Mobile NixOS 启用 |
| Wi-Fi | 可用 | 2.4GHz 与 5GHz 扫描、连接和联网已验证；**首次冷启动刷入后，必须软重启一次才能稳定激活 5GHz。** |
| 蓝牙 | 部分可用 | hci0 与 bluetooth.service 正常；扫描、配对、重连和音频待验证 |
| 音频 | 部分可用 | ALSA 声卡与播放/录音 PCM 已枚举；实际播放和录音待验证 |
| 相机 | 部分可用 | 前后摄 RAW10 实际画面已抓取；libcamera、自动曝光与桌面相机应用待完善 |
| 传感器 | 用户态可用 | 加速度计、距离传感器、光感、指南针已通过 SSC + iio-sensor-proxy D-Bus 路径验证 |
| 指纹 | 不支持 | 硬件采用高通 TEE/TrustZone 专有加密，主线 Linux 无开源解密方案 |
| 充电 | 可用 | 支持标准 PD 与小米 120W MiPPS 私有快充协议 |

## 上游项目

- [mobile-nixos/mobile-nixos](https://github.com/mobile-nixos/mobile-nixos)
  提供设备框架、stage-1 initramfs、Android boot image 构建器、生成的 rootfs 支持、USB gadget 设置以及设备移植约定。
- [DotRedstone/sheng-firmware-full](https://github.com/DotRedstone/sheng-firmware-full)
  提供完整的闭源固件、ADSP 传感器通信配置与注册表。
- [DotRedstone/linux-sheng](https://github.com/DotRedstone/linux-sheng)
  提供本项目维护的设备内核、驱动与 DTS。
- [map220v/sm8550-mainline](https://github.com/map220v/sm8550-mainline)
  提供上游 Xiaomi Pad 6S Pro 主线内核支持。
- [ianchb/xiaomi-mipps-auth](https://github.com/ianchb/xiaomi-mipps-auth)
  提供小米 120W 私有快充协议的用户态认证守护进程。

内核源码在 `nixos/flake.nix` 中配置：

```nix
shengKernelSrc.url = "github:DotRedstone/linux-sheng/sheng-7.0";
```

## 启动原理

平板仍然像 Android 设备一样启动。

```text
Android bootloader
  -> boot_b / boot.img
       -> sheng kernel
       -> sm8550-xiaomi-sheng.dtb
       -> Mobile NixOS stage-1 initramfs
            -> 挂载 /dev/disk/by-partlabel/linux
            -> 读取 nix-path-registration
            -> 切换到选定的 NixOS 系统闭包

linux 分区
  -> Mobile NixOS 生成的 ext4 rootfs
       -> nix/store
       -> nix-path-registration
```

这里的 rootfs 镜像故意没有采用标准的 PC 风格根目录。对于 Mobile NixOS 生成的 rootfs 而言，顶层只有 `nix/store` 和 `nix-path-registration` 是正常的现象：stage-1 会使用这些注册数据来寻找 NixOS 系统闭包并运行其 `init`。

### 🌟 特色功能：Stage-1 世代回滚菜单 (Boot Generation Menu)

由于 Android 设备的 Bootloader 无法直接引导标准的 GRUB/systemd-boot 菜单，本项目在 `stage-1` initramfs 中专门开发了一套**纯文本 framebuffer 启动菜单**。

在系统中执行 `sudo sheng-reboot-generation-menu`，或在 NixOS 启动文字出现后于 2 秒内快速按三次音量加键，平板会显示轻量级的世代选择器：
- 使用 **音量键** 上下切换历史 NixOS 世代。
- 使用 **电源键** 确认启动。
- 30秒无操作自动启动默认世代。

这使得你在移动设备上也能享受到完整的 NixOS 原子化升级与“无限后悔药”回滚体验！详细文档请参阅 [`docs/boot-generation-menu_zh.md`](docs/boot-generation-menu_zh.md)。

## 仓库结构

```text
.
|-- .github/workflows/
|   |-- kernel.yml          # 构建 Mobile NixOS Android boot image
|   `-- nixos-rootfs.yml    # 构建 Mobile NixOS rootfs image
|-- nixos/
|   |-- flake.nix           # Flake 入口
|   |-- configuration.nix   # 系统核心与基础服务配置
|   |-- hardware/           # 硬件抽象层：包含设备树、内核、ALSA调音、底层引导
|   |   |-- xiaomi-sheng/   # Mobile NixOS 基础设备定义
|   |   |-- audio/          # ALSA UCM2 硬件调音文件
|   |   |-- hardware.nix    # NixOS 硬件特性模块
|   |   `-- mobile.nix      # Mobile NixOS Stage-1 配置
|   |-- modules/            # 自定义 NixOS 服务与特性 (MiPPS 认证等)
|   |-- home/               # 用户级 Home Manager 配置
|   |-- profiles/           # 上层桌面方案 (GNOME 等)
|   |-- packages/           # 自定义构建软件包
|   |-- patches/            # 启动流程 Ruby 补丁
|   `-- scripts/            # 目标机执行脚本
|-- scripts/
|   `-- inspect-bootimg.sh  # 离线的 boot.img/initrd 检查辅助脚本
`-- build-nixos-rootfs.sh
```

## 仓库职责

本仓库负责可复用的 sheng 平台：kernel、DTB、firmware、Mobile NixOS
启动流程、硬件服务、rootfs 布局，以及可选的 GNOME profile。
本仓库也会构建带临时默认用户的公开测试镜像。

个人用户、凭据、应用、Home Manager 配置，以及 hostname、locale、时区等个人设置
应放在独立的 dotfiles flake 中。下游 flake 应调用
`nixos-sheng.lib.aarch64-linux.mkShengSystem`，不要尝试将 Mobile NixOS
设备模块导入普通的 `nixpkgs.lib.nixosSystem` 求值。

```nix
{
  inputs.nixos-sheng.url =
    "github:DotRedstone/nixos-sheng?dir=nixos";

  outputs = { self, nixos-sheng, ... }@inputs: {
    nixosConfigurations.sheng =
      nixos-sheng.lib.aarch64-linux.mkShengSystem [
        { _module.args.inputs = inputs; }
        ./hosts/sheng/configuration.nix
      ];
  };
}
```

`mkShengSystem` 只提供不绑定桌面环境的 sheng 平台。只有下游明确希望使用本仓库
GNOME profile 时才调用 `mkShengGnomeSystem`。`mkShengMinimalSystem` 作为
`mkShengSystem` 的兼容别名保留。公开构造器不会创建用户，也不会注入本仓库的
Home Manager profile，用户配置必须由下游模块提供。

完整的私人 flake 起始模板位于
[`examples/sheng-dotfiles`](examples/sheng-dotfiles)。

## 使用 GitHub Actions 构建

打开 Actions 标签页并在 `sheng` 分支上运行以下工作流：

- `Build Sheng Kernel`：构建 `boot_sheng_nixos.img`。
- `Build NixOS RootFS`：构建可刷入的 `nixos-sheng-*.img`。
- `Check Public Flake`：验证公开构造器与仓库锁文件。

对于测试构建，请保持开启 `Skip GitHub release`，这样工作流就只会上传产物而不会发布 Release。

正式 Release 的 rootfs 镜像会以分卷 ZIP 发布，方便 Windows 用户使用 Bandizip、
7-Zip、WinRAR 等图形解压工具。请下载所选版本的全部分卷，例如
`rootfs-minimal.z01`、`rootfs-minimal.z02` 和 `rootfs-minimal.zip`，
然后打开最后的 `.zip` 文件，解压得到可直接刷入的 `.img`。

## 本地构建

本地构建需要一个启用了 Nix flakes 的 aarch64 Linux 环境。

当需要刷新 inputs 时更新 flake lock：

```bash
nix flake lock ./nixos
```

构建 boot image：

```bash
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
```

构建可刷入的 Mobile NixOS rootfs 镜像：

```bash
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
```

构建设备内 `nixos-rebuild` 使用的 GNOME stage-2 系统：

```bash
nix build ./nixos#nixosConfigurations.sheng.config.system.build.toplevel
```

将所有面向 fastboot 的 Mobile NixOS 镜像输出到一个目录中：

```bash
nix build ./nixos#mobileFastbootImages -o out/mobile-fastboot
```

构建并将 rootfs 镜像复制到 `out/nixos-sheng-*.img`：

```bash
./build-nixos-rootfs.sh
```

保留了 `fullRootfsImage` 作为旧命令的兼容别名。它与 `mobileRootfsImage` 指向同一个 Mobile NixOS 生成的 rootfs。

## 刷机指南

对于插槽 `b` 的双启动测试，请将 Android 保留在另一个插槽，并仅刷入非活动插槽的 boot 镜像以及专用的 `linux` rootfs 分区：

```bash
fastboot erase dtbo_b
fastboot flash boot_b out/mobile-bootimg
fastboot flash linux out/nixos-sheng-YYYYMMDD_HHMMSS.img
fastboot --set-active=b
fastboot reboot
```

如果您直接使用 `nix build ./nixos#mobileRootfsImage` 构建了 rootfs，需要刷入的文件是生成的 `rootfs.img`：

```bash
fastboot flash linux out/mobile-rootfs/rootfs.img
```

如果 stage-1 代码或 Android 启动配置发生了变化，请重新构建并刷入 `boot_b`。如果只有 NixOS userspace/rootfs 发生了变化，请重新构建并刷入 `linux`。

**重要提醒**：在刷入全新的系统镜像并通过 fastboot 首次冷启动后，可能会遭遇硬件初始化时序的竞争问题（例如 ADSP 调制解调器在 Wi-Fi 驱动之后才加载完毕），导致 5GHz Wi-Fi 等功能失效。**在首次刷机开机后，您必须执行一次软重启 (`systemctl reboot`) 来解决这些初始化怪癖，以确保所有驱动程序都能稳定加载。**

不要刷入 `userdata`。固件、软件包、systemd 单元、用户和其他 rootfs 内容都位于 `linux` 分区；仅刷入 `boot_b` 并不会更新 `/lib/firmware`。

完成首次刷机后，普通 stage-2 配置可以直接在平板上通过
`nixos-rebuild` 构建、测试、切换和回滚。kernel、DTS、stage-1 initrd
和 boot cmdline 仍需要单独构建并刷入 `boot_b`。安全操作流程见
[`docs/nixos-rebuild_zh.md`](docs/nixos-rebuild_zh.md)。

生成的 rootfs 文件系统可能小于专用 `linux` 分区。创建多个世代前应先离线扩容，
具体步骤见 [`docs/linux-partition-resize_zh.md`](docs/linux-partition-resize_zh.md)。

## 固件、传感器与 USB-C

sheng 上的 USB-C 主机模式和各类传感器均强依赖于完整的 Qualcomm remoteproc 固件（包含 ADSP 与 CDSP）。
由于 NixOS 是无状态的，我们在系统中引入了 [sheng-firmware-full](https://github.com/DotRedstone/sheng-firmware-full) 来管理所有闭源文件，并配置了系统去挂载原生的 Android `persist` 分区以提供 DSP 传感器所需的注册表。

当前传感器走 Qualcomm SSC 用户态路径。`iio-sensor-proxy` 已能通过 D-Bus 暴露加速度计、距离传感器、光感和指南针数据。该方案不会创建 kernel IIO sysfs 节点，因此当前 `/sys/bus/iio/devices` 为空属于预期现象。

有关完整的依赖链、离线 rootfs 检查、运行时验证命令以及常见的故障特征，请参阅：
- [docs/sheng-firmware-and-usbc_zh.md](docs/sheng-firmware-and-usbc_zh.md)
- [docs/sensors-ssc-userland_zh.md](docs/sensors-ssc-userland_zh.md)
- [docs/nixos-rebuild_zh.md](docs/nixos-rebuild_zh.md)
- [docs/install-dualboot_zh.md](docs/install-dualboot_zh.md)
- [docs/linux-partition-resize_zh.md](docs/linux-partition-resize_zh.md)
- [docs/boot-generation-menu_zh.md](docs/boot-generation-menu_zh.md)
- [docs/camera-raw-capture_zh.md](docs/camera-raw-capture_zh.md)
- [docs/mipps-120w_zh.md](docs/mipps-120w_zh.md)

## 许可证与第三方材料

由 DotRedstone 原创的项目内容采用 [MIT License](LICENSE)。第三方源代码、
Linux 内核代码与补丁、固件、二进制文件和商标仍受各自条款约束，详情见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本移植使用的设备专有固件并非开源软件。文件出现在公开仓库中并不自动代表获得了
再分发许可。任何分发预构建镜像的人都需要自行确认其所在地对所有内含二进制文件的
再分发权限。法律风险最低的发布方式是仅发布源代码，并由用户从自己拥有的设备中
提取和提供固件。

权利人如认为仓库文件或 Release 产物涉及权利问题，可以通过 GitHub 请求复核；详见
`THIRD_PARTY_NOTICES.md`。本项目与 Xiaomi、Qualcomm 或其他组件厂商不存在隶属或
背书关系。

## 调试

ADB 通过 `mobile.adbd.enable` 启用。在成功的过渡期间，stage-1 的 ADB 可能会在 stage-2 接管 USB gadget 设置时短暂断开。

要离线检查生成的 boot image：

```bash
scripts/inspect-bootimg.sh out/mobile-bootimg
```

该辅助脚本会打印 `/etc/boot/config`、initrd applets 以及关键的启动标志（如 `boot_as_recovery`、`splash.disabled`、rootfs 挂载设置和 USB 特性）。

## 动态凭据与默认登录

为了避免将敏感密码硬编码进开源仓库中，我们的 `vars.nix` 会在系统构建期进行**参数动态注入**。

这些凭据只用于本仓库构建的测试镜像。通过 `mkShengSystem` 或
`mkShengMinimalSystem` 创建的系统，其用户和凭据完全由下游 flake 定义。

- **云端构建**：在 GitHub Actions 手动触发 `Build NixOS RootFS` 工作流时，您可以**直接输入**自定义的用户名、用户密码和 Root 密码。Actions 运行时会生成携带您专属密码的专属镜像。
- **本地开发**：您可以直接在本地创建或修改 `nixos/vars.nix`。

如果在 Actions 中留空或未做修改，当前测试镜像将回落到预设体验凭据：

- 用户名：`luser`
- 密码：`1`
- root 密码：`123456`

## 免责声明

本项目是实验性 Mobile NixOS 移植。正常按照文档操作通常不会导致问题，但刷机、
分区和 slot 切换仍然具有风险。操作前请备份数据，并确认你理解每一条命令。

本项目不对以下情况负责：

- 因个人误操作、跳过文档步骤、刷错分区等原因导致设备无法启动或分区数据异常
- 因沉迷折腾 NixOS、反复调试 boot image、上课还在研究 flake 导致期末挂科
- 因沉迷 rice、反复调整透明终端、窗口圆角和状态栏间距导致没时间找女朋友

但如果你因此感受到了原子系统的优雅，从此远离 Debian，避免成为小男娘，请感谢本项目。

本项目的源代码、说明文档、镜像和其他产物均不提供担保。
