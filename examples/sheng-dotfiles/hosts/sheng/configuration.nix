# ---
# Module: Personal Sheng Host
# Description: Defines the private user and system preferences layered over the sheng platform
# Scope: System
# ---

{ pkgs, ... }:

{
  networking.hostName = "nixos-sheng";
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.user = {
    isNormalUser = true;
    initialPassword = "change-me";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" "render" ];
  };

  environment.systemPackages = with pkgs; [
    git
    vim
  ];
}
