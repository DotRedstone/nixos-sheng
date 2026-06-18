# Xiaomi MiPPS 快充

[English](mipps-120w.md) | [简体中文](mipps-120w_zh.md)

`sheng` 分支包含面向 sheng 的 Xiaomi MiPPS 充电器认证支持。当前集成已验证，
但持续输入功率和温度行为仍需要长期测试。

该支持需要两个部分：

- 一个 kernel patch，用于在 `/sys/devices/platform/pmic-glink/*/xiaomi/`
  下暴露小米 battery-manager 属性。
- `xiaomi-mipps-auth` 用户态服务，在 USB-C partner 接入时触发。

认证服务只会在充电器报告 Xiaomi SVID `0x2717` 时尝试小米私有流程。其他充电器
仍然走标准 PD/PPS 协商。

该服务会在接入后有意重试。sheng 上第一个 USB-C uevent 可能早于 battery
manager 更新 `real_type`、`adapter_svid` 和 `pdo2`。此时充电器可能仍显示为
`SDP`，或者 `pdo2` 仍为 `00000000`。包装脚本会等待 Xiaomi SVID、PD/PPS
`real_type` 和非空 PDO，再运行 MiPPS 握手，并在后续 USB power-supply 变化时
重试。

## 已验证结果

在 sheng 上使用兼容的小米 120W 充电器和线缆验证成功。一次成功认证会报告：

```text
adapter_svid=0x2717
authentic_verified=1
slave_authentic_verified=1
pd_auth=1
authentic=1
slave_authentic=1
apdo_max=120
power_max=120
fastchg_mode=1
pd_verifed=1
```

这证明 kernel 接口和用户态认证流程可以解锁充电器的 120W MiPPS profile。
它不证明平板会持续吸收 120W；实际输入功率仍取决于电池状态、温度和充电控制环路。

## 构建与刷机

需要同时刷入 boot image 和 GNOME rootfs：

```sh
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
nix build ./nixos#mobileRootfsImageGnome -o out/mobile-rootfs

fastboot flash boot_b out/mobile-bootimg
fastboot flash linux out/mobile-rootfs/rootfs.img
```

不要刷 `userdata`。

## 运行时验证

使用兼容的小米充电器和线缆，然后执行：

```sh
find /sys/devices/platform/pmic-glink -path '*/xiaomi/*' -maxdepth 8 -type f -print | sort

systemctl status xiaomi-mipps-auth --no-pager -l
journalctl -b -u xiaomi-mipps-auth --no-pager -o short-monotonic

for f in /sys/devices/platform/pmic-glink/*/xiaomi/{request_vdm_cmd,authentic,slave_authentic,adapter_svid,adapter_id,apdo_max,power_max,fastchg_mode,pd_verifed,bq2597x_bus_voltage,bq2597x_bus_current,bq2597x_slave_bus_current}; do
  [ -e "$f" ] || continue
  printf '%s: ' "$f"
  cat "$f"
done

for d in /sys/class/power_supply/*; do
  echo "--- $d ---"
  grep -H . "$d"/{type,online,status,usb_type,voltage_now,current_now,power_now,temp} 2>/dev/null || true
done
```

不要把 `power_max=120` 单独当成 120W 充电证明。成功验证需要：

- service journal 中出现 `pd_auth=1`。
- 小米 battery-manager 属性中 `pd_verifed=1`。
- 实测电压和电流上升。
- 电池和充电器温度稳定。
- 外置 USB-C 功率计确认。

如果快充没有激活，先看服务日志。类似
`real_type=SDP adapter_svid=10007 pdo2=00000000` 的日志表示检测到了小米
充电器，但 PD/PPS source PDO 尚未就绪。稳定状态下不应再需要反复拔插，因为
后续 `power_supply` 变化会重新触发服务。如果这些值一直卡在 `SDP` 和
`pdo2=00000000`，问题位于用户态以下的 Type-C/PD 协商状态。

## 风险与回滚

高功率充电会增加电池和接口温度。如果温度异常上升或充电反复断开，应立即停止测试。

这个实验同时改变 kernel 和 rootfs。回滚方式是刷回上一份确认可用的 `boot_b`
和 `linux` 镜像。
