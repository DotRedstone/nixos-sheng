[🇨🇳 简体中文](AGENTS.md) | [🇬🇧 English](AGENTS_en.md)

# AGENTS.md

This repository is the Mobile NixOS / NixOS port for the Xiaomi Pad 6S Pro 12.4 (`sheng`).

All agents / collaborators MUST read this file before starting any task.
This file is used to constrain development behaviors, flashing boundaries, verification processes, and commit conventions. Specific feature TODOs, roadmaps, and known issues should NOT be written here; they belong in README, docs, TODO.md, or GitHub Issues.

## Basic Principles

* Diagnose first, modify second.
* Prioritize minimal changes.
* Prioritize functional stability.
* Do not perform unrelated refactoring.
* Do not perform unconfirmed large-scale formatting, directory rearranging, or style unifying.
* Do not delete unverified hardware workarounds just to make the code "look clean".
* Do not mix multiple hardware issues in a single patch or commit.
* Determine the impact scope before modifying: boot, rootfs, kernel, firmware, systemd, udev, and desktop environments must be handled separately.

## Branch Conventions

New features, experimental changes, and high-risk hardware fixes must be developed in new branches. Do not trial-and-error directly on stable branches.

Recommended branch naming:

* `feat/...`: New features
* `fix/...`: Bug fixes
* `docs/...`: Documentation
* `exp/...`: Experimental verification
* `cleanup/...`: Cleanups or patch audits
* `wip/...`: Work in progress

Example:

```text
feat/gnome-profile
fix/usbc-firmware-rootfs
docs/flash-guide
exp/wifi-ath12k
cleanup/kernel-patches
```

Experimental branches must explicitly state the risks. Do not default to merging unverified experimental branches into stable branches.

## Commit Conventions

Commit messages must use Chinese, adopting a format similar to Conventional Commits:

```text
<type>(<scope>): <summary>
```

Common types:

* `feat`: New features
* `fix`: Bug fixes
* `docs`: Documentation
* `refactor`: Refactoring
* `cleanup`: Cleanup
* `test`: Testing
* `build`: Build related
* `ci`: CI related
* `chore`: Miscellaneous maintenance

Common scopes:

* `nixos`
* `mobile`
* `kernel`
* `firmware`
* `usbc`
* `wifi`
* `rootfs`
* `docs`

Example:

```text
docs(nixos): 补充 sheng 固件与 USB-C 验证流程
fix(rootfs): 将 sheng 固件注入 /lib/firmware
fix(kernel): 恢复 qcom pd mapper 辅助总线模型
feat(wifi): 启用 WCN7850 驱动支持
cleanup(kernel): 降低 UCSI 调试日志噪音
```

Commit requirements:

* Try to only do one type of thing per commit.
* Do not mix feature fixes, log cleanups, and documentation organization in a single commit.
* Do not commit build artifacts, temporary logs, or runtime caches.
* Do not commit secrets, tokens, cookies, sessions, personal account info, API keys, or raw sensitive logs.
* If logs need to be referenced, keep only the necessary excerpts and remove serial numbers, accounts, keys, network credentials, and other sensitive information.

## flake.lock Rules

Do not update `flake.lock` without a reason.

Updates are only allowed in the following situations:

* Adding, removing, or explicitly upgrading a flake input.
* Fixing a build strictly requires a newer locked version.
* The user explicitly requests an update.
* The documentation or report explicitly states why an update is necessary.

After updating, the reasons and impact must be clearly documented in the report.

## boot / rootfs Boundaries

This project involves both the Android boot image and the Linux rootfs. After every modification, you must clarify which partition needs to be flashed.

General rules:

| Modified Content | Build Target | Flashed Partition |
| --- | --- | --- |
| kernel config | `mobileAndroidBootimg` | `boot_b` |
| kernel patch | `mobileAndroidBootimg` | `boot_b` |
| DTS / DTB | `mobileAndroidBootimg` | `boot_b` |
| initrd / stage-1 | `mobileAndroidBootimg` | `boot_b` |
| boot cmdline | `mobileAndroidBootimg` | `boot_b` |
| firmware | `mobileRootfsImage` | `linux` |
| systemd service | `mobileRootfsImage` | `linux` |
| udev rules | `mobileRootfsImage` | `linux` |
| desktop profile | `mobileRootfsImage` | `linux` |
| ordinary packages | `mobileRootfsImage` | `linux` |
| rootfs layout | `mobileRootfsImage` | `linux` |
| kernel modules in rootfs| `mobileRootfsImage`, build boot if needed | `linux`, flash `boot_b` if needed |

If both kernel and rootfs are modified, you usually need to flash both `boot_b` and `linux`.

Do not flash `userdata` unless explicitly requested and the user understands the risks.

Common build and flash commands:

```bash
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
fastboot flash boot_b out/mobile-bootimg
```

```bash
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
fastboot flash linux out/mobile-rootfs/rootfs.img
```

## Mobile NixOS Special Considerations

Do not assume standard NixOS rootfs behaviors will automatically apply to Mobile NixOS.

Pay special attention to:

