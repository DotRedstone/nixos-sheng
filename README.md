# NixOS on Xiaomi Pad 6S Pro

This repository contains an experimental Mobile NixOS based port for the
Xiaomi Pad 6S Pro (`sheng`, SM8550).

The project is intentionally NixOS-only. Older Debian, Ubuntu, Fedora, Arch
Linux, `.deb`, and bundle workflows have been removed so the tree can grow into
a clean independent port.

## Status

Current target: a Mobile NixOS based bring-up image for the existing Android
`boot.img` flow.

| Area | Status | Notes |
| --- | --- | --- |
| Kernel image | Work in progress | Built from `code002-2/sm8550-mainline` |
| Android boot image | Work in progress | Uses upstream sheng kernel plus Mobile NixOS stage-1 |
| NixOS rootfs | Initial skeleton | Builds an ext4 image with Mobile NixOS filesystem tooling |
| Local console | Debug console enabled | kmscon/getty for bring-up |
| TWRP generation switcher | Planned | Future goal for switching NixOS generations |

## Repository Layout

```text
.
|-- .github/workflows/
|   |-- kernel.yml          # Build kernel, DTB, modules, boot images
|   `-- nixos-rootfs.yml    # Build Mobile NixOS rootfs image
|-- nixos/
|   |-- devices/xiaomi-sheng/
|   |-- flake.nix
|   |-- configuration.nix
|   |-- hardware-sheng.nix
|   |-- mobile-profile.nix
|   `-- services/
|-- build-nixos-rootfs.sh
|-- build-stage1-initramfs.sh
|-- sheng-kernel_build.sh
`-- mkbootimg
```

## Default Login

The first minimal image intentionally keeps simple credentials for bring-up:

- User: `luser`
- Password: `luser`
- Root password: `1234`

Change these before publishing images for real users.

## Build Kernel Artifacts

The kernel workflow produces:

- `boot_sheng_dualboot.img`
- `boot_sheng_singleboot.img`
- `boot_sheng_nixos.img`
- `sheng-stage1-initramfs.cpio.gz`
- `sheng-kernel-files.tar.zst`
- `sheng-kernel-modules.tar.zst`

`boot_sheng_nixos.img` is the important bring-up image. It keeps using the
upstream sheng kernel tree, but its initramfs is built from Mobile NixOS
stage-1 so early boot can show Mobile NixOS splash/error handling before the
rootfs is mounted.

Locally, on an aarch64 Linux host with the required toolchain:

```bash
bash sheng-kernel_build.sh 7.1
```

## Build NixOS RootFS

The rootfs workflow builds a console-focused Mobile NixOS ext4 image:

```bash
sudo ./build-nixos-rootfs.sh
```

The default image size is `auto`. Mobile NixOS computes a compact ext4 image
and adds padding. If you want a fixed size, pass a value such as `8G`.

Output:

```text
out/nixos-sheng-YYYYmmdd_HHMMSS.img
out/nixos-sheng-YYYYmmdd_HHMMSS.img.zip
```

The image expects the Linux partition to be named `linux` and the boot image to
pass:

```text
root=PARTLABEL=linux rootwait console=tty0 console=ttyMSM0,115200n8 fbcon=map:0 fbcon=rotate:1 loglevel=7 ignore_loglevel
```

These arguments live in `boot_sheng_nixos.img`, not in the rootfs. Rebuild and
reflash `boot_b` after changing kernel command-line arguments or stage-1.

The rootfs workflow can optionally inject kernel artifacts from a release such
as `kernel-7.1`. Build the kernel workflow first, then pass that tag as
`kernel_release_tag` when building the rootfs. Boot images are produced only by
the kernel workflow; use `boot_sheng_nixos.img` for NixOS testing.

## Bring-up Plan

1. Confirm the kernel reaches Mobile NixOS stage-1 and shows splash/error UI.
2. Confirm stage-1 mounts the `linux` partition and switches to NixOS.
3. Confirm serial/getty on `ttyMSM0` and local login.
4. Import kernel modules and firmware into the image.
5. Add Wi-Fi/Bluetooth/audio validation after basic boot is stable.
6. Implement a TWRP-side generation switcher that selects NixOS generations.

## Warning

This is a device-porting project. Flashing boot images and repartitioning can
brick the tablet or destroy data. Back up everything and assume all commands are
dangerous until proven otherwise.
