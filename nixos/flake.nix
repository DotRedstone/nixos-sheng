{
  description = "Mobile NixOS rootfs for Xiaomi Pad 6S Pro (sheng)";

  inputs = {
    mobile-nixos = {
      url = "github:mobile-nixos/mobile-nixos/development";
      flake = false;
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    shengKernelSrc = {
      url = "github:code002-2/sm8550-mainline/1c2d6f012c0a3c529ad68c5dc4d47cc0f60fb9f2";
      flake = false;
    };
  };

  outputs = { self, mobile-nixos, nixpkgs, shengKernelSrc }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      shengSystem = self.nixosConfigurations.sheng.config.system.build.toplevel;
      mobileEval = import "${mobile-nixos}/lib/eval-with-configuration.nix" {
        inherit system;
        device = ./devices/xiaomi-sheng;
        configuration = [
          ({ ... }: {
            nixpkgs.overlays = [
              (final: prev: {
                inherit shengKernelSrc;
              })
            ];
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
