{ lib, pkgs, ... }:

let
  headlessStage1Task = pkgs.writeTextDir "zz-sheng-headless-stage1.rb" (
    builtins.readFile ./patches/stage-1-headless-no-gui.rb
  );
in
{
  mobile.enable = true;

  mobile.generatedFilesystems.rootfs = {
    name = "nixos-sheng-rootfs";
    filesystem = lib.mkDefault "ext4";
    label = lib.mkForce "linux";
    location = lib.mkForce "/rootfs.img";
    extraPadding = lib.mkForce (1024 * 1024 * 1024);
  };

  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-partlabel/linux";
    fsType = "ext4";
    neededForBoot = true;
    autoResize = false;
    options = [ "noatime" ];
  };

  mobile.boot.stage-1 = {
    compression = "gzip";
    crashToBootloader = false;

    bootConfig = {
      log.level = "DEBUG";
      boot.fail.shell = true;
      splash.disabled = true;
    };

    gui.enable = false;

    tasks = [
      headlessStage1Task
    ];

    shell.shellOnFail = true;

    kernel.modules = [ ];
    kernel.additionalModules = [ ];
  };

  mobile.boot.stage-1.fail.reboot = false;

  mobile.adbd.enable = lib.mkDefault true;

  mobile.beautification.silentBoot = lib.mkForce false;

  documentation.enable = false;
}
