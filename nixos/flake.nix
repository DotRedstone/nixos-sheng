# ---
# Module: Flake Entry
# Description: Main entry point for NixOS system and Home Manager
# Scope: Flake
# ---

{
  description = "Mobile NixOS rootfs for Xiaomi Pad 6S Pro (sheng)";

  inputs = {
    mobile-nixos = {
      url = "github:mobile-nixos/mobile-nixos/development";
      flake = false;
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    shengKernelSrc = {
      url = "github:map220v/sm8550-mainline/sheng-7.0";
      flake = false;
    };
    shengFirmware = {
      url = "github:DotRedstone/sheng-firmware-full/719086ce25222dcc54920ae12409eb5d4401bbff";
      # Note: This is now a true flake, so we remove `flake = false;`
    };
  };

  outputs = { self, mobile-nixos, nixpkgs, home-manager, shengKernelSrc, shengFirmware }:
    let
      system = "aarch64-linux";
      shengOverlay = final: prev: {
        inherit shengKernelSrc;
        sheng-firmware = shengFirmware.packages.${prev.system}.default;
        libinput = prev.libinput.override {
          luaSupport = false;
        };
        gadget-tool = prev.gadget-tool.overrideAttrs (old: {
          cmakeFlags = (old.cmakeFlags or []) ++ [
            "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
          ];
          postPatch = (old.postPatch or "") + ''
            if grep -q "cmake_minimum_required(VERSION 2.8)" CMakeLists.txt; then
              substituteInPlace CMakeLists.txt \
                --replace-fail "cmake_minimum_required(VERSION 2.8)" \
                               "cmake_minimum_required(VERSION 3.5)"
            fi
          '';
        });
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
      homeManagerModule = {
        environment.systemPackages = [
          home-manager.packages.${system}.default
        ];
      };
      mobileEvalFor = extraModules:
        let vars = import ./vars.nix; in
        import "${mobile-nixos}/lib/eval-with-configuration.nix" {
        inherit pkgs;
        device = ./hardware/xiaomi-sheng;
        configuration = [
          { _module.args.vars = vars; }
          ({ lib, ... }: {
            nixpkgs.overlays = lib.mkAfter [ shengOverlay ];
          })
          ./configuration.nix
          homeManagerModule
          home-manager.nixosModules.home-manager
          ({ ... }: {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit vars; };
            home-manager.users.${vars.username} = import ./home/user.nix;
          })
        ] ++ extraModules ++ [
          ./hardware/mobile.nix
        ];
      };
      mobileEval = mobileEvalFor [ ];
      mobileGnomeEval = mobileEvalFor [
        ./profiles/gnome-minimal.nix
      ];
    in
    {
      # Reuse the exact Mobile NixOS evaluations used by the flashable images.
      # This keeps nixos-rebuild generations aligned with the fixed boot image,
      # sheng kernel modules, firmware, hardware services, and desktop profile.
      nixosConfigurations = {
        sheng = mobileGnomeEval;
        sheng-minimal = mobileEval;
      };

      homeConfigurations = let vars = import ./vars.nix; in {
        "${vars.username}@sheng" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit vars; };
          modules = [ ./home/user.nix ];
        };
      };

      packages.${system} = {
        mobileAndroidBootimg = mobileEval.outputs.android.android-bootimg;
        mobileFastbootImages = mobileEval.outputs.android.android-fastboot-images;
        mobileRootfsImage = mobileEval.outputs.generatedFilesystems.rootfs;
        mobileRootfsImageGnome = mobileGnomeEval.outputs.generatedFilesystems.rootfs;
        # Compatibility alias for older workflow names. This is the Mobile NixOS
        # generated rootfs, not a separate hand-built filesystem.
        fullRootfsImage = mobileEval.outputs.generatedFilesystems.rootfs;
        mobileStage1Initrd = pkgs.runCommand "sheng-mobile-stage1-initrd" {} ''
          mkdir -p $out
          cp ${mobileEval.outputs.initrd} $out/initrd
        '';
      };
    };
}
