# Sheng boot generation menu

[English](boot-generation-menu.md) | [简体中文](boot-generation-menu_zh.md)

Sheng uses a fixed Android `boot_b` image and selectable NixOS stage-2
generations from the writable `linux` partition.

The normal boot path remains headless. Open the one-shot generation menu from
the running system:

```sh
sudo sheng-reboot-generation-menu
```

The command writes a one-time request to the writable `linux` partition and
reboots. Stage-1 consumes the request before displaying the menu.

If stage-2 is unavailable, wait until NixOS boot text appears and then press
volume up three times within two seconds. Stage-1 listens for this gesture
non-blockingly between normal boot tasks, so an untouched boot has no fixed
delay. It only allows a short completion window after the first one or two
presses have already been detected:

The framebuffer UI presents generation details on two levels together with the
current position, button icons, and an automatic-boot progress indicator. The
selected generation has a high-contrast highlight and direction marker. After
confirmation, the handoff screen identifies the generation and version that is
about to enter stage-2.

- Volume up/down or an external keyboard's up/down arrows change the
  highlighted stage-2 generation.
- Holding a navigation key repeats the selection movement.
- Volume key handling is edge-triggered, so selection redraw does not wait for
  a delayed key-release event.
- Power or an external keyboard's Enter key confirms the selection.
- The highlighted entry boots automatically after 30 seconds.
- The menu draws directly to the framebuffer and adapts its panel and visible
  row count to the display dimensions.
- Generation numbers and date/version details use separate visual levels, so a
  long version does not compete with the row title.
- The timeout uses both a status label and progress bar. Moving the selection
  changes it to a clearly paused state.
- If framebuffer rendering is unavailable, the menu falls back to a tty text
  interface instead of accepting input on a blank display.
- Only changed selections, scroll windows, or timeout state are redrawn,
  avoiding periodic full-screen writes and flicker.
- Console input echo and VT keyboard translation are disabled while the menu is
  active, preventing physical volume keys from printing escape sequences over
  the menu.
- Kernel console logging is temporarily suppressed while the menu is active,
  preventing asynchronous driver logs from overwriting it.
- Each generation row is cleared before redraw to avoid display remnants after
  moving the selection.
- The menu always keeps using the kernel, DTB, stage-1 initrd, and command line
  from the flashed `boot_b`.

Do not hold either volume key while powering on the tablet. Before Linux starts,
the Xiaomi bootloader interprets volume up as Recovery and volume down as
Fastboot. Only perform the triple-press gesture after NixOS boot text appears.

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

Test both `sudo sheng-reboot-generation-menu` and the volume-up triple press
after NixOS boot text appears. Choose an older generation and confirm with the
power key. After boot:

```sh
readlink /nix/var/nix/profiles/system
readlink -f /run/current-system
systemctl --failed --no-pager
```

If the menu does not appear, the previous known-good `boot_b` image is the
rollback path for menu failures.
