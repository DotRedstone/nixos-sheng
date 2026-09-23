# Release readiness

[English](release-readiness.md) | [简体中文](release-readiness_zh.md)

This is the release gate for `nixos-sheng`. It distinguishes source review,
hardware validation, and artifact provenance. A successful build is not by
itself a release approval.

## Current decision

**v0.3.0 was published from reviewed commit `25c8463`.** Normal boot, the
manual generation-selection handoff, source review, and automated artifact
provenance/filesystem gates passed. Items that remain unchecked are documented
validation or redistribution gaps, not claims of verified support.

## Source gates

- [x] Merged `linux-sheng:feat/stylus-thp` into the maintained 7.1.8 branch via
  PR #1 and locked `shengKernelSrc` to that maintained ref.
- [x] Reviewed the current NixOS audit branch in PR #25 and confirmed there
  were no unrelated branch renames or history rewrites.
- [x] `nix flake lock ./nixos` produces no unexpected lock drift.
- [x] `nix flake check ./nixos --no-build` passes.
- [x] Generation-menu Ruby syntax, renderer bounds, command stream, paging,
  key-repeat, and pending-selection tests pass.
- [x] `git diff --check`, Markdown links, YAML parsing, license/notices, and a
  tracked-file credential scan pass.

## Hardware gates

Use the exact release-candidate boot and rootfs commit.

- [ ] Three normal boots complete with zero failed units and no new coredumps.
- [x] Stay in the generation menu for at least 15 seconds, choose an older
  generation, and verify exactly one quick reboot followed by a menu skip.
- [x] `adsprpcd-sensorspd` and `iio-sensor-proxy` are active with
  `NRestarts=0`; direct SSC queries work.
- [x] Root is writable, ext4 is clean, `errors_count=0`, and no UFS reset,
  timeout, abort, or block I/O error appears.
- [ ] 2.4 GHz and 5 GHz Wi-Fi connect without a required reboot. Preserve logs
  before reboot if the rare post-flash 5 GHz issue occurs.
- [ ] Standard PD and MiPPS are tested separately; USB data-port charging is
  reported separately from charger-only behavior.
- [ ] After a full power-off, inserting a charger enters the offline charging
  target without starting the desktop; short power-key press wakes the battery
  UI, long press starts GNOME, and unplugging powers the tablet off.
- [ ] Speaker playback/restart and microphone recording work; WirePlumber has
  no new coredump.
- [ ] Touch, rotation, cover, Focus Pen pressure/tilt/buttons, fingerprint
  enrollment/verification, and screen-off wake are checked.
- [ ] Front/rear RAW capture still works and CAMSS returns to runtime suspend.

Suggested capture:

```sh
sudo scripts/collect-hardware-baseline.sh 10 > sheng-release-health.txt
systemctl --failed --no-pager
coredumpctl list --since boot
systemctl show adsprpcd-sensorspd iio-sensor-proxy \
  -p Id -p ActiveState -p NRestarts
sheng-rootfs-status
```

Review the output manually before making it public; automated redaction does
not replace a privacy check.

## Artifact gates

- [x] Kernel, minimal rootfs, and GNOME rootfs workflow runs all have the same
  `headSha`, matching the reviewed merge commit.
- [x] The boot image is smaller than the `boot_b` partition and its module
  archive has the same `modDirVersion`.
- [x] Rootfs images pass read-only `e2fsck` and contain `metadata_csum`, `64bit`,
  and `dir_index`.
- [ ] Release archives extract to directly flashable images; every asset is in
  `sha256sums.txt`.
- [x] Release assets include `LICENSE` and `THIRD_PARTY_NOTICES.md`.
- [x] Rootfs candidates use strong yescrypt password hashes, never repository
  development passwords or plaintext workflow inputs.
- [ ] Firmware and proprietary binary redistribution has been reviewed for the
  actual artifact contents.

## Evidence recorded on 2026-08-30

A normal boot using commit `0151b29`'s boot image completed in 21.066 seconds:
9.075 seconds kernel plus 11.990 seconds userspace; `graphical.target` was
reached after 11.006 seconds userspace. The system was `running`, had zero
failed units, and both SSC services were active with `NRestarts=0`.

A separate boot with the old behavior spent about 29 seconds in
`Tasks::SwitchRoot` after a roughly 0.18-second `e2fsck -p`. It then reproduced
missing SSC QMI service and repeated sensor daemon restarts.

On 2026-08-30, commit `86c2b22`'s boot image passed the fixed-path regression.
The first boot remained in the menu for about 24 seconds before manual
confirmation, then performed exactly one quick reboot. The second boot skipped
the menu and removed the one-shot selection marker. It completed in 18.075
seconds, with `graphical.target` reached after 11.216 seconds userspace. The
system was `running`, had zero failed units and no coredump, mounted root as
writable ext4 with `errors_count=0`, and kept `adsprpcd`, `pd-mapper`,
`adsprpcd-sensorspd`, and `iio-sensor-proxy` active with `NRestarts=0`. This
clears the handoff's device-validation blocker, but does not replace the final
merged-artifact regression.

The v0.3.0 artifacts were built from merge commit `25c8463` by kernel run
`33312231001`, minimal-rootfs run `33312236690`, and GNOME-rootfs run
`33312241560`. Release run `33315331473` verified the shared commit, checked and
shrunk both ext4 images, generated split ZIP archives and checksums, and
published nine uploaded assets. Full end-user extraction of every split archive
and proprietary-binary redistribution review remain explicitly open above.
