#!/usr/bin/env bash

# ---
# Module: Inspect Boot Image
# Description: Diagnostic script to unpack and inspect Android boot images
# Scope: Script
# ---
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/inspect-bootimg.sh path/to/boot.img

Unpacks an Android boot.img and inspects the Mobile NixOS stage-1 initrd.
Requires one boot image unpacker: unpack_bootimg, magiskboot, or abootimg.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require() {
  have "$1" || die "missing required tool: $1"
}

print_section() {
  echo
  echo "===== $* ====="
}

try_unpack_bootimg() {
  local bootimg=$1
  local out=$2

  if unpack_bootimg --boot_img "$bootimg" --out "$out" >/tmp/inspect-bootimg-unpack.log 2>&1; then
    return 0
  fi

  if unpack_bootimg -i "$bootimg" -o "$out" >/tmp/inspect-bootimg-unpack.log 2>&1; then
    return 0
  fi

  return 1
}

try_magiskboot() {
  local bootimg=$1
  local out=$2

  cp "$bootimg" "$out/boot.img"
  (
    cd "$out"
    magiskboot unpack boot.img
  ) >/tmp/inspect-bootimg-unpack.log 2>&1
}

try_abootimg() {
  local bootimg=$1
  local out=$2

  (
    cd "$out"
    abootimg -x "$bootimg"
  ) >/tmp/inspect-bootimg-unpack.log 2>&1
}

find_ramdisk() {
  local out=$1

  find "$out" -maxdepth 3 -type f \
    \( -iname 'ramdisk*' -o -iname 'initrd*' -o -iname '*.cpio' -o -iname '*.cpio.gz' \) \
    ! -name 'boot.img' \
    | sort \
    | head -n1
}

extract_ramdisk() {
  local ramdisk=$1
  local dest=$2
  local cpio_file=$3
  local description

  description=$(file -b "$ramdisk" || true)
  echo "ramdisk: $ramdisk"
  echo "ramdisk file type: $description"

  case "$description" in
    *gzip*|*GZip*)
      require gzip
      gzip -cd "$ramdisk" > "$cpio_file"
      ;;
    *'ASCII cpio archive'*|*'cpio archive'*)
      cp "$ramdisk" "$cpio_file"
      ;;
    *)
      if [[ $ramdisk == *.gz ]]; then
        require gzip
        gzip -cd "$ramdisk" > "$cpio_file"
      else
        cp "$ramdisk" "$cpio_file"
      fi
      ;;
  esac

  (
    cd "$dest"
    cpio -idm --quiet < "$cpio_file"
  )
}

json_get_bool() {
  local config=$1
  local jq_expr=$2
  local grep_pattern=$3
  local expected=$4

  if have jq; then
    jq -r "$jq_expr // \"missing\"" "$config" 2>/dev/null || echo "missing"
  else
    if grep -Eq "$grep_pattern" "$config"; then
      echo "$expected"
    else
      echo "missing"
    fi
  fi
}

main() {
  if [[ $# -ne 1 ]]; then
    usage
    exit 2
  fi

  local bootimg=$1
  [[ -f $bootimg ]] || die "boot image not found: $bootimg"

  require file
  require cpio
  require grep

  if ! have unpack_bootimg && ! have magiskboot && ! have abootimg; then
    die "need one boot image unpacker: unpack_bootimg, magiskboot, or abootimg"
  fi

  local work
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT

  local unpack_dir=$work/unpacked
  local initrd_dir=$work/initrd
  local cpio_file=$work/ramdisk.cpio
  mkdir -p "$unpack_dir" "$initrd_dir"

  print_section "Unpacking boot image"
  echo "boot image: $bootimg"

  if have unpack_bootimg && try_unpack_bootimg "$bootimg" "$unpack_dir"; then
    echo "unpacker: unpack_bootimg"
  elif have magiskboot && try_magiskboot "$bootimg" "$unpack_dir"; then
    echo "unpacker: magiskboot"
  elif have abootimg && try_abootimg "$bootimg" "$unpack_dir"; then
    echo "unpacker: abootimg"
  else
    cat /tmp/inspect-bootimg-unpack.log >&2 || true
    die "failed to unpack boot image"
  fi

  print_section "Unpacked files"
  find "$unpack_dir" -maxdepth 3 -type f -print | sort

  local ramdisk
  ramdisk=$(find_ramdisk "$unpack_dir")
  [[ -n $ramdisk ]] || die "could not find ramdisk/initrd in unpacked boot image"

  print_section "Extracting initrd"
  extract_ramdisk "$ramdisk" "$initrd_dir" "$cpio_file"

  print_section "Stage-1 key files"
  (
    cd "$initrd_dir"
    ls -la init init.mrb loader 2>/dev/null || true
    if [[ -d applets ]]; then
      ls -la applets
    else
      echo "applets: missing"
    fi
  )

  local config=$initrd_dir/etc/boot/config
  print_section "/etc/boot/config"
  if [[ -f $config ]]; then
    if have jq; then
      jq . "$config" || cat "$config"
    else
      cat "$config"
    fi
  else
    echo "missing: etc/boot/config"
  fi

  print_section "Config grep"
  if [[ -f $config ]]; then
    grep -nE 'boot_as_recovery|splash|bootFileSystems|autoResize|boot\.usb\.features|kernel\.modules|modules' "$config" || true
  fi

  print_section "Conclusion"
  if [[ -f $config ]]; then
    local boot_as_recovery
    local auto_resize
    local splash_disabled
    boot_as_recovery=$(json_get_bool "$config" '.device.boot_as_recovery' '"boot_as_recovery"[[:space:]]*:[[:space:]]*false' "false")
    auto_resize=$(json_get_bool "$config" '.bootFileSystems["/"].autoResize' '"autoResize"[[:space:]]*:[[:space:]]*false' "false")
    splash_disabled=$(json_get_bool "$config" '.splash.disabled' '"disabled"[[:space:]]*:[[:space:]]*true' "true")

    echo "boot_as_recovery: $boot_as_recovery"
    echo "root autoResize: $auto_resize"
    echo "splash.disabled: $splash_disabled"
  else
    echo "boot_as_recovery: unknown (missing config)"
    echo "root autoResize: unknown (missing config)"
    echo "splash.disabled: unknown (missing config)"
  fi

  if [[ -e $initrd_dir/applets/boot-selection.mrb ]]; then
    echo "boot-selection.mrb: present"
  else
    echo "boot-selection.mrb: missing"
  fi

  if find "$initrd_dir" -maxdepth 4 \( -type f -o -type l \) | grep -Ei '/adb(d)?$|ffs\.adb|gadget' >/dev/null; then
    echo "adb/gadget content: present"
    find "$initrd_dir" -maxdepth 4 \( -type f -o -type l \) | grep -Ei '/adb(d)?$|ffs\.adb|gadget' | sort
  else
    echo "adb/gadget content: not found in shallow scan"
  fi
}

main "$@"
