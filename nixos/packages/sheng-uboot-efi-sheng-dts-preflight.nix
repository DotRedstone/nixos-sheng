# ---
# Module: Sheng U-Boot EFI DTS Preflight
# Description: Compiles and inspects a minimal Sheng U-Boot device tree without producing a flashable image
# Scope: Package
# ---
{
  buildPackages,
  buildUBoot,
  dtc,
  lib,
  runCommand,
  shengUbootSrc,
}:
let
  firmware = (buildUBoot {
    pname = "sheng-uboot-efi-sheng-dts-preflight-firmware";
    version = "2026.10-rc5";
    src = shengUbootSrc;
    defconfig = "qcom_defconfig";
    extraPatches = [
      ../patches/u-boot/sheng-baseline/common/0001-acm-stop-cancelled-rx.patch
      ../patches/u-boot/sheng-baseline/common/0002-acm-nonblocking-console.patch
      ../patches/u-boot/sheng-baseline/common/0003-button-kbd-events.patch
      ../patches/u-boot/sheng-baseline/common/0004-spmi-single-byte.patch
      ../patches/u-boot/sheng-baseline/common/0005-pmic-gpio-input-state.patch
      ../patches/u-boot/sheng-baseline/common/0006-simplefb-optional-properties.patch
      ../patches/u-boot/sheng-baseline/sm8550/0001-pm8550b-repeater.patch
      ../patches/u-boot/sheng-baseline/sm8550/0002-snps-repeater-lifecycle.patch
      ../patches/u-boot/sheng-baseline/sm8550/0003-sm8550-unipro-clock.patch
      ../patches/u-boot/sheng-baseline/sm8550/0004-usb-cfg-noc-clock.patch
      ../patches/u-boot/sheng-baseline/sm8550/0005-unipro-divider.patch
      ../patches/u-boot/sheng-baseline/sheng/0001-sheng-boot-dts.patch
      ../patches/u-boot/sheng-baseline/sheng/0002-usb2-pipe-clock.patch
      ../patches/u-boot/sheng-baseline/sheng/0003-sheng-abl-framebuffer.patch
      ../patches/u-boot/sheng-baseline/sheng/0004-efi-abl-boot-reason.patch
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
      cat >> .config <<'CONFIG'
      CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8550-xiaomi-sheng"
      CONFIG_TEXT_BASE=0x80000000
      CONFIG_PHY_QCOM_PM8550B_EUSB2=y
      CONFIG_EFI_LOADER=y
      CONFIG_CMD_BOOTEFI=y
      CONFIG_CMD_PART=y
      CONFIG_CMD_FAT=y
      CONFIG_FS_FAT=y
      CONFIG_FS_FAT_HANDLE_SECTOR_SIZE_MISMATCH=y
      CONFIG_CMD_PMIC=y
      CONFIG_NO_FB_CLEAR=y
      CONFIG
      make olddefconfig

      runHook postConfigure
    '';
    extraMeta = {
      description = "Sheng U-Boot device-tree preflight, not a flashable firmware image";
      homepage = "https://source.denx.de/u-boot/u-boot";
      license = lib.licenses.gpl2Plus;
      platforms = [ "aarch64-linux" ];
    };
  }).overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ buildPackages.xxd ];
    postPatch = (old.postPatch or "") + ''
      test -s dts/upstream/src/arm64/qcom/sm8550-xiaomi-sheng.dts
      grep -Fqx '&usb_1_hsphy {' dts/upstream/src/arm64/qcom/sm8550-xiaomi-sheng.dts
      tail -n 1 dts/upstream/src/arm64/qcom/sm8550-xiaomi-sheng.dts | grep -Fqx '};'
      grep -Fq 'case GCC_UFS_PHY_UNIPRO_CORE_CLK:' drivers/clk/qcom/clock-sm8550.c
      grep -Fq 'GCC_CFG_NOC_USB3_PRIM_AXI_CLK' drivers/clk/qcom/clock-sm8550.c
      grep -Fq 'clk_bcr_update(priv->base + 0x77098)' drivers/clk/qcom/clock-sm8550.c
      test -s drivers/phy/qcom/phy-pm8550b-eusb2.c
      grep -Fq 'generic_phy_init(&qcom_snps_eusb2->repeater)' drivers/phy/qcom/phy-qcom-snps-eusb2.c
    '';
  });
in
runCommand "sheng-uboot-efi-sheng-dts-preflight" {
  nativeBuildInputs = [ dtc buildPackages.binutils ];
} ''
  test -s ${firmware}/u-boot-nodtb.bin
  test -s ${firmware}/u-boot.dtb
  grep -Fx 'CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8550-xiaomi-sheng"' ${firmware}/.config
  grep -Fx 'CONFIG_UFS_QCOM=y' ${firmware}/.config
  grep -Fx 'CONFIG_PHY_QCOM_PM8550B_EUSB2=y' ${firmware}/.config
  grep -Fx 'CONFIG_USB_FUNCTION_ACM=y' ${firmware}/.config
  grep -Fx 'CONFIG_NO_FB_CLEAR=y' ${firmware}/.config
  strings ${firmware}/u-boot-nodtb.bin | grep -Fq 'qcom,pm8550b-eusb2-repeater'
  test "$(fdtget -t s ${firmware}/u-boot.dtb / model)" = 'Xiaomi Pad 6S Pro 12.4'
  fdtget -t s ${firmware}/u-boot.dtb / compatible | grep -Fqx 'xiaomi,sheng qcom,sm8550'
  fdtget ${firmware}/u-boot.dtb /reserved-memory/splash_region@b8000000 no-map >/dev/null
  test "$(fdtget -t s ${firmware}/u-boot.dtb /soc@0/usb@a600000 dr_mode)" = 'peripheral'
  fdtget ${firmware}/u-boot.dtb /soc@0/usb@a600000 qcom,select-utmi-as-pipe-clk >/dev/null
  test "$(fdtget -t s ${firmware}/u-boot.dtb /chosen/framebuffer@b8000000 format)" = 'a8r8g8b8'

  mkdir -p "$out"
  cat > "$out/README.md" <<'DOC'
  # Sheng U-Boot EFI DTS preflight

  This result verifies that the minimal Sheng U-Boot device tree compiles and is
  selected as the final U-Boot DTB. It is not a bootable or flashable image.

  DO NOT FLASH THIS RESULT. It statically verifies the Sheng UFS, PM8550B
  eUSB2, USB ACM and ABL framebuffer descriptions. It does not package an
  Android boot image or prove device runtime behaviour.
  DOC
  touch "$out/NOT_FLASHABLE"
'' // {
  passthru = { inherit firmware; };
}
