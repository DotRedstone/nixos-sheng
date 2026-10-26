#!/usr/bin/env bash

# ---
# Module: Sheng Linux rootfs probe initrd
# Description: Builds a temporary initrd that enters an isolated Linux rootfs image on Sheng.
# Scope: Script
# Notes:
# - This is an experimental short boot probe, not a persistent system installer.
# - The selected image is mounted read-only; only stage markers are written to the existing linux partition.
# ---
set -euo pipefail

if [[ $# != 3 ]]; then
  echo "Usage: $0 ALPINE_MINIROOTFS_TAR_GZ PROBE_ID OUTPUT_INITRD_GZ" >&2
  exit 2
fi

source_tar=$1
probe_id=$2
output=$3
expected_sha=4d3f80afaebd447c5591a63a73bde380a149fe8b2d85488cafabb2ff97551f50

[[ $probe_id =~ ^[a-z][a-z0-9-]{0,31}$ ]] || {
  echo 'PROBE_ID must be 1-32 lowercase letters, digits or hyphens and start with a letter' >&2
  exit 2
}
for command in cpio find gzip mktemp sed sha256sum tar; do
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
temporary_output=$(mktemp "$output_dir/.linux-rootfs-probe.XXXXXX")
trap 'rm -rf -- "$scratch"; rm -f -- "$temporary_output"' EXIT
mkdir "$scratch/rootfs"
tar -xzf "$source_tar" --no-same-owner --same-permissions -C "$scratch/rootfs"

cat > "$scratch/init.template" <<'INIT'
#!/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH
probe_id=PROBE_ID_PLACEHOLDER

fail() {
  printf 'Sheng rootfs probe %s failed: %s\n' "$probe_id" "$1" > /dev/console
  sync
  sleep 3
  reboot -f
  while :; do sleep 60; done
}

mount -t devtmpfs devtmpfs /dev || fail devtmpfs
mount -t proc proc /proc || fail proc
mount -t sysfs sysfs /sys || fail sysfs

# devtmpfs does not create udev's /dev/disk/by-partlabel links.
linux_device=
for info in /sys/class/block/*/uevent; do
  if grep -qx 'PARTNAME=linux' "$info"; then
    linux_device=${info%/uevent}
    linux_device=${linux_device##*/}
    break
  fi
done
[ -n "$linux_device" ] || fail linux-partition

mkdir -p /host /newroot
mount -t ext4 -o rw,nosuid,nodev "/dev/$linux_device" /host || fail host-mount
probe_dir=/host/var/lib/sheng-multiboot
mkdir -p "$probe_dir" || fail probe-dir
printf 'stage=host-mounted\n' > "$probe_dir/$probe_id.stage" || fail stage-marker
image=$probe_dir/$probe_id.img
[ -f "$image" ] && [ ! -L "$image" ] || fail rootfs-image
losetup -r /dev/loop0 "$image" || fail loop
mount -t ext4 -o ro /dev/loop0 /newroot || fail rootfs-mount
printf 'stage=rootfs-mounted\n' >> "$probe_dir/$probe_id.stage" || fail stage-marker
[ -x /newroot/init ] || fail rootfs-init
for path in host dev proc sys; do
  [ -d "/newroot/$path" ] || fail "missing-$path"
done
printf 'stage=ready-switch\n' >> "$probe_dir/$probe_id.stage" || fail stage-marker
sync
mount -o move /host /newroot/host || fail move-host
mount -o move /dev /newroot/dev || fail move-dev
mount -o move /proc /newroot/proc || fail move-proc
mount -o move /sys /newroot/sys || fail move-sys
exec switch_root -c /dev/console /newroot /init
INIT
sed "s/PROBE_ID_PLACEHOLDER/$probe_id/" "$scratch/init.template" > "$scratch/rootfs/init"
chmod 0755 "$scratch/rootfs/init"
(
  cd "$scratch/rootfs"
  find . -print0 | cpio --null -o -H newc --owner=0:0 --quiet | gzip -9 > "$temporary_output"
)
gzip -t "$temporary_output"
chmod 0644 "$temporary_output"
mv -f -- "$temporary_output" "$output"
sha256sum "$output"
