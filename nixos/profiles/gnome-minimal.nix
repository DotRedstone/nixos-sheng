{ lib, pkgs, ... }:

let
  gjs-osk = pkgs.callPackage ../packages/gjs-osk.nix { };
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
        enabled-extensions = [ "gjsosk@vishram1123.com" ];
      };

      settings."org/gnome/desktop/a11y/applications" = {
        screen-keyboard-enabled = true;
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

  environment.systemPackages = with pkgs; [
    gjs-osk
    gnome-console
    nautilus
  ];
}
