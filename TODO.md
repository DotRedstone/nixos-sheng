# TODO

本文件用于跟踪 Xiaomi Pad 6S Pro 12.4（xiaomi-sheng）在本仓库 NixOS 移植侧的硬件对齐进度。

目标不是开发全新驱动，而是优先对齐 postmarketOS wiki 中已经标记为可用或部分可用的硬件功能。
未适配或明确需要新驱动/用户态库的项目，当前阶段只记录，不作为主线目标。

## 状态图例

* [x] 已在 NixOS 侧验证可用
* [ ] 待修复 / 待对齐
* [~] 部分可用 / 待补验证
* [-] 当前阶段暂不处理

## 当前已验证基础状态

### Boot / rootfs / NixOS 基础

* [x] 系统可启动进入 NixOS
* [x] rootfs 可写
* [x] `/run/current-system` 存在
* [x] `/nix/var/nix/profiles/system` 存在
* [x] `nix` 可用
* [x] `nixos-rebuild` 可用
* [x] `systemctl` 可用
* [x] flake 与 Home Manager 基础配置已集成
* [x] Home Manager 独立环境与 `hms` (standalone switch) 别名已集成，并在云端构建工作流中成功验证，彻底打通系统级与应用级的配置隔离。
* [x] `systemd-timesyncd` 已启用并实机确认时间同步
* [~] `linux` 分区约 77.7GiB，但当前 ext4 文件系统约 10GiB；在线扩容失败，
  需要在 TWRP/救援环境中离线执行 `e2fsck` 与 `resize2fs`
* [x] `nixosConfigurations.sheng` 已与 GNOME Mobile NixOS rootfs 共用同一求值，并通过 Actions 构建验证
* [x] 纯 flake stage-2 profile rollback 与 `switch-to-configuration switch` 已实机验证
* [~] 开机世代菜单、音量选择和电源确认已实机验证；当前仅有一个真实 system
  generation，仍待扩容后验证跨世代选择与回滚
* [~] `nixos-rebuild --flake` 仅更新 stage-2 系统世代；涉及 kernel、DTS、stage-1 initrd 或 boot cmdline 时仍需另外生成并刷写 `boot_b`
* [ ] 发布前补充并验证 `nixos/flake.lock`，避免设备端求值重复下载大型 inputs

### GNOME desktop

* [x] GDM 登录界面：为 greeter 单独启用原生屏幕键盘和密码登录已通过实机验证
* [x] 精简 GNOME profile 可启动，GDM 与 GNOME Shell 正常运行
* [x] 已集成 GJS OSK，并启用拖动与触摸输入自动弹出配置
* [x] 默认终端已强制设定为 `gnome-console` (kgx)
* [x] 加速度计 mount matrix 已按横屏原生方向修正
* [~] 悬浮软键盘在不同应用中的自动弹出行为仍需长期使用验证
* [~] 自动旋转方向已修正配置，仍需验证四个方向和旋转后的触摸坐标

### Firmware / remoteproc

* [x] `sheng-firmware` 已进入 `/lib/firmware`
* [x] ADSP remoteproc 可启动
* [x] CDSP remoteproc 可启动
* [x] GPU firmware 可加载
* [x] `msm/adsp/charger_pd` 可通过 PDR 通知
* [x] `ucsi_glink` 可注册 Type-C

## 按 postmarketOS 已适配项对齐

### SoC

postmarketOS 状态：Y
型号：Qualcomm SM8550P-AB / Snapdragon 8 Gen 2

* [x] NixOS 可启动
* [x] 基础设备树与 kernel 可用
* [x] ADSP/CDSP remoteproc 可启动

验证命令：

```sh
uname -a
cat /proc/cmdline
dmesg | grep -Ei 'sm8550|soc|remoteproc|adsp|cdsp' | tail -200
```

### Power button

postmarketOS 状态：Y
型号：Qualcomm PMK8550 PWRKEY

* [x] `pmic_pwrkey` input 设备存在
* [x] 实体电源键息屏与唤醒已通过自研 `sheng-power-key-display-toggle` 脚本完美验证

验证命令：

```sh
cat /proc/bus/input/devices
dmesg | grep -Ei 'pwrkey|pmic_pwrkey|input|wakeup' | tail -200
```

