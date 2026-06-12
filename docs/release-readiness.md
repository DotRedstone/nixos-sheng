# Release readiness

This document records the latest release-candidate validation. It does not
replace `TODO.md`; it lists only release blockers and high-signal results.

## Validated through 2026-06-12

- Kernel 7.0.0 boots into the GNOME rootfs.
- Display manager, NetworkManager, NTP, Bluetooth, sensors, Type-C, ALSA, and
  camera media nodes are active or enumerate as documented.
- Accelerometer, ambient light, proximity, and compass values update through
  SSC and `iio-sensor-proxy`.
- `/sys/bus/iio/devices` remains empty. The current working sensor path is SSC
  user space plus D-Bus, not kernel IIO sysfs.
- `switch-to-configuration test` activates the current NixOS system
  successfully.
- Nix, `nixos-rebuild`, the Home Manager CLI, the system profile, and the
  writable Nix store are present.
- 5 GHz NetworkManager scanning and connection were verified at 5180 MHz,
  80 MHz, with networking working.
- Battery and USB power-supply state, DRM, Type-C, ALSA, and camera media nodes
  enumerate.
- Rear S5KJN1 and front OV32D40 RAW10 captures were re-verified at the expected
  15,618,240-byte and 9,987,840-byte frame sizes.
- Bluetooth discovery found nearby devices. Pairing, reconnect, and Bluetooth
  audio remain unverified.
- The one-time boot generation menu appears and physical volume-key navigation
  works.
- The generation menu supports held-key repeat and external arrow/Enter keys.
- Four-way automatic rotation and rotated touch coordinates were verified.
- Hall cover close/open blanks and redraws the display without exposing
  `SW_LID` to GNOME.
- A private downstream flake successfully evaluated and activated through the
  public `mkShengSystem` constructor.
- A second synthetic stage-2 generation was created and activated, then the
  system profile was rolled back and activated successfully. The synthetic
  generation was removed after validation.

## Alpha.2 release blockers

- Publish the validated boot image and GNOME rootfs from the same
  release-candidate commit.
- Verify the release attachments, checksums, and tag after publication.

## Stable release blockers

- Expand the ext4 filesystem offline to the full `linux` partition, then
  validate a full device-side `nixos-rebuild --flake`.
- Build and activate the repository Home Manager configuration once. The
  current flashed image contains the CLI but no Home Manager generation.
- Verify selection and rollback between real stage-2 generations through the
  boot generation menu.
- Implement kernel `iio:device*` nodes if strict kernel IIO acceptance is
  required. The current working sensors use SSC user space plus D-Bus.

## Known issues

- A first attempt to activate a saved 5 GHz connection may report that the
  network cannot be found. Refreshing the full NetworkManager scan before
  activation works. Frequency-directed `iw scan freq ...` is not a reliable
  health check on the current ath12k stack.
- 6 GHz Wi-Fi remains disabled and untested.
- Kernel, DTS, stage-1 initrd, and boot command-line updates still require
  separately flashing `boot_b`.
- Audio playback/recording, Bluetooth pairing/audio, official keyboard/touchpad,
  and desktop camera integration still require broader user-facing validation.
