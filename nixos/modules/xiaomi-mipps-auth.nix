# ---
# Module: Xiaomi MIPPS Auth Service
# Description: Systemd service for Xiaomi MIPPS authentication
# Scope: Service
# ---

{ config, lib, pkgs, ... }:

let
  cfg = config.services.xiaomi-mipps-auth;
  package = pkgs.callPackage ../packages/xiaomi-mipps-auth.nix { };
in
{
  options.services.xiaomi-mipps-auth.enable =
    lib.mkEnableOption "Xiaomi MiPPS/PPS charger authentication";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ package ];

    systemd.services.xiaomi-mipps-auth = {
      description = "Xiaomi MiPPS/PPS charger authentication";
      unitConfig.ConditionPathExistsGlob =
        "/sys/devices/platform/pmic-glink/*/xiaomi/request_vdm_cmd";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.util-linux}/bin/flock -n -E 0 /run/xiaomi-mipps-auth.lock ${package}/bin/xiaomi-mipps-auth --timeout 4 --once-per-attach";
        TimeoutStartSec = 20;
      };
    };

    services.udev.extraRules = ''
      # Delegate Xiaomi MiPPS authentication to systemd after a USB-C partner attaches.
      ACTION=="add", SUBSYSTEM=="typec", KERNEL=="port*-partner", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xiaomi-mipps-auth.service"
    '';
  };
}
