{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.sheng-fingerprint;
  package = pkgs.xiaomi-sheng-fingerprint;
  waitForQteeDevices = pkgs.writeShellScript "wait-for-qtee-devices" ''
    for attempt in $(seq 1 30); do
      if [ -c /dev/tee0 ] && {
        [ -e /dev/bsg/0:0:0:49476 ] || [ -e /dev/bsg/ufs-bsg0 ];
      }; then
        exit 0
      fi

      if [ "$attempt" -eq 30 ]; then
        echo "Timed out waiting for the QTEE and UFS RPMB devices" >&2
        exit 1
      fi

      sleep 1
    done
  '';
in
{
  options.services.sheng-fingerprint.enable = lib.mkEnableOption "the Xiaomi sheng FPC1553 fingerprint sensor";

  config = lib.mkIf cfg.enable {
    services.fprintd.enable = true;

    # GNOME Settings may run outside the logind session scope when activated
    # through the per-user service manager. Authorize device owners explicitly
    # so fprintd discovery does not fail and hide the fingerprint settings row.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id.indexOf("net.reactivated.fprint.device.") === 0 &&
            subject.isInGroup("wheel")) {
          return polkit.Result.YES;
        }
      });
    '';

    # GNOME Settings hides the fingerprint row when the GDM login-screen
    # schema is absent, even if fprintd already exposes a working device.
    environment.sessionVariables.XDG_DATA_DIRS = [
      "${pkgs.gdm}/share/gsettings-schemas/${pkgs.gdm.name}"
    ];

    environment.systemPackages = [ package ];

    services.udev.extraRules = ''
      SUBSYSTEM=="tee", KERNEL=="tee[0-9]*", MODE="0600", OWNER="root", GROUP="root", TAG+="systemd", ENV{SYSTEMD_WANTS}+="qteesupplicant.service"
    '';

    systemd.services.sfsconfig = {
      description = "QTEE secure-file-system configuration";
      before = [ "qteesupplicant.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${package}/libexec/fpc-sfs-config";
      };
    };

    systemd.services.qteesupplicant = {
      description = "Qualcomm TEE listener services";
      requires = [ "sfsconfig.service" ];
      after = [ "sfsconfig.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.LD_LIBRARY_PATH = "${package}/lib/qtee-listeners";
      serviceConfig = {
        Type = "exec";
        ExecStartPre = waitForQteeDevices;
        ExecStart = "${package}/libexec/qteesupplicant";
        Restart = "always";
        RestartSec = "2s";
        AmbientCapabilities = [ "CAP_SYS_RAWIO" ];
        CapabilityBoundingSet = [ "CAP_SYS_RAWIO" ];
        ProtectSystem = "full";
        ProtectHome = false;
        PrivateTmp = false;
        NoNewPrivileges = false;
        DeviceAllow = [
          "/dev/tee0 rw"
          "/dev/bsg/0:0:0:49476 rw"
          "/dev/bsg/ufs-bsg0 rw"
        ];
      };
    };

    systemd.services.fprintd = {
      requires = [ "qteesupplicant.service" ];
      after = [ "qteesupplicant.service" ];
      environment = {
        FP_FPC1553 = "1";
        FPC1553_TA_PATH = "${package}/lib/firmware/fpcsheng.elf";
        LD_LIBRARY_PATH = "${package}/lib/xiaomi-sheng-fingerprint";
      };
      serviceConfig = {
        StateDirectory = lib.mkForce "fprint fpc1553";
        StateDirectoryMode = "0700";
        DeviceAllow = [ "/dev/tee0 rw" ];
        ReadWritePaths = [ "/sys/devices" ];
      };
    };
  };
}
