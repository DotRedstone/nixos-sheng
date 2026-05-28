# NixOS on Xiaomi Pad 6S Pro

This repository contains an experimental NixOS port for the Xiaomi Pad 6S Pro
(`sheng`, SM8550).

The project is intentionally NixOS-only. Older Debian, Ubuntu, Fedora, Arch
Linux, `.deb`, and bundle workflows have been removed so the tree can grow into
a clean independent port.

## Status

Current target: a minimal bootable NixOS root filesystem for the existing
Android `boot.img` flow.

| Area | Status | Notes |
| --- | --- | --- |
| Kernel image | Work in progress | Built from `code002-2/sm8550-mainline` |
| Android boot image | Work in progress | Uses `mkbootimg` and `root=PARTLABEL=linux` |
| NixOS rootfs | Initial skeleton | Builds an ext4 image from a NixOS tarball |
| Graphical desktop | Debug desktop enabled | XFCE + LightDM autologin for bring-up |
| TWRP generation switcher | Planned | Future goal for switching NixOS generations |

## Repository Layout

```text
.
├── .github/workflows/
│   ├── kernel.yml          # Build kernel, DTB, modules, boot images
│   └── nixos-rootfs.yml    # Build minimal NixOS rootfs image
├── nixos/
│   ├── flake.nix
│   ├── configuration.nix
│   ├── hardware-sheng.nix
│   └── services/
├── build-nixos-rootfs.sh
├── sheng-kernel_build.sh
└── mkbootimg
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
- `sheng-kernel-files.tar.zst`
- `sheng-kernel-modules.tar.zst`

Locally, on an aarch64 Linux host with the required toolchain:

```bash
bash sheng-kernel_build.sh 7.1
```

## Build NixOS RootFS

The rootfs workflow builds an XFCE debug desktop ext4 image:

```bash
sudo ./build-nixos-rootfs.sh
```

Output:

```text
out/nixos-sheng-YYYYmmdd_HHMMSS.img
out/nixos-sheng-YYYYmmdd_HHMMSS.img.7z
```

The image expects the Linux partition to be labeled `linux` and the boot image
to pass:

```text
root=PARTLABEL=linux init=/init rootwait
```

The rootfs workflow can optionally inject kernel artifacts from a release such
as `kernel-7.1`. Build the kernel workflow first, then pass that tag as
`kernel_release_tag` when building the rootfs.

## Bring-up Plan

1. Confirm kernel reaches init with the minimal NixOS rootfs.
2. Confirm serial/getty on `ttyMSM0` and local login.
3. Import kernel modules and firmware into the image.
4. Add NetworkManager, Wi-Fi/Bluetooth firmware validation, and ALSA UCM.
5. Add a desktop profile after basic hardware is stable.
6. Implement a TWRP-side generation switcher that selects NixOS generations.

## Warning

This is a device-porting project. Flashing boot images and repartitioning can
brick the tablet or destroy data. Back up everything and assume all commands are
dangerous until proven otherwise.
