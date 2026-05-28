# nixos-xiaomi-sheng

Experimental Mobile NixOS port for the Xiaomi Pad 6S Pro 12.4 (`sheng`,
Qualcomm SM8550).

This repository is intentionally NixOS-only. It is no longer a Debian/Ubuntu
rootfs bundle project: the old distribution build scripts, Debian package
metadata, firmware bundles, and helper binaries are not part of the maintained
tree. The goal is to keep this as a small device port that describes the tablet
with Nix and lets Mobile NixOS build the boot and rootfs artifacts.

## Status

This is an early bring-up project.

| Area | Status | Notes |
| --- | --- | --- |
| Device framework | Mobile NixOS | Device definition lives in `nixos/devices/xiaomi-sheng` |
| Kernel | Upstream sheng kernel | Built from `code002-2/sm8550-mainline` through Nix |
| Boot image | Work in progress | Mobile NixOS Android boot image for `boot_b` |
| RootFS | Minimal image | ext4 image labeled `linux` |
| Display/console | Bring-up | Kernel and stage-1 still need real-device testing |
| TWRP generation switcher | Planned | Future goal for selecting NixOS generations |

## Upstream Projects

This project is mainly glue between two upstream efforts:

- [mobile-nixos/mobile-nixos](https://github.com/mobile-nixos/mobile-nixos)
  provides the mobile device framework, stage-1 initramfs, Android boot image
  builder, generated rootfs support, and device-port conventions.
- [code002-2/sm8550-mainline](https://github.com/code002-2/sm8550-mainline)
  provides the Xiaomi Pad 6S Pro mainline kernel work: device tree, display,
  storage, USB, panel, and other hardware support.

Mobile NixOS does not magically provide device drivers. The driver support
still comes from the sheng kernel. The difference is that the kernel, initramfs,
boot image, and rootfs are now built from one Nix device definition instead of
from hand-written distribution scripts.

The kernel source is pinned in `nixos/flake.nix`:

```nix
shengKernelSrc.url = "github:code002-2/sm8550-mainline/1c2d6f012c0a3c529ad68c5dc4d47cc0f60fb9f2";
```

The kernel configuration is based on the postmarketOS sheng configuration that
has already been used by the Debian bring-up path:

```text
device/testing/linux-postmarketos-qcom-sm8550/config-postmarketos-qcom-sm8550.aarch64
```

The Mobile NixOS kernel builder is kept aligned with that flow by completing
configuration through `olddefconfig`, then building `Image.gz`, modules, and
DTBs through the Mobile NixOS Android boot image pipeline.

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
- `Build NixOS RootFS`: builds `nixos-sheng-*.img` and a single-layer
  `nixos-sheng-*.img.zip`.

For test builds, keep `Skip GitHub release` enabled so the workflow only
uploads artifacts.

## Local Build

Local builds require an aarch64 Linux environment with Nix flakes enabled.

Build the boot image:

```bash
nix build ./nixos#mobileAndroidBootimg
```

Build the rootfs image:

```bash
sudo ./build-nixos-rootfs.sh
```

## Flashing

If the `linux` partition already exists from the old project flow, the expected
test path is:

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot_sheng_nixos.img
fastboot flash linux nixos-sheng-*.img
fastboot set_active b
fastboot reboot
```

After the first successful boot, the rootfs can be expanded:

```bash
resize2fs /dev/sda30
```

Check the actual block device on your device before running resize commands.

## What Is Not Maintained Here

The old Debian-style repository carried scripts and package fragments for many
distributions. Those are intentionally out of scope now:

- no Debian package directories;
- no Ubuntu/Fedora/Arch rootfs builders;
- no bundled `parted` or one-off helper binaries;
- no separate shell script that manually clones and packs the kernel.

For this project, the maintained base is:

- Mobile NixOS framework;
- pinned sheng upstream kernel;
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
