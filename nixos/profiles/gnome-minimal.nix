{ lib, pkgs, ... }:

{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # GDM owns the display VT in this image.
  services.kmscon.enable = lib.mkForce false;

  hardware.graphics.enable = true;

  services.gnome = {
    core-apps.enable = false;
    core-developer-tools.enable = false;
    games.enable = false;
    evolution-data-server.enable = false;
    gnome-browser-connector.enable = false;
    gnome-initial-setup.enable = false;
    gnome-online-accounts.enable = false;
    gnome-remote-desktop.enable = false;
    gnome-user-share.enable = false;
    localsearch.enable = false;
    rygel.enable = false;
    tinysparql.enable = false;
  };

  services.dleyna.enable = false;

  environment.systemPackages = with pkgs; [
    gnome-console
    nautilus
  ];
}
