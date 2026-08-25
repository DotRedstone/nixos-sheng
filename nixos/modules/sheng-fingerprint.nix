{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.sheng-fingerprint;
  package = pkgs.xiaomi-sheng-fingerprint;
  wakeUnlock = pkgs.writeScript "sheng-fingerprint-wake-unlock" ''
    #!${pkgs.python3}/bin/python3
    import os
    import pwd
    import signal
    import subprocess
    import time

    BUSCTL = "${pkgs.systemd}/bin/busctl"
    FPRINTD_VERIFY = "${config.services.fprintd.package}/bin/fprintd-verify"
    LOGINCTL = "${pkgs.systemd}/bin/loginctl"
    MUTTER_DESTINATION = "org.gnome.Mutter.DisplayConfig"
    MUTTER_INTERFACE = "org.gnome.Mutter.DisplayConfig"
    MUTTER_PATH = "/org/gnome/Mutter/DisplayConfig"

    def output(*args):
        try:
            return subprocess.check_output(
                args, stderr=subprocess.DEVNULL, text=True, timeout=2
            ).strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    def display_session():
        session = output(LOGINCTL, "show-user", str(os.getuid()),
                         "-p", "Display", "--value")
        if not session:
            return ""
        active = output(LOGINCTL, "show-session", session,
                        "-p", "Active", "--value")
        return session if active == "yes" else ""

    def display_power_mode():
        value = output(BUSCTL, "--user", "get-property", MUTTER_DESTINATION,
                       MUTTER_PATH, MUTTER_INTERFACE, "PowerSaveMode")
        try:
            return int(value.rsplit(maxsplit=1)[-1])
        except (IndexError, ValueError):
            return -1

    def session_locked(session):
        return output(LOGINCTL, "show-session", session,
                      "-p", "LockedHint", "--value") == "yes"

    def wake_display(session):
        if session_locked(session):
            subprocess.run([LOGINCTL, "unlock-session", session], check=False)
        subprocess.run(
            [BUSCTL, "--user", "set-property", MUTTER_DESTINATION,
             MUTTER_PATH, MUTTER_INTERFACE, "PowerSaveMode", "i", "0"],
            check=False,
        )

    def stop_verification(process):
        if process.poll() is not None:
            return process.communicate()[0]
        process.send_signal(signal.SIGINT)
        try:
            return process.communicate(timeout=2)[0]
        except subprocess.TimeoutExpired:
            process.kill()
            return process.communicate()[0]

    while True:
        session = display_session()
        if not session or display_power_mode() != 3:
            time.sleep(0.25)
            continue

        process = subprocess.Popen(
            [FPRINTD_VERIFY, pwd.getpwuid(os.getuid()).pw_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        while process.poll() is None and display_power_mode() == 3:
            time.sleep(0.25)

        result = (process.communicate()[0] if process.poll() is not None
                  else stop_verification(process))
        if "verify-match" in result and display_power_mode() == 3:
            current_session = display_session()
            if current_session:
                wake_display(current_session)
                print("Fingerprint matched; woke and unlocked session",
                      flush=True)

        time.sleep(0.25)
  '';
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
  options.services.sheng-fingerprint = {
    enable = lib.mkEnableOption "the Xiaomi sheng FPC1553 fingerprint sensor";
    wakeUnlock = lib.mkEnableOption "fingerprint wake and unlock while the display is off";
  };

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

    systemd.user.services.sheng-fingerprint-wake-unlock = lib.mkIf cfg.wakeUnlock {
      description = "Wake and unlock the GNOME session with FPC1553";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" ];
      serviceConfig = {
        ExecStart = wakeUnlock;
        Restart = "always";
        RestartSec = "1s";
      };
    };
  };
}
