# Sheng camera RAW capture

The sheng camera sensors and Qualcomm CAMSS pipeline can capture RAW frames
without a userspace camera stack.

Verified sensors:

- Rear Samsung S5KJN1: `4080x3060` packed RAW10
- Front OmniVision OV32D40: `3264x2448` packed RAW10

This verifies the sensor, CSI PHY, CSID, VFE, and V4L2 capture path. It does
not provide automatic exposure, white balance, denoising, JPEG output, or a
desktop camera application. Those require a suitable libcamera pipeline and
userspace integration.

## Rear camera

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

Expected frame size: `15618240` bytes.

## Front camera

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

Expected frame size: `9987840` bytes.

Reset configurable media links after testing:

```sh
media-ctl -r
```
