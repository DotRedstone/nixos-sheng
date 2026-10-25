#!/usr/bin/env bash

# ---
# Module: Sheng EFI Generations
# Description: Mirrors installed NixOS system profiles into systemd-boot entries on the dedicated ESP
# Scope: Script
# ---
set -euo pipefail

esp=${1:?ESP path required}
profiles=${2:-/nix/var/nix/profiles}
entries=$esp/loader/entries
loader_conf=$esp/loader/loader.conf

[[ $(id -u) == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ -f $loader_conf && -d $entries && -d $profiles ]] || {
  echo 'EFI loader or system profiles are missing.' >&2
  exit 1
}

# /boot 是直接自动挂载点；先读取目录，确保 findmnt 能看到 FAT 挂载层。
ls -1 "$esp" >/dev/null
source=$(findmnt -rn -o SOURCE,FSTYPE --target "$esp" | awk '$2 == "vfat" { print $1; exit }')
[[ -n $source && $(blkid -s PARTLABEL -o value "$source") == linux-boot ]] || {
  echo "$esp is not the linux-boot FAT ESP." >&2
  exit 1
}

exec 9>"$esp/.sheng-efi-generations.lock"
flock -x 9

default_entry=$(awk '$1 == "default" { print $2; exit }' "$loader_conf")
[[ $default_entry =~ ^nixos-sheng-[A-Za-z0-9._-]+\.conf$ && -f $entries/$default_entry ]] || {
  echo 'No valid Sheng EFI default entry.' >&2
  exit 1
}

field() {
  awk -v key="$1" '$1 == key { print $2; exit }' "$2"
}

base_entry=$default_entry
if [[ $default_entry == nixos-sheng-generation-*.conf ]]; then
  base_entry=
  selected_linux=$(field linux "$entries/$default_entry")
  for file in "$entries"/nixos-sheng-*.conf; do
    [[ -f $file && $(basename "$file") != nixos-sheng-generation-*.conf ]] || continue
    if [[ $(field linux "$file") == "$selected_linux" ]]; then
      base_entry=$(basename "$file")
      break
    fi
  done
fi
[[ -n $base_entry && -f $entries/$base_entry ]] || {
  echo 'Cannot identify the immutable Sheng EFI payload.' >&2
  exit 1
}

base=$entries/$base_entry
linux_path=$(field linux "$base")
initrd_path=$(field initrd "$base")
dtb_path=$(field devicetree "$base")
options=$(sed -n 's/^options //p' "$base" | head -n1)
[[ $linux_path == /EFI/NixOS/sheng-*/linux &&
   $initrd_path == /EFI/NixOS/sheng-*/initrd &&
   $dtb_path == /EFI/NixOS/sheng-*/sm8550-xiaomi-sheng.dtb ]] || {
  echo 'The base EFI entry does not point to a Sheng payload.' >&2
  exit 1
}
for path in "$linux_path" "$initrd_path" "$dtb_path"; do
  [[ -s $esp$path ]] || { echo "Missing EFI payload: $path" >&2; exit 1; }
done
kernel_identity=$esp${linux_path%/linux}/kernel.store-path
expected_kernel=
expected_version=
if [[ -s $kernel_identity ]]; then
  expected_kernel=$(<"$kernel_identity")
  [[ $expected_kernel == /nix/store/*-linux-* ]] || {
    echo 'Invalid EFI payload kernel identity.' >&2
    exit 1
  }
else
  # 旧载荷没有闭包标识；至少核对内核版本，不能把现用世代指向旧内核。
  base_version=$(field version "$base")
  expected_version=${base_version%%-*}
  [[ $expected_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo 'Invalid legacy EFI payload kernel version.' >&2
    exit 1
  }
fi

staging=$(mktemp -d "$esp/loader/.sheng-generations.XXXXXXXX")
trap 'rm -r -- "$staging"' EXIT
shopt -s nullglob
count=0
for profile in "$profiles"/system-*-link; do
  [[ -L $profile ]] || continue
  number=${profile##*/system-}
  number=${number%-link}
  [[ $number =~ ^[0-9]+$ ]] || continue
  target=$(readlink -f -- "$profile")
  [[ $target == /nix/store/*-nixos-system-* && -x $target/init ]] || continue
  [[ -e $target/kernel ]] || continue
  profile_kernel=$(readlink -f -- "$target/kernel")
  if [[ -n $expected_kernel ]]; then
    [[ ${profile_kernel%/*} == "$expected_kernel" ]] || continue
  else
    [[ ${profile_kernel%/*} == /nix/store/*-linux-"$expected_version" ]] || continue
  fi
  entry="nixos-sheng-generation-$number.conf"
  cat > "$staging/$entry" <<EOF
title NixOS Generation $number
version $number
sort-key nixos-sheng-generation
architecture aa64
options $options mobile-nixos.generation=$profile
linux $linux_path
initrd $initrd_path
devicetree $dtb_path
EOF
  count=$((count + 1))
done
[[ $count -gt 0 ]] || { echo 'No bootable system generations found.' >&2; exit 1; }

default_profile=$(readlink -- "$profiles/system")
[[ $default_profile =~ ^system-([0-9]+)-link$ ]] || {
  echo 'The default system profile is not a numbered generation.' >&2
  exit 1
}
selected="nixos-sheng-generation-${BASH_REMATCH[1]}.conf"
[[ -f $staging/$selected ]] || {
  echo 'The default system generation is not bootable.' >&2
  exit 1
}

# 先发布世代条目再切换默认项；保留固定 EFI 载荷条目以便回退。
for file in "$staging"/*.conf; do
  install -m 0644 "$file" "$entries/$(basename "$file").new"
  mv "$entries/$(basename "$file").new" "$entries/$(basename "$file")"
done
for file in "$entries"/nixos-sheng-generation-*.conf; do
  [[ -f $file ]] || continue
  [[ -f $staging/$(basename "$file") ]] || rm -- "$file"
done
rm -r -- "$staging"
trap - EXIT
sync

awk -v selected="$selected" '
  $1 == "default" { print "default " selected; found = 1; next }
  { print }
  END { if (!found) print "default " selected }
' "$loader_conf" > "$esp/loader/loader.conf.new"
mv "$esp/loader/loader.conf.new" "$loader_conf"

(
  cd "$esp"
  find EFI loader -type f ! -path 'loader/random-seed' ! -name '*.new' -print0 | sort -z | xargs -0 sha256sum > manifest.sha256.new
  mv manifest.sha256.new manifest.sha256
)
sync
echo "Synced $count NixOS generations; default is $selected using $base_entry."
