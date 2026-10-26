# ---
# Module: Sheng U-Boot EFI Preflight
# Description: Builds and inspects an upstream Qcom U-Boot EFI baseline without producing a flashable image
# Scope: Package
# ---
{
  buildPackages,
  buildUBoot,
  lib,
  runCommand,
  shengUbootSrc,
}:
let
  firmware = (buildUBoot {
    pname = "sheng-uboot-efi-preflight-firmware";
    version = "2026.10-rc5";
    src = shengUbootSrc;
    defconfig = "qcom_defconfig";
    filesToInstall = [
      "u-boot-nodtb.bin"
      "u-boot.dtb"
      ".config"
    ];
    configurePhase = ''
      runHook preConfigure

      make qcom_defconfig
      scripts/kconfig/merge_config.sh -m .config board/qualcomm/qcom-phone.config
      make olddefconfig

      runHook postConfigure
    '';
    extraMeta = {
      description = "Unmodified upstream Qualcomm U-Boot EFI compile baseline for Sheng";
      homepage = "https://source.denx.de/u-boot/u-boot";
      license = lib.licenses.gpl2Plus;
      platforms = [ "aarch64-linux" ];
    };
  }).overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ buildPackages.xxd ];
  });
in
runCommand "sheng-uboot-efi-preflight" { } ''
  test -s ${firmware}/u-boot-nodtb.bin
  test -s ${firmware}/u-boot.dtb
  grep -Fx 'CONFIG_EFI_LOADER=y' ${firmware}/.config
  grep -Fx 'CONFIG_CMD_BOOTEFI=y' ${firmware}/.config
  grep -Fx 'CONFIG_CMD_PART=y' ${firmware}/.config
  grep -Fx 'CONFIG_CMD_FAT=y' ${firmware}/.config
  grep -Fx 'CONFIG_FS_FAT=y' ${firmware}/.config

  mkdir -p "$out"
  cat > "$out/README.md" <<'EOF'
  # Sheng U-Boot EFI preflight

  This result proves that the pinned, official U-Boot source builds an EFI-capable
  Qualcomm baseline. It is not a Sheng firmware image.

  DO NOT FLASH THIS RESULT. It does not include the Sheng board DTS, SM8550 UFS
  clock support, PM8550B eUSB2 repeater support, an ABL framebuffer hand-off, or
  an Android boot-image envelope. The raw build inputs remain internal to this
  derivation so this output cannot be passed to fastboot by mistake.

  Source: official U-Boot v2026.10-rc5, signed tag commit
  a06e89ab05eaa2b8344d521319399333cd760ae5.
  EOF
  touch "$out/NOT_FLASHABLE"
'' // {
  passthru = { inherit firmware; };
}
