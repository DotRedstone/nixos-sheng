#!/usr/bin/env bash
set -euo pipefail

IMAGE_SIZE="${IMAGE_SIZE:-auto}"
ROOTFS_FLAKE_ATTR="${ROOTFS_FLAKE_ATTR:-mobileRootfsImage}"
FILESYSTEM_UUID="${FILESYSTEM_UUID:-ee8d3593-59b1-480e-a3b6-4fefb17ee7d8}"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
ROOTFS_IMG="nixos-sheng-${TIMESTAMP}.img"
OUT_DIR="${OUT_DIR:-out}"
OUT_LINK="${OUT_DIR}/nixos-sheng-${ROOTFS_FLAKE_ATTR}"

if [ -n "${ROOTFS_BACKEND:-}" ] && [ "${ROOTFS_BACKEND}" != "mobile" ]; then
    echo "ROOTFS_BACKEND=${ROOTFS_BACKEND} is no longer supported."
    echo "This project now flashes the Mobile NixOS generated rootfs image."
    exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
    echo "nix is required. Install Nix with flakes enabled first."
    exit 1
fi

mkdir -p "${OUT_DIR}"

case "${ROOTFS_FLAKE_ATTR}" in
    mobileRootfsImage|mobileRootfsImageGnome)
        ;;
    *)
        echo "Unsupported ROOTFS_FLAKE_ATTR=${ROOTFS_FLAKE_ATTR}"
        echo "Supported values: mobileRootfsImage, mobileRootfsImageGnome"
        exit 1
        ;;
esac

echo "==> Settings:"
echo "ROOTFS_FLAKE_ATTR: ${ROOTFS_FLAKE_ATTR}"
echo "OUT_LINK: ${OUT_LINK}"
echo "OUT_DIR: ${OUT_DIR}"

echo "==> Building Mobile NixOS generated rootfs image: ${ROOTFS_FLAKE_ATTR}"
nix --extra-experimental-features "nix-command flakes" \
    build "./nixos#${ROOTFS_FLAKE_ATTR}" \
    --out-link "${OUT_LINK}"

ROOTFS_DIR="$(readlink -f "${OUT_LINK}")"
echo "ROOTFS_DIR: ${ROOTFS_DIR}"

readarray -t ROOTFS_CANDIDATES < <(find "${ROOTFS_DIR}" -type f \( -name "rootfs.img" -o -name "rootfs.img.zst" \))

if [ ${#ROOTFS_CANDIDATES[@]} -ne 1 ]; then
    echo "ERROR: Expected exactly 1 rootfs candidate in ${ROOTFS_DIR}, found ${#ROOTFS_CANDIDATES[@]}:"
    printf '  - %s\n' "${ROOTFS_CANDIDATES[@]}"
    exit 1
fi

ROOTFS_SOURCE="${ROOTFS_CANDIDATES[0]}"

echo "==> Copying rootfs image to ${OUT_DIR}/${ROOTFS_IMG}"
case "${ROOTFS_SOURCE}" in
    *.zst)
        if ! command -v zstd >/dev/null 2>&1; then
            echo "zstd is required to decompress ${ROOTFS_SOURCE}"
            exit 1
        fi
        zstd -dc "${ROOTFS_SOURCE}" > "${OUT_DIR}/${ROOTFS_IMG}"
        ;;
    *)
        cp "${ROOTFS_SOURCE}" "${OUT_DIR}/${ROOTFS_IMG}"
        ;;
esac

chmod +w "${OUT_DIR}/${ROOTFS_IMG}"

if [ "${IMAGE_SIZE}" != "auto" ]; then
    echo "==> Resizing rootfs image to ${IMAGE_SIZE}"
    e2fsck -fy "${OUT_DIR}/${ROOTFS_IMG}"
    truncate -s "${IMAGE_SIZE}" "${OUT_DIR}/${ROOTFS_IMG}"
    resize2fs "${OUT_DIR}/${ROOTFS_IMG}"
fi

echo "==> Setting rootfs UUID ${FILESYSTEM_UUID}"
tune2fs -U "${FILESYSTEM_UUID}" "${OUT_DIR}/${ROOTFS_IMG}" >/dev/null

echo "==> Sanity checking rootfs image"
if ! debugfs -R "stat /nix/var/nix/profiles/system/init" "${OUT_DIR}/${ROOTFS_IMG}" 2>/dev/null | grep -q "Inode:"; then
    echo "ERROR: Stage-2 init not found in rootfs image!"
    exit 1
fi
if ! debugfs -R "stat /nix-path-registration" "${OUT_DIR}/${ROOTFS_IMG}" 2>/dev/null | grep -q "Inode:"; then
    echo "ERROR: nix-path-registration not found in rootfs image!"
    exit 1
fi

echo "Done: ${OUT_DIR}/${ROOTFS_IMG}"
echo "Note: a Mobile NixOS rootfs is expected to contain nix/store and nix-path-registration."
