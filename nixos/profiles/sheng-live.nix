# ---
# Module: Sheng Graphical Live Profile
# Description: Provides a local desktop and Nix tools for booting from linux-live
# Scope: System
# ---

{ config, lib, pkgs, ... }:

{
  networking.hostName = "sheng-live";
  services.displayManager.autoLogin = {
    enable = true;
    user = "live";
  };
  users.users.live = {
    isNormalUser = true;
    description = "Sheng Live";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" "render" ];
    # The local session must remain usable after GNOME locks the screen.
    initialHashedPassword = "";
  };
  security.sudo.wheelNeedsPassword = false;
  environment.systemPackages = with pkgs; [
    curl
    gnome-console
    iw
    nautilus
  ];

  services.openssh.enable = false;
  services.xiaomi-mipps-auth.enable = lib.mkForce false;
  mobile.adbd.enable = false;
  services.sheng-uboot-efi.enable = lib.mkForce false;
  systemd.services.sheng-mark-boot-successful.enable = false;
  fileSystems."/mnt/vendor/persist".options = lib.mkForce [ "ro" "noload" "noatime" ];
  mobile.boot.stage-1.bootConfig.sheng_generation_menu.enable = lib.mkForce false;

  system.build.shengLiveEfi = pkgs.callPackage ../packages/sheng-live-efi.nix {
    inherit (config.boot) kernelParams;
    kernel = config.system.build.kernel;
    initrd = config.mobile.outputs.initrd;
  };
}
