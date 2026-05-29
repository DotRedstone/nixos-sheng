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
      rootfsExtraCommands = pkgs.writeScript "sheng-rootfs-extra-commands.sh" ''
        mkdir -p dev proc sys tmp var sbin
        chmod 1777 tmp
        ln -sfn ../init sbin/init
      '';
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
        mobileStage1Initrd = pkgs.runCommand "sheng-mobile-stage1-initrd" {} ''
          mkdir -p $out
          cp ${mobileEval.outputs.initrd} $out/initrd
        '';
        rootfsTarball =
          pkgs.callPackage "${nixpkgs}/nixos/lib/make-system-tarball.nix" {
            fileName = "nixos-sheng-aarch64-linux";
            contents = [
              {
                source = "${shengSystem}/.";
                target = "./";
              }
            ];
            storeContents = [
              {
                object = shengSystem;
                symlink = "run/current-system";
              }
              {
                object = pkgs.stdenv;
                symlink = "none";
              }
            ];
            extraArgs = "--owner=0";
            extraCommands = rootfsExtraCommands;
          };
      };
    };
}
