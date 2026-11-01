# ---
# Module: Sheng U-Boot Android v4 probe image
# Description: Packages the direct Android probe for persistent boot_b testing
# Scope: Package
# Notes:
# - Experimental: the device must have a backed-up boot_b and a valid dtbo_b.
# ---
{
  buildPackages,
  directProbe,
  runCommand,
}:
let
  firmware = directProbe.passthru.firmware;
in
runCommand "sheng-u-boot-android-direct-v4-probe.img" {
  nativeBuildInputs = [ buildPackages.android-tools buildPackages.binutils buildPackages.python3 ];
  passthru = {
    inherit firmware;
    flashPartition = "boot_b";
    maximumBytes = 201326592;
    mode = "android-direct-v4-probe";
  };
} ''
  test -s ${firmware}/u-boot.bin
  strings ${firmware}/u-boot.bin | grep -Fqx 'bootcmd=run menucmd; run boot_linux; reset'
  mkbootimg \
    --header_version 4 \
    --kernel ${firmware}/u-boot.bin \
    --ramdisk /dev/null \
    --pagesize 4096 \
    -o "$out"

  python3 - "$out" ${firmware}/u-boot.bin <<'PY'
import pathlib
import struct
import sys

image = pathlib.Path(sys.argv[1]).read_bytes()
firmware = pathlib.Path(sys.argv[2]).read_bytes()
assert image[:8] == b"ANDROID!"
kernel_size, ramdisk_size = struct.unpack_from("<II", image, 8)
header_version = struct.unpack_from("<I", image, 40)[0]
assert header_version == 4
assert kernel_size == len(firmware)
assert ramdisk_size == 0
assert image[4096 : 4096 + kernel_size] == firmware
assert len(image) <= 201326592
PY
''
