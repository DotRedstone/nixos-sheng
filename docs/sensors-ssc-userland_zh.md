# Xiaomi Pad 6S Pro 12.4 (sheng) Sensors 用户态适配方案

[English](sensors-ssc-userland.md) | [简体中文](sensors-ssc-userland_zh.md)

## 当前结论

sheng 的传感器链路已经通过 Qualcomm SSC 用户态方案跑通。实机验证可用：

- accelerometer，加速度计
- proximity，距离传感器
- ambient light，光感
- compass，指南针
- `iio-sensor-proxy.service` 开机后保持 `active (running)`

当前实现不是内核 IIO sysfs 方案，因此 `/sys/bus/iio/devices` 下面仍不会出现 `iio:device*`。这不影响 `iio-sensor-proxy` 通过 D-Bus 给桌面和应用提供传感器数据。

GNOME profile 默认关闭 `ambient-enabled` 和 `idle-dim`。SSC 光感仍会通过
`iio-sensor-proxy` 暴露给应用和诊断工具，但 GNOME 不会根据有波动的 lux 数值
自动改写背光，也不会在闲置时临时降低亮度。用户仍可手动调节亮度。

## 路线判断

sheng 的传感器不是普通 Linux AP 侧 I2C/SPI 设备路径。不要在 DTS 中强行编造 `icm42607`、`qmc6308`、`stk36c61` 等物理设备节点，也不要把“没有 `/sys/bus/iio/devices/iio:device*`”直接等同于传感器失败。

当前可工作的路径是：

```text
ADSP / sensor_pd
-> FastRPC / QRTR
-> adsprpcd sensorspd
-> libssc
-> iio-sensor-proxy SSC backend
-> D-Bus: net.hadess.SensorProxy
```

`CONFIG_QCOM_SSC_BLOCK_BUS=y` 只提供 SSC/FastRPC/QMI 通信能力，不会自动把 QMI sensor 注册成 kernel IIO 设备。Debian 用户态方案也是通过 `libssc` 直接读取 SSC，再由 `iio-sensor-proxy` 暴露给上层。

## 关键实现点

本仓库通过 `nixos/hardware/xiaomi-sheng/sensors/default.nix` 集成传感器用户态链路：

- 打包 `fastrpc`、`libssc`、`pd-mapper`、`qrtr`、`sheng-sensors-file`
- 为 `iio-sensor-proxy` 启用 `-Dssc-support=enabled`
- 启动 `adsprpcd.service`
- 启动 `adsprpcd-sensorspd.service`
- 给 `fastrpc-adsp` udev 设备标记：
  `ssc-accel ssc-proximity ssc-light ssc-compass`
- 为 `ACCEL_MOUNT_MATRIX` 设置 sheng 横屏原生面板对应的方向矩阵，避免 GNOME 自动旋转结果偏移 90°
- 在启动 `iio-sensor-proxy` 前等待 SSC 可查询，避免开机太早导致代理退出

这些等待用于处理短暂抖动，不应掩盖 stage-1 的长时间停留。2026-08-30 的干净启动
约 21 秒完成，`adsprpcd-sensorspd` 和 `iio-sensor-proxy` 均为 `NRestarts=0`；在世代
菜单停留约 29 秒则能复现 SSC QMI 服务缺失和 daemon 反复重启。因此手动选择世代后
会先保存选择并快速重启，下一次 stage-1 跳过菜单，在 SSC 注册窗口内进入 stage-2。

上游 `iio-sensor-proxy` 默认只给 `fastrpc-adsp` 启用 `ssc-light ssc-compass`，不会默认启用 `ssc-accel` 和 `ssc-proximity`。sheng 需要显式补充 udev 规则，否则加速度计和距离传感器不会被 `monitor-sensor` 看到。

## 验证结果

实机验证时，`monitor-sensor` 输出已确认：

```text
=== Has accelerometer
=== Has proximity sensor
=== Has ambient light sensor
=== Has compass
```

