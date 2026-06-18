# Sheng Firmware and USB-C / OTG Validation

[English](sheng-firmware-and-usbc.md) | [简体中文](sheng-firmware-and-usbc_zh.md)

This document records the firmware dependency chain required for USB-C,
Type-C, and OTG support on Xiaomi Pad 6S Pro (`sheng`), plus build, flashing,
and validation steps.

## Working Chain

USB-C host/OTG support is not decided by DWC3 or HID alone. The validated chain
is:

```text
sheng-firmware
  -> ADSP/CDSP remoteproc loads successfully
  -> msm/adsp/charger_pd service becomes UP through PDR
  -> ucsi_glink pd_running becomes 1
  -> ucsi_register() succeeds
  -> /sys/class/typec exposes a port
  -> usb_role can switch from device to host
  -> OTG hubs, keyboards, and mice enumerate
```

## Root Cause of the Original Failure

The earlier failure was not primarily caused by kernel config, DTS, UCSI,
FSA4480, PS5169, DWC3, or USB HID. The real problem was that the running system
did not contain the Qualcomm firmware files required by sheng.

Typical logs included:

```text
Direct firmware load for qcom/sm8550/sheng/adsp.mbn failed with error -2
Direct firmware load for qcom/sm8550/sheng/cdsp.mbn failed with error -2
Direct firmware load for qcom/a740_sqe.fw failed with error -2
UCSI/PD service never became running after 60 retries
```

An empty `/sys/class/typec` and a `usb_role` stuck at `device` are symptoms, not
the first cause. When ADSP/CDSP firmware does not load, `msm/adsp/charger_pd`
does not come up and `ucsi_glink` cannot register a Type-C port.

## Mobile NixOS RootFS Caveat

On ordinary NixOS, `hardware.firmware` usually participates in system firmware
assembly. Do not assume that it automatically appears in a Mobile NixOS
generated rootfs.

This project's Mobile NixOS rootfs uses custom `populateCommands` and
`lib.mkForce`. That override bypasses parts of the usual rootfs assembly path,
so `sheng-firmware` must be explicitly injected into `/lib/firmware` in the
final image. Stage-1 also needs the same firmware through
`mobile.boot.stage-1.firmware`.

Whenever firmware is added or adjusted, verify the final `rootfs.img` contents.
Do not rely only on the Nix expression.

## Build and Flash

Common build commands:

```bash
nix flake lock ./nixos
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
```

Flash both the boot image and rootfs:

```bash
fastboot flash boot_b out/mobile-bootimg
fastboot flash linux out/mobile-rootfs/rootfs.img
fastboot reboot
```

Notes:

- Kernel, initrd, or DTB-only changes may require only `boot_b`.
- Firmware, rootfs, packages, systemd units, users, and other userland changes
  require flashing the `linux` rootfs partition.
- Do not flash `userdata`.
- Flashing only `boot_b` does not update `/lib/firmware`.

## Offline RootFS Validation

Before flashing, mount the rootfs image and confirm that firmware is present:

```bash
sudo mkdir -p /mnt/sheng-rootfs
sudo mount -o loop,ro out/mobile-rootfs/rootfs.img /mnt/sheng-rootfs

find /mnt/sheng-rootfs/lib/firmware /mnt/sheng-rootfs/usr/lib/firmware -maxdepth 10 -type f 2>/dev/null \
  | grep -Ei 'qcom|sm8550|sheng|adsp|cdsp|ipa|a740' \
  | sort \
  | head -100

sudo umount /mnt/sheng-rootfs
```

Expected examples:

```text
/lib/firmware/qcom/sm8550/sheng/adsp.mbn
/lib/firmware/qcom/sm8550/sheng/cdsp.mbn
/lib/firmware/qcom/sm8550/sheng/ipa_fws.mbn
/lib/firmware/qcom/a740_sqe.fw
```

If these files are missing, do not flash. Fix rootfs generation first.

## Runtime Validation

After booting, inspect firmware, remoteproc, Type-C, and UCSI logs:

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

Success criteria:

- `qcom/sm8550/sheng` firmware files are present.
- `adsp.mbn` and `cdsp.mbn` no longer fail with `request_firmware failed: -2`.
- `ucsi_glink` no longer reports `UCSI/PD service never became running after
  60 retries`.
- `/sys/class/typec` exposes a port.
- OTG or hub insertion can switch `usb_role` to `host`.
- USB keyboard/mouse or hub devices appear in `lsusb`, `/sys/bus/usb/devices`,
  or `/proc/bus/input/devices`.
- ADB device mode still works.

## Troubleshooting

| Symptom | Check first |
| --- | --- |
| `/sys/class/typec` is empty | Check `pd_running`, `charger_pd`, and firmware before HID. |
| `Direct firmware load ... error -2` | Firmware path is missing, or the `linux` rootfs partition was not updated. |
| `usb_role=device` | If Type-C is empty, UCSI did not register; DWC3 host is not necessarily broken. |
| `ps5169 dvdd` uses a dummy regulator | Not the first cause; debug high-speed routing after Type-C registers. |
| `fixed dependency cycle` | Common with device-tree graph dependencies; not the first cause. |
| qcom-battmgr synthetic uevent `-11` | Can be reduced as log noise, but is not the USB-C host root cause. |
| Firmware unchanged after flashing only `boot_b` | Firmware lives in rootfs; flash the `linux` partition. |

## Rollback

If a new rootfs or boot image fails to boot, switch back to the Android slot or
flash the previous known-good `boot_b` and `linux` images. Firmware/rootfs
rollback also requires flashing the `linux` partition.
