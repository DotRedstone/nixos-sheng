# U-Boot 直启 Android A 槽：ROM 配置采集

当前直启入口只适用于 Xiaomi Pad 6S Pro 12.4（`sheng`）上解锁引导器、
使用动态分区的 Android A 槽。U-Boot 从设备自己的 A 槽读取启动镜像；
ROM 的启动设备、fstab 后缀及 AVB 状态须从该 ROM 实际启动时采集。
配置文件存放在 `linux-boot` ESP 的 `/SHENG/ANDROID.ENV`，不进入公共镜像。
持久 `boot_b` 测试须使用 `shengUbootAndroidDirectV4ProbeBootimg` 的 v4 产物；
`shengUbootAndroidDirectProbeBootimg` 是 RAM 探针，不作为刷写镜像。

## 采集与安装

先用原生 A 槽启动 Android，打开 USB 调试并连接电脑。电脑上运行：

```sh
python3 scripts/sheng-android-rom-config.py capture --output /tmp/sheng-android.env
```

脚本只提取启动所需的非个人参数，并要求 Android 报告设备为 `sheng`、
槽位为 `_a`、AVB 状态为 `orange`。缺少参数或发现危险字符时会拒绝生成。
不要将生成文件提交到 Git。ROM 更新后应重新采集。

返回 B 槽 NixOS，确认它已经启动且电脑 ADB 可用，再安装配置：

```sh
python3 scripts/sheng-android-rom-config.py install --profile /tmp/sheng-android.env
```

安装程序要求 root ADB、`/boot` 已挂载到 `linux-boot`，还会只读检查
`dtbo_a` 和 `dtbo_b` 是否有有效 Android DTBO 头。现有
[双系统安装指南](install-dualboot_zh.md)会清空 `dtbo_b`；如果 B 槽仍为空，
先在 NixOS 下显式运行：

```sh
python3 scripts/sheng-android-rom-config.py prepare-dtbo-b --backup-dir ~/sheng-dtbo-backup
```

此命令先把 A/B 两份 DTBO 完整备份到新目录，仅在两分区大小相同、A 有有效
DTBO 头且 B 全为空时复制 A 到 B，写后逐字节校验。B 已有效但与 A 不同时
不会自动覆盖，须人工核对。不要将备份提交到 Git。

配置安装脚本会把旧配置保留为
`ANDROID.ENV.previous`，并在写入后核对 SHA-256。只写 ESP 上的配置文件，
不写 A 槽、`boot_b`、`linux` 或 `userdata`。以后可删除配置文件以停用
Android 直启入口；U-Boot 菜单中的 NixOS 路径仍可用。

## U-Boot 启动时的边界

菜单选择 Android 后，U-Boot 先读取并检查配置，再从 A 槽分区表取得
`boot_a`、`vendor_boot_a`、`init_boot_a` 和 `dtbo_a` 的读取长度。任一分区
超过当前已验证的 RAM 布局上限，或 Android boot header 不属于 v4，
就拒绝交接并返回菜单。当前交接继续使用 ABL 传入的设备树，未采用固定的
DTB/DTBO 索引。

配置采集解决了启动参数随 ROM 变化的问题，但**尚不构成跨 ROM 实机验收**。
Android 更新可能改变启动链、内存布局、ramdisk 或 AVB 行为；更新后必须
重新采集配置并验证 Android 桌面、ADB、活动槽仍为 B，以及返回 NixOS。
首次为其他 ROM 使用时应先备份 `boot_b` 和 ESP，并保留 Fastboot 回退路径。
