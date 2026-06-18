# Xiaomi Pad 6S Pro 12.4 (`sheng`) Sensor User-Space Integration

[English](sensors-ssc-userland.md) | [简体中文](sensors-ssc-userland_zh.md)

## Current Status

The sheng sensor path works through Qualcomm SSC user space. Real-device
validation confirms:

- accelerometer
- proximity sensor
- ambient light sensor
- compass
- `iio-sensor-proxy.service` remains `active (running)` after boot

This is not a kernel IIO sysfs implementation. `/sys/bus/iio/devices` is still
expected to have no `iio:device*` entries. That does not prevent
`iio-sensor-proxy` from exposing sensor data to the desktop and applications
through D-Bus.

The GNOME profile disables `ambient-enabled` and `idle-dim` by default. The SSC
ambient-light sensor remains available through `iio-sensor-proxy` for
applications and diagnostics, but GNOME does not automatically rewrite
backlight values from fluctuating lux readings or dim the display while idle.
Users can still adjust brightness manually.

## Architecture Decision

sheng sensors do not follow the simple Linux AP-side I2C/SPI device model. Do
not invent DTS nodes such as `icm42607`, `qmc6308`, or `stk36c61`, and do not
treat the absence of `/sys/bus/iio/devices/iio:device*` as sensor failure.

The working path is:

```text
ADSP / sensor_pd
-> FastRPC / QRTR
-> adsprpcd sensorspd
-> libssc
-> iio-sensor-proxy SSC backend
-> D-Bus: net.hadess.SensorProxy
```

`CONFIG_QCOM_SSC_BLOCK_BUS=y` only provides SSC/FastRPC/QMI communication. It
does not automatically register QMI sensors as kernel IIO devices. The Debian
user-space approach also reads SSC through `libssc` and exposes the result
through `iio-sensor-proxy`.

## Integration Points

`nixos/hardware/xiaomi-sheng/sensors/default.nix` integrates the user-space
sensor stack:

- packages `fastrpc`, `libssc`, `pd-mapper`, `qrtr`, and
  `sheng-sensors-file`
- builds `iio-sensor-proxy` with `-Dssc-support=enabled`
- starts `adsprpcd.service`
- starts `adsprpcd-sensorspd.service`
- marks the `fastrpc-adsp` udev device with
  `ssc-accel ssc-proximity ssc-light ssc-compass`
- sets `ACCEL_MOUNT_MATRIX` for the sheng landscape-native panel orientation
- waits for SSC to become queryable before starting `iio-sensor-proxy`

Upstream `iio-sensor-proxy` only enables `ssc-light ssc-compass` for
`fastrpc-adsp` by default. sheng needs explicit udev properties for
accelerometer and proximity support.

## Verified Result

`monitor-sensor` reports:

```text
=== Has accelerometer
=== Has proximity sensor
=== Has ambient light sensor
=== Has compass
```

Direct `ssccli` reads also work:

- `ssccli --sensor accelerometer`
- `ssccli --sensor magnetometer`
- `ssccli --sensor proximity`
- `ssccli --sensor light`

## Verification Commands

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

## Known Limitations

- `/sys/bus/iio/devices/iio:device*` remains empty. The current stack uses SSC
  user space and D-Bus instead of kernel IIO sysfs devices.
- Proximity may log `Failed to unpack Xiaomi Davinci proximity measurement
  message`, while `monitor-sensor --proximity` still reports FAR/near state.
- The gyroscope is not exposed as a separate `monitor-sensor` capability yet.
  Compass data currently comes through the SSC rotation-vector / magnetometer
  path, and the accelerometer is enough for display orientation.
- `sheng-devauth.service` currently fails when `/dev/nanosic_auth` is missing.
  That service is for keyboard/stylus authentication and is not required for
  the current sensor path.

## Troubleshooting

If `iio-sensor-proxy` exits with:

```text
No sensors or missing kernel drivers for the sensors. Exiting
```

Check these first:

1. `/dev/fastrpc-adsp` exists.
2. `adsprpcd-sensorspd.service` is running.
3. `ssccli --sensor light --timeout 5` can read data.
4. `fastrpc-adsp` udev properties include
   `ssc-accel ssc-proximity ssc-light ssc-compass`.
5. `/usr/share/qcom/sm8550/Xiaomi/sheng` and `/vendor/etc/sensors`
   registry/config files exist.

## Future Work

The recommended status is "user-space working". If strict kernel IIO sysfs
support becomes necessary, track it as a separate task:

- investigate reusable QMI/SSC-to-IIO kernel bridge drivers
- decide whether a sheng-specific kernel IIO bridge is worth writing
- expose the gyroscope as a separate upper-layer capability
- improve `libssc` decoding for the Xiaomi Davinci proximity payload

These are enhancements and do not block current desktop sensor use.
