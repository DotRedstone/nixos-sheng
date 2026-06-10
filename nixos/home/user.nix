# ---
# Module: User Profile
# Description: Home Manager configuration for the dynamic user
# Scope: Home Manager
# ---

{ pkgs, lib, vars, ... }:

{
  home.username = vars.username;
  home.homeDirectory = "/home/${vars.username}";
  home.stateVersion = "25.05";

  # Workaround for Home Manager unstable zipAttrsWith conflict on fontconfig
  fonts.fontconfig.enable = lib.mkForce false;

  programs.home-manager.enable = true;

  programs.bash = {
    enable = true;
    shellAliases = {
      nrs = "sudo nixos-rebuild switch --flake /home/${vars.username}/nixos-xiaomi-sheng/nixos#sheng";
      hms = "home-manager switch --flake /home/${vars.username}/nixos-xiaomi-sheng/nixos#${vars.username}@sheng";
    };
  };

  dconf.settings = {
    "org/gnome/desktop/default-applications/terminal" = {
      exec = "kgx";
      exec-arg = "-e";
    };
  };

  home.packages = let
    sheng-check = pkgs.writeShellScriptBin "sheng-check" (builtins.readFile ../scripts/sheng-check.sh);
  in with pkgs; [
    sheng-check
    gjs-osk
    gnome-console
    nautilus
    curl
    evtest
    gitMinimal
    brightnessctl
    iproute2
    iw
    nano
    pciutils
    usbutils
    vim
    wget
  ];
}
