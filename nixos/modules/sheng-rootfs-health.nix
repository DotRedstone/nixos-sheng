# ---
# Module: Sheng Root Filesystem Health
# Description: Periodic ext4 checks and automatic recovery from read-only protection
# Scope: System
# ---

{ pkgs, ... }:

let
  rootDevice = "/dev/disk/by-partlabel/linux";

  tuneRootfs = pkgs.writeShellScript "sheng-tune-rootfs" ''
    set -eu

    if [ ! -b ${rootDevice} ]; then
      echo "Root device ${rootDevice} is unavailable" >&2
      exit 1
    fi

    # e2fsck honors both limits in stage-1. This catches latent corruption
    # even when the journal and superblock still appear clean.
    ${pkgs.e2fsprogs}/bin/tune2fs -c 12 -i 14d ${rootDevice}
  '';

  checkRootfs = pkgs.writeShellScript "sheng-check-rootfs-health" ''
    set -eu

    source="$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE --target /)"
    kname="$(${pkgs.util-linux}/bin/lsblk -n -o KNAME "$source" | ${pkgs.coreutils}/bin/head -n 1)"
    errors_file="/sys/fs/ext4/$kname/errors_count"

    [ -r "$errors_file" ] || exit 0
    errors="$(cat "$errors_file")"
    [ "$errors" -gt 0 ] || exit 0

    # Only reboot when ext4 has actually protected the root by making it
    # read-only. A non-fatal counter increment is still preserved in logs.
    if : 2>/dev/null > /var/lib/sheng-rootfs-health/.writable-probe; then
      ${pkgs.util-linux}/bin/logger -p daemon.warning -t sheng-rootfs-health \
        "ext4 reported $errors error(s), but root remains writable"
      exit 0
    fi

    if ! ${pkgs.coreutils}/bin/mkdir /run/sheng-rootfs-recovery-requested 2>/dev/null; then
      exit 0
    fi

    message="Root filesystem entered read-only protection after $errors ext4 error(s); rebooting for offline repair."
    ${pkgs.util-linux}/bin/logger -p daemon.emerg -t sheng-rootfs-health "$message" || true
    printf '%s\n' "$message" | ${pkgs.util-linux}/bin/wall -n || true
    ${pkgs.coreutils}/bin/sync || true
    ${pkgs.coreutils}/bin/sleep 10
    ${pkgs.systemd}/bin/systemctl --no-block reboot
  '';

  rootfsStatus = pkgs.writeShellScriptBin "sheng-rootfs-status" ''
    set -u

    ${pkgs.util-linux}/bin/findmnt -T / -o SOURCE,TARGET,FSTYPE,OPTIONS
    echo
    ${pkgs.e2fsprogs}/bin/tune2fs -l ${rootDevice} 2>/dev/null \
      | ${pkgs.gnugrep}/bin/grep -E \
          'Filesystem state|Filesystem features|Errors behavior|Mount count|Maximum mount count|Last checked|Check interval|Lifetime writes'
    echo
    kname="$(${pkgs.util-linux}/bin/lsblk -n -o KNAME ${rootDevice} | ${pkgs.coreutils}/bin/head -n 1)"
    for field in errors_count first_error_time first_error_func first_error_line last_error_time last_error_func last_error_line; do
      if [ -r "/sys/fs/ext4/$kname/$field" ]; then
        printf '%-20s %s\n' "$field:" "$(cat "/sys/fs/ext4/$kname/$field")"
      fi
    done
  '';
in
{
  environment.systemPackages = [ rootfsStatus ];

  systemd.tmpfiles.rules = [
    "d /var/lib/sheng-rootfs-health 0755 root root -"
  ];

  systemd.services.sheng-rootfs-tune = {
    description = "Configure periodic checks for the sheng root filesystem";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = tuneRootfs;
      RemainAfterExit = true;
    };
  };

  systemd.services.sheng-rootfs-health = {
    description = "Detect ext4 read-only protection and request offline repair";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = checkRootfs;
    };
  };

  systemd.timers.sheng-rootfs-health = {
    description = "Periodically check the sheng root filesystem";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
      Unit = "sheng-rootfs-health.service";
    };
  };
}
