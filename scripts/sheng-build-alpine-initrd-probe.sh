#!/usr/bin/env bash

# ---
# Module: Sheng Alpine initrd probe
# Description: Builds a temporary Alpine userland boot probe for the existing Sheng EFI kernel.
# Scope: Script
# Notes:
# - The output is an initrd, not an Android boot image or an installed Linux rootfs.
# - The probe writes only a small result marker to the existing linux partition.
# ---
set -euo pipefail

if [[ $# != 2 ]]; then
  echo "Usage: $0 ALPINE_MINIROOTFS_TAR_GZ OUTPUT_INITRD_GZ" >&2
  exit 2
fi

source_tar=$1
output=$2
expected_sha=4d3f80afaebd447c5591a63a73bde380a149fe8b2d85488cafabb2ff97551f50

for command in cpio find gzip sha256sum tar; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "missing command: $command" >&2
    exit 1
  }
done

[[ -f $source_tar && ! -L $source_tar ]] || {
  echo "missing or symbolic-link Alpine archive: $source_tar" >&2
  exit 1
}
actual_sha=$(sha256sum "$source_tar")
[[ ${actual_sha%% *} == "$expected_sha" ]] || {
  echo "Alpine 3.24.3 aarch64 archive SHA-256 mismatch" >&2
  exit 1
}

output_dir=$(dirname -- "$output")
[[ -d $output_dir ]] || {
  echo "output directory does not exist: $output_dir" >&2
  exit 1
}
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/rootfs"
tar -xzf "$source_tar" --no-same-owner --same-permissions -C "$scratch/rootfs"

cat > "$scratch/rootfs/init" <<'INIT'
#!/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

mount -t devtmpfs devtmpfs /dev || reboot -f
mount -t proc proc /proc || reboot -f
mount -t sysfs sysfs /sys || reboot -f
printf 'Sheng Linux probe: Alpine %s on kernel %s\n' "$(cat /etc/alpine-release)" "$(uname -r)" > /dev/console

# devtmpfs does not create udev's /dev/disk/by-partlabel links.
linux_device=
for info in /sys/class/block/*/uevent; do
  if grep -qx 'PARTNAME=linux' "$info"; then
    linux_device=${info%/uevent}
    linux_device=${linux_device##*/}
    break
  fi
done
if [ -n "$linux_device" ]; then
  mkdir -p /mnt/nixos
  if mount -t ext4 -o rw,nosuid,nodev,noexec "/dev/$linux_device" /mnt/nixos; then
    mkdir -p /mnt/nixos/var/lib/sheng-multiboot
    printf 'alpine=%s\nkernel=%s\n' "$(cat /etc/alpine-release)" "$(uname -r)" \
      > /mnt/nixos/var/lib/sheng-multiboot/alpine-initrd-probe
    sync
    umount /mnt/nixos
  fi
fi
printf 'Probe complete; returning to the default boot entry in 10 seconds.\n' > /dev/console
sleep 10
reboot -f
INIT
chmod 0755 "$scratch/rootfs/init"

temporary_output=$(mktemp "$output_dir/.alpine-initrd.XXXXXX")
trap 'rm -rf -- "$scratch"; rm -f -- "$temporary_output"' EXIT
(
  cd "$scratch/rootfs"
  find . -print0 | cpio --null -o -H newc --owner=0:0 --quiet | gzip -9 > "$temporary_output"
)
gzip -t "$temporary_output"
chmod 0644 "$temporary_output"
mv -f -- "$temporary_output" "$output"
sha256sum "$output"
