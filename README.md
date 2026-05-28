# NixOS on Xiaomi Pad 6S Pro

This repository contains an experimental Mobile NixOS port for the Xiaomi Pad
6S Pro (`sheng`, SM8550).

The tree is intentionally NixOS-only. The old Debian/Ubuntu/Fedora/Arch bundle
layout has been removed so this can grow as an independent device port.

## Status

Current target: build Mobile NixOS boot and rootfs artifacts for the Android
fastboot flow.

| Area | Status | Notes |
| --- | --- | --- |
| Device framework | Mobile NixOS | Device lives in `nixos/devices/xiaomi-sheng` |
| Kernel | Work in progress | Built by `mobile-nixos.kernel-builder-clang` from `code002-2/sm8550-mainline` |
| Android boot image | Work in progress | Built from Mobile NixOS Android system type |
| RootFS | Initial skeleton | Built as a Mobile NixOS ext4 image labeled `linux` |
| TWRP generation switcher | Planned | Future goal for selecting NixOS generations |

## Repository Layout

```text
.
|-- .github/workflows/
|   |-- kernel.yml          # Build Mobile NixOS Android boot image
|   `-- nixos-rootfs.yml    # Build Mobile NixOS rootfs image
|-- nixos/
|   |-- devices/xiaomi-sheng/
|   |   |-- default.nix
|   |   `-- kernel/
|   |       |-- default.nix
|   |       `-- config.aarch64
|   |-- flake.nix
|   |-- configuration.nix
|   |-- hardware-sheng.nix
|   |-- mobile-profile.nix
|   `-- services/
`-- build-nixos-rootfs.sh
```

## Architecture

The port follows the normal Mobile NixOS split:

```text
boot_b:
  Android boot.img
  - sheng kernel
  - appended sm8550-xiaomi-sheng.dtb
  - Mobile NixOS stage-1 initramfs

linux:
  ext4 rootfs image
  - NixOS stage-2 userspace
  - kernel modules in the Nix store
  - Mobile NixOS generation metadata
```

The kernel source is pinned as a flake input:

```nix
shengKernelSrc.url = "github:code002-2/sm8550-mainline/1c2d6f012c0a3c529ad68c5dc4d47cc0f60fb9f2";
```

So the boot image and rootfs are now derived from one Mobile NixOS device
definition instead of a separate hand-written boot script.

## Default Login

The first minimal image intentionally keeps simple credentials for bring-up:

- User: `luser`
- Password: `luser`
- Root password: `1234`

Change these before publishing images for real users.

## Build Boot Image

GitHub Actions workflow: `Build Sheng Kernel`

Output:

```text
boot_sheng_nixos.img
```

Locally, on an aarch64 Linux host with Nix flakes enabled:

```bash
nix build ./nixos#mobileAndroidBootimg
```

## Build RootFS

GitHub Actions workflow: `Build NixOS RootFS`

Output:

```text
out/nixos-sheng-YYYYmmdd_HHMMSS.img
out/nixos-sheng-YYYYmmdd_HHMMSS.img.zip
```

Locally:

```bash
sudo ./build-nixos-rootfs.sh
```

The default image size is `auto`. Mobile NixOS computes a compact ext4 image
and this wrapper stores it as a single `.img.zip` artifact for easier download.

## Flashing

If the `linux` partition already exists from the original project:

```bash
fastboot erase dtbo_b
fastboot flash boot_b boot_sheng_nixos.img
fastboot flash linux nixos-sheng-*.img
fastboot set_active b
fastboot reboot
```

## Warning

This is a device-porting project. Flashing boot images and repartitioning can
brick the tablet or destroy data. Back up everything and assume all commands are
dangerous until proven otherwise.
