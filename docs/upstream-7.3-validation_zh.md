# sheng 7.3 上游回归与 PR 验证（实验）

> 这份方案只用于 `exp/upstream-7.3-validation`。正式 `sheng` 分支仍使用 7.1.8，不受影响。尚未对 7.3 完成构建或实机验收，**不要把此分支视为可用发行版**。

## 代码与基线

| 用途 | 仓库 / 分支 | 说明 |
| --- | --- | --- |
| 上游 | `map220v/sm8550-mainline:sheng-7.3` | 取固定 commit `9ce9cb0e1543980f85f5a44c074e44c569cf793d` |
| 纯净基线 | `DotRedstone/linux-sheng:exp/sheng-7.3-baseline` | 从上面这个 commit 创建，未添加任何内核补丁 |
| NixOS 实验 | `DotRedstone/nixos-sheng:exp/upstream-7.3-validation` | Flake 引用纯净基线；kernel builder 版本设为 7.3.0 |
| 候选补丁一 | `DotRedstone/linux-sheng:contrib/sheng-ramoops-20261022` | 只恢复原厂 ramoops 4 MiB 保留区 |
| 候选补丁二 | `DotRedstone/linux-sheng:contrib/sheng-cs35l43-standby-20261022` | 只恢复六颗 CS35L43 的待机属性 |

**先建立纯净基线，不要合并这两条补丁分支。** 两条独立候选都基于同一个上游 7.3 commit，可以分别验证和分别发 Draft PR。

## 重要兼容性风险

- 目前 `config.aarch64` 源自 7.1.8，第一次构建会通过 `olddefconfig` 转换；如果现有其他关键配置在 7.3 消失，构建应当失败并核查原因，不要盲目删除所有检查。
- 纯净上游没有本地的 `CONFIG_INPUT_FPC1552` 驱动。实验分支只取消了该项**构建硬断言**，没有假装指纹已经可用。
- 上游包含 NT36532E 驱动，但不等于包含本项目后来实现的 THP 5417 字节帧、触控笔与用户态 ABI；可能完全无法正常触控。
- 小米 MiPPS 认证、FPC1553 以及其他后来添加的适配不能假定在纯净 7.3 中可用。
- `boot.img`、内核模块、stage-2 rootfs 必须来自**一致的内核构建**。`7.1.8` 的 `.ko` 不得与 `7.3.0` 内核混用。CI 产出 boot image 与配套内核模块归档，**不等于**已经产出可安全刷写的整套系统。

## A. 基线构建

GitHub Actions 的 `Validate Sheng Upstream 7.3 Baseline` 工作流只作用于实验分支，不创建 Release，不执行刷机。它在 runner 上刷新 `shengKernelSrc` 对应的 Flake lock、校验固定内核 commit、构建 boot image 和配套内核模块。运行结果以 CI 记录为准。

手动本地构建：

```bash
git switch exp/upstream-7.3-validation
nix --extra-experimental-features 'nix-command flakes' flake lock --update-input shengKernelSrc ./nixos

# 确认锁定的是上游 7.3 的固定 SHA
jq -r '.nodes.shengKernelSrc.locked.rev' nixos/flake.lock
# 预期: 9ce9cb0e1543980f85f5a44c074e44c569cf793d

nix --extra-experimental-features 'nix-command flakes' \
  build ./nixos#mobileAndroidBootimg --out-link result-7.3-boot

nix --extra-experimental-features 'nix-command flakes' \
  build './nixos#nixosConfigurations.sheng.config.boot.kernelPackages.kernel' \
  --out-link result-7.3-kernel
```

完成并确认 CI 使用的锁文件后，再把 `nixos/flake.lock` 在**实验分支**提交固定，避免后续评测自动漂移。不要把更新后的锁文件合并回正式分支。

## 完整 rootfs 构建（基线 CI 通过之后）

本实验新增的 CI **只产生 boot 镜像和配套模块归档**，暂不生成完整 rootfs，也不会自动发布 Release。要做真正的上机测试，需要用**同一个实验分支**生成 stage-2 rootfs。

