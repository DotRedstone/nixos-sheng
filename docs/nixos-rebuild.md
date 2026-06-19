# Updating the installed NixOS system

[English](nixos-rebuild.md) | [简体中文](nixos-rebuild_zh.md)

The flashed Android `boot_b` image is the fixed boot foundation for sheng. It
contains the kernel, DTB, Mobile NixOS stage-1 initrd, and boot command line.
Normal NixOS generations only update stage-2 on the writable `linux` partition.

Before creating multiple generations, make sure the ext4 filesystem uses the
full `linux` partition:

```sh
df -h /
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS
```

Online resizing is not supported by the current sheng kernel/filesystem
combination. Follow [`linux-partition-resize.md`](linux-partition-resize.md)
from TWRP or another rescue environment while the filesystem is unmounted.

The flake exposes the same Mobile NixOS evaluations used to build the flashable
rootfs images:

| Configuration | Desktop | Matching rootfs output |
| --- | --- | --- |
| `sheng` | Optional minimal GNOME | `mobileRootfsImageGnome` |
| `sheng-minimal` | Desktop-neutral console platform | `mobileRootfsImage` |

This is important because a separate ordinary `nixosSystem` evaluation could
select a different kernel module tree or omit sheng hardware services.

For a private dotfiles repository, use the public Mobile NixOS constructor:

```nix
nixosConfigurations.sheng =
  nixos-sheng.lib.aarch64-linux.mkShengSystem [
    ./hosts/sheng/configuration.nix
  ];
```

The constructor provides the complete desktop-neutral sheng platform, but does
not create users, inject credentials, install GNOME, or install this
repository's Home Manager configuration. Keep those personal concerns in the
downstream dotfiles repository. Use `mkShengGnomeSystem` only when the
repository GNOME profile is explicitly wanted.

## First safe test

Clone the repository on the tablet and build without activating it:

```sh
git clone https://github.com/DotRedstone/nixos-sheng
cd nixos-sheng

sudo nixos-rebuild build --flake ./nixos#sheng
```

The repository flake lives in the `nixos/` subdirectory. Remote flake URIs must
therefore use `dir=nixos`; cloning the repository first is recommended.

Release branches should contain `nixos/flake.lock` so evaluation does not
re-resolve and download large inputs on the tablet.

Inspect the result before switching:

```sh
readlink -f result
readlink -f /run/current-system
readlink -f result/kernel-modules 2>/dev/null || true
readlink -f /run/current-system/kernel-modules 2>/dev/null || true
```

Test the new generation without making it the boot default:

```sh
sudo nixos-rebuild test --flake ./nixos#sheng
```

After checking networking, the desktop, and hardware services, make it the
default stage-2 generation:

```sh
sudo nixos-rebuild switch --flake ./nixos#sheng
```

## Generations and rollback

List installed system generations:

```sh
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

Roll back the default profile and activate the selected stage-2 generation:

```sh
sudo nix profile rollback --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

This pure-flake workflow does not depend on legacy NixOS channels or
`<nixpkgs/nixos>`. The sheng boot generation menu can also select a stage-2
generation during boot. It cannot select a different kernel or stage-1
generation.

When checking generations through a non-interactive ADB shell, disable the
pager:

```sh
PAGER=cat nix-env --profile /nix/var/nix/profiles/system --list-generations
```

## Fixed boot boundary

`nixos-rebuild` does not write Android partitions. Changes to these components
still require building and flashing `mobileAndroidBootimg` to `boot_b`:

- kernel or kernel configuration
- DTS / DTB
- Mobile NixOS stage-1 initrd
- boot command line

Do not use `nixos-rebuild` as evidence that such a boot change was installed.
Do not flash `userdata`.

## Configuration ownership

This repository owns hardware integration, boot behavior, firmware, rootfs
layout, and platform services. A private downstream flake owns users,
credentials, personal system packages, and optional Home Manager configuration.

Repository-built test images still include a disposable default user through
`nixos/profiles/default-user.nix`; public constructors do not.
