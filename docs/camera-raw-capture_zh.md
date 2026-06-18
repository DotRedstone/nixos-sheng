# Sheng 相机 RAW 抓取

[English](camera-raw-capture.md) | [简体中文](camera-raw-capture_zh.md)

sheng 的相机传感器和 Qualcomm CAMSS 管线已经可以在没有完整用户态相机栈的
情况下抓取 RAW 帧。

已验证传感器：

- 后摄 Samsung S5KJN1：`4080x3060` packed RAW10
- 前摄 OmniVision OV32D40：`3264x2448` packed RAW10

这验证了 sensor、CSI PHY、CSID、VFE 和 V4L2 capture 路径。它不提供自动曝光、
白平衡、降噪、JPEG 输出或桌面相机应用；这些仍需要合适的 libcamera pipeline
和用户态集成。

## 后摄

```sh
media-ctl -r
media-ctl -l '"msm_csiphy3":1 -> "msm_csid3":0 [1]'
media-ctl -l '"msm_csid3":1 -> "msm_vfe3_rdi0":0 [1]'

for pad in \
  '"s5kjn1 7-0010":0' \
  '"msm_csiphy3":0' '"msm_csiphy3":1' \
  '"msm_csid3":0' '"msm_csid3":1' \
  '"msm_vfe3_rdi0":0' '"msm_vfe3_rdi0":1'; do
  media-ctl -V "$pad [fmt:SGRBG10_1X10/4080x3060 field:none]"
done

v4l2-ctl -d /dev/v4l-subdev31 \
  --set-ctrl=exposure=3000,analogue_gain=1024
v4l2-ctl -d /dev/video9 \
  --set-fmt-video=width=4080,height=3060,pixelformat=pgAA
v4l2-ctl -d /dev/video9 \
  --stream-mmap=4 --stream-count=1 --stream-to=/tmp/s5kjn1.raw
```

预期帧大小：`15618240` 字节。

## 前摄

```sh
media-ctl -r
media-ctl -l '"msm_csiphy4":1 -> "msm_csid4":0 [1]'
media-ctl -l '"msm_csid4":1 -> "msm_vfe4_rdi0":0 [1]'

for pad in \
  '"ov32d40 9-0010":0' \
  '"msm_csiphy4":0' '"msm_csiphy4":1' \
  '"msm_csid4":0' '"msm_csid4":1' \
  '"msm_vfe4_rdi0":0' '"msm_vfe4_rdi0":1'; do
  media-ctl -V "$pad [fmt:SBGGR10_1X10/3264x2448 field:none]"
done

v4l2-ctl -d /dev/v4l-subdev30 \
  --set-ctrl=exposure=2500,analogue_gain=7936
v4l2-ctl -d /dev/video13 \
  --set-fmt-video=width=3264,height=2448,pixelformat=pBAA
v4l2-ctl -d /dev/video13 \
  --stream-mmap=4 --stream-count=1 --stream-to=/tmp/ov32d40.raw
```

预期帧大小：`9987840` 字节。

测试后重置可配置的 media link：

```sh
media-ctl -r
```
