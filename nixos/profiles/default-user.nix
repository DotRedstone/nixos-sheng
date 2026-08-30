# ---
# Module: Default Test User
# Description: Provides the disposable user used by repository-built test images
# Scope: System
# Notes:
# - Downstream dotfiles should define their own users instead of importing this profile.
# ---

{ lib, vars, ... }:

let
  userHasPassword = vars.userPasswordHash != null || vars.userPassword != null;
in
{
  users.users.${vars.username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "input"
      "render"
    ];
  }
  // lib.optionalAttrs (vars.userPasswordHash != null) {
    initialHashedPassword = vars.userPasswordHash;
  }
  // lib.optionalAttrs (vars.userPasswordHash == null && vars.userPassword != null) {
    initialPassword = vars.userPassword;
  };
  users.users.root =
    lib.optionalAttrs (vars.rootPasswordHash != null) {
      initialHashedPassword = vars.rootPasswordHash;
    }
    // lib.optionalAttrs (vars.rootPasswordHash == null && vars.rootPassword != null) {
      initialPassword = vars.rootPassword;
    };

  services.getty.autologinUser = lib.mkIf (!userHasPassword) vars.username;
  services.displayManager.autoLogin = {
    enable = !userHasPassword;
    user = vars.username;
  };
  security.sudo.wheelNeedsPassword = userHasPassword;
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = userHasPassword;
  };
}
