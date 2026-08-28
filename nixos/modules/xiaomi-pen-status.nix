{ config, lib, pkgs, ... }:

let
  cfg = config.services.xiaomi-pen-status;

  penPower = pkgs.writeShellApplication {
    name = "xiaomi-pen-power";
    text = ''
      sysfs=/sys/devices/platform/pmic-glink/pmic_glink.power-supply.0/xiaomi

      while [[ ! -w "$sysfs/reverse_chg_mode" ]]; do
        sleep 1
      done

      while true; do
        if ! hall3=$(<"$sysfs/pen_hall3") || ! hall4=$(<"$sysfs/pen_hall4"); then
          sleep 1
          continue
        fi

        target=0
        if [[ "$hall3" == 0 || "$hall4" == 0 ]]; then
          target=1
        fi

        if ! mode=$(<"$sysfs/reverse_chg_mode") || [[ "$mode" != "$target" ]]; then
          printf '%s\n' "$target" > "$sysfs/reverse_chg_mode"
        fi

        sleep 1
      done
    '';
  };
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

    systemd.services.xiaomi-pen-power = {
      description = "Xiaomi Focus Pen wireless power controller";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udev-settle.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe penPower;
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
