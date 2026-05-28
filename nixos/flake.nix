{
  description = "Mobile NixOS rootfs for Xiaomi Pad 6S Pro (sheng)";

  inputs = {
    mobile-nixos = {
      url = "github:mobile-nixos/mobile-nixos/development";
      flake = false;
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, mobile-nixos, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      shengSystem = self.nixosConfigurations.sheng.config.system.build.toplevel;
      mobileEval = import "${mobile-nixos}/lib/eval-with-configuration.nix" {
        inherit system;
        device = ./devices/xiaomi-sheng;
        configuration = [
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
