# Xiaomi Pad 6S Pro 12.4 (sheng) Sensors 用户态适配方案

## 当前阶段目标
**当前阶段目标是复用 Debian 用户态 SSC 方案，使桌面环境可通过 D-Bus 读取传感器；不是实现内核 IIO sysfs 节点。**

## 硬件路线判断
sheng 设备的传感器（包含 accel, gyro, magnetometer, light, proximity）**并不是**作为普通的 I2C/SPI 设备暴露给 Linux 内核的。因此，**不要**在 DTS 中强行编造 `icm`、`qmc`、`stk` 等物理设备节点，也不要期望通过简单补充 DTS 就能在 `/sys/bus/iio/devices` 看到它们。

sheng 的传感器物理连接至 Qualcomm 的 ADSP/SLPI (Snapdragon Sensor Core, SSC) 中。内核负责底层通信，实际的数据读取需在用户态完成。

## 为什么 `/sys/bus/iio/devices` 为空不代表失败？
内核选项 `CONFIG_QCOM_SSC_BLOCK_BUS=y` 只启用了 FastRPC 和 QMI 通信总线，并没有内核级的“QMI 到 IIO sysfs”驱动。因此，即使底层已跑通，`/sys/bus/iio/devices` 内仍可能为空。
Debian 用户态方案通过 `libssc` 越过内核 IIO 层，直接通过 FastRPC 读取传感器，然后将其以 D-Bus 接口广播给桌面环境。该方案不会产生任何内核态的 `iio:device*` 节点。

## 组件关系
1. **`sensor_pd` / FastRPC**：内核提供底层通信管道，对外暴露 `/dev/fastrpc-*` 节点。
2. **`adsprpcd` (sensorspd)**：用户态守护进程，通过 FastRPC 激活并保持 ADSP 中的 Sensor Protection Domain 处于唤醒状态。
3. **`libssc`**：与底层 SSC 通信的用户态核心库。
4. **registry 文件**：从 Android 提取的专有配置文件，提供校准和硬件元数据。
5. **patched `iio-sensor-proxy`**：链接了 `libssc` 的代理程序，它从 `libssc` 取数据并最终输出为 D-Bus 信号（`org.freedesktop.SensorProxy`），供桌面环境使用。

## 桌面环境如何复用
GNOME、KDE 等现代桌面环境天然支持通过 D-Bus 监听 `org.freedesktop.SensorProxy` 获取屏幕翻转和亮度数据。因此，只要我们在系统中统一配置好上述底层服务，所有上层桌面均能开箱即用，无需各自实现 QMI 解析。

## 成功验证标准
此方案的成功标志如下：
1. `adsprpcd-sensorspd.service` 与 `iio-sensor-proxy` 正常 running。
2. 运行 `busctl tree org.freedesktop.SensorProxy` 能看到相关 D-Bus 路径。
3. 运行 `monitor-sensor` 能读到方位 (orientation)、加速度 (accelerometer) 或光线 (light) 数据。

## 关键依赖（踩坑记录）
DSP 内的 `sensor_pd` 在启动时必须能读取以下文件，否则会默默崩溃且不会通过 QRTR 注册（导致 `qrtr-lookup 400` 为空）：
1. **校准数据与注册表**：位于 `/mnt/vendor/persist/sensors/registry/registry`。NixOS 必须开机静态挂载安卓的 `persist` 分区到该路径。
2. **硬件配置**：位于 `/vendor/etc/sensors/sns_reg_config`。由于 NixOS 是无状态系统，必须通过 `systemd.tmpfiles.rules` 将固件包内的 `/etc/sensors` 链接到 `/vendor/etc/sensors`。
3. **FastRPC DMA Memory Mapping (flags=0)**：Android 的 `fastrpc` 驱动允许用户态库发送 `flags=0` 的内存映射请求，但在上游主线内核 (Mainline Linux) 中，`flags=0` 被视为非法参数并返回 `EINVAL`，导致 DSP 无法映射共享内存，RPC 调用直接崩溃。NixOS 中必须修补 `fastrpc` 用户态库，将 `flags=0` 强制转换为 `0x1000 (ADSP_MMAP_ADD_PAGES)`。

## 失败排查步骤
1. **检查 FastRPC 节点**：`ls -la /dev/fastrpc*` 是否存在。若无，检查内核 `CONFIG_QCOM_SSC_BLOCK_BUS` 与设备树。
2. **检查 PDR**：`dmesg | grep -i pdr` 确认 `sensor_pd` 是否已注册。
3. **检查 adsprpcd 服务**：`systemctl status adsprpcd-sensorspd` 确保没有报错。
4. **检查 iio-sensor-proxy**：`journalctl -u iio-sensor-proxy` 是否报错。如果是 "No sensors or missing kernel drivers"，说明 `libssc` 没有探测到传感器，可能是 registry 缺失或未打通 fastrpc 权限。
