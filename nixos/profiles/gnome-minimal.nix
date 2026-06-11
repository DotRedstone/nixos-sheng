# ---
# Module: GNOME Minimal Profile
# Description: Minimal GNOME desktop environment configuration
# Scope: System
# ---

{ lib, pkgs, ... }:

let
  powerKeyDisplayToggle = pkgs.writeScript "sheng-power-key-display-toggle" ''
    #!${pkgs.python3.withPackages (p: [ p.evdev ])}/bin/python3
    import evdev
    import subprocess
    import time
    import sys
    import os

    device_path = "/dev/input/by-path/platform-c400000.spmi-platform-c400000.spmi:pmic@0:pon@1300:pwrkey-event"

    def get_active_session_info():
        try:
            out = subprocess.check_output(["${pkgs.systemd}/bin/loginctl", "list-sessions", "--no-legend"], text=True)
            for line in out.strip().split("\n"):
                parts = line.split()
                if len(parts) >= 2:
                    session_id = parts[0]
                    state = subprocess.check_output(["${pkgs.systemd}/bin/loginctl", "show-session", session_id, "-p", "Active", "--value"], text=True).strip()
                    if state == "yes":
                        uid = subprocess.check_output(["${pkgs.systemd}/bin/loginctl", "show-session", session_id, "-p", "User", "--value"], text=True).strip()
                        username = subprocess.check_output(["${pkgs.coreutils}/bin/id", "-un", uid], text=True).strip()
                        return uid, username
        except Exception as e:
            print("Error getting session:", e, file=sys.stderr)
        return None, None

    def set_power_save_mode(uid, username, mode):
        bus = f"unix:path=/run/user/{uid}/bus"
        cmd = ["/run/wrappers/bin/su", "-s", "/bin/sh", username, "-c",
               f"DBUS_SESSION_BUS_ADDRESS={bus} ${pkgs.systemd}/bin/busctl --user set-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode i {mode}"]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def simulate_user_activity(ui):
        # Inject a harmless key event to libinput to natively wake GNOME and force a screen repaint
        ui.write(evdev.ecodes.EV_KEY, evdev.ecodes.KEY_WAKEUP, 1)
        ui.syn()
        time.sleep(0.01)
        ui.write(evdev.ecodes.EV_KEY, evdev.ecodes.KEY_WAKEUP, 0)
        ui.syn()

    def get_power_save_mode(uid, username):
        bus = f"unix:path=/run/user/{uid}/bus"
        cmd = ["/run/wrappers/bin/su", "-s", "/bin/sh", username, "-c",
               f"DBUS_SESSION_BUS_ADDRESS={bus} ${pkgs.systemd}/bin/busctl --user get-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode"]
        try:
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
            if out:
                return int(out.split()[-1])
        except Exception as e:
            print("Error getting power save mode:", e, file=sys.stderr)
        return -1

    while not os.path.exists(device_path):
        time.sleep(1)

    dev = evdev.InputDevice(device_path)
    ui = evdev.UInput(name="sheng-power-wakeup")
    
    # Exclusively grab the power button so GNOME/libinput never sees the events
    # This completely solves the race condition of GNOME auto-waking the screen
    try:
        dev.grab()
    except Exception as e:
        print("Failed to grab device:", e, file=sys.stderr)
        sys.exit(1)

    for event in dev.read_loop():
        if event.type == evdev.ecodes.EV_KEY and event.code == evdev.ecodes.KEY_POWER and event.value == 1:
            uid, username = get_active_session_info()
            if uid and username:
                mode = get_power_save_mode(uid, username)
                if mode == 0:
                    set_power_save_mode(uid, username, 3)
                else:
                    # Simulate activity to properly wake GNOME session (fixes blank screen without repaint)
                    simulate_user_activity(ui)
                    # Also set DisplayConfig just to be safe
                    set_power_save_mode(uid, username, 0)
  '';
in
{
  services.xserver.enable = true;
  services.xserver.desktopManager.xterm.enable = false;
  services.xserver.excludePackages = [ pkgs.xterm ];
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
        lid-close-ac-action = "blank";
        lid-close-battery-action = "blank";
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

      # 确保 GNOME 旋转插件处于激活状态且默认不锁定旋转
      settings."org/gnome/settings-daemon/plugins/orientation" = {
        active = true;
      };
      settings."org/gnome/settings-daemon/peripherals/touchscreen" = {
        orientation-lock = false;
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
        lid-close-ac-action = "blank";
        lid-close-battery-action = "blank";
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