* `hardware.firmware` might not automatically appear in the final rootfs under `/lib/firmware`.
* kernel modules might not automatically appear in the final rootfs under `/lib/modules`.
* After modifying firmware or modules, you must check the contents of the final rootfs image.
* Flashing only `boot_b` will not update `/lib/firmware`, `/lib/modules`, systemd, udev, or the desktop environment.
* If the running system already has `nix` / `nixos-rebuild`, you still need to assess rootfs space, profile status, and whether it involves the boot image.

Offline rootfs check example:

```bash
sudo mkdir -p /mnt/sheng-rootfs
sudo mount -o loop,ro out/mobile-rootfs/rootfs.img /mnt/sheng-rootfs

find /mnt/sheng-rootfs/lib/firmware /mnt/sheng-rootfs/usr/lib/firmware -maxdepth 10 -type f 2>/dev/null \
  | sort \
  | head -100

sudo umount /mnt/sheng-rootfs
```

Running system check example:

```sh
find /lib/firmware /usr/lib/firmware -maxdepth 10 -type f 2>/dev/null | sort | head -100
find /lib/modules -type f 2>/dev/null | sort | head -100
ls -la /run/current-system
ls -la /nix/var/nix/profiles/system
```

## Hardware Fix Principles

### USB-C / OTG

USB-C / OTG dependency chain:

```text
sheng-firmware
→ ADSP/CDSP remoteproc
→ msm/adsp/charger_pd
→ PMIC-GLINK / PDR
→ ucsi_glink pd_running=1
→ ucsi_register()
→ /sys/class/typec port appears
→ usb_role can switch to host
```

If `/sys/class/typec` is empty, prioritize checking:

* `/lib/firmware/qcom/sm8550/sheng/`
* ADSP/CDSP remoteproc is started
* `msm/adsp/charger_pd`
* `pd_running`
* `ucsi_register`
* PMIC-GLINK / PDR logs

Do not modify USB HID, DWC3, NetworkManager, or unrelated DTS nodes first.

Common checks:

```sh
ls -la /sys/class/typec
cat /sys/class/usb_role/a600000.usb-role-switch/role

dmesg | grep -Ei 'adsp|cdsp|firmware|charger_pd|pd_running|ucsi|typec|pmic_glink|PDR' | tail -300
```

### Wi-Fi

If there is no `wlan0` or `iw dev` is empty, it means the wireless card hasn't been enumerated or the driver isn't loaded.

Prioritize checking:

* ATH12K / ATH11K / MHI / PCIe related options in kernel config
* If `/lib/modules` contains ath12k / mhi / qmi / qrtr related modules
* If `/lib/firmware/ath12k/...` exists
* PCIe endpoint enumeration
* ath12k / MHI / PCIe logs in dmesg

When there's no wireless interface, do not modify Wi-Fi passwords, wpa_supplicant, or NetworkManager configurations first.

Common checks:

```sh
ip link
iw dev 2>/dev/null || true
rfkill list 2>/dev/null || true

find /lib/modules -type f 2>/dev/null \
  | grep -Ei 'ath12k|ath11k|mhi|qmi|qrtr|wlan' \
  | head -100

find /lib/firmware /usr/lib/firmware -maxdepth 10 -type f 2>/dev/null \
  | grep -Ei 'ath12k|WCN7850|board-2|amss|m3|qca|wlan|wifi' \
  | head -100

dmesg | grep -Ei 'ath12k|ath11k|wcn|wlan|wifi|mhi|pci|pcie|qmi|qrtr|firmware' | tail -300
```

### Kernel patch

Do not arbitrarily delete kernel patches.

Before deleting or cleaning up, a patch audit must be performed:

* What does this patch modify?
* Is it a feature fix, fault tolerance, logging, or a historical workaround?
* Has it been included upstream?
* After deletion, do you need to flash `boot_b` or the rootfs?
* What are the A/B test results?
* What is the rollback method?

Only disable or clean up one patch at a time. Do not delete multiple patches together.

## Verification Requirements

After each modification, you must report:

* Which files were modified
* Why they were modified in this way
* Build commands and results
* Whether it needs to flash `boot_b`, `linux/rootfs`, or both
* Runtime verification commands and results
* Risks
* Rollback methods

Recommended minimum verification commands:

```bash
git status
nix build ./nixos#mobileAndroidBootimg -o out/mobile-bootimg
nix build ./nixos#mobileRootfsImage -o out/mobile-rootfs
```

If only documentation is modified, building can be skipped, but the reason must be stated.

Common runtime checks:

```sh
ls -la /sys/class/typec
cat /sys/class/usb_role/a600000.usb-role-switch/role
ip link
dmesg | grep -Ei 'adsp|cdsp|firmware|charger_pd|pd_running|ucsi|typec|ath12k|mhi|pcie|wlan' | tail -300
```

## Documentation Rules

Working hardware links, flashing methods, known issues, and verification commands must be documented promptly.

Do not leave crucial experiences only in chat logs or temporary notes.

`AGENTS.md` only writes collaboration rules and operational boundaries, not current TODOs.
Current tasks, roadmaps, and known issues should be placed in README, docs, TODO.md, or GitHub Issues.

