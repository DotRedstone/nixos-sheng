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
    '';
  });
in
runCommand "sheng-uboot-efi-sheng-dts-preflight" {
  nativeBuildInputs = [ dtc ];
} ''
  test -s ${firmware}/u-boot-nodtb.bin
  test -s ${firmware}/u-boot.dtb
  grep -Fx 'CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8550-xiaomi-sheng"' ${firmware}/.config
  test "$(fdtget -t s ${firmware}/u-boot.dtb / model)" = 'Xiaomi Pad 6S Pro 12.4'
  fdtget -t s ${firmware}/u-boot.dtb / compatible | grep -Fqx 'xiaomi,sheng qcom,sm8550'
  fdtget ${firmware}/u-boot.dtb /reserved-memory/splash@b8000000 no-map >/dev/null

  mkdir -p "$out"
  cat > "$out/README.md" <<'DOC'
  # Sheng U-Boot EFI DTS preflight

  This result verifies that the minimal Sheng U-Boot device tree compiles and is
  selected as the final U-Boot DTB. It is not a bootable or flashable image.

  DO NOT FLASH THIS RESULT. The candidate is missing the SM8550 UFS clock and
  divider work, PM8550B eUSB2 repeater driver support, Android boot-image
  packaging, ABL framebuffer hand-off, and device runtime validation.
  DOC
  touch "$out/NOT_FLASHABLE"
'' // {
  passthru = { inherit firmware; };
}