可以使用仓库原有的 GitHub Actions `Build NixOS RootFS` 工作流，运行时选择 `exp/upstream-7.3-validation` 分支，并保持 `skip_release=true`。按该工作流原有输入要求提供测试用户和 root 的 **crypt 密码哈希**，不要在仓库提交明文或真实个人密码。选择需要的 `mobileRootfsImageGnome` 或 `mobileRootfsImage` 变体。

注意：现有 rootfs 工作流是为 7.1.8 制定的，可能仍有额外的硬件检查。**只有 rootfs CI 也通过、且校验内部 `/lib/modules/` 与 7.3 构建对应，才进入刷机阶段。** 如果出现因缺失本地驱动导致的失败，应记录并在实验分支处理，不要关闭正式分支的验收规则。

## B. 第一次上机之前（人工操作）

- [ ] CI 内核与 boot 镜像构建成功，记录构建对应的 commit、lock、SHA256。
- [ ] 确认匹配的 stage-2 NixOS rootfs 能构建和部署；不能继续使用仅有旧 7.1.8 模块的 rootfs。
- [ ] 准备好外接 USB 键盘/鼠标、ADB/fastboot 救援路径；**不能依赖触摸屏或指纹作为唯一操作方式**。
- [ ] 备份准备替换的 boot 分区镜像，并保留已确认可启动的原有槽位与 rootfs 回退方案。
- [ ] 在设备上分别核实 `adb shell getprop ro.boot.slot_suffix` 与 `fastboot getvar current-slot`；不要假定一定是 A 或 B。
- [ ] 检查 boot 镜像大小、分区映射及刷机目标后，再由设备持有人决定刷入。此工作流不会自动刷写任何分区。

## C. 上机验证与留证

第一次启动只验证基础能力：能进入 stage-1 / stage-2、ADB 正常、UFS/rootfs 可挂载、显示与 USB 输入可用、没有明显内核崩溃或内存区域冲突。不要求纯净 7.3 立即支持 THP、指纹和私有快充。

示例采集：

```bash
adb shell uname -a
adb shell cat /proc/version
adb shell 'find /lib/modules -maxdepth 1 -mindepth 1 -type d 2>/dev/null'
adb shell 'cat /proc/iomem | grep -Ei "ramoops|reserved|System RAM"'
adb shell 'dmesg | grep -Ei "panic|oops|fail|error|ufs|qcom|nvt|fpc|cs35l43" | tail -160'
adb shell 'systemctl --failed --no-pager'
```

同时保存 `journalctl -b -k` 和对应的 kernel package 版本；这些输出要按基线 A 和补丁 B/C 独立保存。日志公开前人工脱敏。

## D. 逐项引入补丁

1. **B1：ramoops**。从 `contrib/sheng-ramoops-20261022` 单独构建，确认 `0xa7000000–0xa73fffff` 保留区无冲突、pstore/ramoops 驱动注册正常；**无需人为制造 kernel panic**。
2. **B2：CS35L43**。从 `contrib/sheng-cs35l43-standby-20261022` 单独构建，确认六颗功放枚举、播放/暂停/再播放无异常，比较待机日志；不可直接声称已经降低功耗。
3. **后续：FPC/THP/MiPPS 等**。识别哪些在 7.3 缺失，逐项移植并单独测试；涉及驱动和用户态协议的更改，应匹配更新 NixOS 服务和内核模块。
4. 每轮保存「内核 SHA + Flake lock + boot/rootfs SHA256 + 硬件验证结果」，再决定是否独立提交 PR。对已经包含在上游 7.3 的旧提交，不要重复 PR。

**注意**：验证 B1/B2 时，先从此 NixOS 实验分支另建阶段分支，并把 `shengKernelSrc` 指向相应补丁分支及固定提交，不要覆盖 A 的可复现基线。

## E. PR 规则

- 上游目标：`map220v/sm8550-mainline` 的维护者认可的分支。
- 一项独立问题一个补丁/PR，附原厂设备树证据、编译与实机日志、限制说明。
- 只有完成相应验证才把 Draft PR 标为 Ready for review。
- 别把本地的未测试驱动、闭源固件、NixOS 服务或者旧内核历史整体塞进同一个 PR。
