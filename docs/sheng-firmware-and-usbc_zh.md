# sheng 固件与 USB-C / OTG 验证流程

[English](sheng-firmware-and-usbc.md) | [简体中文](sheng-firmware-and-usbc_zh.md)

本文记录 Xiaomi Pad 6S Pro (`sheng`) 上 USB-C / Type-C / OTG 可用所依赖的
固件链路，以及构建、刷机和验证方法。

## 工作链路

USB-C host/OTG 不是单独由 DWC3 或 HID 决定。当前已验证的链路是：

```text
sheng-firmware
  -> ADSP/CDSP remoteproc 成功加载
  -> msm/adsp/charger_pd service 通过 PDR 变为 UP
  -> ucsi_glink 的 pd_running 变为 1
  -> ucsi_register() 成功
  -> /sys/class/typec 出现 port
  -> usb_role 可从 device 切 host
  -> OTG/Hub/键盘鼠标可枚举
```

## 根因

之前失败的主因不是 kernel config、DTS、UCSI、FSA4480、PS5169、DWC3 或
USB HID。真正的问题是运行系统里没有 sheng 需要的 Qualcomm 固件文件。

典型日志包括：

```text
Direct firmware load for qcom/sm8550/sheng/adsp.mbn failed with error -2
Direct firmware load for qcom/sm8550/sheng/cdsp.mbn failed with error -2
Direct firmware load for qcom/a740_sqe.fw failed with error -2
UCSI/PD service never became running after 60 retries
```

`/sys/class/typec` 为空、`usb_role` 一直是 `device` 是结果，不是最初原因：
ADSP/CDSP 固件没加载时，`msm/adsp/charger_pd` 起不来，`ucsi_glink` 也就无
法注册 Type-C port。

## Mobile NixOS RootFS 的特殊点

普通 NixOS 中 `hardware.firmware` 通常会参与系统固件组装，但不能假设这些
固件一定会自动出现在 Mobile NixOS 生成的 rootfs 里。

本项目的 Mobile NixOS rootfs 使用自定义 `populateCommands` 和 `lib.mkForce`
生成。这个覆盖会绕开一部分常规 rootfs 组装路径，所以必须显式把
`sheng-firmware` 注入到最终镜像的 `/lib/firmware`。stage-1 也需要通过
`mobile.boot.stage-1.firmware` 带上同一份固件。

以后凡是新增或调整 firmware，都要验证最终 `rootfs.img` 里真的存在对应文件，
不要只看 Nix 表达式是否写了 `hardware.firmware`。

## 构建与刷机

常用构建命令：

```bash
nix flake lock ./nixos
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
```

刷机时同时刷 boot image 和 rootfs：

```bash
fastboot flash boot_b out/mobile-bootimg
fastboot flash linux out/mobile-rootfs/rootfs.img
fastboot reboot
```

注意：

- 只改 kernel、initrd 或 DTB 时，可能只需要重新刷 `boot_b`。
- 只要涉及 firmware、rootfs、package、systemd、用户或其他 userland 内容，
  就必须重新刷 `linux` rootfs 分区。
- 不要刷 `userdata`。
- 不要误以为只刷 `boot_b` 就能更新 `/lib/firmware`。

## RootFS 镜像离线验证

刷机前先挂载 rootfs 镜像，确认固件已经进入最终镜像：

```bash
sudo mkdir -p /mnt/sheng-rootfs
sudo mount -o loop,ro out/mobile-rootfs/rootfs.img /mnt/sheng-rootfs

find /mnt/sheng-rootfs/lib/firmware /mnt/sheng-rootfs/usr/lib/firmware -maxdepth 10 -type f 2>/dev/null \
  | grep -Ei 'qcom|sm8550|sheng|adsp|cdsp|ipa|a740' \
  | sort \
  | head -100

sudo umount /mnt/sheng-rootfs
```

必须能看到类似：

```text
/lib/firmware/qcom/sm8550/sheng/adsp.mbn
/lib/firmware/qcom/sm8550/sheng/cdsp.mbn
/lib/firmware/qcom/sm8550/sheng/ipa_fws.mbn
/lib/firmware/qcom/a740_sqe.fw
```

如果看不到这些固件，不要刷机，先修 rootfs 生成逻辑。

## 运行系统验证

进入系统后检查固件、remoteproc、Type-C 和 UCSI 日志：

```sh
find /lib/firmware /usr/lib/firmware -maxdepth 10 -type f 2>/dev/null \
  | grep -Ei 'qcom|sm8550|sheng|adsp|cdsp|ipa|a740' \
  | sort \
  | head -100

ls -la /sys/class/remoteproc
for r in /sys/class/remoteproc/remoteproc*; do
  [ -e "$r" ] || continue
  echo "--- $r ---"
  cat "$r/name" 2>/dev/null
  cat "$r/state" 2>/dev/null
  cat "$r/firmware" 2>/dev/null
done

ls -la /sys/class/typec
cat /sys/class/usb_role/a600000.usb-role-switch/role

dmesg | grep -Ei 'adsp|cdsp|Direct firmware load|request_firmware|charger_pd|pd_running|ucsi_register|UCSI/PD service|remoteproc' | tail -250
```

成功标准：

- 能看到 `qcom/sm8550/sheng` 固件文件。
- `adsp.mbn` 和 `cdsp.mbn` 不再 `request_firmware failed: -2`。
- `ucsi_glink` 不再报 `UCSI/PD service never became running after 60 retries`。
- `/sys/class/typec` 出现 port。
- 插入 OTG、Hub 后，`usb_role` 能切到 `host`。
- USB 键鼠或 Hub 能在 `lsusb`、`/sys/bus/usb/devices` 或
  `/proc/bus/input/devices` 中出现。
- ADB device 模式仍可用。

## 故障排查

| 现象 | 优先检查 |
| --- | --- |
| `/sys/class/typec` 为空 | 先查 `pd_running`、`charger_pd` 和 firmware，不要先改 HID。 |
| `Direct firmware load ... error -2` | 固件路径缺失，或刷机时没有更新 `linux` rootfs 分区。 |
| `usb_role=device` | 如果 Type-C 为空，说明 UCSI 未注册，不代表 DWC3 host 一定坏。 |
| `ps5169 dvdd` 使用 dummy regulator | 不是第一主因；等 Type-C 已注册后再排查高速链路。 |
| `fixed dependency cycle` | 常见于设备树 graph 依赖，不作为第一主因。 |
| qcom-battmgr synthetic uevent `-11` | 可以降噪，但不是 USB-C host 主因。 |
| 只刷 `boot_b` 后 firmware 不变 | firmware 在 rootfs 里，必须刷 `linux` 分区。 |

## 回滚

如果新的 rootfs 或 boot image 启动异常，可以切回 Android 所在 slot，或重新刷回
上一份确认可用的 `boot_b` 与 `linux` 镜像。涉及 firmware/rootfs 的回滚同样
需要重新刷 `linux` 分区。
