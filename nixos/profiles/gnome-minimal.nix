{ lib, pkgs, ... }:

let
  gjs-osk = pkgs.callPackage ../packages/gjs-osk.nix { };
  powerKeyDisplayToggle = pkgs.writeShellScript "sheng-power-key-display-toggle" ''
    set -u

    device=/dev/input/by-path/platform-c400000.spmi-platform-c400000.spmi:pmic@0:pon@1300:pwrkey-event

    ${pkgs.evtest}/bin/evtest --grab "$device" | while read -r line; do
      if [[ "$line" == *"type 1 (EV_KEY), code 116 (KEY_POWER), value 1"* ]]; then
        active_uid=""
        for session in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend | ${pkgs.gawk}/bin/awk '{print $1}'); do
          state=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p State --value)
          if [ "$state" = "active" ]; then
            active_uid=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p UID --value)
            break
          fi
        done

        if [ -n "$active_uid" ]; then
          active_user=$(id -un "$active_uid")
          bus_address="unix:path=/run/user/$active_uid/bus"

          mode_output=$(su -s /bin/sh "$active_user" -c "DBUS_SESSION_BUS_ADDRESS=$bus_address ${pkgs.systemd}/bin/busctl --user get-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode" 2>/dev/null || true)
          
          if [ -n "$mode_output" ]; then
            mode=$(echo "$mode_output" | ${pkgs.gawk}/bin/awk '{print $2}')
            if [ "$mode" -eq 0 ]; then
              target=3
            else
              target=0
            fi
            su -s /bin/sh "$active_user" -c "DBUS_SESSION_BUS_ADDRESS=$bus_address ${pkgs.systemd}/bin/busctl --user set-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode i $target" >/dev/null 2>&1 || true
          fi
        fi
      fi
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

  environment.systemPackages = with pkgs; [
    gjs-osk
    gnome-console
    nautilus
  ];
}
