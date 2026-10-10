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
      cat >> .config <<'CONFIG'
      CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8550-xiaomi-sheng"
      CONFIG_PHY_QCOM_EUSB2_REPEATER=y
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
      grep -Fq 'clk_rcg_set_rate_mnd(priv->base, 0x77098,' drivers/clk/qcom/clock-sm8550.c
      test -s drivers/phy/qcom/phy-qcom-eusb2-repeater.c
      grep -Fq 'generic_phy_init(&qcom_snps_eusb2->repeater)' drivers/phy/qcom/phy-qcom-snps-eusb2.c
      grep -Fq 'qcom,pm8550b-eusb2-repeater' drivers/phy/qcom/phy-qcom-eusb2-repeater.c
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
  grep -Fx 'CONFIG_PHY_QCOM_EUSB2_REPEATER=y' ${firmware}/.config
  strings ${firmware}/u-boot-nodtb.bin | grep -Fqx 'qcom-pm8550b-eusb2-repeater'
  test "$(fdtget -t s ${firmware}/u-boot.dtb /soc@0/rsc@17a00000/regulators-sheng-eusb2/ldo5 regulator-name)" = 'vreg_l5b_3p1'
  test "$(fdtget -t s ${firmware}/u-boot.dtb /soc@0/rsc@17a00000/regulators-sheng-eusb2/ldo15 regulator-name)" = 'vreg_l15b_1p8'
  test "$(fdtget -t s ${firmware}/u-boot.dtb / model)" = 'Xiaomi Pad 6S Pro 12.4'
  fdtget -t s ${firmware}/u-boot.dtb / compatible | grep -Fqx 'xiaomi,sheng qcom,sm8550'
  fdtget ${firmware}/u-boot.dtb /reserved-memory/splash@b8000000 no-map >/dev/null

  mkdir -p "$out"
  cat > "$out/README.md" <<'DOC'
  # Sheng U-Boot EFI DTS preflight

  This result verifies that the minimal Sheng U-Boot device tree compiles and is
  selected as the final U-Boot DTB. It is not a bootable or flashable image.

  DO NOT FLASH THIS RESULT. It statically verifies the PM8550B eUSB2
  repeater driver and its two RPMh rails, but UFS PHY/power and storage,
  Android boot-image packaging, ABL framebuffer hand-off, and device runtime
  validation remain outstanding.
  DOC
  touch "$out/NOT_FLASHABLE"
'' // {
  passthru = { inherit firmware; };
}
