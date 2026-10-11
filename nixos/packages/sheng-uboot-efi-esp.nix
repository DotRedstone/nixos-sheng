# ---
# Module: Sheng U-Boot EFI ESP Payload
# Description: Creates and validates the immutable files copied to Sheng's dedicated EFI system partition.
# Scope: Package
# Notes:
# - This package never formats, mounts, or writes the device's linux-boot partition.
# - Its output is a file tree for an already provisioned FAT ESP, not a flashable Android image.
# ---
{
  buildPackages,
  initrd,
  kernel,
  kernelParams,
  lib,
  runCommand,
  systemd,
}:
let
  version = kernel.modDirVersion;
  commandLine = lib.concatStringsSep " " kernelParams;
  efiBootManager = "${systemd}/lib/systemd/boot/efi/systemd-bootaa64.efi";
  kernelImage = "${kernel}/Image";
  deviceTree = "${kernel}/dtbs/qcom/sm8550-xiaomi-sheng.dtb";
  payloadDirectory = "EFI/NixOS/sheng-${version}";
  efiPeCheck = buildPackages.writeText "sheng-check-aa64-pe.py" (
    builtins.concatStringsSep "\n" [
      "import pathlib"
      "import struct"
      "import sys"
      ""
      "for path_string in sys.argv[1:]:"
      "    path = pathlib.Path(path_string)"
      "    data = path.read_bytes()"
      "    assert data[:2] == b\"MZ\", f\"{path}: missing DOS/PE signature\""
      "    pe_offset, = struct.unpack_from(\"<I\", data, 0x3C)"
      "    assert data[pe_offset : pe_offset + 4] == b\"PE\\\\0\\\\0\", f\"{path}: missing PE header\""
      "    machine, = struct.unpack_from(\"<H\", data, pe_offset + 4)"
      "    assert machine == 0xAA64, f\"{path}: expected AA64 PE machine, got {machine:#x}\""
      ""
    ]
  );
in
runCommand "sheng-uboot-efi-esp-${version}" {
  nativeBuildInputs = [
    buildPackages.coreutils
    buildPackages.dosfstools
    buildPackages.findutils
    buildPackages.mtools
    buildPackages.python3
  ];
} ''
  set -euo pipefail
  set -x

  test -s ${efiBootManager}
  test -s ${kernelImage}
  test -s ${initrd}
  test -s ${deviceTree}

  mkdir -p "$out/esp/EFI/BOOT" "$out/esp/${payloadDirectory}" \
    "$out/esp/loader/entries"

  # U-Boot finds this fallback path directly, then systemd-boot enumerates the
  # standard Boot Loader Specification entry below.
  install -m 0644 ${efiBootManager} "$out/esp/EFI/BOOT/BOOTAA64.EFI"
  install -m 0644 ${kernelImage} "$out/esp/${payloadDirectory}/linux"
  install -m 0644 ${initrd} "$out/esp/${payloadDirectory}/initrd"
  install -m 0644 ${deviceTree} "$out/esp/${payloadDirectory}/sm8550-xiaomi-sheng.dtb"

  cat > "$out/esp/loader/loader.conf" <<'EOF'
  default nixos-sheng-${version}.conf
  timeout 3
  console-mode keep
  editor no
  EOF

  cat > "$out/esp/loader/entries/nixos-sheng-${version}.conf" <<'EOF'
  title NixOS Sheng (${version})
  version ${version}
  sort-key nixos-sheng
  architecture aa64
  options ${commandLine}
  linux /${payloadDirectory}/linux
  initrd /${payloadDirectory}/initrd
  devicetree /${payloadDirectory}/sm8550-xiaomi-sheng.dtb
  EOF

  printf 'type1\n' > "$out/esp/loader/entries.srel"
  (
    cd "$out/esp"
    find EFI loader -type f -print0 | sort -z | xargs -0 sha256sum > manifest.sha256
  )

  # Both executables must be AA64 PE/COFF files. Do not parse `file(1)` text:
  # it describes an EFI-stub Linux Image differently across file versions.
  ${buildPackages.python3}/bin/python3 ${efiPeCheck} \
    "$out/esp/EFI/BOOT/BOOTAA64.EFI" \
    "$out/esp/${payloadDirectory}/linux"

  # Exercise the exact FAT directory and long-name layout without producing a
  # 1 GiB store object. The target partition is already a separately verified
  # 1 GiB FAT32 ESP; this transient image only proves payload compatibility.
  fat_image="$TMPDIR/linux-boot-test.img"
  truncate -s 256M "$fat_image"
  mkfs.fat -F 32 -n linux-boot "$fat_image" >/dev/null
  mmd -i "$fat_image" ::/EFI ::/EFI/BOOT ::/EFI/NixOS \
    ::/${payloadDirectory} ::/loader ::/loader/entries
  mcopy -i "$fat_image" "$out/esp/EFI/BOOT/BOOTAA64.EFI" ::/EFI/BOOT/BOOTAA64.EFI
  mcopy -i "$fat_image" "$out/esp/${payloadDirectory}/linux" ::/${payloadDirectory}/linux
  mcopy -i "$fat_image" "$out/esp/${payloadDirectory}/initrd" ::/${payloadDirectory}/initrd
  mcopy -i "$fat_image" "$out/esp/${payloadDirectory}/sm8550-xiaomi-sheng.dtb" \
    ::/${payloadDirectory}/sm8550-xiaomi-sheng.dtb
  mcopy -i "$fat_image" "$out/esp/loader/loader.conf" ::/loader/loader.conf
  mcopy -i "$fat_image" "$out/esp/loader/entries/nixos-sheng-${version}.conf" \
    ::/loader/entries/nixos-sheng-${version}.conf
  mcopy -i "$fat_image" "$out/esp/loader/entries.srel" ::/loader/entries.srel
  mcopy -i "$fat_image" "$out/esp/manifest.sha256" ::/manifest.sha256
  mdir -i "$fat_image" ::/EFI/BOOT/BOOTAA64.EFI
  mdir -i "$fat_image" ::/loader/entries/nixos-sheng-${version}.conf
  mtype -i "$fat_image" ::/loader/entries/nixos-sheng-${version}.conf \
    | cmp - "$out/esp/loader/entries/nixos-sheng-${version}.conf"
''
