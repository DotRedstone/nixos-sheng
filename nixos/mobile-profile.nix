{ config, lib, pkgs, ... }:

{
  mobile.enable = true;

  mobile.generatedFilesystems.rootfs = {
    name = "nixos-sheng-rootfs";
    label = lib.mkForce "linux";
    location = lib.mkForce "/rootfs.img";
    extraPadding = lib.mkForce (1024 * 1024 * 1024);
  };

  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-partlabel/linux";
    fsType = "ext4";
    neededForBoot = true;
    autoResize = true;
    options = [ "noatime" "errors=remount-ro" ];
  };

  mobile.boot.stage-1 = {
    compression = "gzip";
    crashToBootloader = false;

    bootConfig = {
      log.level = "DEBUG";
      boot.fail.shell = true;
    };

    gui = {
      enable = true;
      waitForDevices = {
        enable = true;
        delay = 2;
      };
    };

    shell.shellOnFail = true;

    kernel = {
      package = null;
      modular = false;
      modules = [ ];
      additionalModules = [ ];
    };
  };

  mobile.boot.stage-1.fail.reboot = false;

  mobile.adbd.enable = lib.mkDefault false;

  mobile.beautification.silentBoot = lib.mkForce false;

  documentation.enable = false;
}