### Volume down

postmarketOS 状态：Y
型号：Qualcomm PMK8550 RESIN

* [x] `pmic_resin` input 设备存在
* [~] 需要人工按键事件验证

验证命令：

```sh
cat /proc/bus/input/devices
dmesg | grep -Ei 'resin|volume|gpio-keys|input' | tail -200
```

### Volume up

postmarketOS 状态：Y
型号：GPIO6

* [x] `gpio-keys` input 设备存在
* [~] 需要人工确认是否对应音量上键

验证命令：

```sh
cat /proc/bus/input/devices
dmesg | grep -Ei 'volume|gpio-keys|input' | tail -200
```

### Display

postmarketOS 状态：Y
型号：Tianma panel
备注：GNOME 下 Night Light 不可用；144Hz 因 DPU mode clock 相关提交暂不可用。

* [x] DRM 节点存在：`/dev/dri/card0`
* [x] Render 节点存在：`/dev/dri/renderD128`
* [x] DSI connector 存在：`card0-DSI-1`
* [x] DPU / DSI / panel 基础链路可用
* [x] DRM connector 报告 `3048x2032` 显示模式
* [~] 仍需补充实际刷新率、144Hz、Night Light 与亮度调节实测记录

验证命令：

```sh
ls -la /dev/dri
find /sys/class/drm -maxdepth 2 -type l -o -type d 2>/dev/null | sort
dmesg | grep -Ei 'drm|dpu|panel|dsi|display|mode|refresh' | tail -300
```

### TDDI / Touchscreen

postmarketOS 状态：Y
型号：Novatek NT36532E

* [x] `NVTCapacitiveTouchScreen` input 设备存在
* [x] `libinput list-devices` 识别为 touch 设备
* [x] `CONFIG_TOUCHSCREEN_NT36532E_SPI=m` 对应模块可加载
* [x] 已补入 `novatek/novatek_nt36532e_fw.bin`
* [x] 实机 `evtest` 已验证点击、滑动、坐标、压力和触摸面积事件
* [~] 仍需验证多点触控和旋转后的坐标方向

备注：触摸驱动跟随 DRM panel suspend/resume。minimal 环境中面板休眠后
`evtest` 不会收到事件；唤醒或重启 `kmsconvt@tty1.service` 后可继续验证。

验证命令：

```sh
cat /proc/bus/input/devices
ls -la /dev/input

find /lib/modules -type f 2>/dev/null \
  | grep -Ei 'nt36532|novatek|touch' \
  | sort

dmesg | grep -Ei 'touch|novatek|nt36532|input|i2c|spi|tddi' | tail -300
evtest /dev/input/event3
```

### Backlight

postmarketOS 状态：Y
型号：Kinetic KTZ8866
备注：Two chips powering 10 LEDs.

* [x] `ktz8866-backlight` 节点存在
* [x] `brightness` / `max_brightness` / `actual_brightness` 可读
* [~] 需要人工验证亮度调节是否实际生效

验证命令：

```sh
ls -la /sys/class/backlight
for b in /sys/class/backlight/*; do
  echo "--- $b ---"
  cat "$b/brightness" 2>/dev/null
  cat "$b/max_brightness" 2>/dev/null
  cat "$b/actual_brightness" 2>/dev/null
done
dmesg | grep -Ei 'backlight|ktz8866|brightness|led' | tail -200
```

### GPU / 3D

postmarketOS 状态：Y
型号：Adreno 740

* [x] `/dev/dri/card0` 存在
* [x] `/dev/dri/renderD128` 存在
* [x] `qcom/a740_sqe.fw` 可加载
* [x] `qcom/gmu_gen70200.bin` 可加载
* [x] GMU firmware 已加载
* [~] 需要补充 Mesa / OpenGL / Vulkan 或 Wayland compositor 实测

验证命令：

```sh
ls -la /dev/dri
dmesg | grep -Ei 'drm|gpu|adreno|a740|gmu|mesa|firmware' | tail -300
```

### UFS internal storage

postmarketOS 状态：Y
型号：Micron UFS 4.0

