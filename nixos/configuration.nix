{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ./hardware-sheng.nix
    ./services/sheng-devauth.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  system.stateVersion = "25.11";

  networking.hostName = "nixos-sheng";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.root.initialPassword = "1234";
  users.users.luser = {
    isNormalUser = true;
    initialPassword = "luser";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" "render" ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh.enable = true;

  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
    displayManager.lightdm.enable = true;
  };

  services.displayManager = {
    defaultSession = "xfce";
    autoLogin = {
      enable = true;
      user = "luser";
    };
  };

  services.libinput.enable = true;
  hardware.graphics.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    foot
    gitMinimal
    kmod
    mesa-demos
    nano
    networkmanagerapplet
    pciutils
    xfce.xfce4-terminal
    usbutils
    vim
    vulkan-tools
    wget
  ];

  systemd.services."serial-getty@ttyMSM0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  services.udev.extraRules = ''
    ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"
  '';

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;

  boot.kernelParams = [
    "console=tty0"
    "console=ttyMSM0,115200n8"
    "ignore_loglevel"
    "loglevel=7"
    "root=PARTLABEL=linux"
    "rootwait"
    "systemd.log_level=debug"
  ];

  boot.supportedFilesystems = [ "ext4" ];
}
