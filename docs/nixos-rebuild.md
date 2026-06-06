# Updating the installed NixOS system

The flashed Android `boot_b` image is the fixed boot foundation for sheng. It
contains the kernel, DTB, Mobile NixOS stage-1 initrd, and boot command line.
Normal NixOS generations only update stage-2 on the writable `linux` partition.

The flake exposes the same Mobile NixOS evaluations used to build the flashable
rootfs images:

| Configuration | Desktop | Matching rootfs output |
| --- | --- | --- |
| `sheng` | Minimal GNOME | `mobileRootfsImageGnome` |
| `sheng-minimal` | Console | `mobileRootfsImage` |

This is important because a separate ordinary `nixosSystem` evaluation could
select a different kernel module tree or omit sheng hardware services.

## First safe test

Clone the repository on the tablet and build without activating it:

```sh
git clone https://github.com/DotRedstone/nixos-xiaomi-sheng
cd nixos-xiaomi-sheng

sudo nixos-rebuild build --flake ./nixos#sheng
```

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

Use the NixOS configuration for system-wide users, packages, GNOME, services,
firmware, and hardware integration. Use Home Manager for personal applications,
shell configuration, editor configuration, and per-user GNOME preferences.

The repository currently defines the bring-up users in
`nixos/configuration.nix`. Replace the temporary passwords before distributing
a personalized image or using the tablet as a daily system.
