#!/usr/bin/env bash
set -euo pipefail

KERNEL_VER="${1:-7.1}"
WORKSPACE="${2:-$(pwd)}"
KERNEL_REPO="${KERNEL_REPO:-https://github.com/code002-2/sm8550-mainline.git}"
CONFIG_URL="${CONFIG_URL:-https://gitlab.postmarketos.org/alghiffaryfa19/pmaports/-/raw/sheng/device/testing/linux-postmarketos-qcom-sm8550/config-postmarketos-qcom-sm8550.aarch64}"
OUT_DIR="${WORKSPACE}/out/kernel"

if [ -z "${CCACHE_DIR:-}" ]; then
    export CCACHE_DIR="/home/runner/.ccache"
    export CCACHE_MAXSIZE="10G"
    export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
fi

mkdir -p "${CCACHE_DIR}" "${OUT_DIR}"

export CC="ccache clang"
export CXX="ccache clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export READELF="llvm-readelf"
export STRIP="llvm-strip"

cd "${WORKSPACE}"
rm -rf linux

echo "==> Cloning kernel branch sheng-${KERNEL_VER}"
if ! git clone "${KERNEL_REPO}" --branch "sheng-${KERNEL_VER}" --depth 1 linux; then
    echo "==> Branch sheng-${KERNEL_VER} not found; cloning default branch"
    git clone "${KERNEL_REPO}" --depth 1 linux
fi

cd linux

echo "==> Downloading base kernel config"
wget "${CONFIG_URL}" -O .config

echo "==> Updating config"
make ARCH=arm64 LLVM=1 olddefconfig

echo "==> Building kernel image, compressed image, DTBs, and modules"
make -j"$(nproc)" ARCH=arm64 CC="ccache clang" LLVM=1 Image Image.gz dtbs modules

KERNEL_RELEASE="$(make kernelrelease -s)"
echo "==> Kernel release: ${KERNEL_RELEASE}"

mkdir -p "${OUT_DIR}/boot" "${OUT_DIR}/kernel-modules"

install -Dm644 arch/arm64/boot/Image.gz "${OUT_DIR}/boot/Image.gz"
install -Dm644 arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb \
    "${OUT_DIR}/boot/sm8550-xiaomi-sheng.dtb"
install -Dm644 .config "${OUT_DIR}/boot/config-${KERNEL_RELEASE}"
install -Dm644 System.map "${OUT_DIR}/boot/System.map-${KERNEL_RELEASE}"

make -j"$(nproc)" ARCH=arm64 CC="ccache clang" LLVM=1 \
    INSTALL_MOD_PATH="${OUT_DIR}/kernel-modules" modules_install
rm -rf "${OUT_DIR}"/kernel-modules/lib/modules/*/build \
       "${OUT_DIR}"/kernel-modules/lib/modules/*/source

cat arch/arm64/boot/Image.gz \
    arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > "${OUT_DIR}/boot/Image.gz-dtb_sheng"

cp "${OUT_DIR}/boot/Image.gz-dtb_sheng" "${OUT_DIR}/boot/zImage_sheng"

cd "${WORKSPACE}"
chmod +x ./mkbootimg

echo "==> Building NixOS stage-1 initramfs"
chmod +x ./build-stage1-initramfs.sh
./build-stage1-initramfs.sh "${OUT_DIR}/sheng-stage1-initramfs.cpio.gz"

DUALBOOT_CMDLINE="${DUALBOOT_CMDLINE:-root=PARTLABEL=linux init=/init rootwait console=tty0 console=ttyMSM0,115200n8 fbcon=map:0 fbcon=rotate:1 loglevel=7 ignore_loglevel systemd.log_level=debug}"
SINGLEBOOT_CMDLINE="${SINGLEBOOT_CMDLINE:-root=PARTLABEL=userdata rootwait}"
NIXOS_CMDLINE="${NIXOS_CMDLINE:-root=PARTLABEL=linux rootwait console=tty0 console=ttyMSM0,115200n8 fbcon=map:0 fbcon=rotate:1 loglevel=7 ignore_loglevel}"

echo "==> Creating Android boot images"
./mkbootimg --kernel "${OUT_DIR}/boot/zImage_sheng" \
    --cmdline "${DUALBOOT_CMDLINE}" \
    --base 0x00000000 --kernel_offset 0x00008000 \
    --tags_offset 0x01e00000 --pagesize 4096 --id \
    -o "${OUT_DIR}/boot_sheng_dualboot.img"

./mkbootimg --kernel "${OUT_DIR}/boot/zImage_sheng" \
    --cmdline "${SINGLEBOOT_CMDLINE}" \
    --base 0x00000000 --kernel_offset 0x00008000 \
    --tags_offset 0x01e00000 --pagesize 4096 --id \
    -o "${OUT_DIR}/boot_sheng_singleboot.img"

./mkbootimg --kernel "${OUT_DIR}/boot/zImage_sheng" \
    --ramdisk "${OUT_DIR}/sheng-stage1-initramfs.cpio.gz" \
    --cmdline "${NIXOS_CMDLINE}" \
    --base 0x00000000 --kernel_offset 0x00008000 \
    --tags_offset 0x01e00000 --pagesize 4096 --id \
    -o "${OUT_DIR}/boot_sheng_nixos.img"

echo "==> Fetching optional firmware and ALSA data"
rm -rf "${OUT_DIR}/firmware" "${OUT_DIR}/alsa-ucm" sheng-firmware alsa-sheng

if git clone https://github.com/map220v/sheng-firmware --depth 1 sheng-firmware; then
    mkdir -p "${OUT_DIR}/firmware"
    cp -a sheng-firmware/. "${OUT_DIR}/firmware/"
    rm -rf sheng-firmware
fi

if git clone https://github.com/alghiffaryfa19/alsa-sheng --depth 1 alsa-sheng; then
    mkdir -p "${OUT_DIR}/alsa-ucm"
    cp -a alsa-sheng/. "${OUT_DIR}/alsa-ucm/"
    rm -rf alsa-sheng
fi

echo "==> Packing artifacts"
tar --zstd -cf "${OUT_DIR}/sheng-kernel-files.tar.zst" -C "${OUT_DIR}" boot
tar --zstd -cf "${OUT_DIR}/sheng-kernel-modules.tar.zst" -C "${OUT_DIR}" kernel-modules

if [ -d "${OUT_DIR}/firmware" ]; then
    tar --zstd -cf "${OUT_DIR}/sheng-firmware.tar.zst" -C "${OUT_DIR}" firmware
fi

if [ -d "${OUT_DIR}/alsa-ucm" ]; then
    tar --zstd -cf "${OUT_DIR}/sheng-alsa-ucm.tar.zst" -C "${OUT_DIR}" alsa-ucm
fi

echo "==> Done. Artifacts are in ${OUT_DIR}"
