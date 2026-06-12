# ---
# Module: Personal User Home
# Description: Provides an example Home Manager profile for the private sheng user
# Scope: Home Manager
# ---

{ ... }:

{
  home.username = "user";
  home.homeDirectory = "/home/user";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;
}
