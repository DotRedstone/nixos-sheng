# ---
# Module: Sheng Offline Charging
# Description: Android-style low-power userspace target for charger boot mode
# Scope: System
# ---

{ lib, pkgs, ... }:

let
  offlineChargingProgram = pkgs.writeScript "sheng-offline-charging" (
    builtins.replaceStrings
      [
        "@python@"
        "@systemctl@"
        "@framebufferPainter@"
      ]
      [
        "${pkgs.python3}/bin/python3"
        "${pkgs.systemd}/bin/systemctl"
        "${pkgs.sheng-fb-painter}/bin/sheng-fb-painter"
      ]
      (builtins.readFile ../scripts/sheng-offline-charging.py)
  );

  offlineChargingGenerator = pkgs.writeShellScript "sheng-offline-charging-generator" ''
    set -eu

    output_dir="$1"
    if ! reason="$(${offlineChargingProgram} detect 2>/dev/null)"; then
      exit 0
    fi

    echo "Sheng charger boot detected: $reason" >&2
    ${pkgs.coreutils}/bin/mkdir -p "$output_dir"
    ${pkgs.coreutils}/bin/ln -sfn \
      /etc/systemd/system/sheng-offline-charging.target \
      "$output_dir/default.target"
  '';
in
{
  systemd.generators.sheng-offline-charging = offlineChargingGenerator;

  systemd.targets.sheng-offline-charging = {
    description = "Sheng Offline Charging";
    requires = [
      "basic.target"
      "systemd-udev-settle.service"
    ];
    wants = [
      "systemd-modules-load.service"
      "sheng-sensor-files.service"
      "adsprpcd.service"
      "pd-mapper.service"
      "xiaomi-mipps-auth.service"
    ];
    after = [
      "basic.target"
      "systemd-modules-load.service"
      "systemd-udev-settle.service"
      "sheng-sensor-files.service"
      "adsprpcd.service"
      "pd-mapper.service"
    ];
    unitConfig = {
      AllowIsolate = true;
      Conflicts = "graphical.target shutdown.target";
    };
  };

  systemd.services.sheng-offline-charging = {
    description = "Monitor sheng offline charging mode";
    wantedBy = [ "sheng-offline-charging.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${offlineChargingProgram} monitor";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.services.xiaomi-mipps-auth.after = lib.mkAfter [ "pd-mapper.service" ];
}
