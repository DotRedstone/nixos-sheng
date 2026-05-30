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
  networking.useDHCP = lib.mkDefault true;

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";

  # Bring-up only: replace or remove this once stage-2 access is stable.
  users.users.root.initialPassword = "123456";
  users.users.luser = {
    isNormalUser = true;
    initialPassword = "luser";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" "render" ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };

  services.getty = {
    autologinUser = "luser";
    helpLine = ''
      NixOS sheng debug console
      Useful checks: dmesg -w, journalctl -b, ip addr, lsmod
    '';
  };

  console = {
    earlySetup = true;
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  services.kmscon = {
    enable = true;
    hwRender = false;
    extraConfig = ''
      font-size=18
    '';
  };

  environment.systemPackages = with pkgs; [
    curl
    e2fsprogs
    gitMinimal
    iproute2
    kmod
    nano
    pciutils
    util-linux
    usbutils
    vim
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
    "console=tty1"
    "console=ttyMSM0,115200n8"
    "fbcon=map:0"
    "fbcon=rotate:1"
    "root=PARTLABEL=linux"
    "rootwait"
    "logo.nologo"
    "loglevel=7"
    "systemd.show_status=true"
    "systemd.log_level=debug"
    "systemd.log_target=console"
    "udev.log_level=debug"
    "rd.udev.log_level=debug"
    "vt.global_cursor_default=1"
  ];

  boot.consoleLogLevel = 7;
  boot.initrd.verbose = true;

  boot.supportedFilesystems = [ "ext4" ];
}
