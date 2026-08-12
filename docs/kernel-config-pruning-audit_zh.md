# Sheng 内核配置剪枝审计

## 背景

早期构建排错时，部分配置采用了“编译报错就关闭整组功能”的处理方式。该方式确实绕过了当时的错误，但也误删了移动设备常用能力，而且配置文件中的值不一定等于 Kconfig 最终生效值。

本次审计基于：

- 配置文件的 Git 修改历史；
- Linux 7.1.8 的 `arch/arm64/configs/sm8550.config`；
- 使用 LLVM 运行 `olddefconfig` 后生成的最终 `.config`；
- Sheng 当前 NixOS 启动与模块打包方式。

## 主要发现

### 32 位兼容被整组误关

提交信息原本表示只关闭 compat vDSO，但实际同时关闭了 `CONFIG_COMPAT` 和 `CONFIG_KUSER_HELPERS`。这会阻止全部 AArch32 用户程序运行，而不只是关闭 vDSO 加速。

修复后保留：

- `CONFIG_COMPAT=y`
- `CONFIG_KUSER_HELPERS=y`
- `CONFIG_COMPAT_VDSO=n`

这样既恢复 32 位用户态 ABI，又不重新引入当时 compat vDSO 的工具链问题。

### 移动存储和 Android 常用文件系统被误删

以下能力已恢复为模块：

| 功能 | 配置 | 用途 |
| --- | --- | --- |
| Android 数据分区 | `CONFIG_F2FS_FS=m` | 检查或挂载 F2FS 分区 |
| U 盘和 EFI 介质 | `CONFIG_VFAT_FS=m` | FAT32/VFAT 文件系统 |
| 大容量移动存储 | `CONFIG_EXFAT_FS=m` | exFAT 文件系统 |
| NixOS 常用存储 | `CONFIG_BTRFS_FS=m` | Btrfs 数据盘或外置盘 |
| 光盘镜像介质 | `CONFIG_UDF_FS=m` | UDF 文件系统 |

这些驱动不参与当前 ext4 根分区的早期挂载，因此使用模块可以保留功能，同时避免明显增大 boot 镜像。

### 配置中存在无效值

`CONFIG_MULTIPLEXER=m` 对应的是布尔配置，不能取 `m`。Kconfig 会将其改写，但原配置容易误导后续维护。本次改为合法的 `CONFIG_MULTIPLEXER=y`。

`CONFIG_KERNEL_MODE_NEON=n` 也会被已启用的 ARM64 加密实现反向选择为 `y`。本次将文件中的声明改为最终真实值，避免“看起来关闭、实际开启”的状态。

## 保持关闭的项目

以下功能没有盲目恢复：

- compat vDSO：保留关闭，避免重新引入原工具链问题；
- XFS 及在线修复：当前设备没有 XFS 使用场景，模块体积和维护成本较高；
- F2FS 调试、统计和故障注入：不影响正常读写；
- CIFS 旧协议和调试选项：不启用不安全的旧式协商；
- NFS root、FUSE 实验性 io_uring 路径：不属于当前启动或桌面必需能力；
- ISO9660：当前没有挂载传统 ISO 光盘文件系统的场景，后续有明确需求再启用。

## 防回归

内核 `postConfigure` 阶段现在会检查最终 `build/.config`，而不是只相信源配置文件。以下关键项若被误剪或被 Kconfig 依赖改写，构建会立即失败并打印对应配置：

- AArch32 兼容和 kernel-mode NEON；
- F2FS、exFAT、VFAT、Btrfs、EROFS。

## 预期影响

- boot 镜像仅增加少量内建 AArch32 ABI 代码；
- 文件系统主要进入模块包，对早期启动时序影响很小；
- 恢复外置存储、Android 分区检查和 32 位程序兼容能力；
- 后续配置错误会在 CI 阶段暴露，不必刷机后再排查。

本次没有直接追求最小配置。当前有效配置约 2998 个启用项，Linux 仓库提供的 SM8550 基线约 3004 个，规模接近。后续若继续减小内核，应从已验证的设备基线生成配置片段，并按启动、音频、充电、传感器、相机和休眠链路分批验证，而不应继续根据单次编译错误直接关闭整组功能。
