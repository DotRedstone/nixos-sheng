# ---
# Module: Sheng U-Boot Android Boot Image
# Description: Packages the audited Sheng U-Boot EFI candidate as an Android v0 boot image
# Scope: Package
# Notes:
# - Experimental only: RAM-boot it with fastboot before considering boot_b.
# - This package does not modify the stable Mobile NixOS boot image.
# ---
{
  autoFastboot ? false,
  # Keep the raw form as a separate ABL-entry experiment.  The normal
  # candidate stays gzip, matching the known-good Mobile NixOS boot image.
  rawPayload ? false,
  # Use the upstream Qualcomm U-Boot legacy Android layout verbatim for a
  # separate ABL-entry test: high base addresses and no ramdisk.
  upstreamAndroidLayout ? false,
  buildPackages,
  buildUBoot,
  dtc,
  lib,
  runCommand,
  shengUbootSrc,
}:
let
  firmware = (buildUBoot {
    pname = if autoFastboot then
      if upstreamAndroidLayout then "sheng-uboot-upstream-fastboot-probe-firmware" else
      if rawPayload then "sheng-uboot-raw-fastboot-probe-firmware" else "sheng-uboot-fastboot-probe-firmware"
    else
      "sheng-uboot-android-bootimg-firmware";
    version = "2026.10-rc5";
    src = shengUbootSrc;
    defconfig = "qcom_defconfig";
    extraPatches = [
      ../patches/u-boot/0001-arm64-dts-add-sheng-boot-subset.patch
      ../patches/u-boot/0002-clk-qcom-program-sm8550-unipro-rate.patch
      ../patches/u-boot/0003-phy-qcom-add-pm8550b-eusb2-repeater.patch
    ];
    filesToInstall = [
      "u-boot-nodtb.bin"
      "u-boot.dtb"
      ".config"
    ];
    configurePhase = ''
      runHook preConfigure

      make qcom_defconfig
      scripts/kconfig/merge_config.sh -m .config board/qualcomm/qcom-phone.config
      ${lib.optionalString autoFastboot ''
        cat > board/qualcomm/sheng-ram-fastboot.env <<'ENV'
        # Deliberately do not scan storage: this is a no-display RAM-boot probe.
        bootdelay=0
        stdout=serial
        stderr=serial
        fastboot=fastboot -l $fastboot_addr_r usb 0
        bootcmd=run fastboot
        ENV
      ''}
      cat >> .config <<'CONFIG'
      CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8550-xiaomi-sheng"
      # ABL loads Android boot payloads near this address. 0x0 makes the ARM64
      # text offset wrap when U-Boot relocates itself from the Android envelope.
      CONFIG_TEXT_BASE=0x80000000
      CONFIG_PHY_QCOM_EUSB2_REPEATER=y
      ${lib.optionalString autoFastboot ''
      CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/sheng-ram-fastboot.env"
      # The USB probe must never expose a partition-writing fastboot command.
      # CONFIG_FASTBOOT_FLASH is not set
      ''}
      CONFIG
      make olddefconfig

      runHook postConfigure
    '';
    extraMeta = {
      description = if autoFastboot then
        "Experimental Sheng U-Boot USB fastboot RAM-boot probe" else
        "Experimental Sheng U-Boot EFI firmware for an Android v0 RAM-boot candidate";
      homepage = "https://source.denx.de/u-boot/u-boot";
      license = lib.licenses.gpl2Plus;
      platforms = [ "aarch64-linux" ];
    };
  }).overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ buildPackages.xxd ];
    postPatch = (old.postPatch or "") + ''
      test -s dts/upstream/src/arm64/qcom/sm8550-xiaomi-sheng.dts
      tail -n 1 dts/upstream/src/arm64/qcom/sm8550-xiaomi-sheng.dts | grep -Fqx '};'
      grep -Fq 'case GCC_UFS_PHY_UNIPRO_CORE_CLK:' drivers/clk/qcom/clock-sm8550.c
      grep -Fq 'clk_rcg_set_rate_mnd(priv->base, 0x77098,' drivers/clk/qcom/clock-sm8550.c
      test -s drivers/phy/qcom/phy-qcom-eusb2-repeater.c
      grep -Fq 'generic_phy_init(&qcom_snps_eusb2->repeater)' drivers/phy/qcom/phy-qcom-snps-eusb2.c
      grep -Fq 'qcom,pm8550b-eusb2-repeater' drivers/phy/qcom/phy-qcom-eusb2-repeater.c
    '';
  });
  payload = runCommand "sheng-uboot-android-bootimg-${if rawPayload then "raw" else "gzip"}-payload" {
    nativeBuildInputs = [ buildPackages.gzip ];
  } ''
    mkdir -p "$out"
    ${if rawPayload then
      "cp ${firmware}/u-boot-nodtb.bin \"$out/u-boot.bin\""
    else
      "gzip -n -c ${firmware}/u-boot-nodtb.bin > \"$out/u-boot.gz\""}
    printf 'unused' | gzip -n > "$out/ramdisk.gz"
  '';