## Release and Actions Rules

The build artifacts of this project are meant for real flashing usage, so after each modification, the impact scope must be clearly defined and the corresponding build must be triggered.

### Versioning Rules

Use semantic versioning and use alpha / beta tags during the hardware bring-up phase:

* `v0.1.0-alpha.1`: First bootable test image
* `v0.1.0-alpha.N`: Increment after each user-perceivable hardware feature is working
* `v0.1.0-beta.N`: Use when major hardware is basically usable
* `v0.1.0`: Use when it reaches public daily-driver testing standards

Do not publish releases for plain documentation changes, log noise reduction, or minor refactoring.
Consider publishing a new alpha release every time a distinct hardware capability is working, such as Wi-Fi, touch, Bluetooth, audio, sensors, or cameras.

### Artifact Build Rules

Choose the build target according to the modification scope:

| Modification Scope | Actions Build Target | Release Artifacts |
| --- | --- | --- |
| kernel config / patch / DTS / DTB / initrd / cmdline | boot image | `sheng-boot-*.img` |
| firmware / systemd / udev / packages / desktop / rootfs | rootfs image | `sheng-rootfs-*.img.zst` |
| Affects both boot and rootfs | boot + rootfs | Upload both |
| Documentation only | No flashable build | Do not publish release |

After modifying rootfs content, do not only build the boot image.
After modifying kernel modules, firmware, desktop environment, or regular packages, you must build the rootfs.
After modifying kernel config, DTS, or kernel patches, you must build the boot image; if modules also enter the rootfs, the rootfs must also be built.

### Actions Trigger Rules

Regular branches or PRs:

* Can run build checks.
* Can upload temporary artifacts.
* Do not automatically publish GitHub Releases.

Manual workflow_dispatch:

* Can choose to build `boot`, `rootfs`, or `both`.
* Can choose whether to upload artifacts.
* Default does not publish release, unless release/tag parameters are explicitly passed.

Tag pushes:

* `v*` tags can trigger the formal release workflow.
* The release workflow must generate checksum files.
* The release workflow must upload flashing instructions or clearly document the flashing method in the release notes.

### Release Artifact Rules

Releases must contain at least:

* boot image, if this version needs to flash `boot_b`
* rootfs image, if this version needs to flash `linux`
* `sha256sums.txt`
* Brief flashing instructions
* Known issues

Recommended naming:

```text
sheng-v0.1.0-alpha.1-boot.img
sheng-v0.1.0-alpha.1-rootfs-minimal.img.zst
sheng-v0.1.0-alpha.1-sha256sums.txt
```

Do not bundle GNOME or other large desktop environments into the minimal image by default.
If providing a GNOME test image, use a separate artifact:

```text
sheng-v0.1.0-alpha.N-rootfs-gnome.img.zst
```

### Release Notes Must Include

Each release must clearly state:

* Devices applicable to this version
* Currently usable hardware
* Currently unusable hardware
* Which partitions need to be flashed
* Whether the linux partition needs to be resized
* Whether both `boot_b` and `linux` need to be flashed simultaneously
* Rollback methods
* Reminder not to flash `userdata`

### Security Rules

Actions and releases must not contain:

* tokens
* cookies
* sessions
* Personal account information
* Raw sensitive logs
* Android userdata content
* Uncleared debug dumps

All release artifacts must come from reproducible Actions builds or clearly documented local build processes.

## Commit History and Branch Management Rules

This project is in the hardware bring-up phase, and a large number of early commits is normal. Do not forcefully rewrite history that has already been pushed to remote just to make it "look clean".

Principles:

- Public branches pushed to remote should not be force pushed by default.
- After a release/tag is published, do not rewrite history prior to that tag.
- Debug commits from early bring-up can be retained as issue tracking records.
- From the current stage onward, new commits must be clearer and more granular.
- Try to only do one type of thing per commit.
- Do not mix feature fixes, documentation, CI, and log cleanups in a single commit.
- New features and risky changes must be branched.
- Commits can be organized within a feature branch before merging, but do not change the history of public stable branches.
- If using PRs, squash merge or rebase merge is recommended to keep the mainline history clear.
- Release points are distinguished by tags, not by rewriting history to create a "clean start".

Rewriting history is only considered in the following situations:

- Sensitive information like secrets, tokens, cookies, sessions, API keys, or personal accounts appeared in the history.
- Huge build artifacts or binary garbage were mistakenly committed.
- The user explicitly requests rewriting history and acknowledges the risks of a force push.
- The current branch is not yet publicly used and has no release/tag dependencies.

Before rewriting history, you must report:
- Why it must be rewritten
- Which branches/tags will be affected
- Whether releases need to be deleted or rebuilt
- Rollback method
- Whether existing users need to be notified

Recommended future development model:

- `sheng`: Mainline development, retains real bring-up history.
- `stable/v0.1`: Stable branch targeting releases.
- `feat/...`, `fix/...`, `exp/...`: Feature and experimental branches.
- Every usable hardware capability is recorded via release tags, for example `v0.1.0-alpha.1`, `v0.1.0-alpha.2`.
