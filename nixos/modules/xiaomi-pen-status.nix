{ config, lib, pkgs, ... }:

let
  cfg = config.services.xiaomi-pen-status;
in
{
  options.services.xiaomi-pen-status = {
    enable = lib.mkEnableOption "Xiaomi Focus Pen status and Bluetooth auto-connection";

    package = lib.mkPackageOption pkgs "xiaomi-pen-status" { };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # The background instance runs on the graphical session bus so that BlueZ
    # pairing prompts, notifications, and the tray UI use the logged-in user.
    environment.etc."xdg/autostart/xiaomi-pen-status.desktop".source =
      "${cfg.package}/etc/xdg/autostart/xiaomi-pen-status.desktop";
  };
}