in
runCommand (if autoFastboot then
  if upstreamAndroidLayout then "sheng-u-boot-upstream-fastboot-probe.img" else
  if rawPayload then "sheng-u-boot-raw-fastboot-probe.img" else "sheng-u-boot-fastboot-probe.img"
else
  "sheng-u-boot-experimental-boot_b.img") {
  nativeBuildInputs = [
    buildPackages.android-tools
    buildPackages.binutils
    buildPackages.gzip
    buildPackages.python3
    dtc
  ];
  passthru = {
    inherit firmware payload;
    flashPartition = "boot_b";
    maximumBytes = 201326592;
    mode = if autoFastboot then
      if upstreamAndroidLayout then "upstream-fastboot-probe" else
      if rawPayload then "raw-fastboot-probe" else "fastboot-probe"
    else
      "efi";
  };
} ''
  test -s ${firmware}/u-boot-nodtb.bin
  test -s ${firmware}/u-boot.dtb
  grep -Fx 'CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8550-xiaomi-sheng"' ${firmware}/.config
  grep -Fx 'CONFIG_TEXT_BASE=0x80000000' ${firmware}/.config
  grep -Fx 'CONFIG_PHY_QCOM_EUSB2_REPEATER=y' ${firmware}/.config
  strings ${firmware}/u-boot-nodtb.bin | grep -Fqx 'qcom-pm8550b-eusb2-repeater'
  test "$(fdtget -t s ${firmware}/u-boot.dtb /soc@0/rsc@17a00000/regulators-sheng-eusb2/ldo5 regulator-name)" = 'vreg_l5b_3p1'
  test "$(fdtget -t s ${firmware}/u-boot.dtb /soc@0/rsc@17a00000/regulators-sheng-eusb2/ldo15 regulator-name)" = 'vreg_l15b_1p8'
  ${lib.optionalString autoFastboot ''
    grep -Fx 'CONFIG_ENV_DEFAULT_ENV_TEXT_FILE="board/qualcomm/sheng-ram-fastboot.env"' ${firmware}/.config
    grep -Fx '# CONFIG_FASTBOOT_FLASH is not set' ${firmware}/.config
    strings ${firmware}/u-boot-nodtb.bin | grep -Fqx 'bootcmd=run fastboot'
  ''}
  grep -Fx 'CONFIG_EFI_LOADER=y' ${firmware}/.config
  grep -Fx 'CONFIG_EFI_BOOTMGR=y' ${firmware}/.config
  grep -Fx 'CONFIG_UFS_QCOM=y' ${firmware}/.config
  grep -Fx 'CONFIG_CMD_SCSI=y' ${firmware}/.config
  grep -Fx 'CONFIG_FS_FAT=y' ${firmware}/.config
  test "$(fdtget -t s ${firmware}/u-boot.dtb / model)" = 'Xiaomi Pad 6S Pro 12.4'
  fdtget -t s ${firmware}/u-boot.dtb / compatible | grep -Fqx 'xiaomi,sheng qcom,sm8550'

  kernel_image="$TMPDIR/kernel-with-dtb"
  cat ${payload}/u-boot.${if rawPayload then "bin" else "gz"} ${firmware}/u-boot.dtb > "$kernel_image"
  mkbootimg \
    --header_version 0 \
    --kernel "$kernel_image" \
    --cmdline "" \
    ${if upstreamAndroidLayout then "--base 0x80000000" else ''
    --ramdisk ${payload}/ramdisk.gz \\
    --base 0x00000000 \\
    --kernel_offset 0x00008000 \\
    --ramdisk_offset 0x01000000 \\
    --second_offset 0x00000000 \\
    --tags_offset 0x01e00000''} \
    --pagesize 4096 \
    -o "$out"

  size=$(stat -c %s "$out")
  test "$size" -le 201326592 || {
    echo "Android boot image is $size bytes; limit is 201326592" >&2
    exit 1
  }

  python3 - "$out" ${firmware}/u-boot-nodtb.bin ${firmware}/u-boot.dtb ${payload}/u-boot.${if rawPayload then "bin" else "gz"} ${if upstreamAndroidLayout then "/dev/null" else "${payload}/ramdisk.gz"} <<'PY'
