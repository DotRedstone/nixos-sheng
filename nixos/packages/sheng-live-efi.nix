# ---
# Module: Sheng Live EFI Payload
# Description: Places the Mobile NixOS kernel, initramfs and boot arguments on the Live filesystem
# Scope: Package
# ---

{ buildPackages, initrd, kernel, kernelParams, lib, runCommand }:

runCommand "sheng-live-efi" {
  nativeBuildInputs = with buildPackages; [ dtc gzip ];
} ''
  mkdir -p "$out"
  gzip -dc ${kernel}/Image.gz > "$out/linux.efi"
  install -m 0644 ${initrd} "$out/initrd"
  install -m 0644 ${kernel}/dtbs/qcom/sm8550-xiaomi-sheng.dtb "$out/sheng.dtb"
  fdtput -p -c "$out/sheng.dtb" /chosen
  fdtput -t s "$out/sheng.dtb" /chosen bootargs ${lib.escapeShellArg (lib.concatStringsSep " " kernelParams)}

  # These limits match the Qualcomm board's U-Boot load buffers.
  test "$(head -c 2 "$out/linux.efi")" = MZ
  test "$(stat -c %s "$out/linux.efi")" -le $((128 * 1024 * 1024))
  test "$(stat -c %s "$out/initrd")" -le $((128 * 1024 * 1024))
  test "$(stat -c %s "$out/sheng.dtb")" -le $((2 * 1024 * 1024))
''
