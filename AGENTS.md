# AGENTS.md

本仓库是 Xiaomi Pad 6S Pro 12.4（sheng）的 Mobile NixOS / NixOS 移植项目。

所有 agent / 协作者在开始任何任务前，必须先阅读本文件。
本文件用于约束开发行为、刷机边界、验证流程和提交规范。具体功能 TODO、路线图和已知问题不要写在这里，应放到 README、docs、TODO.md 或 GitHub Issues。

## 基本原则

* 先诊断，再修改。
* 最小改动优先。
* 功能稳定优先。
* 不做无关重构。
* 不做未经确认的大范围格式化、目录重排或风格统一。
* 不要为了“看起来干净”删除尚未验证的硬件 workaround。
* 不要把多个硬件问题混在一个 patch 或一个提交里。
* 修改前先判断影响范围：boot、rootfs、kernel、firmware、systemd、udev、桌面环境分别处理。

## 分支规范

新功能、实验性改动和风险较高的硬件修复必须开新分支开发，不要直接在稳定分支上试错。

建议分支命名：

* `feat/...`：新功能
* `fix/...`：问题修复
* `docs/...`：文档
* `exp/...`：实验性验证
* `cleanup/...`：清理或补丁审计
* `wip/...`：未完成临时工作

示例：

```text
feat/gnome-profile
fix/usbc-firmware-rootfs
docs/flash-guide
exp/wifi-ath12k
cleanup/kernel-patches
```

实验性分支必须明确说明风险。未经验证的实验分支不要默认合并到稳定分支。

## 提交规范

commit message 使用中文，并采用类似 Conventional Commits 的格式：

```text
<type>(<scope>): <summary>
```

常用 type：

* `feat`：新增功能
* `fix`：修复问题
* `docs`：文档
* `refactor`：重构
* `cleanup`：清理
* `test`：测试
* `build`：构建相关
* `ci`：CI 相关
* `chore`：杂项维护

常用 scope：

* `nixos`
* `mobile`
* `kernel`
* `firmware`
* `usbc`
* `wifi`
* `rootfs`
* `docs`

示例：

```text
docs(nixos): 补充 sheng 固件与 USB-C 验证流程
fix(rootfs): 将 sheng 固件注入 /lib/firmware
fix(kernel): 恢复 qcom pd mapper 辅助总线模型
feat(wifi): 启用 WCN7850 驱动支持
cleanup(kernel): 降低 UCSI 调试日志噪音
```

提交要求：

* 每个提交尽量只做一类事情。
* 不要把功能修复、日志清理、文档整理混在一个提交里。
* 不要提交构建产物、临时日志、运行时缓存。
* 不要提交 secret、token、cookie、session、个人账号信息、API key、原始敏感日志。
* 如果需要引用日志，只保留必要片段，并删除序列号、账号、密钥、网络凭据等敏感信息。

## flake.lock 规则

不要无理由更新 `flake.lock`。

只有以下情况允许更新：

* 新增、删除或明确升级 flake input。
* 修复构建必须依赖新的锁定版本。
* 用户明确要求更新。
* 文档或报告中明确说明为什么必须更新。

更新后必须在报告中写清楚原因和影响。

## boot / rootfs 边界

本项目同时涉及 Android boot image 和 Linux rootfs。每次修改后必须明确需要刷哪个分区。

通常规则：

| 修改内容                     | 构建目标                            | 刷写分区                   |
| ------------------------ | ------------------------------- | ---------------------- |
| kernel config            | `mobileAndroidBootimg`          | `boot_b`               |
| kernel patch             | `mobileAndroidBootimg`          | `boot_b`               |
| DTS / DTB                | `mobileAndroidBootimg`          | `boot_b`               |
| initrd / stage-1         | `mobileAndroidBootimg`          | `boot_b`               |
| boot cmdline             | `mobileAndroidBootimg`          | `boot_b`               |
| firmware                 | `mobileRootfsImage`             | `linux`                |
| systemd service          | `mobileRootfsImage`             | `linux`                |
| udev rules               | `mobileRootfsImage`             | `linux`                |
| desktop profile          | `mobileRootfsImage`             | `linux`                |
| ordinary packages        | `mobileRootfsImage`             | `linux`                |
| rootfs layout            | `mobileRootfsImage`             | `linux`                |
| kernel modules in rootfs | `mobileRootfsImage`，必要时也构建 boot | `linux`，必要时也刷 `boot_b` |

如果同时改 kernel 和 rootfs，通常需要同时刷 `boot_b` 和 `linux`。

不要刷 `userdata`，除非用户明确要求并理解风险。

常用构建和刷机命令：

```bash
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
fastboot flash boot_b out/mobile-bootimg
```

```bash
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
fastboot flash linux out/mobile-rootfs/rootfs.img
```

## Mobile NixOS 特殊注意事项

不要假设普通 NixOS 的 rootfs 行为会自动适用于 Mobile NixOS。

特别注意：