* [x] Linux rootfs 可从 UFS 分区启动
* [x] `/` 可写
* [x] dmesg 可见 Micron UFS 设备
* [~] 需要补充分区布局与扩容流程记录

验证命令：

```sh
lsblk
mount | grep ' / '
df -h /
dmesg | grep -Ei 'ufs|ufshc|sda|micron|lun|block' | tail -300
```

### Main camera

postmarketOS 状态：Y
型号：Samsung S5KJN1
备注：相较 Android 画质降低；8K 模式使用 Quad Bayer，目前 libcamera 支持情况未知。

* [x] `/dev/media0` 与 `/dev/video0` 至 `/dev/video16` 已出现
* [x] `qcom-camss` media graph 已出现
* [x] `s5kjn1 7-0010` 已注册并连接到 `msm_csiphy3`
* [x] `CONFIG_VIDEO_S5KJN1_SHENG=m` 与 QCOM CAMSS 模块已进入 rootfs 并加载
* [x] 已通过 CAMSS/V4L2 管线抓取 `4080x3060` packed RAW10 实际画面
* [~] 尚无 libcamera 相机应用、自动曝光、白平衡、降噪与 JPEG 输出
* [-] 仅对齐 postmarketOS 已有状态，不开发画质增强或 8K 支持

验证命令：

```sh
ls -la /dev/video* /dev/media* 2>/dev/null
media-ctl -p 2>/dev/null || true

find /lib/modules -type f 2>/dev/null \
  | grep -Ei 's5kjn1|camss|video|media' \
  | sort

dmesg | grep -Ei 'camera|camss|s5kjn1|cci|csi|csiphy|media|video' | tail -350
```

### Front camera

postmarketOS 状态：Y
型号：OmniVision OV32D40
备注：相较 Android 画质降低。

* [x] `ov32d40 9-0010` 已注册并连接到 `msm_csiphy4`
* [x] `CONFIG_VIDEO_OV32D40=m` 模块已进入 rootfs 并加载
* [x] 已通过 CAMSS/V4L2 管线抓取 `3264x2448` packed RAW10 实际画面
* [~] 尚无 libcamera 相机应用、自动曝光、白平衡、降噪与 JPEG 输出
* [-] 仅对齐 postmarketOS 已有状态，不开发画质增强

验证命令：

```sh
ls -la /dev/video* /dev/media* 2>/dev/null
media-ctl -p 2>/dev/null || true

find /lib/modules -type f 2>/dev/null \
  | grep -Ei 'ov32d40|camss|video|media' \
  | sort

dmesg | grep -Ei 'ov32d40|camera|camss|cci|csi|csiphy|media|video' | tail -350
```

### Camera flash

postmarketOS 状态：Y
型号：Qualcomm PM8550B supply

* [x] `/sys/class/leds/white:flash-0` 节点已出现
* [~] 当前未验证 camera flash 实际点亮
* [-] 暂不做相机补光实测主线

验证命令：

```sh
ls -la /sys/class/leds 2>/dev/null
dmesg | grep -Ei 'flash|led|pm8550|camera' | tail -200
```

### RGB LED

postmarketOS 状态：Y
型号：Qualcomm PM8550B PWM

* [x] `/sys/class/leds/rgb:status` 节点已出现
* [~] 需要人工验证颜色、亮度和触发器行为

验证命令：

```sh
ls -la /sys/class/leds 2>/dev/null
dmesg | grep -Ei 'led|rgb|pwm|pm8550' | tail -200
```

### Audio codec

postmarketOS 状态：Y
型号：Qualcomm WCD9380
备注：用于麦克风和 Type-C 模拟音频输出。

* [x] ALSA 声卡 `Xiaomi-Pad6SPro` 已注册
* [x] `aplay -l` 可看到两个 playback PCM，`arecord -l` 可看到一个 capture PCM
* [x] QDSP6 / WCD9380 / SoundWire 模块已进入 rootfs 并加载
* [~] PipeWire 输出、Type-C 模拟音频和实际播放/录音仍需验证

验证命令：

