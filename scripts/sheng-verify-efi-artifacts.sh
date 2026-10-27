#!/usr/bin/env bash

# ---
# Module: Sheng EFI Artifact Verification
# Description: Verifies that downloaded boot and ESP artifacts belong to one reviewed commit
# Scope: Script
# ---
set -euo pipefail

usage() {
  echo "Usage: $0 BOOT_ARTIFACT_DIR ESP_ARTIFACT_DIR EXPECTED_COMMIT_SHA" >&2
  exit 2
}

die() {
  echo "EFI artifact verification failed: $*" >&2
  exit 1
}

[[ $# == 3 ]] || usage
boot_dir=$1
esp_dir=$2
expected_sha=$3
[[ $expected_sha =~ ^[0-9a-f]{40}$ ]] || die "expected commit must be a 40-character lowercase SHA"

boot_img="$boot_dir/sheng-u-boot-experimental-boot_b/sheng-u-boot-experimental-boot_b.img"
boot_sum="$boot_img.sha256"
boot_revision="$boot_img.source-revision"
esp="$esp_dir/sheng-uboot-efi-esp/esp"
esp_manifest="$esp/manifest.sha256"
esp_sum="$esp_dir/sheng-uboot-efi-esp.manifest.sha256"
esp_revision="$esp_dir/sheng-uboot-efi-esp.source-revision"

for path in "$boot_img" "$boot_sum" "$boot_revision" "$esp_manifest" "$esp_sum" "$esp_revision"; do
  [[ -s $path && ! -L $path ]] || die "missing, empty, or symbolic-link file: $path"
done
[[ ! -L $esp ]] || die "ESP tree must not be a symbolic link"
if find "$esp" -type l -print -quit | grep -q .; then
  die "ESP tree contains symbolic links"
fi

boot_sha=$(tr -d '\n' < "$boot_revision")
esp_sha=$(tr -d '\n' < "$esp_revision")
[[ $boot_sha == "$expected_sha" && $esp_sha == "$expected_sha" ]] ||
  die "boot and ESP source revisions must both equal $expected_sha"

read -r recorded_boot_hash recorded_boot_name < "$boot_sum"
[[ $recorded_boot_hash =~ ^[0-9a-f]{64}$ ]] || die "invalid boot SHA-256 record"
[[ $recorded_boot_name == out/sheng-u-boot-experimental-boot_b.img ]] ||
  die "unexpected boot SHA-256 filename"
actual_boot_hash=$(sha256sum "$boot_img")
[[ ${actual_boot_hash%% *} == "$recorded_boot_hash" ]] || die "boot image SHA-256 mismatch"

read -r recorded_manifest_hash recorded_manifest_name < "$esp_sum"
[[ $recorded_manifest_hash =~ ^[0-9a-f]{64}$ ]] || die "invalid ESP manifest SHA-256 record"
[[ $recorded_manifest_name == out/sheng-uboot-efi-esp/esp/manifest.sha256 ]] ||
  die "unexpected ESP manifest SHA-256 filename"
actual_manifest_hash=$(sha256sum "$esp_manifest")
[[ ${actual_manifest_hash%% *} == "$recorded_manifest_hash" ]] || die "ESP manifest SHA-256 mismatch"

(cd "$esp" && sha256sum --quiet -c manifest.sha256) || die "ESP payload SHA-256 mismatch"

mapfile -t entries < <(find "$esp/loader/entries" -maxdepth 1 -type f \
  -name 'nixos-sheng-*.conf' -printf '%f\n' | sort)
[[ ${#entries[@]} == 1 ]] || die "expected one immutable Sheng EFI entry"
entry=${entries[0]}
awk -v entry="$entry" '$1 == "default" && $2 == entry { found = 1 } END { exit !found }' \
  "$esp/loader/loader.conf" || die "ESP default does not select the immutable entry"
version=${entry#nixos-sheng-}
version=${version%.conf}
[[ $version =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid EFI payload ID"
payload="EFI/NixOS/sheng-$version"
for field in \
  "linux /$payload/linux" \
  "initrd /$payload/initrd" \
  "devicetree /$payload/sm8550-xiaomi-sheng.dtb"; do
  grep -Fxq "$field" "$esp/loader/entries/$entry" || die "entry is missing: $field"
done
[[ -s $esp/$payload/kernel.store-path ]] || die "missing kernel closure identity"
kernel_path=$(cat "$esp/$payload/kernel.store-path")
[[ $kernel_path =~ ^/nix/store/[a-z0-9]{32}-linux-[A-Za-z0-9._+-]+$ ]] ||
  die "invalid kernel closure identity"

printf 'Commit: %s\nBoot SHA-256: %s\nESP manifest SHA-256: %s\nKernel: %s\nEntry: %s\n' \
  "$expected_sha" "$recorded_boot_hash" "$recorded_manifest_hash" "$kernel_path" "$entry"
