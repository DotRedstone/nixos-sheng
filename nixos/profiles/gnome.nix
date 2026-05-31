{ lib, pkgs, ... }:

{
  services.xserver.enable = lib.mkDefault true;
  services.displayManager.gdm.enable = lib.mkDefault true;
  services.desktopManager.gnome.enable = lib.mkDefault true;

  networking.networkmanager.enable = lib.mkDefault true;

  security.rtkit.enable = lib.mkDefault true;
  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };

  hardware.graphics.enable = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    gnome-console
    gnome-text-editor
    nautilus
    firefox
    usbutils
    pciutils
    alsa-utils
    libinput
    evtest
    iw
    bluez
    brightnessctl
    mesa-demos
    v4l-utils
    iio-sensor-proxy
  ];
}
