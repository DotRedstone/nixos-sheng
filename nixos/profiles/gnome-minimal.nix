# ---
# Module: GNOME Minimal Profile
# Description: Minimal GNOME desktop environment configuration
# Scope: System
# ---

{ lib, pkgs, ... }:

let
  gjs-osk = pkgs.callPackage ../packages/gjs-osk.nix { };
  powerKeyDisplayToggle = pkgs.writeShellScript "sheng-power-key-display-toggle" ''
    set -u

    device=/dev/input/by-path/platform-c400000.spmi-platform-c400000.spmi:pmic@0:pon@1300:pwrkey-event

    get_active_session_info() {
      for session in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend | ${pkgs.gawk}/bin/awk '{print $1}'); do
        local state
        state=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Active --value 2>/dev/null || true)
        if [ "$state" = "yes" ]; then
          ${pkgs.systemd}/bin/loginctl show-session "$session" -p UID --value 2>/dev/null || true
          return
        fi
      done
    }

    get_power_save_mode() {
      local uid="$1"
      local user
      user=$(id -un "$uid" 2>/dev/null || true)
      [ -z "$user" ] && echo "unknown" && return
      local bus="unix:path=/run/user/$uid/bus"
      local out
      out=$(su -s /bin/sh "$user" -c "DBUS_SESSION_BUS_ADDRESS=$bus ${pkgs.systemd}/bin/busctl --user get-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode" 2>/dev/null || true)
      if [ -n "$out" ]; then
        echo "$out" | ${pkgs.gawk}/bin/awk '{print $2}'
      else
        echo "unknown"
      fi
    }

    set_power_save_mode() {
      local uid="$1"
      local target="$2"
      local user
      user=$(id -un "$uid" 2>/dev/null || true)
      [ -z "$user" ] && return
      local bus="unix:path=/run/user/$uid/bus"
      su -s /bin/sh "$user" -c "DBUS_SESSION_BUS_ADDRESS=$bus ${pkgs.systemd}/bin/busctl --user set-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode i $target" >/dev/null 2>&1 || true
    }

    ${pkgs.coreutils}/bin/stdbuf -oL ${pkgs.evtest}/bin/evtest "$device" 2>/dev/null | while IFS= read -r line; do
      case "$line" in
        *"type 1 (EV_KEY), code 116 (KEY_POWER), value 1"*)
          uid=$(get_active_session_info)
          if [ -n "$uid" ]; then
            mode=$(get_power_save_mode "$uid")
            if [ "$mode" = "0" ]; then
              set_power_save_mode "$uid" 3
            else
              set_power_save_mode "$uid" 0
            fi
          fi
          ;;
      esac
    done
  '';
in
{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.desktopManager.gnome.sessionPath = [
    pkgs.gnome-settings-daemon
  ];

  # GDM owns the display VT in this image.
  services.kmscon.enable = lib.mkForce false;

  hardware.graphics.enable = true;

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/shell" = {
        enabled-extensions = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
      };

      settings."org/gnome/desktop/a11y/applications" = {
        screen-keyboard-enabled = true;
      };

      settings."org/gnome/settings-daemon/plugins/power" = {
        power-button-action = "nothing";
      };

      settings."org/gnome/shell/extensions/gjsosk" = {
        enable-drag = true;
        enable-tap-gesture = lib.gvariant.mkInt32 1;
        indicator-enabled = true;
        landscape-width-percent = lib.gvariant.mkInt32 70;
        landscape-height-percent = lib.gvariant.mkInt32 30;
        portrait-width-percent = lib.gvariant.mkInt32 100;
        portrait-height-percent = lib.gvariant.mkInt32 30;
      };
    }
  ];

  # GDM uses a separate dconf profile. Keep the greeter on GNOME's native OSK
  # so the third-party movable keyboard cannot interfere with password entry.
  programs.dconf.profiles.gdm.databases = [
    {
      settings."org/gnome/login-screen" = {
        enable-password-authentication = true;
        disable-user-list = false;
      };

      settings."org/gnome/desktop/a11y/applications" = {
        screen-keyboard-enabled = true;
      };

      settings."org/gnome/settings-daemon/plugins/power" = {
        power-button-action = "nothing";
        sleep-inactive-ac-type = "nothing";
        sleep-inactive-battery-type = "nothing";
      };

      settings."org/gnome/desktop/session" = {
        idle-delay = lib.gvariant.mkUint32 300;
      };

      settings."org/gnome/shell" = {
        enabled-extensions = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
      };
    }
  ];

  services.gnome = {
    core-apps.enable = lib.mkForce false;
    core-developer-tools.enable = lib.mkForce false;
    games.enable = lib.mkForce false;
    evolution-data-server.enable = lib.mkForce false;
    gnome-browser-connector.enable = lib.mkForce false;
    gnome-initial-setup.enable = lib.mkForce false;
    gnome-online-accounts.enable = lib.mkForce false;
    gnome-remote-desktop.enable = lib.mkForce false;
    gnome-user-share.enable = lib.mkForce false;
    localsearch.enable = lib.mkForce false;
    rygel.enable = lib.mkForce false;
    tinysparql.enable = lib.mkForce false;
  };

  services.dleyna.enable = lib.mkForce false;

  systemd.services.sheng-power-key-display-toggle = {
    description = "Toggle the sheng display with the power key";
    wantedBy = [ "multi-user.target" ];
    after = [ "display-manager.service" ];
    serviceConfig = {
      ExecStart = powerKeyDisplayToggle;
      Restart = "always";
      RestartSec = 1;
    };
  };

}
