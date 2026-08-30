# 发布审查清单

[English](release-readiness.md) | [简体中文](release-readiness_zh.md)

本文是 `nixos-sheng` 的发版门禁，分别检查源码、实机和产物来源。构建成功不等于
可以发布。

## 当前结论

**v0.3.0 已从审查后的提交 `25c8463` 正式发布。** 普通启动、手动世代选择交接、
源码审查以及自动化产物来源和文件系统门禁均已通过。下方仍未勾选的项目继续作为
验证或再分发缺口公开记录，不表述为已经完整验证。

## 源码门禁

- [x] 已通过 PR #1 将 `linux-sheng:feat/stylus-thp` 合并到维护中的 7.1.8 分支，
  并把 `shengKernelSrc` 锁定到该维护 ref。
- [x] 通过 PR #25 审查当前 NixOS audit 分支，确认没有无关的分支改名或
  历史重写。
- [x] `nix flake lock ./nixos` 不产生意外 lock 漂移。
- [x] `nix flake check ./nixos --no-build` 通过。
- [x] 世代菜单 Ruby 语法、渲染边界、命令流、分页、长按重复和待启动选择测试通过。
- [x] `git diff --check`、Markdown 链接、YAML 解析、许可证/第三方声明和已跟踪文件
  凭据扫描通过。

## 实机门禁

必须使用同一个发布候选提交对应的 boot 和 rootfs。

- [ ] 连续 3 次普通启动均为 0 failed unit，且没有新 coredump。
- [x] 在世代菜单停留至少 15 秒，选择旧世代；确认只快速重启一次，下一次跳过菜单。
- [x] `adsprpcd-sensorspd` 和 `iio-sensor-proxy` active、`NRestarts=0`，直接 SSC
  查询成功。
- [x] 根分区可写、ext4 clean、`errors_count=0`，无 UFS reset、timeout、abort 或
  block I/O error。
- [ ] 2.4 GHz 与 5 GHz 无需重启即可连接；若低概率首次刷入问题出现，应先保存日志。
- [ ] 标准 PD 与 MiPPS 分开测试；电脑 USB 数据口充电也与纯充电器场景分开表述。
- [ ] 扬声器播放/重播和麦克风录音正常，WirePlumber 没有新 coredump。
- [ ] 触控、旋转、盖板、Focus Pen 压感/倾斜/按键、指纹录入/验证和熄屏唤醒完成。
- [ ] 前后摄 RAW 抓取无回归，CAMSS 能回到 runtime suspend。

建议采集：

```sh
sudo scripts/collect-hardware-baseline.sh 10 > sheng-release-health.txt
systemctl --failed --no-pager
coredumpctl list --since boot
systemctl show adsprpcd-sensorspd iio-sensor-proxy \
  -p Id -p ActiveState -p NRestarts
sheng-rootfs-status
```

公开前仍需人工复查内容；自动脱敏不能替代隐私检查。

## 产物门禁

- [x] Kernel、minimal rootfs、GNOME rootfs 三个 workflow run 的 `headSha` 完全相同，
  且对应经过审查的合并提交。
- [x] Boot image 小于 `boot_b` 分区，模块归档的 `modDirVersion` 与内核一致。
- [x] Rootfs 通过只读 `e2fsck`，并包含 `metadata_csum`、`64bit`、`dir_index`。
- [ ] 发布压缩包能解出可直接刷写的镜像，每个资产都进入 `sha256sums.txt`。
- [x] Release 同时包含 `LICENSE` 和 `THIRD_PARTY_NOTICES.md`。
- [x] Rootfs 候选版使用强 yescrypt password hash，不使用仓库开发密码，也不通过
  workflow 传明文密码。
- [ ] 针对实际产物内容复核 firmware 和闭源二进制再分发权限。

## 2026-08-30 已记录证据

使用提交 `0151b29` boot image 的一次普通启动为 21.066 秒：kernel 9.075 秒，
userspace 11.990 秒，`graphical.target` 在 userspace 11.006 秒到达。系统状态为
`running`、0 failed unit，两个 SSC 服务均 active 且 `NRestarts=0`。

另一次旧实现启动的 `e2fsck -p` 约 0.18 秒，但在 `Tasks::SwitchRoot` 停留约 29 秒，
随后复现 SSC QMI 服务缺失和 sensor daemon 反复重启。

2026-08-30 使用提交 `86c2b22` 的 boot image 完成修复后回归：第一次启动在菜单内
停留约 24 秒并手动确认，随后发生一次快速重启；第二次启动跳过菜单，一次性选择标记
已删除。第二次启动总计 18.075 秒，`graphical.target` 在 userspace 11.216 秒到达；
系统为 `running`、0 failed unit、无 coredump，root 为可写 ext4 且
`errors_count=0`。`adsprpcd`、`pd-mapper`、`adsprpcd-sensorspd` 和
`iio-sensor-proxy` 均 active、`NRestarts=0`。这解除菜单交接的实机阻断，但不替代
合并提交正式产物的完整回归。

v0.3.0 的全部产物来自合并提交 `25c8463`：kernel run `33312231001`、minimal
rootfs run `33312236690`、GNOME rootfs run `33312241560`。Release run
`33315331473` 核对了共同提交，检查并缩小两份 ext4，生成分卷 ZIP 与校验和，最终
发布 9 个已上传附件。完整分卷的终端用户解压实测和闭源二进制再分发审查仍按上方
清单保持未完成。
