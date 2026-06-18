# TODO

[English](TODO.md) | [简体中文](TODO_zh.md)

This file tracks high-level Xiaomi Pad 6S Pro 12.4 (`xiaomi-sheng`) NixOS port
status. The detailed Chinese hardware-alignment matrix is kept in
[`TODO_zh.md`](TODO_zh.md).

The goal is not to develop every missing driver from scratch. The current
priority is to keep the NixOS port aligned with already-known sheng hardware
support, document what has been verified, and keep release blockers visible.

## Legend

- `[x]` Verified on NixOS
- `[~]` Partially working or needs broader validation
- `[ ]` Needs work
- `[-]` Out of scope for the current stage

## Core System

- [x] Boots into NixOS from the Mobile NixOS Android boot flow.
- [x] Writable root filesystem on the dedicated `linux` partition.
- [x] `/run/current-system` and `/nix/var/nix/profiles/system` exist.
- [x] `nix`, `nixos-rebuild`, `systemctl`, and Home Manager CLI are available.
- [x] Public flake constructors are available for downstream dotfiles:
  `mkShengSystem`, `mkShengGnomeSystem`, and the compatibility alias
  `mkShengMinimalSystem`.
- [x] A private downstream flake has been evaluated and activated through the
  public `mkShengSystem` constructor.
- [x] Stage-2 NixOS generation switching and rollback have been verified.
- [x] Stage-1 boot generation menu works with volume/power keys and external
  arrow/Enter keys.
- [~] Kernel, DTS, stage-1 initrd, and boot command-line changes still require
  rebuilding and flashing `boot_b`; `nixos-rebuild` only updates stage-2.

## Desktop and Input

- [x] GNOME rootfs boots with GDM and GNOME Shell.
- [x] `gjs-osk` on-screen keyboard is integrated for touch input.
- [x] Physical power key toggles display on/off without entering suspend.
- [x] Four-way automatic rotation works, including rotated touch coordinates.
- [x] Hall-cover close/open blanks and redraws the display without exposing
  `SW_LID` to GNOME.
- [x] GNOME automatic ambient-light brightness and idle dimming are disabled to
  avoid unexpected brightness changes.
- [~] Floating on-screen keyboard behavior still needs long-term validation
  across more applications.

## Firmware and Remoteproc

- [x] `sheng-firmware` is present in `/lib/firmware`.
- [x] ADSP and CDSP remoteproc can start.
- [x] GPU firmware loads.
- [x] `msm/adsp/charger_pd` can become available through PDR.
- [x] `ucsi_glink` can register Type-C.
- [x] `pd-mapper` firmware preparation is limited to `qcom/sm8550/sheng`,
  reducing avoidable `/run` usage by roughly 500 MiB on tested GNOME systems.

## Hardware Status

- [x] Display panel and DRM nodes enumerate.
- [x] Touchscreen works through the Novatek driver and firmware.
- [x] Backlight sysfs nodes exist and manual brightness control works.
- [x] Wi-Fi works on 2.4 GHz and 5 GHz after the known post-flash warm reboot.
- [x] USB-C Type-C role detection and OTG host mode work.
- [x] Sensors are available through Qualcomm SSC user space and
  `iio-sensor-proxy` D-Bus: accelerometer, proximity, ambient light, compass.
- [x] Camera sensors and CAMSS can capture RAW10 frames through V4L2.
- [x] Xiaomi 120W MiPPS authentication can unlock the fast-charging profile.
- [x] MiPPS authentication now retries when early power-supply events arrive
  before `real_type`, `adapter_svid`, or `pdo2` are ready.
- [~] Bluetooth controller enumerates; pairing, reconnect, and audio need more
  validation.
- [~] ALSA card and playback/capture PCM devices enumerate; real playback and
  recording need broader validation.
- [~] Sustained charging power, charger compatibility, and thermal behavior
  need longer testing with an external USB-C power meter.
- [~] Official keyboard, touchpad, and stylus authentication remain incomplete.
- [-] Fingerprint is unsupported because it depends on proprietary Qualcomm
  TEE/TrustZone behavior with no open Linux solution.

## Release Blockers

- [x] English and Simplified Chinese README files are present.
- [x] Docs follow the repository convention: default `.md` is English and
  `_zh.md` is Simplified Chinese.
- [x] Release notes are available in English and Simplified Chinese.
- [x] Dual-boot installation docs are available in English and Simplified
  Chinese.
- [x] Third-party notices document upstream projects, proprietary firmware, and
  rights-holder review path.
- [x] Rootfs release assets use Windows-friendly split ZIP archives.
- [x] Checksum verification remains optional but documented.
- [ ] Boot, minimal rootfs, and GNOME rootfs artifacts for the next release
  must come from the same release commit.

## Future Improvements

- Expand the ext4 filesystem to the full `linux` partition and validate
  long-term device-side `nixos-rebuild` usage.
- Validate real multi-generation selection through the stage-1 boot menu after
  the filesystem has enough space for more generations.
- Improve desktop camera integration through libcamera or another suitable
  userspace stack.
- Validate Bluetooth pairing/audio and ALSA playback/recording.
- Continue charging compatibility and thermal testing across chargers and
  cables.
- Investigate kernel IIO exposure only if strict `/sys/bus/iio/devices`
  compatibility becomes necessary; the current SSC + D-Bus path works for the
  desktop.