```sh
aplay -l 2>/dev/null || true
arecord -l 2>/dev/null || true
pactl list short sinks 2>/dev/null || true
pactl list short sources 2>/dev/null || true
cat /proc/asound/cards 2>/dev/null || true

find /lib/modules -type f 2>/dev/null \
  | grep -Ei 'wcd938|qdsp6|soundwire|snd|lpass|wsa|cs35' \
  | sort

dmesg | grep -Ei 'wcd9380|sound|audio|alsa|asoc|apr|gpr|mic|type-c|snd|soundwire|lpass' | tail -350
```

### Amplifier

postmarketOS 状态：Y
型号：Cirrus CS35L43
备注：6 个扬声器各一个。

* [x] `CONFIG_SND_SOC_CS35L43=m` 与 I2C 模块已进入 rootfs
* [x] `snd_soc_cs35l43_i2c` 已加载并绑定 6 个放大器
* [~] 仍需实际播放验证 6 个扬声器与音量控制

验证命令：

```sh
find /lib/modules -type f 2>/dev/null \
  | grep -Ei 'cs35l43|snd|sound' \
  | sort

dmesg | grep -Ei 'cs35l43|speaker|amp|sound|audio|asoc|snd' | tail -350
```

### Speaker

postmarketOS 状态：Y
备注：PulseAudio 下可能有轻微 crackling；PipeWire 下应更正常。

* [x] ALSA playback PCM 已枚举
* [~] 当前未验证扬声器实际播放、音量控制和 crackling 情况

验证命令：

```sh
pactl list short sinks 2>/dev/null || true
aplay -l 2>/dev/null || true
dmesg | grep -Ei 'speaker|pipewire|pulse|sound|audio|cs35' | tail -250
```

### Microphones

postmarketOS 状态：Y
备注：4 个麦克风，mainline 可用 stereo configuration。

* [x] ALSA capture PCM 已枚举
* [~] 当前未验证麦克风实际录音与声道映射

验证命令：

```sh
arecord -l 2>/dev/null || true
pactl list short sources 2>/dev/null || true
dmesg | grep -Ei 'mic|microphone|wcd9380|sound|audio|snd' | tail -250
```

### Wi-Fi

postmarketOS 状态：Y
型号：Qualcomm WCN7851

当前 NixOS 状态：

* [x] `wlp1s0` 与 P2P interface 已出现
* [x] NetworkManager 可扫描并连接 Wi-Fi
* [x] PCIe Root Port 与 WCN7850 endpoint 可枚举：`0000:01:00.0 [17cb:1107]`
* [x] `ath12k_wifi7` / `ath12k` / `mhi` / `cfg80211` / `mac80211` 模块已加载
* [x] WCN7850 firmware 已进入 rootfs，`ath12k_wifi7_pci` probe 成功
* [x] 中国监管域已生效，5GHz 信道 36–64 与 149–165 可用
* [x] 更新 WCN7850 `board-2.bin` 后，5GHz 定向扫描与 NetworkManager 连接已实机验证
* [x] 已连接 `5200 MHz` / 信道 40 / `80 MHz` AP，链路速率为 `1200.9 MBit/s`
* [x] 当前候选版本重新连接 `5180 MHz` / 信道 36 / `80 MHz` AP，收发链路约
  `960.7/1080.6 MBit/s`，联网正常
* [x] 将 `p2p-dev-wlp1s0` 排除出 NetworkManager 管理后，Wi-Fi off/on 不再导致
  5GHz 扫描结果全部消失
* [~] 当前为保持普通 Wi-Fi 扫描稳定，暂不支持 Wi-Fi Direct / P2P
* [~] 当前 ath12k 下定向 `iw scan freq` 不应作为唯一健康判据
* [~] 当前 6GHz 信道仍被禁用，尚未验证 6GHz

验证命令：

```sh
ip link
iw dev 2>/dev/null || true
rfkill list 2>/dev/null || true
nmcli device 2>/dev/null || true

find /lib/modules -type f 2>/dev/null \
  | grep -Ei 'ath12k|ath11k|mhi|qmi|qrtr|wlan' \
  | head -100

find /lib/firmware /usr/lib/firmware -maxdepth 10 -type f 2>/dev/null \
  | grep -Ei 'ath12k|WCN7850|WCN7851|board-2|amss|m3|qca|wlan|wifi' \
  | head -100

ls -la /sys/bus/pci/devices
find /sys/bus/platform/devices -maxdepth 1 -type l 2>/dev/null \
  | grep -Ei 'wifi|wlan|mhi|pci|pcie'

dmesg | grep -Ei 'ath12k|ath11k|wcn|wlan|wifi|mhi|pci|pcie|qmi|qrtr|firmware' | tail -350
```

