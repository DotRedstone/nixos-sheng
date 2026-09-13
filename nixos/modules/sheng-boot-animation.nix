# ---
# Module: Sheng Boot Presentation
# Description: Keep boot logs on the diagnostic VT and hand the native animation to the display manager
# Scope: System
# ---
{ config, lib, pkgs, ... }:
let
  painter = "${pkgs.sheng-fb-painter}/bin/sheng-fb-painter";
  control = "/run/sheng-boot-ui";
  hasDisplayManager = config.services.displayManager.enable;
in
{
  # VT1 belongs to the display manager, VT2 to the boot UI. The kernel can
  # append loglevel=6, so quiet alone is insufficient: fbcon only maps VT3-6.
  mobile.boot.defaultConsole = "tty3";
  boot.kernelParams = [ "quiet" "fbcon=vc:3-6" ];

  # Keep the full stage-1 bootlog and journal; this only changes presentation.
  systemd.settings.Manager.ShowStatus = false;
  systemd.services."getty@tty1".enable = false;
  systemd.services."kmsconvt@tty1".enable = false;
  systemd.services."getty@tty2".enable = false;
  systemd.services."kmsconvt@tty2".enable = false;

  boot.postBootCommands = lib.mkAfter (lib.optionalString (!hasDisplayManager) ''
    ${painter} --stop ${control} || true
    ${painter} --details ${control} || true
  '');

  systemd.services.sheng-boot-splash = {
    description = "Sheng rounded boot animation";
    wantedBy = lib.optional hasDisplayManager "graphical.target";
    before = [ "display-manager.service" ];
    after = [ "local-fs.target" ];
    conflicts = [ "shutdown.target" "emergency.target" "rescue.target" "sheng-offline-charging.target" ];
    onFailure = [ "sheng-boot-details.service" ];
    unitConfig = {
      ConditionPathExists = [ "${control}.normal" "!${control}.disabled" "!${control}.done" ];
      ConditionKernelCommandLine = "!sheng.boot-ui=0";
    };
    serviceConfig = {
      Type = "simple";
      # Retire the stage-1 process and its initrd mappings before starting the
      # stage-2 process. Both retain the last frame during this short handoff.
      ExecStartPre = "${painter} --stop ${control}";
      ExecStart = "${painter} --animate ${pkgs.sheng-boot-animation} start ${control}";
      # Type=simple alone would allow GDM to stop us before the child had
      # acquired its writer lock. Complete startup only after its first paint.
      ExecStartPost = pkgs.writeShellScript "sheng-boot-splash-ready" ''
        for attempt in $(${pkgs.coreutils}/bin/seq 1 50); do
          test -e ${control}.ready && exit 0
          test -e ${control}.disabled && exit 1
          ${pkgs.coreutils}/bin/sleep 0.1
        done
        exit 1
      '';
      ExecStop = "${painter} --stop ${control}";
      TimeoutStartSec = 10;
      TimeoutStopSec = 5;
      StandardOutput = "journal";
      StandardError = "journal";
      Restart = "no";
    };
  };

  systemd.services.display-manager = lib.mkIf hasDisplayManager {
    preStart = lib.mkBefore ''
      # Do not replay the boot UI when a later system switch restarts units.
      ${pkgs.coreutils}/bin/touch ${control}.done
      # Acknowledge the writer's exit before the compositor acquires scanout.
      ${painter} --stop ${control} || true
    '';
    onFailure = [ "sheng-boot-details.service" ];
  };
  systemd.services.sheng-boot-details = {
    description = "Show Sheng boot diagnostics";
    wantedBy = [ "emergency.target" "rescue.target" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${painter} --details ${control}";
    };
  };
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "sheng-boot-details" ''
      exec ${painter} --details ${control}
    '')
  ];
}
