# ---
# Module: Sheng Live EFI Payload
# Description: Places the Mobile NixOS kernel, initramfs and boot arguments on the Live filesystem
# Scope: Package
# ---

{ buildPackages, initrd, kernel, kernelParams, lib, runCommand }:

runCommand "sheng-live-efi" {
  nativeBuildInputs = with buildPackages; [ dtc gzip python3 ];
} ''
  mkdir -p "$out"
  gzip -dc ${kernel}/Image.gz > "$out/linux.efi"
  install -m 0644 ${initrd} "$out/initrd"
  install -m 0644 ${kernel}/dtbs/qcom/sm8550-xiaomi-sheng.dtb "$out/sheng.dtb"
  fdtput -p -c "$out/sheng.dtb" /chosen
  fdtput -t s "$out/sheng.dtb" /chosen bootargs ${lib.escapeShellArg (lib.concatStringsSep " " kernelParams)}

  # These limits match the Qualcomm board's U-Boot load buffers.
  python3 - "$out/linux.efi" <<'PY'
  import struct, sys
  data = open(sys.argv[1], "rb").read()
  assert data[:2] == b"MZ", "linux.efi missing MZ header"
  offset = struct.unpack_from("<I", data, 0x3C)[0]
  assert data[offset:offset + 6] == b"PE\x00\x00\x64\xaa", "linux.efi is not an AArch64 PE/COFF image"
  PY
  fdtget "$out/sheng.dtb" /chosen bootargs | grep -Fq 'root=PARTLABEL=linux-live'
  test "$(stat -c %s "$out/linux.efi")" -le $((128 * 1024 * 1024))
  test "$(stat -c %s "$out/initrd")" -le $((128 * 1024 * 1024))
  test "$(stat -c %s "$out/sheng.dtb")" -le $((2 * 1024 * 1024))
''
