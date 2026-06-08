{ pkgs, ... }:

{
  home.username = "luser";
  home.homeDirectory = "/home/luser";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

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
    v4l-utils
    vim
    wget
  ];
}