`ssccli` 也可直接读取：

- `ssccli --sensor accelerometer`
- `ssccli --sensor magnetometer`
- `ssccli --sensor proximity`
- `ssccli --sensor light`

## 验证命令

```sh
echo '=== system ==='
uname -a
readlink -f /run/current-system 2>/dev/null || true

echo '=== services ==='
systemctl status adsprpcd pd-mapper adsprpcd-sensorspd iio-sensor-proxy --no-pager -l || true

echo '=== fastrpc / udev ==='
ls -la /dev/fastrpc* /dev/adsprpc* 2>/dev/null || true
udevadm info -q property -p /sys/devices/virtual/misc/fastrpc-adsp 2>/dev/null \
  | grep -E 'IIO_SENSOR_PROXY_TYPE|ACCEL_MOUNT_MATRIX' || true

echo '=== iio-sensor-proxy ==='
monitor-sensor --accel
monitor-sensor --proximity
monitor-sensor --light
monitor-sensor --compass

echo '=== GNOME brightness policy ==='
gsettings get org.gnome.settings-daemon.plugins.power ambient-enabled
gsettings get org.gnome.settings-daemon.plugins.power idle-dim

echo '=== libssc direct ==='
ssccli --sensor accelerometer --timeout 5
ssccli --sensor magnetometer --timeout 5
ssccli --sensor proximity --timeout 5
ssccli --sensor light --timeout 5

echo '=== logs ==='
journalctl -b -u adsprpcd -u pd-mapper -u adsprpcd-sensorspd -u iio-sensor-proxy \
  --no-pager -o short-monotonic | tail -300
```

## 已知限制

- `/sys/bus/iio/devices/iio:device*` 仍为空。当前方案走 SSC 用户态和 D-Bus，不创建 kernel IIO sysfs 设备。
- proximity 会出现 `Failed to unpack Xiaomi Davinci proximity measurement message` 日志，但 `monitor-sensor --proximity` 仍能看到 FAR/near 状态。
- gyroscope 尚未作为单独的 `monitor-sensor` 能力暴露。当前 compass 来自 SSC rotation vector / magnetometer 路线，加速度计可用于屏幕方向判断。
- 当前测试镜像上的 `sheng-devauth.service` 保持 active，等待小米配件认证 challenge；
  它服务于键盘/触控笔配件认证，不是 SSC 传感器样本来源。
- 使用旧 boot image 并在 stage-1 菜单长时间停留时仍可能错过 SSC 注册。应先升级到
  带手动选择交接的 boot image，并检查单调时钟启动日志，不要继续叠加用户态 sleep。

## 常见失败判断

如果 `iio-sensor-proxy` 退出并显示：

```text
No sensors or missing kernel drivers for the sensors. Exiting
```

优先检查：

1. `/dev/fastrpc-adsp` 是否存在。
2. `adsprpcd-sensorspd.service` 是否运行。
3. `ssccli --sensor light --timeout 5` 是否能读到数据。
4. `fastrpc-adsp` 的 udev 属性是否包含：
   `ssc-accel ssc-proximity ssc-light ssc-compass`
5. `/usr/share/qcom/sm8550/Xiaomi/sheng` 和 `/vendor/etc/sensors` 相关 registry/config 是否存在。
6. Stage-1 挂载根分区到 switch-root 之间是否出现异常长停留。可将
   `journalctl -b -o short-monotonic` 与 Mobile NixOS 导入的 boot log 对照。

## 后续方向

当前建议把 sensors 状态标记为“用户态可用”。如果后续需要满足严格的 kernel IIO sysfs 标准，需要另开任务研究：

- 是否存在可复用的 QMI/SSC 到 IIO 的内核桥接驱动
- 是否值得为 sheng 编写 kernel IIO bridge
- 是否要把 gyro 单独映射到上层可消费的接口
- proximity Xiaomi Davinci payload 解包是否需要补 `libssc`

这些是后续增强，不阻塞当前传感器在桌面侧使用。
