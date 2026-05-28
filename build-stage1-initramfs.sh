#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-out/kernel/sheng-stage1-initramfs.cpio.gz}"
WORKDIR="$(mktemp -d)"

cleanup() {
    rm -rf "${WORKDIR}"
}
trap cleanup EXIT

if ! command -v busybox >/dev/null 2>&1; then
    echo "busybox is required to build stage-1 initramfs"
    exit 1
fi

mkdir -p "$(dirname "${OUT}")"
mkdir -p "${WORKDIR}/root/bin" "${WORKDIR}/root/dev" "${WORKDIR}/root/proc" \
    "${WORKDIR}/root/sys" "${WORKDIR}/root/newroot"

BUSYBOX="$(command -v busybox)"
cp "${BUSYBOX}" "${WORKDIR}/root/bin/busybox"
chmod +x "${WORKDIR}/root/bin/busybox"

for applet in sh mount umount sleep mkdir mdev switch_root cat dmesg; do
    ln -s busybox "${WORKDIR}/root/bin/${applet}"
done

cat > "${WORKDIR}/root/init" <<'EOF'
#!/bin/sh
export PATH=/bin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev || mdev -s

exec >/dev/console 2>&1
echo "sheng-stage1: waiting for PARTLABEL=linux"
echo "sheng-stage1: waiting for PARTLABEL=linux" > /dev/kmsg

ROOTDEV=""
i=0
while [ "$i" -lt 60 ]; do
    for dev in /dev/disk/by-partlabel/linux /dev/block/by-name/linux; do
        if [ -e "$dev" ]; then
            ROOTDEV="$dev"
            break
        fi
    done
    if [ -n "$ROOTDEV" ]; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

if [ -z "$ROOTDEV" ]; then
    echo "sheng-stage1: linux rootfs was not found"
    echo "sheng-stage1: linux rootfs was not found" > /dev/kmsg
    exec sh
fi

echo "sheng-stage1: mounting $ROOTDEV"
echo "sheng-stage1: mounting $ROOTDEV" > /dev/kmsg
mount -t ext4 -o rw "$ROOTDEV" /newroot || exec sh

mkdir -p /newroot/proc /newroot/sys /newroot/dev
mount --move /proc /newroot/proc
mount --move /sys /newroot/sys
mount --move /dev /newroot/dev

echo "sheng-stage1: switching to NixOS /init"
echo "sheng-stage1: switching to NixOS /init" > /newroot/dev/kmsg
exec switch_root /newroot /init
EOF

chmod +x "${WORKDIR}/root/init"

(cd "${WORKDIR}/root" && find . -print0 | cpio --null -ov --format=newc | gzip -9) > "${OUT}"
echo "Built ${OUT}"
