# ---
# Module: Sheng systemd-boot clear-screen probe
# Description: Builds an AA64 EFI manager without the menu-exit clear for one-off display diagnosis
# Scope: Package
# Notes:
# - Experimental only; install BOOTAA64.EFI with an independently verified backup.
# ---
{
  buildPackages,
  runCommand,
  systemd,
}:
let
  patchedSystemd = systemd.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../patches/systemd/0001-sheng-keep-menu-frame-on-handoff.patch ];
  });
in
runCommand "sheng-systemd-boot-no-clear" {
  nativeBuildInputs = [ buildPackages.python3 ];
} ''
  set -euo pipefail
  mkdir -p "$out"
  install -m 0644 ${patchedSystemd}/lib/systemd/boot/efi/systemd-bootaa64.efi \
    "$out/BOOTAA64.EFI"

  python3 - "$out/BOOTAA64.EFI" <<'PY'
import pathlib
import struct
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
assert data[:2] == b"MZ"
pe_offset, = struct.unpack_from("<I", data, 0x3C)
assert data[pe_offset:pe_offset + 4] == b"PE\0\0"
machine, = struct.unpack_from("<H", data, pe_offset + 4)
assert machine == 0xAA64, f"expected AA64 EFI binary, got {machine:#x}"
PY
''