### Bluetooth

postmarketOS 状态：Y
型号：Qualcomm WCN7851
备注：systemd 下可用，OpenRC 下不可用。systemd 是默认 init system。

当前 NixOS 状态：

* [x] `hci0` 已出现，rfkill 未阻止蓝牙
* [x] `bluetooth.service` 正常运行
* [x] `bluetoothctl show` 可看到已上电控制器 `nixos-sheng`
* [x] qca bluetooth firmware 存在
* [x] `hci_uart` / `btqca` / Bluetooth 核心模块已加载
* [~] 尚未实测扫描、配对、重连、BLE 与蓝牙音频

验证命令：

```sh
rfkill list 2>/dev/null || true
bluetoothctl list 2>/dev/null || true
hciconfig -a 2>/dev/null || true
systemctl --no-pager --full status bluetooth 2>/dev/null | head -100 || true

find /lib/modules -type f 2>/dev/null \
  | grep -Ei 'btqca|bluetooth|hci|qca' \
  | sort

dmesg | grep -Ei 'bluetooth|bt|hci|qca|btqca|uart|serdev|firmware|rfkill' | tail -250
```

### Sixaxis / IMU

postmarketOS 状态：Y
型号：InvenSense ICM42607P

* [x] 加速度计已通过 SSC + `iio-sensor-proxy` 用户态路径验证可用
* [x] `monitor-sensor --accel` 可看到 accelerometer/orientation/tilt
* [x] `ssccli --sensor accelerometer` 可读取实时三轴数据
* [ ] 陀螺仪尚未作为单独上层能力暴露，后续需要确认 `libssc` / `iio-sensor-proxy` 是否支持
* [~] `/sys/bus/iio/devices` 下仍无 `iio:device*`；当前方案不走 kernel IIO sysfs
* [-] 暂不编造 ICM42607P DTS 节点，除非后续确认存在 AP 侧直连路径

验证命令：

```sh
monitor-sensor --accel
ssccli --sensor accelerometer --timeout 5
journalctl -b -u adsprpcd-sensorspd -u iio-sensor-proxy --no-pager -o short-monotonic | tail -200
```

### Hall sensor

postmarketOS 状态：Y

* [x] `gpio-keys` input 设备存在
* [~] input 设备中出现 `SW=1`，疑似 Hall/LID switch
* [ ] 需要人工磁吸/键盘盖状态变化验证

验证命令：

```sh
cat /proc/bus/input/devices
dmesg | grep -Ei 'hall|lid|SW_LID|gpio-keys|input' | tail -200
```

### Magnetometer

postmarketOS 状态：Y
型号：QST QMC6308

* [x] 指南针已通过 SSC + `iio-sensor-proxy` 用户态路径验证可用
* [x] `monitor-sensor --compass` 可看到 heading 变化
* [x] `ssccli --sensor magnetometer` 可读取磁力计数据
* [~] `/sys/bus/iio/devices` 下仍无 `iio:device*`；当前方案不走 kernel IIO sysfs
* [-] 暂不编造 QMC6308 DTS 节点，除非后续确认存在 AP 侧直连路径

验证命令：

```sh
monitor-sensor --compass
ssccli --sensor magnetometer --timeout 5
journalctl -b -u adsprpcd-sensorspd -u iio-sensor-proxy --no-pager -o short-monotonic | tail -200
```

### RGB Light & IR Proximity

postmarketOS 状态：Y
型号：Sensortek STK36C61-A
备注：作为 light sensor 暴露，而不是 AMS TSL2522。

