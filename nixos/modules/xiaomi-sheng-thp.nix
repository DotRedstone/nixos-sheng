{ config, lib, pkgs, ... }:

let
  cfg = config.services.xiaomi-sheng-thp;
in
{
  options.services.xiaomi-sheng-thp = {
    enable = lib.mkEnableOption "Xiaomi sheng userspace touch and Focus Pen processing";

    package = lib.mkPackageOption pkgs "xiaomi-sheng-thp" { };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [ "uinput" ];
    environment.systemPackages = [ cfg.package ];

    systemd.services.xiaomi-sheng-thp = {
      description = "Xiaomi sheng NT36532E touch and Focus Pen processor";
      wantedBy = [ "multi-user.target" ];
      wants = [ "bluetooth.service" ];
      after = [
        "sheng-touchscreen-modules.service"
        "systemd-modules-load.service"
      ];
      before = [ "display-manager.service" ];
      unitConfig.StartLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        RuntimeDirectory = "xiaomi-sheng-thp";
        RuntimeDirectoryMode = "0755";
        ExecStartPre = pkgs.writeShellScript "wait-for-sheng-thp" ''
          for attempt in {1..100}; do
            if [ -r /proc/nvt_thp_stream ] && \
               [ -w /proc/nvt_thp_raw ] && \
               [ -w /proc/nvt_thp_stylus ] && \
               [ -c /dev/uinput ]; then
              exit 0
            fi
            ${pkgs.coreutils}/bin/sleep 0.1
          done

          echo "NT36532E THP interfaces did not become ready" >&2
          exit 1
        '';
        ExecStart = "${cfg.package}/libexec/xiaomi-sheng-thp/xiaomi-sheng-thp";
        Restart = "on-failure";
        RestartSec = "1s";
        KillSignal = "SIGINT";
        TimeoutStopSec = "10s";
      };
    };
  };
}
