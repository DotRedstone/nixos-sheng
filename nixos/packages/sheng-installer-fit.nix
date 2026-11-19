# ---
# Module: Sheng RAM Installer FIT
# Description: Packages the Sheng kernel and storage recovery initramfs for U-Boot USB boot.
# Scope: Package
# ---
{
  buildPackages,
  initrd,
  kernel,
  kernelParams,
  lib,
  runCommand,
}:
runCommand "sheng-installer-fit" {
  nativeBuildInputs = with buildPackages; [ dtc gzip ubootTools ];
} ''
  gzip -dc ${kernel}/Image.gz > Image
  cp ${initrd} initrd
  cp ${kernel}/dtbs/qcom/sm8550-xiaomi-sheng.dtb sheng.dtb
  cp ${./sheng-installer.its} installer.its
  chmod u+w sheng.dtb
  fdtput -p -c sheng.dtb /chosen
  fdtput -t s sheng.dtb /chosen bootargs ${lib.escapeShellArg (lib.concatStringsSep " " kernelParams)}

  mkdir -p "$out"
  mkimage -f installer.its "$out/sheng-installer.itb"
  if [ "$(stat -c %s "$out/sheng-installer.itb")" -gt 117440512 ]; then
    echo 'The installer FIT exceeds the 112 MiB U-Boot USB buffer.' >&2
    exit 1
  fi
''
