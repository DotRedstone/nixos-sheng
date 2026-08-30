# Release readiness

[English](release-readiness.md) | [简体中文](release-readiness_zh.md)

This is the release gate for `nixos-sheng`. It distinguishes source review,
hardware validation, and artifact provenance. A successful build is not by
itself a release approval.

## Current decision

**Not ready to publish a new release yet.** The normal-boot candidate is healthy,
but the manual generation-selection handoff must be built and verified on the
tablet. Kernel and NixOS feature branches also need to be merged before final
artifacts are produced.

## Source gates

- [ ] Merge `linux-sheng:feat/stylus-thp` into the maintained 7.1.8 branch and
  lock `shengKernelSrc` to that maintained ref.
- [ ] Open and review a pull request from the current NixOS audit branch to
  `sheng`; confirm no unrelated branch renames or history rewrites.
- [ ] `nix flake lock ./nixos` produces no unexpected lock drift.
- [ ] `nix flake check ./nixos --no-build` passes.
- [ ] Generation-menu Ruby syntax, renderer bounds, command stream, paging,
  key-repeat, and pending-selection tests pass.
- [ ] `git diff --check`, Markdown links, YAML parsing, license/notices, and a
  tracked-file credential scan pass.

## Hardware gates

Use the exact release-candidate boot and rootfs commit.

- [ ] Three normal boots complete with zero failed units and no new coredumps.
- [ ] Stay in the generation menu for at least 15 seconds, choose an older
  generation, and verify exactly one quick reboot followed by a menu skip.
- [ ] `adsprpcd-sensorspd` and `iio-sensor-proxy` are active with
  `NRestarts=0`; direct SSC queries work.
- [ ] Root is writable, ext4 is clean, `errors_count=0`, and no UFS reset,
  timeout, abort, or block I/O error appears.
- [ ] 2.4 GHz and 5 GHz Wi-Fi connect without a required reboot. Preserve logs
  before reboot if the rare post-flash 5 GHz issue occurs.
- [ ] Standard PD and MiPPS are tested separately; USB data-port charging is
  reported separately from charger-only behavior.
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

- [ ] Kernel, minimal rootfs, and GNOME rootfs workflow runs all have the same
  `headSha`, matching the reviewed merge commit.
- [ ] The boot image is smaller than the `boot_b` partition and its module
  archive has the same `modDirVersion`.
- [ ] Rootfs images pass read-only `e2fsck` and contain `metadata_csum`, `64bit`,
  and `dir_index`.
- [ ] Release archives extract to directly flashable images; every asset is in
  `sha256sums.txt`.
- [ ] Release assets include `LICENSE` and `THIRD_PARTY_NOTICES.md`.
- [ ] Rootfs candidates use strong yescrypt password hashes, never repository
  development passwords or plaintext workflow inputs.
- [ ] Firmware and proprietary binary redistribution has been reviewed for the
  actual artifact contents.

## Evidence recorded on 2026-08-30

A normal boot using commit `0151b29`'s boot image completed in 21.066 seconds:
9.075 seconds kernel plus 11.990 seconds userspace; `graphical.target` was
reached after 11.006 seconds userspace. The system was `running`, had zero
failed units, and both SSC services were active with `NRestarts=0`.

A separate boot spent about 29 seconds in `Tasks::SwitchRoot` after a roughly
0.18-second `e2fsck -p`. It then reproduced missing SSC QMI service and repeated
sensor daemon restarts. This is why the unverified manual-selection handoff is
a release blocker rather than a documentation-only change.
