#!/usr/bin/env bash
set -euo pipefail

IMAGE_SIZE="${IMAGE_SIZE:-8G}"
FILESYSTEM_UUID="${FILESYSTEM_UUID:-ee8d3593-59b1-480e-a3b6-4fefb17ee7d8}"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
ROOTFS_IMG="nixos-sheng-${TIMESTAMP}.img"
OUT_DIR="${OUT_DIR:-out}"
ROOTDIR="$(mktemp -d)"

cleanup() {
    set +e
    if mountpoint -q "${ROOTDIR}/dev/pts"; then umount "${ROOTDIR}/dev/pts"; fi
    if mountpoint -q "${ROOTDIR}/dev"; then umount "${ROOTDIR}/dev"; fi
    if mountpoint -q "${ROOTDIR}/proc"; then umount "${ROOTDIR}/proc"; fi
    if mountpoint -q "${ROOTDIR}/sys"; then umount "${ROOTDIR}/sys"; fi
    if mountpoint -q "${ROOTDIR}"; then umount "${ROOTDIR}"; fi
    rm -rf "${ROOTDIR}"
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root: sudo ./build-nixos-rootfs.sh"
    exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
    echo "nix is required. Install Nix with flakes enabled first."
    exit 1
fi

mkdir -p "${OUT_DIR}"

echo "==> Building NixOS system tarball"
nix --extra-experimental-features "nix-command flakes" \
    build ./nixos#rootfsTarball \
    --out-link "${OUT_DIR}/nixos-sheng-rootfs-tarball"

TARBALL_DIR="$(readlink -f "${OUT_DIR}/nixos-sheng-rootfs-tarball")"
TARBALL="$(find "${TARBALL_DIR}" -type f \( -name "*.tar.xz" -o -name "*.tar.zst" -o -name "*.tar.gz" -o -name "*.tgz" \) | head -n 1)"
if [ -z "${TARBALL}" ] || [ ! -f "${TARBALL}" ]; then
    echo "Could not find a NixOS rootfs tarball in ${TARBALL_DIR}"
    exit 1
fi

echo "==> Creating ext4 image ${OUT_DIR}/${ROOTFS_IMG}"
truncate -s "${IMAGE_SIZE}" "${OUT_DIR}/${ROOTFS_IMG}"
mkfs.ext4 -L linux "${OUT_DIR}/${ROOTFS_IMG}"
mount -o loop "${OUT_DIR}/${ROOTFS_IMG}" "${ROOTDIR}"

echo "==> Extracting rootfs"
case "${TARBALL}" in
    *.tar.xz) tar -xJf "${TARBALL}" -C "${ROOTDIR}" ;;
    *.tar.zst) tar --zstd -xf "${TARBALL}" -C "${ROOTDIR}" ;;
    *.tar.gz|*.tgz) tar -xzf "${TARBALL}" -C "${ROOTDIR}" ;;
    *)
        echo "Unsupported tarball format: ${TARBALL}"
        exit 1
        ;;
esac

if [ -d artifacts/kernel-modules ]; then
    echo "==> Injecting external kernel modules"
    mkdir -p "${ROOTDIR}/lib/modules"
    cp -a artifacts/kernel-modules/lib/modules/. "${ROOTDIR}/lib/modules/"
fi

if [ -d artifacts/firmware ]; then
    echo "==> Injecting firmware blobs"
    mkdir -p "${ROOTDIR}/lib/firmware"
    cp -a artifacts/firmware/. "${ROOTDIR}/lib/firmware/"
fi

if [ -d artifacts/alsa-ucm ]; then
    echo "==> Injecting ALSA UCM data"
    mkdir -p "${ROOTDIR}/usr/share/alsa/ucm2"
    cp -a artifacts/alsa-ucm/. "${ROOTDIR}/usr/share/alsa/ucm2/"
fi

sync
umount "${ROOTDIR}"

tune2fs -U "${FILESYSTEM_UUID}" "${OUT_DIR}/${ROOTFS_IMG}" >/dev/null

echo "==> Packing image as zip"
(cd "${OUT_DIR}" && zip -9 "${ROOTFS_IMG}.zip" "${ROOTFS_IMG}")

echo "Done: ${OUT_DIR}/${ROOTFS_IMG}.zip"
