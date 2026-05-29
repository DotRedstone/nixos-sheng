# nixos-xiaomi-sheng

Experimental Mobile NixOS port for the Xiaomi Pad 6S Pro 12.4 (`sheng`,
Qualcomm SM8550).

This repository is a NixOS-only device port. The goal is to keep the tablet
definition, kernel build, boot image, and rootfs image in Nix so Mobile NixOS
can produce the artifacts used for flashing and bring-up.

## Status

This is an early bring-up project.

| Area | Status | Notes |
| --- | --- | --- |
| Device framework | Mobile NixOS | Device definition lives in `nixos/devices/xiaomi-sheng` |
| Kernel | Upstream sheng kernel | Built from `map220v/sm8550-mainline` through Nix |
| Boot image | Work in progress | Mobile NixOS Android boot image for `boot_b` |
| RootFS | Minimal image | ext4 image labeled `linux` |
| Display/console | Bring-up | Kernel and stage-1 still need real-device testing |
| TWRP generation switcher | Planned | Future goal for selecting NixOS generations |

## Upstream Projects

This project is mainly glue between two upstream efforts:

- [mobile-nixos/mobile-nixos](https://github.com/mobile-nixos/mobile-nixos)
  provides the mobile device framework, stage-1 initramfs, Android boot image
  builder, generated rootfs support, and device-port conventions.
- [map220v/sm8550-mainline](https://github.com/map220v/sm8550-mainline)
  provides the Xiaomi Pad 6S Pro mainline kernel work: device tree, display,
  storage, USB, panel, and other hardware support.

Mobile NixOS provides the device framework, stage-1 initramfs, Android boot
image builder, and generated rootfs support. The sheng kernel input provides
the device-specific kernel and device tree support.

The kernel source is configured in `nixos/flake.nix`:

```nix
shengKernelSrc.url = "github:map220v/sm8550-mainline/sheng-7.0";
```

The kernel configuration starts from the postmarketOS sheng configuration:

```text
device/testing/linux-postmarketos-qcom-sm8550/config-postmarketos-qcom-sm8550.aarch64
```

The Mobile NixOS kernel builder is kept aligned with that flow by completing
configuration through `olddefconfig`, then building `Image.gz`, modules, and
DTBs through the Mobile NixOS Android boot image pipeline. For this test path,
Mobile NixOS structured kernel config validation is disabled for the sheng
kernel package so the imported configuration can be evaluated without being
rewritten to Mobile NixOS firewall defaults first.

## How Boot Works

The tablet still boots like an Android device.

```text
Android bootloader
  -> boot_b / boot.img
       -> sheng kernel
       -> sm8550-xiaomi-sheng.dtb
       -> Mobile NixOS stage-1 initramfs
            -> mounts the linux partition
            -> switches into the NixOS system closure

linux partition
  -> ext4 rootfs
       -> /nix/store
       -> NixOS userspace
       -> Mobile NixOS generation metadata
```

So there are two important artifacts:

- `boot_sheng_nixos.img`: Android boot image containing kernel + DTB +
  Mobile NixOS stage-1.
- `nixos-sheng-*.img`: ext4 rootfs image for the `linux` partition.

The kernel is not stored in the rootfs in the PC-style `/boot` sense. On this
device the Android bootloader loads the kernel from `boot_b`; the rootfs is the
userspace that the kernel switches into.

## Repository Layout

```text
.
|-- .github/workflows/
|   |-- kernel.yml          # Builds the Mobile NixOS Android boot image
|   `-- nixos-rootfs.yml    # Builds the Mobile NixOS rootfs image
|-- nixos/
|   |-- devices/xiaomi-sheng/
|   |   |-- default.nix     # Mobile NixOS device definition
|   |   `-- kernel/
|   |       |-- default.nix # Nix kernel builder for the sheng kernel
|   |       `-- config.aarch64
|   |-- flake.nix
|   |-- configuration.nix
|   |-- hardware-sheng.nix
|   |-- mobile-profile.nix
|   `-- services/
`-- build-nixos-rootfs.sh
```

## Build With GitHub Actions

Open the Actions tab and run these workflows on the `sheng` branch:

- `Build Sheng Kernel`: builds `boot_sheng_nixos.img`.
- `Build NixOS RootFS`: builds the flashable `nixos-sheng-*.img`.

For test builds, keep `Skip GitHub release` enabled so the workflow only
uploads artifacts.

## Local Build

Local builds require an aarch64 Linux environment with Nix flakes enabled.

Build the boot image:

```bash
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
```

Build the Mobile NixOS rootfs image:

```bash
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
```

Build all fastboot-facing images in one output:

```bash
nix build ./nixos#mobileFastbootImages -o out/mobile-fastboot
```

Build the rootfs image:

```bash
sudo ./build-nixos-rootfs.sh
```

## Flashing

Use the Mobile NixOS Android device flow. This repository boots through a
Mobile NixOS `boot.img` with a stage-1 initramfs and a generated ext4 rootfs
image labeled `linux`.

For a dual-boot test on slot `b`, keep Android on the other slot and flash only
the inactive slot boot image plus the dedicated `linux` rootfs partition:

```bash
fastboot erase dtbo_b
fastboot flash boot_b out/mobile-bootimg
fastboot flash linux out/mobile-rootfs/rootfs.img
fastboot set_active b
fastboot reboot
```

If you build `mobileFastbootImages`, its output contains Mobile NixOS' own
`boot.img`, `system.img`, and `flash-critical.sh` helper. The helper flashes the
boot image; the rootfs still needs to be flashed manually to this device's
`linux` partition:

```bash
nix build ./nixos#mobileFastbootImages -o out/mobile-fastboot
./out/mobile-fastboot/flash-critical.sh
fastboot flash linux ./out/mobile-fastboot/system.img
```

If you build the rootfs directly with `nix build ./nixos#mobileRootfsImage`,
flash the generated ext4 image to `linux`. Do not flash `rootfsTarball` to the
`linux` partition: that tarball is a NixOS system archive, not the Mobile NixOS
ext4 image expected by fastboot.

ADB is enabled in this bring-up profile so stage-1 or userspace can expose a
debug shell when the screen is still black. If the device does not show up in
`adb devices`, treat that as a boot-stage signal and compare it with kernel
logs or fastboot behavior.

## What Is Not Maintained Here

This repository intentionally stays focused on the Mobile NixOS port. The
following are out of scope for this tree:

- no distribution-specific rootfs builders;
- no package-manager-specific kernel packages;
- no bundled `parted` or one-off helper binaries;
- no separate shell script that manually clones and packs the kernel.

For this project, the maintained base is:

- Mobile NixOS framework;
- configured sheng upstream kernel;
- Nix device definition;
- GitHub Actions that build the Nix outputs.

Firmware, ALSA UCM data, display quirks, and TWRP generation switching can still
be added later, but they should be expressed as Nix packages/modules rather than
as ad-hoc tarballs copied into a rootfs.

## Default Login

The bring-up image currently keeps simple credentials:

- user: `luser`
- password: `luser`
- root password: `1234`

Change these before publishing images for general use.

## Warning

This is a low-level device-porting project. Flashing boot images, changing the
active slot, and writing partitions can brick the tablet or destroy data. Back
up everything and assume every command is dangerous until proven on your own
device.
