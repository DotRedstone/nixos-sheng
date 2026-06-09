# ---
# Module: User Profile
# Description: Home Manager configuration for the dynamic user
# Scope: Home Manager
# ---

{ pkgs, vars, ... }:

{
  home.username = vars.username;
  home.homeDirectory = "/home/${vars.username}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  programs.bash = {
    enable = true;
    shellAliases = {
      nrs = "sudo nixos-rebuild switch --flake /home/${vars.username}/nixos-xiaomi-sheng/nixos#sheng";
    };
  };

  home.packages = let
    sheng-check = pkgs.writeShellScriptBin "sheng-check" (builtins.readFile ../scripts/sheng-check.sh);
  in with pkgs; [
    sheng-check
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