* [x] 光感已通过 SSC + `iio-sensor-proxy` 用户态路径验证可用
* [x] 距离传感器已通过 SSC + `iio-sensor-proxy` 用户态路径验证可用
* [x] `monitor-sensor --light` 可看到 ambient light
* [x] `monitor-sensor --proximity` 可看到 proximity 状态
* [x] `ssccli --sensor light` 可读取 lux
* [x] `ssccli --sensor proximity` 可读取 FAR/near 状态
* [~] proximity 当前会出现 `Failed to unpack Xiaomi Davinci proximity measurement message` 日志，但不影响基本 FAR/near 状态
* [~] `/sys/bus/iio/devices` 下仍无 `iio:device*`；当前方案不走 kernel IIO sysfs
* [-] 不按 AMS TSL2522 处理；当前有效路线是 Sensortek/SSC

验证命令：

```sh
monitor-sensor --light
monitor-sensor --proximity
ssccli --sensor light --timeout 5
ssccli --sensor proximity --timeout 5
journalctl -b -u adsprpcd-sensorspd -u iio-sensor-proxy --no-pager -o short-monotonic | tail -200
```

### Battery

postmarketOS 状态：Y
型号：ATL BP50
备注：Two batteries connected in parallel.

* [x] `qcom-battmgr-bat` power_supply 节点存在
* [x] 电池容量可读
* [x] 充电状态可读
* [x] 电压/电流字段可读
* [~] 需要长期验证容量、充放电曲线、双电池合并行为

验证命令：

```sh
ls -la /sys/class/power_supply
for p in /sys/class/power_supply/*; do
  echo "--- $p ---"
  for f in type status capacity present voltage_now current_now charge_now charge_full energy_now energy_full; do
    [ -e "$p/$f" ] && printf '%s=' "$f" && cat "$p/$f" 2>/dev/null
  done
done
dmesg | grep -Ei 'battery|batt|qcom-battmgr|power_supply|pmic_glink' | tail -300
```

### Fuel gauge

postmarketOS 状态：Y
型号：Texas Instruments BQ27Z561
备注：两个 gauge/battery 由 ADSP 报告为一个 battery。

* [x] fuel gauge 信息通过 `qcom-battmgr-bat` 暴露
* [x] capacity/status/current/voltage 字段可读
* [~] 需要长期验证数据准确性

验证命令同 Battery。

### Charger

postmarketOS 状态：Y
型号：Qualcomm PM8550B and Southchip SC8581
备注：MiPPS 认证已实机成功，原装 120W 充电器可报告 `apdo_max=120`、`power_max=120`，并进入 `fastchg_mode=1`；持续实际输入功率仍需外置功率计和温度测试验证。

* [x] charger_pd 主链路已修复
* [x] USB-C / Type-C 主链路已修复
* [x] `qcom-battmgr-usb` 节点存在
* [x] UCSI source power_supply 节点存在
* [x] 当前可读取 USB online、电压、电流、usb_type
* [x] MiPPS 用户态认证成功，`authentic=1`、`slave_authentic=1`、`pd_verifed=1`
* [~] 需要验证不同充电器下 PD 3.0 协商、电压、电流
* [~] 需要使用外置功率计验证实际输入功率，并长期观察电池与接口温度

验证命令：

```sh
ls -la /sys/class/power_supply
for p in /sys/class/power_supply/*; do
  echo "--- $p ---"
  for f in type status online voltage_now current_now usb_type; do
    [ -e "$p/$f" ] && printf '%s=' "$f" && cat "$p/$f" 2>/dev/null
  done
done
dmesg | grep -Ei 'charger|charging|pd|pdo|typec|ucsi|qcom-battmgr|pmic_glink' | tail -300
```

### USB / OTG

postmarketOS 状态：Y

* [x] Type-C / UCSI 注册成功
* [x] USB role switch 存在
* [x] USB Host / xHCI 可启动
* [x] USB Hub 可枚举
* [x] USB 鼠标可枚举
* [x] USB 键盘可枚举
* [ ] 待验证：U 盘、ADB device 模式

验证命令：

```sh
lsusb
dmesg | grep -Ei 'usb|xhci|hub|mouse|keyboard|ucsi|typec|role' | tail -300
```

### Keyboard

postmarketOS 状态：Y
型号：Xiaomi Pad 6S Pro 12.4 Touchpad Keyboard

