# Sheng boot generation menu

[English](boot-generation-menu.md) | [简体中文](boot-generation-menu_zh.md)

Sheng uses a fixed Android `boot_b` image and selectable NixOS stage-2
generations from the writable `linux` partition.

The normal boot path remains headless. Open the text generation menu from the
running system:

```sh
sudo sheng-reboot-generation-menu
```

The command writes a one-time request to the writable `linux` partition and
reboots. Stage-1 consumes the request before displaying the menu:

```text
NixOS Sheng - Select stage-2 generation

> NixOS #2 (2026-06-06 - 26.11pre-git)
  NixOS #1 (2026-06-06 - 26.11pre-git)

Volume +/-: select    Power: boot
```

- Volume up/down or an external keyboard's up/down arrows change the
  highlighted stage-2 generation.
- Holding a navigation key repeats the selection movement.
- Volume key handling is edge-triggered, so selection redraw does not wait for
  a delayed key-release event.
- Power or an external keyboard's Enter key confirms the selection.
- The highlighted entry boots automatically after 30 seconds.
- The menu uses a 16x32 console font and padded full redraws when visible state
  changes, avoiding stale rows, coordinate drift, and periodic screen flicker.
- Console input echo and VT keyboard translation are disabled while the menu is
  active, preventing physical volume keys from printing escape sequences over
  the menu.
- Kernel console logging is temporarily suppressed while the menu is active,
  preventing asynchronous driver logs from overwriting it.
- Each generation row is cleared before redraw to avoid inverse-video remnants
  after moving the selection.
- The menu always keeps using the kernel, DTB, stage-1 initrd, and command line
  from the flashed `boot_b`.

Do not hold volume down while powering on the tablet. The Xiaomi bootloader
intercepts it before Linux starts and enters Fastboot mode.

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

Run `sudo sheng-reboot-generation-menu`, choose an older generation, and
confirm with the power key. After boot:

```sh
readlink /nix/var/nix/profiles/system
readlink -f /run/current-system
systemctl --failed --no-pager
```

If the menu does not appear, the previous known-good `boot_b` image is the
rollback path for menu failures.
