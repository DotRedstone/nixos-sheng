{
  description = "Mobile NixOS rootfs for Xiaomi Pad 6S Pro (sheng)";

  inputs = {
    mobile-nixos = {
      url = "github:mobile-nixos/mobile-nixos/development";
      flake = false;
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    shengKernelSrc = {
      url = "github:map220v/sm8550-mainline/sheng-7.0";
      flake = false;
    };
  };

  outputs = { self, mobile-nixos, nixpkgs, shengKernelSrc }:
    let
      system = "aarch64-linux";
      shengOverlay = final: prev: {
        inherit shengKernelSrc;
        mobile-nixos = prev.mobile-nixos // {
          kernel-builder-clang = args:
            (prev.mobile-nixos.kernel-builder-clang args).overrideAttrs (old: {
              # Temporary troubleshooting override: keep Mobile NixOS' builder
              # shape, but force the non-interactive config update while making
              # the effective mode visible in CI logs.
              configurePhase = ''
                echo "===== mobile-nixos kernel configure override: replacing oldconfig with olddefconfig ====="
                ${builtins.replaceStrings
                  [ "oldconfig" ]
                  [ "olddefconfig" ]
                  old.configurePhase}
                echo "===== mobile-nixos kernel configure override: olddefconfig configurePhase completed ====="
              '';
            });
        };
      };
      pkgs = import nixpkgs {
        inherit system;
      };
      shengSystem = self.nixosConfigurations.sheng.config.system.build.toplevel;
      mobileEval = import "${mobile-nixos}/lib/eval-with-configuration.nix" {
        inherit pkgs;
        device = ./devices/xiaomi-sheng;
        configuration = [
          ({ lib, ... }: {
            nixpkgs.overlays = lib.mkAfter [ shengOverlay ];
          })
          ./configuration.nix
          ./mobile-profile.nix
        ];
      };
      mobilePkgs = mobileEval.pkgs;
      mobileSystem = mobileEval.config.system.build.toplevel;
      rootfsExtraCommands = pkgs.writeScript "sheng-rootfs-extra-commands.sh" ''
        mkdir -p dev proc sys tmp var sbin
        chmod 1777 tmp
        ln -sfn ../init sbin/init
      '';
      mkRootfsTarball = systemBuild:
        mobilePkgs.callPackage "${nixpkgs}/nixos/lib/make-system-tarball.nix" {
          fileName = "nixos-sheng-aarch64-linux";
          contents = [
            {
              source = "${systemBuild}/.";
              target = "./";
            }
          ];
          storeContents = [
            {
              object = systemBuild;
              symlink = "run/current-system";
            }
            {
              object = mobilePkgs.stdenv;
              symlink = "none";
            }
          ];
          extraArgs = "--owner=0";
          extraCommands = rootfsExtraCommands;
        };
      mobileRootfsTarball = mkRootfsTarball mobileSystem;
      fullRootfsImage = (mobilePkgs.image-builder.evaluateFilesystemImage {
        config = {
          name = "nixos-sheng-full-rootfs";
          filesystem = "ext4";
          label = "linux";
          location = "/rootfs.img";
          extraPadding = 1024 * 1024 * 1024;
          ext4.partitionID = "ee8d3593-59b1-480e-a3b6-4fefb17ee7d8";
          nativeBuildInputs = with mobilePkgs.buildPackages; [
            gnutar
            xz
            zstd
          ];
          populateCommands = ''
            tarball="$(${mobilePkgs.buildPackages.findutils}/bin/find ${mobileRootfsTarball} -type f \( -name "*.tar.xz" -o -name "*.tar.zst" -o -name "*.tar.gz" -o -name "*.tgz" \) | ${mobilePkgs.buildPackages.coreutils}/bin/head -n 1)"
            if [ -z "$tarball" ] || [ ! -f "$tarball" ]; then
              echo "Could not find rootfs tarball in ${mobileRootfsTarball}"
              ${mobilePkgs.buildPackages.findutils}/bin/find ${mobileRootfsTarball} -maxdepth 3 -print
              exit 1
            fi

            echo "Extracting full rootfs from $tarball"
            case "$tarball" in
              *.tar.xz) ${mobilePkgs.buildPackages.gnutar}/bin/tar -xJf "$tarball" -C . ;;
              *.tar.zst) ${mobilePkgs.buildPackages.gnutar}/bin/tar --zstd -xf "$tarball" -C . ;;
              *.tar.gz|*.tgz) ${mobilePkgs.buildPackages.gnutar}/bin/tar -xzf "$tarball" -C . ;;
              *)
                echo "Unsupported tarball format: $tarball"
                exit 1
                ;;
            esac

            test -e ./etc
            test -e ./sbin/init
            test -d ./nix/store
          '';
        };
      }).config.output;
    in
    {
      nixosConfigurations.sheng = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ({ lib, ... }: {
            nixpkgs.overlays = lib.mkAfter [ shengOverlay ];
          })
          ./configuration.nix
        ];
      };

      packages.${system} = {
        mobileAndroidBootimg = mobileEval.outputs.android.android-bootimg;
        mobileFastbootImages = mobileEval.outputs.android.android-fastboot-images;
        mobileRootfsImage = mobileEval.outputs.generatedFilesystems.rootfs;
        inherit fullRootfsImage;
        mobileStage1Initrd = pkgs.runCommand "sheng-mobile-stage1-initrd" {} ''
          mkdir -p $out
          cp ${mobileEval.outputs.initrd} $out/initrd
        '';
        rootfsTarball = mkRootfsTarball shengSystem;
      };
    };
}