* [ ] 当前未看到外接键盘 input 设备
* [ ] 当前未看到 Nanosic/HID accessory 设备
* [ ] 需要连接官方键盘后重新验证
* [x] `CONFIG_HID_NANOSIC_WN8030=m` 已启用，`hid_nanosic_wn8030` 模块已进入 rootfs 并加载

验证命令：

```sh
cat /proc/bus/input/devices
ls -la /dev/input

find /lib/modules -type f 2>/dev/null \
  | grep -Ei 'nanosic|hid' \
  | sort

dmesg | grep -Ei 'keyboard|nanosic|hid|input|i2c|pogo|accessory|cover' | tail -300
```

### Touchpad

postmarketOS 状态：Y
型号：Xiaomi Pad 6S Pro 12.4 Touchpad Keyboard

* [ ] 当前未看到触摸板 input 设备
* [ ] 需要连接官方键盘后重新验证
* [x] Nanosic/HID 模块已进入 rootfs 并加载

验证命令：

```sh
cat /proc/bus/input/devices
libinput list-devices 2>/dev/null || true
dmesg | grep -Ei 'touchpad|nanosic|hid|input|i2c|pogo|accessory|cover' | tail -300
```

## postmarketOS 标记为部分/未知的项目

### Depth camera

postmarketOS 状态：?
型号：OmniVision OV02B1B
备注：libcamera 不支持 10-bit Grayscale。

* [x] `ov02b1b 8-003c` 已注册并连接到 `msm_csiphy1`
* [~] 尚未验证 depth camera 实际画面与 10-bit Grayscale 用户态支持
* [-] 暂不开发 libcamera 10-bit Grayscale 支持

### NFC

postmarketOS 状态：?
型号：NXP NTA5332

* [~] 当前阶段仅记录
* [-] 暂不作为主线目标，除非 NixOS 侧已自然出现设备节点

### SAR

postmarketOS 状态：?
型号：Semtech SX9371

* [~] 当前阶段仅记录
* [-] 暂不作为主线目标

### Pen wireless charger

postmarketOS 状态：?
型号：Southchip SC9625

* [~] 当前阶段仅记录
* [-] 暂不作为主线目标

## postmarketOS 标记为不可用的项目

### Stylus

postmarketOS 状态：N
型号：Xiaomi Focus Pen
备注：需要驱动；Novatek touchscreen driver 可能提供 stylus data。

* [-] 当前阶段不开发新驱动
* [-] 不作为 NixOS 对齐目标

### Fingerprint

postmarketOS 状态：N
型号：Fingerprint Cards AB FPC1553 / Goodix
备注：基于逆向分析，指纹图像采集依赖 Qualcomm TEE / TrustZone 加密隔离，当前主线 Linux 无解密方案，无法使用 `libfprint`。

* [-] 当前无解，永久搁置
* [-] 不开发用户态指纹库

### Light sensor

postmarketOS 状态：N
型号：AMS TSL2522

* [-] 当前阶段不处理
* [-] wiki 说明 RGB Light & IR Proximity 以 light sensor 形式暴露，优先验证 STK36C61-A

## 当前优先级

### P0：已枚举但需要实机功能验证

* [x] USB-C / OTG：Hub、键盘、鼠标已验证；待验证 U 盘、ADB device 模式
* [x] Sensors：加速度计、距离传感器、光感、指南针已通过 SSC + `iio-sensor-proxy` 验证
* [x] Touchscreen：固件加载、input/libinput、点击、滑动和坐标事件已实机验证
* [x] GNOME：桌面、悬浮软键盘和旋转配置已集成；电源键息屏唤醒已完全验证；待长期验证四向旋转与触摸坐标
* [~] Bluetooth：控制器、服务和扫描发现已验证；待验证配配对、重连、BLE 和蓝牙音频
* [~] Audio：声卡与 playback/capture PCM 已枚举；待验证扬声器、麦克风和 Type-C 音频
* [~] Camera：当前候选版本已重新验证前后摄 RAW10 实际抓帧；待完善 libcamera 与桌面相机应用
* [~] Display：3048x2032 已确认；待验证刷新率、144Hz、Night Light、背光调节
* [x] Power / volume buttons：实体键事件、开机世代菜单选择及日常息屏已验证
* [ ] Battery / charger：不同充电器下电压、电流、PD 状态

