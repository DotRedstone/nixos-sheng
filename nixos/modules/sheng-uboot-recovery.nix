# ---
# Module: Sheng U-Boot Storage Recovery
# Description: Provides an ADB-accessible RAM-only stage-1 shell for audited EFI storage work.
# Scope: System
# Notes:
# - This module must remain separate from the installed Mobile NixOS configuration.
# - It deliberately mounts no persistent filesystem and never performs storage writes itself.
# ---
{ lib, mobileNixosSource, pkgs, ... }:

let
  recoveryHoldTask = pkgs.writeText "sheng-recovery-hold.rb" ''
    # USB must be active before the recovery loop prevents SwitchRoot.
    class Tasks::ShengRecoveryHold < SingletonTask
      def initialize()
        add_dependency(:Task, Tasks::SetupGadgetMode.instance)
        Targets[:SwitchRoot].add_dependency(:Task, self)
      end

      def run()
        $logger.info("Sheng RAM recovery is ready over ADB; SwitchRoot is intentionally blocked.")
        loop { sleep(3600) }
      end
    end
  '';
in
{
  fileSystems = lib.mkForce { };

  mobile.boot.stage-1 = {
    # A dedicated task blocks SwitchRoot only after the USB gadget is ready,
    # leaving linux unmounted while the operator audits it over stage-1 ADB.
    shell.enable = lib.mkForce false;
    shell.shellOnFail = lib.mkForce false;
    fail.reboot = lib.mkForce false;

    # A recovery image must not run normal-boot presentation or power-policy
    # logic.  Keeping those values would make a RAM-only shell enter the
    # charging guard, generation picker, or framebuffer animation first.
    bootConfig = {
      sheng_boot_animation.enable = lib.mkForce false;
      sheng_generation_menu.enable = lib.mkForce false;
      sheng_early_charge_guard.enable = lib.mkForce false;
    };

    # Do not inherit the normal Sheng tasks: its root fsck task can repair the
    # installed ext4 filesystem.  Recovery only needs the ADB FunctionFS
    # gadget, whose task mounts pseudo-filesystems but no persistent storage.
    tasks = lib.mkForce [
      "${mobileNixosSource}/modules/stage-1/tasks/usb-gadget-task.rb"
      recoveryHoldTask
    ];

    # The normal Sheng stage-1 includes the animation assets solely for its
    # presentation task.  Recovery has no such task, so omit the assets too.
    contents = lib.mkForce [ ];

    # All commands are interactive only.  The image contains no startup task
    # that alters GPT, ext4, FAT, Android slots, or firmware partitions.
    extraUtils = [
      pkgs.coreutils
      pkgs.dosfstools
      pkgs.e2fsprogs
      pkgs.util-linuxMinimal
    ];
  };

  mobile.adbd.enable = lib.mkForce true;
}
