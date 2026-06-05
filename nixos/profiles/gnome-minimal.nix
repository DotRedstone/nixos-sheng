{ lib, pkgs, ... }:

let
  optionalPackages = names:
    builtins.filter (package: package != null) (
      map (name: lib.attrByPath [ name ] null pkgs) names
    );
in
{
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # GDM owns the display VT in this image.
  services.kmscon.enable = lib.mkForce false;

  hardware.graphics.enable = true;

  environment.gnome.excludePackages = optionalPackages [
    "baobab"
    "cheese"
    "decibels"
    "epiphany"
    "evince"
    "geary"
    "gnome-calendar"
    "gnome-characters"
    "gnome-clocks"
    "gnome-connections"
    "gnome-contacts"
    "gnome-font-viewer"
    "gnome-logs"
    "gnome-maps"
    "gnome-music"
    "gnome-system-monitor"
    "gnome-text-editor"
    "gnome-tour"
    "gnome-weather"
    "loupe"
    "simple-scan"
    "snapshot"
    "totem"
    "yelp"
  ];

  environment.systemPackages = with pkgs; [
    gnome-console
    nautilus
  ];
}
