# Sheng boot generation menu

Sheng uses a fixed Android `boot_b` image and selectable NixOS stage-2
generations from the writable `linux` partition.

The normal boot path remains headless. Hold either volume key while the device
starts to open the text generation menu:

```text
NixOS Sheng - Select stage-2 generation

> NixOS - Default
  NixOS #2 (2026-06-06 - 26.11pre-git)
  NixOS #1 (2026-06-06 - 26.11pre-git)

Volume +/-: select    Power: boot
```

- Volume up/down changes the highlighted stage-2 generation.
- Power confirms the selection.
- The highlighted entry boots automatically after 30 seconds.
- The menu always keeps using the kernel, DTB, stage-1 initrd, and command line
  from the flashed `boot_b`.

The menu is implemented without the Mobile NixOS LVGL splash because enabling
the graphical stage-1 path previously blocked sheng from reaching stage-2.

Building or changing this menu affects the Android boot image and requires
flashing `boot_b`. Creating, selecting, switching, or rolling back stage-2
generations does not require flashing.

## Verification

Before testing the menu, confirm at least two generations exist:

```sh
PAGER=cat nix-env --profile /nix/var/nix/profiles/system --list-generations
```

Reboot, hold either volume key, choose an older generation, and confirm with the
power key. After boot:

```sh
readlink /nix/var/nix/profiles/system
readlink -f /run/current-system
systemctl --failed --no-pager
```

If the menu does not appear, boot continues normally after the key is released.
The previous known-good `boot_b` image is the rollback path for menu failures.
