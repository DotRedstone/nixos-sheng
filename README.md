[🇨🇳 简体中文](README_zh.md) | [🇬🇧 English](README.md)

# nixos-xiaomi-sheng

Experimental Mobile NixOS port for the Xiaomi Pad 6S Pro 12.4 (`sheng`,
Qualcomm SM8550).

This repository is a NixOS-only device port. The maintained flashing path is
the Mobile NixOS Android boot flow: a `boot.img` for the inactive Android slot
and a Mobile NixOS generated ext4 rootfs image for the dedicated `linux`
partition.

## Status

This is an early bring-up project.

| Area | Status | Notes |
| --- | --- | --- |
| Device framework | Mobile NixOS | Device definition lives in `nixos/devices/xiaomi-sheng` |
| Kernel | Sheng mainline kernel | Built from `map220v/sm8550-mainline` through Nix |
| Boot image | Bring-up | Mobile NixOS Android boot image for `boot_b` |
| RootFS | Mobile NixOS generated rootfs | ext4 image labeled `linux` |
| Display/console | Bring-up | Stage-1 currently runs headless until display works |
| Debug access | Bring-up | Stage-1/stage-2 ADB is enabled through Mobile NixOS |

## Upstream Projects

- [mobile-nixos/mobile-nixos](https://github.com/mobile-nixos/mobile-nixos)
  provides the device framework, stage-1 initramfs, Android boot image builder,
  generated rootfs support, USB gadget setup, and device-port conventions.
- [map220v/sm8550-mainline](https://github.com/map220v/sm8550-mainline)
  provides the Xiaomi Pad 6S Pro mainline kernel work.

The kernel source is configured in `nixos/flake.nix`:

```nix
shengKernelSrc.url = "github:map220v/sm8550-mainline/sheng-7.0";
```

## How Boot Works

The tablet still boots like an Android device.

```text
Android bootloader
  -> boot_b / boot.img
       -> sheng kernel
       -> sm8550-xiaomi-sheng.dtb
       -> Mobile NixOS stage-1 initramfs
            -> mounts /dev/disk/by-partlabel/linux
            -> reads nix-path-registration
            -> switches into the selected NixOS system closure

linux partition
  -> Mobile NixOS generated ext4 rootfs
       -> nix/store
       -> nix-path-registration
```

The rootfs image is intentionally not a normal PC-style root directory. Seeing
only `nix/store` and `nix-path-registration` at the top level is expected for
the Mobile NixOS generated rootfs: stage-1 uses that registration data to find
the NixOS system closure and then runs its `init`.

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
|   |-- patches/            # Small stage-1 bring-up patches
|   |-- flake.nix
|   |-- configuration.nix
|   |-- hardware-sheng.nix
|   |-- mobile-profile.nix
|   `-- services/
|-- scripts/
|   `-- inspect-bootimg.sh  # Offline boot.img/initrd inspection helper
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

Update the flake lock when inputs need to be refreshed:

```bash
nix flake lock ./nixos
```

Build the boot image:

```bash
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
```

Build the flashable Mobile NixOS rootfs image:

```bash
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
```

Build the optional GNOME hardware-test rootfs image:

```bash
nix build ./nixos#mobileRootfsImageGnome -o out/mobile-rootfs-gnome
```

The GNOME profile lives in `nixos/profiles/gnome.nix` and is only included by
the `mobileRootfsImageGnome` output. The default `mobileRootfsImage` output stays
minimal.

Build all Mobile NixOS fastboot-facing images in one output:

```bash
nix build ./nixos#mobileFastbootImages -o out/mobile-fastboot
```

Build and copy the rootfs image into `out/nixos-sheng-*.img`:

```bash
./build-nixos-rootfs.sh
```

Build and copy the GNOME rootfs image through the helper:

```bash
ROOTFS_FLAKE_ATTR=mobileRootfsImageGnome ./build-nixos-rootfs.sh
```

`fullRootfsImage` is kept as a compatibility alias for older commands. It points
to the same Mobile NixOS generated rootfs as `mobileRootfsImage`.

## Flashing

For a dual-boot test on slot `b`, keep Android on the other slot and flash only
the inactive slot boot image plus the dedicated `linux` rootfs partition:

```bash
fastboot erase dtbo_b
fastboot flash boot_b out/mobile-bootimg
fastboot flash linux out/nixos-sheng-YYYYMMDD_HHMMSS.img
fastboot --set-active=b
fastboot reboot
```

If you built the rootfs directly with `nix build ./nixos#mobileRootfsImage`, the
file to flash is the generated `rootfs.img`:

```bash
fastboot flash linux out/mobile-rootfs/rootfs.img
```

If stage-1 code or the Android boot configuration changed, rebuild and flash
`boot_b`. If only the NixOS userspace/rootfs changed, rebuild and flash
`linux`.

Do not flash `userdata`. Firmware, packages, systemd units, users, and other
rootfs content live in the `linux` partition; flashing only `boot_b` does not
update `/lib/firmware`.

## Firmware, USB-C, and OTG

USB-C host mode on sheng depends on Qualcomm remoteproc firmware being present
in the final Mobile NixOS rootfs. See
[docs/sheng-firmware-and-usbc.md](docs/sheng-firmware-and-usbc.md) for the
full dependency chain, offline rootfs checks, runtime verification commands,
and common failure signatures.

## Debugging

ADB is enabled through `mobile.adbd.enable`. During a successful transition,
stage-1 ADB may briefly disconnect while stage-2 takes over USB gadget setup.

To inspect a generated boot image offline:

```bash
scripts/inspect-bootimg.sh out/mobile-bootimg
```

The helper prints `/etc/boot/config`, initrd applets, and key boot flags such as
`boot_as_recovery`, `splash.disabled`, rootfs mount settings, and USB features.

## Default Login

The bring-up image currently keeps simple credentials:

- user: `luser`
- password: `luser`
- root password: `123456`

Change these before publishing images for general use.

## Warning

This is a low-level device-porting project. Flashing boot images, changing the
active slot, and writing partitions can brick the tablet or destroy data. Back
up everything and assume every command is dangerous until proven on your own
device.
