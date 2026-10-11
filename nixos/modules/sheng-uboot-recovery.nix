# ---
# Module: Sheng U-Boot Storage Recovery
# Description: Provides an ADB-accessible RAM-only stage-1 shell for audited EFI storage work.
# Scope: System
# Notes:
# - This module must remain separate from the installed Mobile NixOS configuration.
# - It deliberately mounts no persistent filesystem and never performs storage writes itself.
# ---
{ lib, pkgs, ... }:

{
  fileSystems = lib.mkForce { };

  mobile.boot.stage-1 = {
    # Prevent SwitchRoot so linux stays unmounted while the operator audits or
    # repairs it through stage-1 ADB.
    shell.enable = lib.mkForce true;
    fail.reboot = lib.mkForce false;

    # All commands are interactive only.  The image contains no startup task
    # that alters GPT, ext4, FAT, Android slots, or firmware partitions.
    extraUtils = [
      pkgs.coreutils
      pkgs.dosfstools
      pkgs.e2fsprogs
      pkgs.util-linux
    ];
  };

  mobile.adbd.enable = lib.mkForce true;
}
