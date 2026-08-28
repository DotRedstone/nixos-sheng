# Third-party notices

This repository combines original integration code with independently
licensed upstream software and device-specific binary firmware. The top-level
MIT license applies only to original project material authored by DotRedstone.
It does not relicense third-party material.

## Source dependencies

| Component | Source | License/status |
| --- | --- | --- |
| Mobile NixOS | https://github.com/mobile-nixos/mobile-nixos | MIT |
| Nixpkgs | https://github.com/NixOS/nixpkgs | Mixed; see upstream package metadata |
| Home Manager | https://github.com/nix-community/home-manager | MIT |
| Sheng Linux kernel | https://github.com/DotRedstone/linux-sheng | GPL-2.0-only Linux kernel terms; forked from `map220v/sm8550-mainline` |
| MiPPS authentication script | https://github.com/ianchb/xiaomi-mipps-auth | GPL-2.0-only, as declared by its source SPDX header |
| GJS OSK | https://github.com/Vishram1123/gjs-osk | GPL-3.0 |
| FastRPC | https://github.com/qualcomm/fastrpc | BSD-3-Clause |
| QRTR | https://github.com/linux-msm/qrtr | BSD-3-Clause |
| PD Mapper | https://github.com/linux-msm/pd-mapper | BSD-3-Clause |
| libssc | https://codeberg.org/DylanVanAssche/libssc | Source files predominantly declare AGPL-3.0-or-later; exact vendored origin is recorded in `nixos/vendor/libssc/ORIGIN.md` |
| Xiaomi Sheng THP | https://github.com/ianchb/xiaomi-sheng-thp | Apache-2.0 |
| Sheng sensor configuration | https://github.com/alghiffaryfa19/sheng-sensors-file | No upstream license published; treated as unfree |

Kernel source modifications remain subject to the Linux kernel's GPL-2.0-only
terms and any copyright notices embedded in the source.

The complete corresponding project source, Nix expressions, downstream
patches, and vendored libssc source used to build a release are available from
the Git tag associated with that release.

## Proprietary firmware and binaries

`DotRedstone/sheng-firmware-full` contains device firmware, Android vendor
libraries, configuration data, and executables originating from Xiaomi,
Qualcomm, component vendors, or device images. These files are not covered by
this repository's MIT license. Their copyright and redistribution terms remain
with their respective owners.

The factory NT36532E firmware used by the THP pipeline is fetched from
`ianchb/sheng-firmware` at a fixed revision and is subject to the same
proprietary firmware terms.

The public rootfs and boot images may include redistributable firmware selected
by Nixpkgs as well as device-specific proprietary files from
`sheng-firmware-full`. Publication of a file in a repository does not itself
grant redistribution permission. Distributors are responsible for confirming
that they have permission to redistribute every included binary in their
jurisdiction.

For the lowest redistribution risk, do not redistribute prebuilt rootfs or
boot images containing proprietary files. Build from source while supplying
firmware extracted from a device you own, and distribute only the original
project source and patches.

## Rights-holder notices

If you are a rights holder and believe that material in this repository or in
published release artifacts infringes your rights, please open a GitHub issue
or contact the repository owner through GitHub with enough information to
identify the affected file, the right being asserted, and the requested action.
The project maintainer will review good-faith requests and remove or replace
affected material when appropriate.

This notice is a practical contact path for rights holders. It does not state
or imply that every third-party file is owned by this project or that every
redistribution right has been granted.

## Warranty and device risk

This project, including source code, instructions, boot images, rootfs images,
and other release artifacts, is provided without warranty. Flashing low-level
device partitions can brick hardware, break Android boot, or destroy data.
Users and downstream distributors are responsible for verifying legality,
fitness, safety, and compatibility before use or redistribution.

## No endorsement

Xiaomi, Qualcomm, Snapdragon, and other names and marks belong to their
respective owners. This community project is not affiliated with or endorsed
by those companies.
