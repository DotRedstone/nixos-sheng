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

  offlineChargingGenerator = pkgs.writeShellScript "sheng-offline-charging-generator" ''
    set -eu

    # NixOS installs /etc/systemd/system/default.target. Only generator.early
    # precedes that path in systemd's unit lookup order.
    output_dir="$2"
    boot_mode=/run/sheng-boot-ui.mode
    normal_reboot_marker=/var/lib/sheng-offline-charging/force-normal-once
    if [ -r "$boot_mode" ]; then
      IFS= read -r decided_mode < "$boot_mode" || decided_mode=
      case "$decided_mode" in
        normal)
          echo "Sheng stage-1 selected the normal boot target." >&2
          exit 0
          ;;
        charger)
          reason="stage-1-decision=charger"
          ;;
        *)
          echo "Sheng stage-1 boot decision is invalid; falling back to PON detection." >&2
          reason=
          ;;
      esac
    fi
    if [ -z "''${reason:-}" ] && [ -e "$normal_reboot_marker" ]; then
      # Stage 1 saw this marker before deciding whether to enter charger mode.
      # This is a fallback for paths that reach stage 2 without the explicit
      # /run decision. An actual poweroff starts with a fresh /run.
      rm -f "$normal_reboot_marker"
      echo "Sheng normal reboot marker detected; keeping the normal boot target." >&2
      exit 0
    fi
    if [ -z "''${reason:-}" ] && ! reason="$(${offlineChargingProgram} detect 2>/dev/null)"; then
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
      Conflicts = "graphical.target shutdown.target";
    };
  };

  systemd.services.sheng-offline-charging = {
    description = "Monitor sheng offline charging mode";
    wantedBy = [ "sheng-offline-charging.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${offlineChargingProgram} monitor";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.services.xiaomi-mipps-auth.after = lib.mkAfter [ "pd-mapper.service" ];
}
