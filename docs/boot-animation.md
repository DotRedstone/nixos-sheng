# Rounded boot animation

[简体中文](boot-animation_zh.md)

Normal boot uses a restrained black and white loop. Once the Linux framebuffer
is available, the white Nix snowflake fades in. Soft light travels through its
six interlocking lambda arms while the upright mark breathes by at most 1.8%.
Only the `NixOS` wordmark accompanies it; stage
labels and colored battery-like bars have been removed. The rounded generation
menu retains its three-second timeout and volume-key selection. Selecting a
system returns to the same seamless animation through stage-1 and stage-2; the
display manager stops the writer before taking over scanout. No artificial
progress percentage or fixed animation delay is added. Offline charging keeps
its static battery.

Snowflake geometry is adapted from [NixOS artwork](https://github.com/NixOS/nixos-artwork/tree/master/logo),
by Simon Frankau and Tim Cuthbertson, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
This version adds grayscale lighting and scale animation.

## Console and ownership

VT1 is reserved for the desktop, VT2 for the boot UI, and VT3–6 for diagnostics.
`fbcon=vc:3-6` keeps text off the UI even if the Android bootloader appends a louder
kernel log level. Logs remain in `dmesg`, the journal and `/run/log/stage-1.log`.
Press Esc on an external keyboard during the animation, or run
`sudo sheng-boot-details`, to reveal VT3 and disable animation for the current
boot. Stage-1 failure, emergency/rescue targets, display-manager failure and the
120-second animation limit also reveal diagnostics. `sheng.boot-ui=0` disables
the UI for one boot. Systems without a display manager return to the text console
at the end of early stage-2 activation.

The implementation uses the existing native SFB1 painter, with frames baked at
build time. It does not re-enable the LVGL boot path. The loop runs at 20fps and
updates only a central 720px composition, scaling for small screens. File locks
exclude competing writers. Before switch_root, the child must load its frames
and open the control and VT descriptors it carries across the mount move. The
stage-2 service retires the old process before starting its own, freeing initrd
mappings. The display manager waits for an explicit stop acknowledgement.
Stage-2 waits for the first frame before allowing the display manager to start.
Once the desktop takes over, a per-boot completion marker prevents replaying the
animation during later system switches.
Early charger detection does not cache the normal-reboot marker before the root
filesystem has mounted.

Vendor logos and unlock warnings precede Linux and are outside this code's
control. An early kernel crash or an unavailable display driver may still
require serial/ADB diagnostics.

## Build, preview and deployment

```sh
nix build ./nixos#checks.aarch64-linux.bootAnimation --no-link
nix build ./nixos#checks.aarch64-linux.generationMenuRenderer --no-link
nix build ./nixos#checks.aarch64-linux.offlineCharging --no-link
nix build ./nixos#packages.aarch64-linux.mobileAndroidBootimg -o out/mobile-bootimg
nix build ./nixos#packages.aarch64-linux.mobileRootfsImage -o out/mobile-rootfs
```

This changes cmdline, stage-1, the shared painter and stage-2 services. Deploy a
matching `boot_b` and system generation or `linux/rootfs`; updating only one side
does not provide the complete handoff. Roll back both boot_b and the system
generation if needed. Physical boot/display acceptance is still pending.

With host-native painter/assets and Pillow, export GIFs directly from native
framebuffer bytes:

```sh
python3 scripts/preview-boot-animation.py "$PAINTER/bin/sheng-fb-painter" \
  "$ANIMATION" out/boot-animation-preview --menu out/rounded-generation-menu-preview
```

Generate the optional menu directory with `scripts/preview-generation-menu.py`.
The animation file-target mode never opens the host's real display. Tests cover
16/24/32bpp, padded strides, landscape/portrait/small screens, loop continuity,
writer exclusion, acknowledged stop, moved control directories, diagnostic
markers, malformed assets and charger/reboot-marker isolation.

After installing matching images, check cold boot, USB-connected normal reboot,
manual generation selection, charging-only boot, Esc/diagnostics, and desktop
handoff. Confirm no visible log flashes, no surviving animation writer, working
volume/power controls and healthy sensor/display-manager services. Charging must
retain the original battery, eight-second blanking and power-key wakeup.

```sh
systemctl status sheng-boot-splash display-manager --no-pager
journalctl -b -u sheng-boot-splash --no-pager
pgrep -af 'sheng-fb-painter.*--animate'
systemctl --failed --no-pager
cat /sys/class/tty/tty0/active
```