import pathlib
import struct
import sys
import zlib

image, nodtb_path, dtb_path, payload_path, ramdisk_path = map(pathlib.Path, sys.argv[1:])
data = image.read_bytes()
assert data[:8] == b"ANDROID!", "missing Android boot magic"
(
    kernel_size,
    kernel_addr,
    ramdisk_size,
    ramdisk_addr,
    second_size,
    second_addr,
    tags_addr,
    page_size,
    dt_size,
    unused,
) = struct.unpack_from("<10I", data, 8)
assert page_size == 4096, page_size
upstream_android_layout = ${if upstreamAndroidLayout then "True" else "False"}
assert kernel_addr == (0x80008000 if upstream_android_layout else 0x8000), hex(kernel_addr)
assert ramdisk_addr == (0x0 if upstream_android_layout else 0x01000000), hex(ramdisk_addr)
assert second_size == 0, second_size
assert second_addr == 0, hex(second_addr)
assert tags_addr == (0x80000100 if upstream_android_layout else 0x01E00000), hex(tags_addr)
assert dt_size == 0, dt_size
assert unused == 0, unused
align = lambda value: (value + page_size - 1) // page_size * page_size
kernel_start = page_size
kernel = data[kernel_start : kernel_start + kernel_size]
expected_payload = payload_path.read_bytes()
expected_dtb = dtb_path.read_bytes()
payload_is_raw = ${if rawPayload then "True" else "False"}
if payload_is_raw:
    assert expected_payload == nodtb_path.read_bytes()
    assert expected_payload[0x38:0x3c] == b"ARMd", "U-Boot is missing the ARM64 Image header"
    assert kernel == expected_payload + expected_dtb, "kernel payload is not raw U-Boot followed by its DTB"
else:
    assert kernel == expected_payload + expected_dtb, "kernel payload is not gzip U-Boot followed by its DTB"
    decompressor = zlib.decompressobj(wbits=16 + zlib.MAX_WBITS)
    assert decompressor.decompress(kernel) + decompressor.flush() == nodtb_path.read_bytes()
    assert decompressor.eof, "U-Boot gzip stream did not terminate"
    assert decompressor.unused_data == expected_dtb, "U-Boot DTB is not the trailing payload"
assert expected_dtb[:4] == b"\xd0\x0d\xfe\xed", "invalid flattened DTB magic"
ramdisk_start = align(kernel_start + kernel_size)
expected_ramdisk = ramdisk_path.read_bytes()
if upstream_android_layout:
    assert ramdisk_size == 0, ramdisk_size
    assert len(data) == ramdisk_start, "unexpected Android boot image tail"
else:
    assert data[ramdisk_start : ramdisk_start + ramdisk_size] == expected_ramdisk
    assert len(data) == align(ramdisk_start + ramdisk_size), "unexpected Android boot image tail"
PY
''
