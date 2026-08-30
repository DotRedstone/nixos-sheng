# TODO

[English](TODO.md) | [简体中文](TODO_zh.md)

This file tracks release-facing work for the Xiaomi Pad 6S Pro 12.4 (`sheng`)
NixOS port. A checked item means it was verified on real hardware, not merely
enabled in a kernel configuration.

## Legend

- `[x]` Verified on sheng
- `[~]` Integrated, but broader or longer testing is still needed
- `[ ]` Not complete
- `[-]` Deliberately out of scope

## Verified Platform

- [x] Mobile NixOS Android boot flow using an inactive `boot` slot and a
  dedicated ext4 `linux` partition.
- [x] Writable rootfs, offline stage-1 fsck/resize, ext4 health monitoring, and
  device-side `nixos-rebuild` generation switching.
- [x] Public desktop-neutral flake constructor, optional GNOME constructor,
  and downstream private-dotfiles activation.
- [x] Stage-1 framebuffer generation menu with three-second automatic boot,
  paged volume/arrow navigation, key hold repeat, and power/Enter confirmation.
- [x] GNOME, gjs-osk, four-way rotation, cover handling, touch input, and power
  key display control.
- [x] 2.4 GHz and 5 GHz Wi-Fi, USB-C role detection/OTG, standard USB-PD, and
  Xiaomi MiPPS authentication.
- [x] Qualcomm SSC accelerometer, proximity, ambient light, and compass through
  `iio-sensor-proxy` D-Bus.
- [x] Front and rear RAW10 camera capture through V4L2/CAMSS.
- [x] NT36532E THP multitouch and Xiaomi Focus Pen pressure, tilt, hover, and
  button events.
- [x] FPC1553 fingerprint discovery, graphical enrollment, and verification
  through the QTEE-backed private libfprint driver.

## Needs More Validation

- [~] Bluetooth controller startup and Focus Pen HID reconnect work; general
  discovery, pairing, Bluetooth audio, and suspend/resume need wider testing.
- [~] ALSA playback and capture devices enumerate and the audio userspace is
  integrated; repeat playback/recording and subjective tuning need controlled
  tests on the release image.
- [~] Xiaomi 120 W MiPPS unlock works, but sustained power depends on battery
  state, temperature, charger, and cable. Publish measured traces rather than a
  guaranteed wattage.
- [~] Computer C-to-C charging follows the USB data-port current limit; improve
  only with evidence that the host and charger firmware allow a higher mode.
- [~] libcamera, automatic exposure, and a polished desktop camera application
  are not complete even though RAW capture works.
- [~] Stylus palm rejection and button mapping should be tested across more
  drawing applications.
- [~] Fingerprint wake-unlock should receive repeated screen-off and
  suspend/resume testing.

## Release Blockers

- [ ] Validate the manual generation-selection reboot handoff on hardware:
  remain in the menu, choose an older generation, then confirm that the next
  boot skips the menu and SSC/IIO both start with `NRestarts=0`.
- [ ] Merge `DotRedstone/linux-sheng:feat/stylus-thp` into the maintained 7.1.8
  branch, then update and lock `shengKernelSrc` to that maintained ref.
- [ ] Merge this audit branch into the default `sheng` branch through a reviewed
  pull request. Do not publish directly from an audit branch.
- [ ] Build boot, minimal rootfs, and GNOME rootfs from the exact same merged
  commit; verify run `headSha`, checksums, boot partition size, matching kernel
  modules, and ext4 features before publishing.
- [ ] Run three normal boots plus one deliberately delayed generation-menu boot
  on the release candidate; retain `systemd-analyze`, failed-unit, coredump,
  SSC, charging, rootfs, and kernel-warning evidence.
- [ ] Review proprietary firmware and binary redistribution for every release.
  Source availability is not redistribution permission.

## Follow-up Work

- [ ] Add libcamera tuning/IPA integration and a desktop camera path.
- [ ] Validate Bluetooth audio profiles and long suspend/resume cycles.
- [ ] Run repeatable speaker and microphone A/B tests with the same
  PipeWire/WirePlumber state and publish the test method.
- [ ] Expand charger/cable/temperature coverage with an external power meter.
- [ ] Decode the remaining Xiaomi proximity payload warning and expose gyro
  only if an application needs it.
- [ ] Improve recovery documentation and automate collection of a sanitized
  release-candidate health bundle.
- [-] A kernel IIO bridge is not required while the SSC + D-Bus path satisfies
  the desktop; revisit only for software that strictly requires IIO sysfs.