* `hardware.firmware` 不一定会自动出现在最终 rootfs 的 `/lib/firmware`。
* kernel modules 不一定会自动出现在最终 rootfs 的 `/lib/modules`。
* 修改 firmware 或 modules 后，必须检查最终 rootfs 镜像内容。
* 只刷 `boot_b` 不会更新 `/lib/firmware`、`/lib/modules`、systemd、udev、桌面环境。
* 如果运行系统已有 `nix` / `nixos-rebuild`，仍需判断 rootfs 空间、profile 状态和是否涉及 boot image。

rootfs 离线检查示例：

```bash
sudo mkdir -p /mnt/sheng-rootfs
sudo mount -o loop,ro out/mobile-rootfs/rootfs.img /mnt/sheng-rootfs

find /mnt/sheng-rootfs/lib/firmware /mnt/sheng-rootfs/usr/lib/firmware -maxdepth 10 -type f 2>/dev/null \
  | sort \
  | head -100

sudo umount /mnt/sheng-rootfs
```

运行系统检查示例：

```sh
find /lib/firmware /usr/lib/firmware -maxdepth 10 -type f 2>/dev/null | sort | head -100
find /lib/modules -type f 2>/dev/null | sort | head -100
ls -la /run/current-system
ls -la /nix/var/nix/profiles/system
```

## 硬件修复原则

### USB-C / OTG

USB-C / OTG 依赖链路：

```text
sheng-firmware
→ ADSP/CDSP remoteproc
→ msm/adsp/charger_pd
→ PMIC-GLINK / PDR
→ ucsi_glink pd_running=1
→ ucsi_register()
→ /sys/class/typec 出现 port
→ usb_role 可切 host
```

如果 `/sys/class/typec` 为空，优先检查：

* `/lib/firmware/qcom/sm8550/sheng/`
* ADSP/CDSP remoteproc 是否启动
* `msm/adsp/charger_pd`
* `pd_running`
* `ucsi_register`
* PMIC-GLINK / PDR 日志

不要先去改 USB HID、DWC3、NetworkManager 或无关 DTS。

常用检查：

```sh
ls -la /sys/class/typec
cat /sys/class/usb_role/a600000.usb-role-switch/role

dmesg | grep -Ei 'adsp|cdsp|firmware|charger_pd|pd_running|ucsi|typec|pmic_glink|PDR' | tail -300
```

### Wi-Fi

如果没有 `wlan0` 或 `iw dev` 为空，说明无线网卡还没枚举或驱动没加载。

优先检查：

* kernel config 中 ATH12K / ATH11K / MHI / PCIe 相关选项
* `/lib/modules` 是否包含 ath12k / mhi / qmi / qrtr 相关模块
* `/lib/firmware/ath12k/...` 是否存在
* PCIe endpoint 是否枚举
* dmesg 中 ath12k / MHI / PCIe 日志

没有无线接口时，不要先修改 Wi-Fi 密码、wpa_supplicant 或 NetworkManager 配置。

常用检查：

```sh
ip link
iw dev 2>/dev/null || true
rfkill list 2>/dev/null || true

find /lib/modules -type f 2>/dev/null \
  | grep -Ei 'ath12k|ath11k|mhi|qmi|qrtr|wlan' \
  | head -100

find /lib/firmware /usr/lib/firmware -maxdepth 10 -type f 2>/dev/null \
  | grep -Ei 'ath12k|WCN7850|board-2|amss|m3|qca|wlan|wifi' \
  | head -100

dmesg | grep -Ei 'ath12k|ath11k|wcn|wlan|wifi|mhi|pci|pcie|qmi|qrtr|firmware' | tail -300
```

### Kernel patch

不要随意删除 kernel patch。

删除或清理前必须做补丁审计：

* 这个 patch 改了什么？
* 是功能修复、容错、日志，还是历史 workaround？
* 是否已被上游包含？
* 删除后需要刷 `boot_b` 还是 rootfs？
* A/B 测试结果是什么？
* 回滚方式是什么？

每次只禁用或清理一个 patch，不要多个一起删。

## 验证要求

每次修改后必须报告：

* 改了哪些文件
* 为什么这样改
* 构建命令和结果
* 需要刷 `boot_b`、`linux/rootfs`，还是都要刷
* 运行时验证命令和结果
* 风险
* 回滚方式

推荐最小验证命令：

```bash
git status
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
```

如果只改文档，可以不构建，但需要说明原因。

运行时常用检查：

```sh
ls -la /sys/class/typec
cat /sys/class/usb_role/a600000.usb-role-switch/role
ip link
dmesg | grep -Ei 'adsp|cdsp|firmware|charger_pd|pd_running|ucsi|typec|ath12k|mhi|pcie|wlan' | tail -300
```

## 文档规则

修通的硬件链路、刷机方式、已知问题和验证命令必须及时写入文档。

不要只把关键经验留在聊天记录或临时日志里。

`AGENTS.md` 只写协作规则和操作边界，不写当前 TODO。
当前任务、路线图、已知问题应放在 README、docs、TODO.md 或 GitHub Issues。

## Release 与 Actions 规则

本项目的构建产物面向真实刷机使用，因此每次修改后必须明确影响范围，并触发对应构建。

### 版本规则

使用语义化版本，并在硬件 bring-up 阶段使用 alpha / beta 标记：

