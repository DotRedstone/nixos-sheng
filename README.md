[🇬🇧 English](README.md) | [🇨🇳 简体中文](README_zh.md)

# nixos-sheng

Mobile NixOS port for the Xiaomi Pad 6S Pro 12.4 (`sheng`,
Qualcomm SM8550).

![Device](https://img.shields.io/badge/device-Xiaomi%20Pad%206S%20Pro%2012.4-blue)
![Kernel](https://img.shields.io/badge/kernel-7.1.8-blueviolet)
![NixOS](https://img.shields.io/badge/NixOS-Mobile%20NixOS-5277c3)
![License](https://img.shields.io/badge/license-MIT%20%2B%20third--party%20terms-orange)

This repository is a NixOS-only device port. The maintained flashing path is
the Mobile NixOS Android boot flow: a `boot.img` for the inactive Android slot
and a Mobile NixOS generated ext4 rootfs image for the dedicated `linux`
partition.

If this project helps you, or if you simply want to see NixOS become more real
on mobile devices, please consider giving the repository a star. It helps other
sheng users find the port and makes the late-night boot-image archaeology feel
a little less lonely.

## Highlights

- Mobile NixOS boot flow for Xiaomi Pad 6S Pro 12.4 (`sheng`)
- Flashable Android `boot_b` image plus dedicated `linux` rootfs image
- Desktop-neutral public flake constructor for private dotfiles repositories
- Optional GNOME image with touch keyboard, rotation, and cover handling
- Stage-1 NixOS generation menu controlled by volume and power keys
- Working Wi-Fi, USB-C role/OTG, SSC sensors, RAW camera capture, and MiPPS
  fast-charging authentication
- Integrated NT36532E THP touch/stylus and FPC1553 fingerprint support

## Status

The first public release is available from
[GitHub Releases](https://github.com/DotRedstone/nixos-sheng/releases/latest).
Some hardware remains partially supported; review the status table and known
issues before flashing.

| Area | Status | Notes |
| --- | --- | --- |
| Device framework | Mobile NixOS | Device definition lives in `nixos/hardware/xiaomi-sheng` |
| Kernel | Sheng device kernel | Built from `DotRedstone/linux-sheng` through Nix |
| Boot image | Bring-up | Mobile NixOS Android boot image for `boot_b` |
| RootFS | Mobile NixOS generated rootfs | ext4 image labeled `linux` |
| Display/desktop | Working | 3048x2032 panel, GNOME shell, gjs-osk onscreen keyboard, physical power key toggle, four-way rotation, and cover open/close display control work |
| Debug access | Bring-up | Stage-1/stage-2 ADB is enabled through Mobile NixOS |
| Wi-Fi | Working | 2.4 GHz and 5 GHz scanning, connection, and networking verified; a rare missing-5-GHz state was seen after a fresh flash and recovered after a soft reboot, but is not reproducible yet |
| Bluetooth | Partially working | hci0, bluetooth.service, and Focus Pen HID reconnect work; general pairing, Bluetooth audio, and suspend/resume need wider validation |
| Audio | Partially working | ALSA playback/capture PCM and the userspace path are integrated; repeat playback, recording, and controlled tuning tests are still needed on the release image |
| Cameras | Partially working | front/rear RAW10 frames captured; libcamera, auto exposure, and desktop camera app need integration |
| Sensors | User-space working | accelerometer, proximity, ambient light, and compass work through SSC + iio-sensor-proxy D-Bus |
| Touch and stylus | Working | NT36532E THP multitouch plus Xiaomi Focus Pen pressure, tilt, hover, and button events are verified; wider application compatibility still needs testing |
| Fingerprint | Working | Graphical enrollment and verification work through the FPC1553 QTEE-backed private libfprint driver; screen-off wake-unlock needs long-term testing |
| Charging | Working | Standard PD and Xiaomi MiPPS authentication work; actual power depends on charge state, temperature, charger, and cable and is not a guaranteed 120 W |

## Upstream Projects

- [mobile-nixos/mobile-nixos](https://github.com/mobile-nixos/mobile-nixos)
  provides the device framework, stage-1 initramfs, Android boot image builder,
  generated rootfs support, USB gadget setup, and device-port conventions.
- [DotRedstone/sheng-firmware-full](https://github.com/DotRedstone/sheng-firmware-full)
  provides the complete proprietary firmware, ADSP sensor communication configs, and registry.
- [DotRedstone/linux-sheng](https://github.com/DotRedstone/linux-sheng)
  carries the maintained device kernel, drivers, and DTS used by this project.
- [map220v/sm8550-mainline](https://github.com/map220v/sm8550-mainline)
  provides the upstream Xiaomi Pad 6S Pro mainline kernel work.
- [ianchb/xiaomi-mipps-auth](https://github.com/ianchb/xiaomi-mipps-auth)
  provides the userspace authentication daemon for the Xiaomi 120W private fast charging protocol.

The kernel source is configured in `nixos/flake.nix`:

```nix
shengKernelSrc.url = "github:DotRedstone/linux-sheng/upgrade/sheng-7.1.8";
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

### Stage-1 Boot Generation Menu

Because standard Android bootloaders cannot render GRUB or systemd-boot menus, this project implements a **custom framebuffer text menu** directly inside the `stage-1` initramfs.

The menu appears briefly on every boot and automatically enters the newest
generation after three seconds without input. Run
`sudo sheng-reboot-generation-menu` to reboot to it explicitly.

- Volume keys or external Up/Down arrows move the highlight; holding a key
  repeats movement.
- Power or Enter confirms the selection.
- Manual input pauses the countdown. Confirmation stores the selection and
  performs one quick reboot; the next stage-1 consumes it and skips the menu.
  This preserves a clean Qualcomm SSC registration window even when the user
  spends a long time choosing a generation.

See [`docs/boot-generation-menu.md`](docs/boot-generation-menu.md) for details.

## Repository Layout

```text
.
|-- .github/workflows/
|   |-- kernel.yml          # Builds the Mobile NixOS Android boot image
|   `-- nixos-rootfs.yml    # Builds the Mobile NixOS rootfs image
|-- nixos/
|   |-- flake.nix           # Main Flake entrypoint
|   |-- configuration.nix   # Core OS and system services configuration
|   |-- hardware/           # Hardware Abstraction: DTB, kernel, ALSA, boot
|   |   |-- xiaomi-sheng/   # Mobile NixOS base device definition
|   |   |-- audio/          # ALSA UCM2 hardware audio tuning
|   |   |-- hardware.nix    # NixOS hardware module configurations
|   |   `-- mobile.nix      # Mobile NixOS Stage-1 configurations
|   |-- modules/            # Custom NixOS modules & services (MiPPS auth etc.)
|   |-- home/               # User-level Home Manager configurations
|   |-- profiles/           # High-level desktop profiles (GNOME, etc.)
|   |-- packages/           # Custom package derivations
|   |-- patches/            # Boot-flow Ruby patches
|   `-- scripts/            # Target-side execution scripts
|-- scripts/
|   `-- inspect-bootimg.sh  # Offline boot.img/initrd inspection helper
`-- build-nixos-rootfs.sh
```

## Repository Responsibility

This repository owns the reusable sheng platform: kernel, DTB, firmware,
Mobile NixOS boot flow, hardware services, rootfs layout, and an optional
GNOME profile. It also builds public test images with a disposable default
user.

Personal users, credentials, applications, Home Manager configuration, and
private settings such as hostname, locale, and time zone belong in a separate
dotfiles flake. Downstream flakes should use
`nixos-sheng.lib.aarch64-linux.mkShengSystem` rather than importing a Mobile
NixOS module into an ordinary `nixpkgs.lib.nixosSystem` evaluation.

```nix
{
  inputs.nixos-sheng.url =
    "github:DotRedstone/nixos-sheng?dir=nixos";

  outputs = { self, nixos-sheng, ... }@inputs: {
    nixosConfigurations.sheng =
      nixos-sheng.lib.aarch64-linux.mkShengSystem [
        { _module.args.inputs = inputs; }
        ./hosts/sheng/configuration.nix
      ];
  };
}
```

`mkShengSystem` provides the desktop-neutral sheng platform. Use
`mkShengGnomeSystem` only when the downstream configuration explicitly wants
the repository's GNOME profile. `mkShengMinimalSystem` remains as a
compatibility alias for `mkShengSystem`. Public constructors do not create a
user or install the repository's Home Manager profile.

A complete private-flake starting point is available in
[`examples/sheng-dotfiles`](examples/sheng-dotfiles).

## Build With GitHub Actions

Open the Actions tab and run these workflows on the `sheng` branch:

- `Build Sheng Kernel`: builds `boot_sheng_nixos.img`.
- `Build NixOS RootFS`: builds the flashable `nixos-sheng-*.img`.
- `Check Public Flake`: verifies the public constructors and committed lock
  file.

For test builds, keep `Skip GitHub release` enabled so the workflow only
uploads artifacts.

Formal release rootfs images are published as split ZIP archives for Windows
users. Download every volume for the chosen variant, such as
`rootfs-minimal.z01`, `rootfs-minimal.z02`, and `rootfs-minimal.zip`, then open
the `.zip` file with Bandizip, 7-Zip, WinRAR, or another split-ZIP compatible
tool to extract the directly flashable `.img`.

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

Build the installed GNOME stage-2 system used by `nixos-rebuild`:

```bash
nix build ./nixos#nixosConfigurations.sheng.config.system.build.toplevel
```

Build all Mobile NixOS fastboot-facing images in one output:

```bash
nix build ./nixos#mobileFastbootImages -o out/mobile-fastboot
```

Build and copy the rootfs image into `out/nixos-sheng-*.img`:

```bash
./build-nixos-rootfs.sh
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

A rare missing-5-GHz state has been observed after the first boot of a fresh
flash and recovered after a normal soft reboot. It is not reproducible enough
to make a mandatory reboot part of the normal installation. If it occurs,
capture `dmesg`, `journalctl -b -u NetworkManager`, and `iw dev` before
rebooting.

Do not flash `userdata`. Firmware, packages, systemd units, users, and other
rootfs content live in the `linux` partition; flashing only `boot_b` does not
update `/lib/firmware`.

After the initial flash, normal stage-2 configuration changes can be built,
tested, switched, and rolled back directly on the tablet with
`nixos-rebuild`. Kernel, DTS, stage-1 initrd, and boot command-line changes
still require a separately built and flashed `boot_b` image. See
[`docs/nixos-rebuild.md`](docs/nixos-rebuild.md) for the safe workflow.

The generated rootfs filesystem can be smaller than the dedicated `linux`
partition. A matching boot image expands it automatically in stage-1 before
the first rootfs mount. See
[`docs/linux-partition-resize.md`](docs/linux-partition-resize.md) for
verification and the rescue fallback.

## Firmware, Sensors, and USB-C

USB-C host mode and various sensors on sheng heavily depend on the complete Qualcomm remoteproc firmware (including ADSP and CDSP).
Since NixOS is stateless, we introduced [sheng-firmware-full](https://github.com/DotRedstone/sheng-firmware-full) to manage all proprietary files, and configured the system to mount the native Android `persist` partition to provide the registry required by the DSP sensors.

Sensors currently use the Qualcomm SSC user-space path. `iio-sensor-proxy`
exposes accelerometer, proximity, ambient light, and compass data over D-Bus.
This does not create kernel IIO sysfs nodes, so an empty
`/sys/bus/iio/devices` directory is expected for the current implementation.

For the full dependency chain, offline rootfs checks, runtime verification commands, and common failure signatures, see:
- [docs/sheng-firmware-and-usbc.md](docs/sheng-firmware-and-usbc.md)
- [docs/sensors-ssc-userland.md](docs/sensors-ssc-userland.md)
- [docs/nixos-rebuild.md](docs/nixos-rebuild.md)
- [docs/install-dualboot.md](docs/install-dualboot.md)
- [docs/linux-partition-resize.md](docs/linux-partition-resize.md)
- [docs/boot-generation-menu.md](docs/boot-generation-menu.md)
- [docs/camera-raw-capture.md](docs/camera-raw-capture.md)
- [docs/mipps-120w.md](docs/mipps-120w.md)
- [docs/release-readiness.md](docs/release-readiness.md)
- [docs/kernel-optimization-log_zh.md](docs/kernel-optimization-log_zh.md)
- [docs/sheng-optimization-post-draft_zh.md](docs/sheng-optimization-post-draft_zh.md)

## License and third-party material

Original project material authored by DotRedstone is licensed under the
[MIT License](LICENSE). Third-party source code, Linux kernel code and patches,
firmware, binaries, and trademarks remain under their respective terms; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The device-specific firmware used by this port is proprietary. Its presence in
a public source repository does not by itself grant redistribution permission.
Anyone distributing prebuilt images is responsible for confirming permission
for every included binary in their jurisdiction. The lowest-risk distribution
model is source-only, with users supplying firmware extracted from devices they
own.

Rights holders can request review of affected files or release artifacts
through GitHub; see `THIRD_PARTY_NOTICES.md`. This project is not affiliated
with or endorsed by Xiaomi, Qualcomm, or other component vendors.

## Debugging

ADB is enabled through `mobile.adbd.enable`. During a successful transition,
stage-1 ADB may briefly disconnect while stage-2 takes over USB gadget setup.

To inspect a generated boot image offline:

```bash
scripts/inspect-bootimg.sh out/mobile-bootimg
```

The helper prints `/etc/boot/config`, initrd applets, and key boot flags such as
`boot_as_recovery`, `splash.disabled`, rootfs mount settings, and USB features.

## Test-image Credentials

Repository-built root filesystems are public test images. Downstream users and
credentials belong in a private flake. Actions no longer accept plaintext
passwords or falls back to public weak passwords for release candidates.
Generate a yescrypt hash on a trusted machine before running
`Build NixOS RootFS`:

```bash
mkpasswd -m yescrypt
```

The workflow writes only the hash to `initialHashedPassword`. Hashes can still
be attacked offline, so use a strong random password. The repository default
has no password: it enables local auto-login and passwordless sudo for
development evaluation while keeping SSH password and root login disabled.
Release builds require supplied random hashes to lock unknown password entry,
but retain local auto-login and passwordless sudo for the disposable test user.
SSH password authentication and root login remain disabled. Long-term users
should replace this profile with users from a private downstream flake.

## Disclaimer

This is an experimental Mobile NixOS port. Following the documentation should
keep the process predictable, but flashing, partitioning, and slot switching
still carry real risk. Back up your data and make sure you understand every
command before running it.

The project is not responsible for boot failures, data loss, partition damage,
or hardware problems caused by user error, skipped steps, incorrect partition
targets, device variation, or experimental drivers. Source code, instructions,
images, and other artifacts are provided as-is without warranty.
