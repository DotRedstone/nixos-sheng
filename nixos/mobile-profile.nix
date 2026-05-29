{ config, lib, pkgs, ... }:

let
  headlessStage1Task = pkgs.writeTextDir "zz-sheng-headless-stage1.rb" (
    builtins.readFile ./patches/stage-1-headless-no-gui.rb
  );
  closureInfo = pkgs.buildPackages.closureInfo {
    rootPaths = config.system.build.toplevel;
  };
in
{
  mobile.enable = true;

  mobile.generatedFilesystems.rootfs = lib.mkForce {
    name = "nixos-sheng-rootfs";
    filesystem = "ext4";
    label = "linux";
    ext4.partitionID = "ee8d3593-59b1-480e-a3b6-4fefb17ee7d8";
    location = "/rootfs.img";
    extraPadding = 1024 * 1024 * 1024;

    # Keep this aligned with Mobile NixOS' default rootfs.nix populate logic.
    populateCommands = ''
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

      echo "Done copying system closure..."
      cp -v ${closureInfo}/registration ./nix-path-registration
    '';

    additionalCommands = ''
      echo ":: Adding hydra-build-products"
      (PS4=" $ "; set -x
      mkdir -p $out_path/nix-support
      cat <<EOF > $out_path/nix-support/hydra-build-products
      file rootfs $img
      EOF
      )
    '';
  };

  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-partlabel/linux";
    fsType = "ext4";
    neededForBoot = true;
    autoResize = false;
    options = [ "noatime" ];
  };

  mobile.boot.stage-1 = {
    compression = "gzip";
    crashToBootloader = false;

    bootConfig = {
      log.level = "DEBUG";
      boot.fail.shell = true;
      gui.enable = false;
      splash.disabled = true;
    };

    gui.enable = false;

    tasks = [
      headlessStage1Task
    ];

    shell.shellOnFail = true;

    kernel.modules = [ ];
    kernel.additionalModules = [ ];
  };

  mobile.boot.stage-1.fail.reboot = false;

  mobile.adbd.enable = lib.mkDefault true;

  mobile.beautification.silentBoot = lib.mkForce false;

  documentation.enable = false;
}
