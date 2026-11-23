#!/usr/bin/env bash

# ---
# Module: Sheng ADB Reboot Bootloader
# Description: Requests ABL fastboot through the Sheng kernel reboot-mode driver
# Scope: Script
# ---
set -euo pipefail

adb_bin=${ADB:-adb}
fastboot_bin=${FASTBOOT:-fastboot}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
device_script=/data/local/tmp/sheng-reboot-bootloader.pl

die() {
  echo "error: $*" >&2
  exit 1
}

command -v "$adb_bin" >/dev/null 2>&1 || die "missing adb: $adb_bin"
command -v "$fastboot_bin" >/dev/null 2>&1 || die "missing fastboot: $fastboot_bin"

"$adb_bin" get-state 2>/dev/null | grep -Fxq device || die "no authorized ADB device"
"$adb_bin" push "$script_dir/../nixos/scripts/sheng-reboot-bootloader.pl" "$device_script" >/dev/null

# The raw syscall intentionally drops the ADB transport before the remote shell
# can return. A disconnect is therefore expected; fastboot enumeration is the
# success criterion below.
"$adb_bin" shell "chmod 0700 $device_script; exec perl $device_script" >/dev/null 2>&1 || true

for _ in $(seq 1 30); do
  devices=$("$fastboot_bin" devices 2>/dev/null || true)
  if [[ -n $devices ]]; then
    printf '%s\n' "$devices"
    exit 0
  fi
  sleep 1
done

die "ABL fastboot did not enumerate within 30 seconds"
