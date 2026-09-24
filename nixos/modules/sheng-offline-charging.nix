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
        "@chargingFont@"
      ]
      [
        "${pkgs.python3.withPackages (ps: [ ps.pillow ])}/bin/python3"
        "${pkgs.systemd}/bin/systemctl"
        "${pkgs.sheng-fb-painter}/bin/sheng-fb-painter"
        "${pkgs.inter}/share/fonts/truetype/Inter.ttc"
      ]
      (builtins.readFile ../scripts/sheng-offline-charging.py)
  );

  offlineChargingGenerator = pkgs.writeShellScript "sheng-offline-charging-generator" (
    builtins.replaceStrings
      [ "@detect@" "@mv@" "@mkdir@" "@ln@" ]
      [ "${offlineChargingProgram}" "${pkgs.coreutils}/bin/mv"
        "${pkgs.coreutils}/bin/mkdir" "${pkgs.coreutils}/bin/ln" ]
      (builtins.readFile ../scripts/sheng-offline-charging-generator.sh)
  );
in
{
  systemd.services.sheng-normal-reboot-marker = {
    description = "Preserve normal boot mode across USB-connected reboots";
    wantedBy = [ "reboot.target" ];
    before = [ "shutdown.target" "systemd-reboot.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "sheng-normal-reboot-marker" ''
        set -eu
        marker_dir=/var/lib/sheng-offline-charging
        marker="$marker_dir/force-normal-once"
        ${pkgs.coreutils}/bin/mkdir -p "$marker_dir"
        temporary="$(${pkgs.coreutils}/bin/mktemp "$marker_dir/.force-normal-once.XXXXXX")"
        printf '%s\\n' normal-reboot > "$temporary"
        ${pkgs.coreutils}/bin/mv -f "$temporary" "$marker"
        ${pkgs.coreutils}/bin/sync -f "$marker" || true
      '';
    };
  };

  # Mobile NixOS starts the stage-2 manager without running this custom
  # generator in every boot path. Clean the one-shot handoff marker from a
  # regular early service as well, after stage 1 has made its decision.
  systemd.services.sheng-consume-normal-reboot-marker = {
    description = "Consume the completed normal reboot marker";
    wantedBy = [ "basic.target" ];
    after = [ "local-fs.target" ];
    before = [ "shutdown.target" ];
    unitConfig.ConditionPathExists = "/var/lib/sheng-offline-charging/force-normal-once";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/rm -f /var/lib/sheng-offline-charging/force-normal-once";
    };
  };

  systemd.generators.sheng-offline-charging = offlineChargingGenerator;

  systemd.targets.sheng-offline-charging = {
    description = "Sheng Offline Charging";
    requires = [ "basic.target" ];
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
      "sheng-sensor-files.service"
      "adsprpcd.service"
      "pd-mapper.service"
    ];
    unitConfig = {
      AllowIsolate = true;
      Conflicts = "graphical.target display-manager.service sheng-boot-splash.service shutdown.target";
    };
  };

  systemd.services.sheng-offline-charging = {
    description = "Monitor sheng offline charging mode";
    wantedBy = [ "sheng-offline-charging.target" ];
    partOf = [ "sheng-offline-charging.target" ];
    conflicts = [ "display-manager.service" "sheng-boot-splash.service" "sheng-boot-details.service" ];
    before = [ "display-manager.service" "sheng-boot-splash.service" "sheng-boot-details.service" ];
    serviceConfig = {
      Type = "simple";
      ExecCondition = "${offlineChargingProgram} is-charger";
      # Stop the initrd writer too, even if the stage-2 splash unit never ran.
      ExecStartPre = "${pkgs.sheng-fb-painter}/bin/sheng-fb-painter --stop /run/sheng-boot-ui";
      ExecStart = "${offlineChargingProgram} monitor";
      Restart = "on-failure";
      RestartSec = 2;
      TimeoutStopSec = 6;
    };
  };

  systemd.services.xiaomi-mipps-auth.after = lib.mkAfter [ "pd-mapper.service" ];
}
