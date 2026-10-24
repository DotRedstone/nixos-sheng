# Sheng Linux 7.3 补丁上游价值审计

审计日期：2026-10-25。范围是 `map220v/sm8550-mainline` 的 `sheng-7.3`（`9ce9cb0e`）、`DotRedstone/linux-sheng` PR #3–#5、`nixos-sheng` PR #46–#49，以及未提交 PR 的 Wi-Fi、原生笔、THP、MiPPS 实验分支。本报告区分源码推断、构建结果和设备日志；本轮没有刷写设备或制造 kernel panic。

## 结论与 PR 状态

| PR | 真实增量及价值 | 审计处置 |
| --- | --- | --- |
| [内核 #3](https://github.com/DotRedstone/linux-sheng/pull/3) | sheng 独有的 ramoops 保留区有诊断价值。原版 2 MiB console + 2 MiB pmsg 占满 4 MiB，且未设 `record-size`，没有 oops/panic 记录槽。 | 已追加修复提交 `3864dca`，转 Draft；目标 ramoops schema 校验通过，待新镜像、完整 `dtbs_check`、内存归属与跨重启验证后再考虑设备内核上游。 |
| [内核 #4](https://github.com/DotRedstone/linux-sheng/pull/4) | 六颗功放的合法 DTS 属性被驱动读取，改变 hibernate/standby 策略。它不自动意味着降低功耗。 | 保留候选并转 Draft；需同条件功耗和稳定性 A/B。暂不向上游提交。 |
| [内核 #5](https://github.com/DotRedstone/linux-sheng/pull/5) | 增加 FPC 资源、复位和 IRQ 桥接；对下游 TEE 方案可能有用，未证明生物识别流程。 | 维持 Draft；先厘清 binding、ABI、来源与生命周期问题，不作为正式 Linux 上游驱动提交。 |
| [NixOS #46](https://github.com/DotRedstone/nixos-sheng/pull/46) | SSC 启动等待由 6 次改为 30 次、超时由 20 秒改为 90 秒，是 NixOS 用户态时序缓解。 | 更新证据描述并转 Draft；需要冷启动 A/B 和失败路径测试。 |
| [NixOS #47](https://github.com/DotRedstone/nixos-sheng/pull/47) | 固定 #3 内核版本并构建配套 boot、模块和 rootfs。 | 已更新到 `3864dca` 及对应 NAR hash，转 Draft；旧 CI/实机记录不覆盖新 pin。 |
| [NixOS #48](https://github.com/DotRedstone/nixos-sheng/pull/48) | 固定 #4 内核候选，便于隔离构建。 | 更新描述并转 Draft；需功耗 A/B。 |
| [NixOS #49](https://github.com/DotRedstone/nixos-sheng/pull/49) | 固定 #5 候选并强制检查 `CONFIG_INPUT_FPC1552=y`。 | 维持 Draft；未完成登记、匹配和解锁验收。 |

这七条 PR 都以实验基线为目标。本报告由独立的文档 [NixOS #50](https://github.com/DotRedstone/nixos-sheng/pull/50) 提交。#47、#48、#49 各自修改同一 `shengKernelSrc` 锁定值；不能连续合并锁文件来表示内核补丁已组合。正式 `sheng` 未合并。

## 技术审查

### Ramoops：修复了确定的记录区缺失

内核 #3 的原 DTS 只有 `console-size = <0x200000>` 和 `pmsg-size = <0x200000>`。上游 [ramoops binding](https://github.com/map220v/sm8550-mainline/blob/sheng-7.3/Documentation/devicetree/bindings/reserved-memory/ramoops.yaml) 将 `record-size` 默认设为 0；[驱动](https://github.com/map220v/sm8550-mainline/blob/sheng-7.3/fs/pstore/ram.c) 从总长减去 console/pmsg 后才创建 dmesg 槽。因此原补丁只能提供 console/pmsg，不能称作完整 panic 转储配置。

修复后的 `arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dts` 保持 `0xa7000000` 起始地址和 4 MiB 总长，设置 `record-size = <0x40000>`、console 1 MiB、pmsg 1 MiB；余下 2 MiB 可形成八个 256 KiB 记录槽。改动只在内核 #3，提交为 [3864dca](https://github.com/DotRedstone/linux-sheng/commit/3864dca39b4fd2fb70332c576673c1da11cffa18)。NixOS #47 的锁文件和 CI 精确值同步提交为 [e276f93](https://github.com/DotRedstone/nixos-sheng/commit/e276f93)。

`qcs8550.dtsi` 把 `0xa7000000..0xd4cfffff` 描述为 kernel-available；设备原始日志显示 `0xa7000000..0xa73fffff` 被预留、ramoops 注册、pstore 挂载。邻近 DT 保留区和日志中的 `/proc/iomem` 未显示重叠。这些事实不足以证明旧厂商内核、UEFI/bootloader、TrustZone 或 ramdump 从不使用该区，也不足以证明内存在重启后保留。专题报告称 `/dev/pmsg0` 写入成功，但归档没有独立读回记录，更没有跨重启读回；不能称作持久化闭环。目标 ramoops schema 校验通过，完整 `dtbs_check` 尚未完成。

最低风险补测：使用与 `3864dca` 匹配的 boot/rootfs，确认 DT 属性、`/sys/module/ramoops/parameters/record_size` 和启动日志；向 pmsg 写入无敏感内容的短标记，正常**热重启**后只读检查 `/sys/fs/pstore` 是否保留，再做正常关机/冷启动对照。记录 bootloader 版本和内存布局。无需、也不得主动触发 panic。

### CS35L43：属性有效，功耗结论反向风险较大

内核 #4 是六行 DTS 属性，未修改 ALSA mixer 或均衡配置。`Documentation/devicetree/bindings/sound/cs35l43.txt` 记载 `cirrus,low-pwr-mode-standby`；`sound/soc/codecs/cs35l43.c` 读取它，在 DSP 启动后发送 `CS35L43_MBOX_CMD_PREVENT_HIBERNATE`，并在 standby 模式跳过 hibernate runtime PM 初始化。这确实改变六颗同型功放的行为，但 standby 取代 hibernate 可能增加静态耗电，不能按属性名称推断节能。

原始设备记录支持六颗 I²C 芯片探测、ALSA 声卡/PCM 枚举；专题报告称完成一次双声道 `speaker-test`，但归档中没有该命令的独立原始输出或录音。没有六个物理扬声器逐个听音、待机状态读回、功率/温度数值、无属性基线 A/B 或多次挂起恢复。若固件要求避免 hibernate，需用唤醒失败或爆音等可复现差异说明；若主要目标是节能，先测静置电流、温度和唤醒时延。完成前不应将其称作“低功耗改善”。

### FPC1553：资源探测成立，驱动和 ABI 未达上游标准

内核 #5 在 `arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dts` 声明 GPIO40 IRQ、GPIO41 reset、`vreg_l9b_3p3` 及 `wakeup-source`，并新增 `drivers/input/misc/fpc1552.c`。原始日志有 probe 和 IRQ 159 注册；所截取的 `/proc/interrupts` 计数为 0，专题报告称复位后 `irq_count=2`，但归档没有该操作的独立原始输出。`fprintd-list` 能列出 FPC1553，同时明确没有已登记指纹。TEE 枚举也不能证明这 352 行资源驱动是认证必需条件，更不能证明登记、匹配或解锁成功。

当前 DTS 用 `compatible = "fpc,fpc1020"` 表示 FPC1553，缺少针对这个资源控制模型的 DT binding；旧型号字符串不应仅为匹配驱动而复用。驱动暴露 `hw_reset`、`device_prepare`、`irq`、`irq_count`、`fingerdown_wait`、`wakeup_enable` 等设备私有 sysfs 属性；`irq_store` 接收 `ack` 却不清状态，`fingerdown_wait` 只被写入而未用于后续行为。`device_init_wakeup()` 成功而 `dev_pm_set_wake_irq()` 失败时，probe 返回路径未对称撤销 wakeup 初始化。上游前须确定真实用户态依赖、稳定 ABI、权限与并发/卸载语义，并核对 7.1.8 原始实现的提交来源、许可和署名。现有 PR 的 `checkpatch.pl --strict` 为 0 error、1 warning（新增文件是否需 MAINTAINERS）。

建议先在下游保留可复现的最小 regulator/reset/IRQ 资源层，删除无消费者的私有控制接口，再单独提交 binding 与 DTS；若 TEE 认证完全不依赖此驱动，应重新评估驱动是否必要。

### SSC / FastRPC：有效等待条件，尚无等待长度因果证据

NixOS #46 的 `nixos/hardware/xiaomi-sheng/sensors/default.nix` 以 `ssccli --sensor light --timeout 1` 做就绪条件，`adsprpcd-sensorspd` 的 `ExecStartPost` 和 `iio-sensor-proxy` 的 `ExecStartPre` 都执行该检查。`after`/`wants` 顺序能在正常路径配合，服务失败仍可能触发重试和延迟；30 次查询每次最多 1 秒并各有 1 秒 sleep，90 秒超时只提供容忍窗口，不是事件通知。固定轮询不能说明 ADSP/FastRPC 的初始错误已解决。

原始 `ssc-status.txt` 显示首次查询即成功，D-Bus 返回可用传感器，但所截取的 `AccelerometerTilt` 是 `undefined`、光强是 0.0；报告中的 `face-down` 没有对应原始查询。`ssc-dmesg.txt` 还记录 ADSP subsystem event timeout。因此当前证据支持“这一轮服务可启动并可查询”，不支持“原 6 次一定不足”或“所有传感器值稳定”。需要保留两套启动时间线、attempt 计数、冷/热启动多轮、服务崩溃/重启与真实数值后才能确定合并价值。该改动仅属于 NixOS 下游。

## 尚未提交 PR 的实验

| 分支/主题 | 审核结果与下一步 |
| --- | --- |
| NixOS `exp/7.3-wifi-single-pass` | 只调整 Wi-Fi 模块加载脚本。设备原始日志确认 WCN7850 枚举和固件加载，但 `ath12k-dmesg.txt` 未包含报告引述的 ARP `-11` 行；该错误目前只在整理报告中。不能由 `-11` 单独锁定固件/WMI 根因。保存完整同次 `dmesg`、接口 UP 时间线、固件版本和模块状态，做基线 A/B；不建立内核 PR。 |
| 内核 `exp/sheng-7.3-native-pen-probe` / `...-events` | 前者只启用 DTS 属性；后者把解析块从 `#if 0` 改为 `#if 1`，并增加 `BTN_STYLUS` 与基于估算尺寸的 X/Y resolution。原始日志只有笔设备 `event4` 枚举和 libinput 忽略消息，没有真实坐标、压力或按键事件。先用受控 `evtest`/libinput 记录真实输入并量测物理尺寸，再评估解析和上游接口；不因补齐 capability 就宣称可用。 |
| 内核 `exp/sheng-7.3-thp-legacy-port` | 修改约 4 个文件、私有协议帧为 257 + 5160 = 5417 字节，增加大容量 FIFO/字符设备读取。属于设备/固件协议候选，尚无真实帧、CRC、丢帧、ABI 与安全边界验收；不宜作为通用触控子系统补丁。先做最小只读采样、协议与来源审查。 |
| 内核 `exp/sheng-7.3-mipps-sysfs-port` | 修改 `qcom_battmgr.c`，新增 Xiaomi 私有 GLINK property/sysfs 接口；不能凭编译恢复高电流快充。差异还把原 `devm_work_autocancel()` 改为 `INIT_WORK()`，应先证明退出时 work 已取消。维持隔离实验，不自动启用高电流，补足协议响应、错误处理、温度/电流边界及拔插回归后再考虑拆分。 |

## 验证层级与交付记录

| 层级 | 本轮结果 |
| --- | --- |
| Git/范围 | 两仓库起始 `git status --short` 为空；未切换原检出目录。内核和 NixOS 改动在独立工作树完成。#3/#4 只改 sheng DTS；#5 改 DTS、Kconfig、Makefile 和一个驱动；#46 改服务与专用 CI；#47–#49 各自使用不同内核 pin。 |
| 静态 | #3 全部当前 PR diff 的 `git diff --check`、`checkpatch.pl --no-tree --strict` 通过（0 error/warning）；#4 checkpatch 也是 0 error/warning。#3 预处理 + `dtc` 成功，基线与修复版均为相同 23 行既有 DTC 警告。通过 Nix 临时提供的 `dtschema` 执行 `dt-mk-schema`，再用 `dt-validate -l ramoops` 检查修复版 DTB，目标节点 0 诊断。#5 checkpatch 为 0 error、1 MAINTAINERS warning。尚未执行完整 `make dtbs_check`：当前内核是稀疏检出；目标 schema 通过不代替全树检查。 |
| Nix evaluation | #47 新 pin 的 `nix flake update shengKernelSrc --flake ./nixos` 仅改该输入的 rev、NAR hash、时间；`jq` 校验通过；`nix eval './nixos#nixosConfigurations.sheng.config.boot.kernelPackages.kernel.modDirVersion' --raw` 得到 `7.3.0`。未在本机编译完整新 boot/rootfs。 |
| CI 构建 | 旧 PR 的 NixOS Actions 曾成功：[SSC](https://github.com/DotRedstone/nixos-sheng/actions/runs/39907775319)、[ramoops 旧 pin](https://github.com/DotRedstone/nixos-sheng/actions/runs/39916464434)、[CS35L43](https://github.com/DotRedstone/nixos-sheng/actions/runs/39916551027)、[FPC](https://github.com/DotRedstone/nixos-sheng/actions/runs/39916481771)。#47 新 pin 的 [public flake 检查](https://github.com/DotRedstone/nixos-sheng/actions/runs/40118923955) 已成功，匹配 boot/模块/rootfs 的 [构建](https://github.com/DotRedstone/nixos-sheng/actions/runs/40118920838) 截至本报告更新时仍在运行；旧 run 不覆盖修复。内核 PR 无独立 status checks。 |
| 设备 | 仅审阅 `~/sheng-7.3-testing` 报告及原始日志。本轮未接触设备。ramoops 原始日志见注册，pmsg 写入只有专题报告描述；CS35L43 原始日志见探测，双声道播放只有专题报告描述；FPC 原始日志见资源/TEE 枚举，复位计数只有专题报告描述；SSC 仅见一轮就绪；Wi-Fi 和原生笔未通过功能验收。 |

代码修改只影响候选内核 DTS（未来刷 `boot_b`）和 #47 的内核 pin/构建工作流（须重新构建配套 boot、模块、rootfs；若实际部署，`boot_b` 与 `linux` 成套）。本轮无刷写。回退方式是在各 PR 分支撤销本轮小提交或将锁文件恢复到原提交，保留旧镜像和测试日志。不能将旧 rootfs 模块与新内核混用。

推荐顺序：先使 #3 的内存归属、DT schema、新镜像和安全跨重启检查成立，再单独向 `map220v/sm8550-mainline` 的 `sheng-7.3` 提交设备 DTS；#4 仅在 A/B 证明平台确需 standby 后作为第二个独立 DTS 候选；#5 先重构并完成真正认证验收，暂不上游；SSC 留在 NixOS。最后建立一个组合内核 revision，统一重新锁定 NAR hash，构建 boot + rootfs 并做独立集成回归，之后才讨论正式 `sheng`。

本轮没有向设备内核上游创建 PR：#3 尚缺物理内存归属和新镜像实机保留性证据，#4 尚缺收益或必要性的 A/B，#5 的 binding/ABI 尚未成立。#3 当前补丁可从[上游基线比较页](https://github.com/map220v/sm8550-mainline/compare/sheng-7.3...DotRedstone:linux-sheng:contrib/sheng-ramoops-20261022)独立复核；该链接仅供审查，不表示已满足合并条件。
