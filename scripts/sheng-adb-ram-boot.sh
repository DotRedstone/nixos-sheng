#!/usr/bin/env bash

# ---
# Module: Sheng ADB RAM Boot
# Description: Starts fastboot boot before requesting the short-lived ABL fastboot window
# Scope: Script
# ---
set -euo pipefail

if [[ $# != 1 || ! -s $1 ]]; then
  echo "Usage: $0 /path/to/experimental-boot.img" >&2
  exit 2
fi

adb_bin=${ADB:-adb}
fastboot_bin=${FASTBOOT:-fastboot}
adb_serial=${SHENG_ADB_SERIAL:-${ANDROID_SERIAL:-}}
fastboot_serial=${SHENG_FASTBOOT_SERIAL:-}
adb_args=()
fastboot_args=()
if [[ -n $adb_serial ]]; then
  adb_args=(-s "$adb_serial")
fi
if [[ -n $fastboot_serial ]]; then
  fastboot_args=(-s "$fastboot_serial")
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
device_script=/data/local/tmp/sheng-reboot-bootloader.pl

command -v "$adb_bin" >/dev/null 2>&1 || { echo "Missing adb: $adb_bin" >&2; exit 1; }
command -v "$fastboot_bin" >/dev/null 2>&1 || { echo "Missing fastboot: $fastboot_bin" >&2; exit 1; }
"$adb_bin" "${adb_args[@]}" get-state 2>/dev/null | grep -Fxq device || { echo 'No authorized ADB device.' >&2; exit 1; }

"$adb_bin" "${adb_args[@]}" push "$script_dir/../nixos/scripts/sheng-reboot-bootloader.pl" "$device_script" >/dev/null
log=$(mktemp)
boot_pid=
cleanup() {
  if [[ -n $boot_pid ]]; then
    kill "$boot_pid" 2>/dev/null || true
  fi
  rm -f -- "$log"
}
trap cleanup EXIT

# ABL fastboot may enumerate only briefly. Keep the boot request waiting before
# the reboot syscall drops ADB, then use the fastboot result as the proof.
timeout 60 env -u ANDROID_SERIAL "$fastboot_bin" "${fastboot_args[@]}" boot "$1" >"$log" 2>&1 &
boot_pid=$!
"$adb_bin" "${adb_args[@]}" shell "test \"\$(stat -c %s $device_script)\" -gt 1000 && chmod 0700 $device_script && exec perl $device_script" >/dev/null 2>&1 || true
if wait "$boot_pid"; then
  boot_pid=
  cat "$log"
else
  boot_pid=
  cat "$log" >&2
  echo 'RAM boot did not complete in ABL fastboot.' >&2
  exit 1
fi
