# ---
# Module: Sheng Boot Slot
# Description: Mark the NixOS B slot successful after userspace is usable
# Scope: System
# ---

{ pkgs, ... }:

let
  markBootSuccessful = pkgs.writeShellScript "sheng-mark-boot-successful" ''
    set -eu

    current="$(${pkgs.qbootctl}/bin/qbootctl -c)"
    if [ "$current" != "Current slot: _b" ]; then
      echo "Refusing to update boot metadata: expected slot _b, got: $current" >&2
      exit 1
    fi

    exec ${pkgs.qbootctl}/bin/qbootctl -m b
  '';
in
{
  environment.systemPackages = [ pkgs.qbootctl ];

  systemd.services.sheng-mark-boot-successful = {
    description = "Mark the NixOS boot slot successful";
    wantedBy = [ "graphical.target" ];
    after = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = [
      "/dev/disk/by-partlabel/boot_a"
      "/dev/disk/by-partlabel/boot_b"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = markBootSuccessful;
      RemainAfterExit = true;
      TimeoutStartSec = 30;
    };
  };
}
