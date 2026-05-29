{ config, lib, pkgs, ... }:

let
  closureInfo = pkgs.buildPackages.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };
in
{
  mobile.enable = true;

  mobile.generatedFilesystems.rootfs.name = "nixos-sheng-rootfs";
  mobile.generatedFilesystems.rootfs.filesystem = lib.mkDefault "ext4";
  mobile.generatedFilesystems.rootfs.label = lib.mkForce "linux";
  mobile.generatedFilesystems.rootfs.location = lib.mkForce "/rootfs.img";
  mobile.generatedFilesystems.rootfs.extraPadding = lib.mkForce (1024 * 1024 * 1024);
  mobile.generatedFilesystems.rootfs.populateCommands = ''
    mkdir -p ./nix/store
    echo "Copying system closure..."

    err=0
    while IFS= read -r path; do
      echo "  Copying $path"
      if test -e "$path"; then
        cp -prf "$path" ./nix/store
      else
        2>&1 printf "ERROR: path %q does not exist...\n" "$path"
        (( ++err ))
      fi
    done < "${closureInfo}/store-paths"

    if (( err > 0 )); then
      2>&1 printf "... Bailing out, %d errors.\n" "$err"
      exit 2
    fi

    echo "Done copying system closure."
    cp -v ${closureInfo}/registration ./nix-path-registration
  '';

  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-partlabel/linux";
    fsType = "ext4";
    neededForBoot = true;
    autoResize = true;
    options = [ "noatime" "errors=remount-ro" ];
  };

  mobile.boot.stage-1 = {
    compression = "gzip";
    crashToBootloader = false;

    bootConfig = {
      log.level = "DEBUG";
      boot.fail.shell = true;
    };

    gui = {
      enable = true;
      waitForDevices = {
        enable = true;
        delay = 2;
      };
    };

    shell.shellOnFail = true;

    kernel.modules = [ ];
    kernel.additionalModules = [ ];
  };

  mobile.boot.stage-1.fail.reboot = false;

  mobile.adbd.enable = lib.mkDefault true;

  mobile.beautification.silentBoot = lib.mkForce false;

  systemd.services.adbd = lib.mkIf config.mobile.adbd.enable {
    script = lib.mkForce ''
      ${pkgs.adbd}/bin/adbd &

      # Wait a bit so the FunctionFS userspace endpoint is ready before binding.
      sleep 1

      if [ -e /sys/kernel/config/usb_gadget ]; then
        for gadget in /sys/kernel/config/usb_gadget/*; do
          [ -d "$gadget" ] || continue
          [ -e "$gadget/UDC" ] || continue

          read -r current_udc < "$gadget/UDC" || current_udc=""
          udc_name="$current_udc"

          if [ -z "$udc_name" ]; then
            for udc in /sys/class/udc/*; do
              [ -e "$udc" ] || continue
              udc_name="''${udc##*/}"
              break
            done
          fi

          [ -n "$udc_name" ] || continue
          printf '%s' "$udc_name" > "$gadget/UDC" || true
        done
      fi

      wait
    '';
  };

  boot.postBootCommands = lib.mkBefore ''
    if [ -f /nix-path-registration ]; then
      ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration
      touch /etc/NIXOS
      ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
      rm -f /nix-path-registration
    fi
  '';

  documentation.enable = false;
}