* `v0.1.0-alpha.1`：首个可启动测试镜像
* `v0.1.0-alpha.N`：每次修通一个用户可感知硬件功能后递增
* `v0.1.0-beta.N`：主要硬件基本可用后使用
* `v0.1.0`：达到可公开日用测试标准后使用

不要因为普通文档修改、日志降噪、小型重构发布 release。
每修通一个明确硬件能力，例如 Wi-Fi、触摸、蓝牙、音频、传感器、相机，可以考虑发布新的 alpha release。

### 构建产物规则

根据修改范围选择构建目标：

| 修改范围                                                                                      | Actions 构建目标  | Release 附件               |
| ----------------------------------------------------------------------------------------- | ------------- | ------------------------ |
| kernel config / kernel patch / DTS / DTB / initrd / cmdline                               | boot image    | `sheng-boot-*.img`       |
| firmware / systemd / udev / packages / desktop / rootfs layout / kernel modules in rootfs | rootfs image  | `sheng-rootfs-*.img.zst` |
| 同时影响 boot 和 rootfs                                                                        | boot + rootfs | 两者都上传                    |
| 仅文档                                                                                       | 不构建刷机包        | 不发布 release              |

修改 rootfs 内容后，不要只构建 boot。
修改 kernel modules、firmware、桌面环境、普通软件包后，必须构建 rootfs。
修改 kernel config、DTS、kernel patch 后，必须构建 boot；如果模块也进入 rootfs，则 rootfs 也要构建。

### Actions 触发规则

普通分支或 PR：

* 可以运行构建检查。
* 可以上传临时 artifact。
* 不自动发布 GitHub Release。

手动 workflow_dispatch：

* 可选择构建 `boot`、`rootfs` 或 `both`。
* 可选择是否上传 artifact。
* 默认不发布 release，除非显式传入 release/tag 参数。

tag 推送：

* `v*` tag 可以触发正式 release workflow。
* release workflow 必须生成校验文件。
* release workflow 必须上传刷机说明或在 release notes 中写清楚刷机方式。

### Release 附件规则

Release 至少包含：

* boot 镜像，如果本版本需要刷 `boot_b`
* rootfs 镜像，如果本版本需要刷 `linux`
* `sha256sums.txt`
* 简要刷机说明
* Known issues

推荐命名：

```text
sheng-v0.1.0-alpha.1-boot.img
sheng-v0.1.0-alpha.1-rootfs-minimal.img.zst
sheng-v0.1.0-alpha.1-sha256sums.txt
```

GNOME 或其它大桌面环境不要默认塞进 minimal 镜像。
如果提供 GNOME 测试镜像，使用单独附件：

```text
sheng-v0.1.0-alpha.N-rootfs-gnome.img.zst
```

### Release notes 必须包含

每个 release 必须写清楚：

* 当前版本适用设备
* 当前可用硬件
* 当前不可用硬件
* 需要刷哪些分区
* 是否需要扩容 linux 分区
* 是否需要同时刷 `boot_b` 和 `linux`
* 回滚方式
* 不要刷 `userdata` 的提醒

### 安全规则

Actions 和 release 中不得包含：

* token
* cookie
* session
* 私人账号信息
* 原始敏感日志
* Android userdata 内容
* 未清理的调试 dump

所有 release 附件必须来自可复现的 Actions 构建或明确记录的本地构建流程。

## 提交历史与分支整理规则

本项目处于硬件 bring-up 阶段，早期 commit 数量多是正常现象。不要为了“看起来干净”强行重写已经推送到远端的历史。

原则：

- 已经推送到远端的公共分支，默认不 force push。
- 已经发布 release/tag 之后，不要重写该 tag 之前的历史。
- 早期 bring-up 的调试 commit 可以保留，作为问题定位记录。
- 从当前阶段开始，新增提交必须更清晰、更小粒度。
- 一个 commit 尽量只做一类事情。
- 不要把功能修复、文档、CI、日志清理混在一个 commit。
- 新功能和风险改动必须开分支。
- 合并前可以在功能分支内整理 commit，但不要改公共稳定分支历史。
- 如果使用 PR，推荐 squash merge 或 rebase merge，让主线历史保持清晰。
- release 节点通过 tag 区分，而不是靠重写历史制造“干净起点”。

只有以下情况允许考虑重写历史：

- 历史中出现 secret、token、cookie、session、API key、个人账号等敏感信息。
- 误提交了巨大构建产物或二进制垃圾。
- 用户明确要求重写历史，并确认了解 force push 风险。
- 当前分支尚未公开使用，且没有 release/tag 依赖。

重写历史前必须先报告：
- 为什么必须重写
- 会影响哪些分支/tag
- 是否需要删除或重建 release
- 回滚方式
- 是否需要通知已有使用者

建议后续开发模式：

- `sheng`：开发主线，保留真实 bring-up 历史。
- `stable/v0.1`：面向 release 的稳定分支。
- `feat/...`、`fix/...`、`exp/...`：功能和实验分支。
- 每个可用硬件能力通过 release tag 记录，例如 `v0.1.0-alpha.1`、`v0.1.0-alpha.2`。
