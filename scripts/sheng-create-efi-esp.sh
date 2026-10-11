#!/bin/sh

# ---
# Module: Sheng EFI ESP Provisioner
# Description: Shrinks only Sheng's Linux partition tail and creates its EFI system partition.
# Scope: Script
# ---

set -eu

disk=/dev/sda
linux_partition=/dev/sda30
esp_partition=/dev/sda31
backup=/run/sheng-sda-gpt-before-efi-esp.sfdisk

# The recovery image uses the UFS device's native 4 KiB logical sectors.
expected_disk_bytes=262173360128
expected_sector_size=4096
expected_gpt_sha256=22b99acd1b885facf1beaf2e4250873deccd87eb55aee4d3359975b01373d85c
expected_linux_fs_uuid=ee8d3593-59b1-480e-a3b6-4fefb17ee7d8
expected_linux_start=43628032
expected_linux_size=20379131
new_linux_size=20116987
esp_start=63745019
esp_size=262144
esp_type=C12A7328-F81F-11D2-BA4B-00A0C93EC93

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

assert_eq() {
  [ "$1" = "$2" ] || die "$3 (expected $2, got $1)"
}

[ "${1:-}" = --apply ] && [ "$#" -eq 1 ] || die "usage: $0 --apply"

for command in awk blkid blockdev cmp e2fsck grep id mkfs.fat partx resize2fs sed seq sfdisk sha256sum sleep sync tr; do
  require "$command"
done

[ "$(id -u)" -eq 0 ] || die "must run as root"
[ -b "$disk" ] || die "missing disk: $disk"
[ -b "$linux_partition" ] || die "missing Linux partition: $linux_partition"
[ ! -e "$esp_partition" ] || die "$esp_partition already exists"

if grep -Eq "(^|[[:space:]])(/dev/sda30|/dev/disk/by-partlabel/linux)([[:space:]]|$)" /proc/mounts; then
  die "$linux_partition is mounted"
fi

assert_eq "$(blockdev --getsize64 "$disk")" "$expected_disk_bytes" "unexpected disk size"
assert_eq "$(blockdev --getss "$disk")" "$expected_sector_size" "unexpected logical sector size"
assert_eq "$(blkid -o value -s UUID "$linux_partition")" "$expected_linux_fs_uuid" "unexpected Linux filesystem UUID"

sfdisk --verify "$disk"
sfdisk --dump "$disk" > "$backup"
assert_eq "$(sha256sum "$backup" | awk '{print $1}')" "$expected_gpt_sha256" "unexpected GPT layout"

linux_line=$(grep '^/dev/sda30 :' "$backup" | tr -d ' ')
case "$linux_line" in
  *"start=$expected_linux_start"*"size=$expected_linux_size"*'name="linux"'*) ;;
  *) die "unexpected Linux partition boundary" ;;
esac

printf '%s\n' "Preflight passed; backing up GPT to $backup"

# A clean read-only check happens before the repair-capable check.  -p aborts
# rather than making speculative repairs, so an unexpected filesystem state
# cannot silently turn into a destructive operation.
e2fsck -fn "$linux_partition"
e2fsck -fp "$linux_partition"

resize2fs "$linux_partition" "$new_linux_size"
e2fsck -fn "$linux_partition"

# Update only entry 30 in place.  sfdisk preserves its start, type, UUID, and
# label; the following assertions reject any other pre-existing GPT layout.
printf ',%s\n' "$new_linux_size" | sfdisk --no-reread --force -N 30 "$disk"
partx --update "$disk"
sfdisk --verify "$disk"

after_shrink=/run/sheng-sda-gpt-after-shrink.sfdisk
sfdisk --dump "$disk" > "$after_shrink"
grep '^/dev/sda[1-29] :' "$backup" > /run/sheng-protected-before
grep '^/dev/sda[1-29] :' "$after_shrink" > /run/sheng-protected-after
cmp /run/sheng-protected-before /run/sheng-protected-after || die "a protected GPT entry changed"

shrunk_line=$(grep '^/dev/sda30 :' "$after_shrink" | tr -d ' ')
case "$shrunk_line" in
  *"start=$expected_linux_start"*"size=$new_linux_size"*'name="linux"'*) ;;
  *) die "Linux partition was not resized as expected" ;;
esac

printf 'start=%s, size=%s, type=%s, name="linux-boot"\n' \
  "$esp_start" "$esp_size" "$esp_type" | sfdisk --append "$disk"
partx --add --nr 31 "$disk" || true

for attempt in $(seq 1 10); do
  [ -b "$esp_partition" ] && break
  sleep 1
done
[ -b "$esp_partition" ] || die "kernel did not expose $esp_partition"

mkfs.fat -F 32 -n linux-boot "$esp_partition"
assert_eq "$(blkid -o value -s TYPE "$esp_partition")" vfat "EFI partition format failed"
assert_eq "$(blkid -o value -s LABEL "$esp_partition")" linux-boot "EFI partition label failed"

sfdisk --verify "$disk"
sync
printf '%s\n' "EFI ESP created successfully: $esp_partition"