### P1：尚未完成的硬件功能

* [x] Wi-Fi：2.4GHz 与 5GHz 扫描、连接和联网已验证
* [ ] Keyboard / Touchpad：连接官方键盘后检查 Nanosic/HID
* [~] RGB LED：节点已出现，待验证颜色与触发器
* [~] Camera flash：节点已出现，待验证实际点亮

### P2：postmarketOS 已工作但需要更多用户态验证的项目

* [ ] Hall sensor
* [~] Sensors：SSC 用户态链路可用；严格 kernel IIO 验收仍未通过，需实现
  `iio:device*`、单独 gyroscope 暴露，并完善 proximity Davinci payload 解包

### 暂不处理

* [-] Stylus
* [-] Fingerprint
* [-] AMS TSL2522 light sensor
* [-] NFC
* [-] SAR
* [-] Pen wireless charger

## 下一步建议

### 已完成 P0：Touchscreen

验证结果：

* rootfs 已包含 `/lib/firmware/novatek/novatek_nt36532e_fw.bin`。
* `NVT-ts-spi` 可完成固件更新并注册 `NVTCapacitiveTouchScreen`。
* 面板唤醒后，`evtest` 已捕获连续 X/Y、压力和触摸面积事件。
* minimal 环境中触摸会跟随 DRM panel 正常 suspend；这不是驱动故障。
* 系统 suspend 当前仍会在冻结任务时超时；已让 logind 忽略短按电源键，
  避免 GDM 登录界面触发约 40 秒的假死。真正的 suspend/resume 仍待修复。
* GNOME 会话中短按电源键仅切换 Mutter 显示电源，不再 suspend 或锁定会话。

剩余验证：

1. 多点触控
2. 屏幕旋转后的坐标方向

### 已完成 P1：Wi-Fi

理由：

* postmarketOS 标记为可用，说明硬件链路理论上已有参考实现。
* Wi-Fi 是后续图形桌面、包管理、远程调试和日用测试的基础能力。
* PCIe endpoint、ath12k、MHI 与 firmware 均正常。
* 5GHz 阻塞来自旧 `board-2.bin` 不包含 sheng 请求的 `subsystem-device=1107,qmi-board-id=255` 匹配项。
* 更新板级数据库后，5GHz 定向扫描不再触发 `received scan start failure event`，并已完成连接与联网验证。

建议检查顺序：

1. `ip link` / `iw dev` / `rfkill list`
2. `/lib/firmware/ath12k/WCN7850/hw2.0/amss.bin` 是否存在
3. WCN7850/WCN7851 firmware、board-2 文件是否进入 rootfs
4. MHI 是否能从 firmware load failure 进入正常状态
5. 修复后 NetworkManager 是否能扫描与连接

### 建议下一步：Audio / Bluetooth / Camera 实测

理由：

* Audio 已有 ALSA 声卡与 playback/capture PCM，优先验证实际播放、录音、PipeWire 路由和 Type-C 音频。
* Bluetooth 控制器和服务已正常运行，下一步直接验证扫描、配对、重连、BLE 和蓝牙音频。
* 前后摄 RAW10 实际画面已抓取，下一步完善 libcamera pipeline、自动曝光和桌面相机应用。

### 仍未完成的主要项目

1. 官方键盘与触摸板实机验证
2. 扬声器、麦克风、Type-C 音频与蓝牙音频实测
3. 相机 libcamera/桌面应用、camera flash 与 RGB LED 实测
4. 显示刷新率、144Hz、Night Light 与背光调节实测
5. 电源键、音量键、Hall sensor、U 盘与 ADB device 模式实测
6. 充电功率长期测试、不同充电器兼容性与温度观察
7. 6GHz Wi-Fi、独立 gyroscope 等增强；kernel IIO sysfs bridge 仍是严格 IIO 验收项

### Sensors 后续增强

当前传感器已通过 SSC 用户态链路供桌面使用，但严格 kernel IIO 验收尚未通过。
后续工作应单独开任务，避免与已工作的 SSC 链路混改：

* kernel IIO sysfs bridge（严格 IIO 验收与稳定发布前仍需解决）
* gyroscope 单独暴露
* proximity Xiaomi Davinci payload 解包
