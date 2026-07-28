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
        libcamera = prev.libcamera.overrideAttrs (old: {
          version = "0.7.2";
          src = final.fetchurl {
            url = "https://gitlab.freedesktop.org/camera/libcamera/-/archive/v0.7.2/libcamera-v0.7.2.tar.bz2";
            hash = "sha256-bzXdR53WNKHsUIUvqXFsnagabAevk7vymQ97vYKfDf0=";
          };
          mesonFlags = (old.mesonFlags or [ ]) ++ [
            "-Dlibdw=disabled"
            "-Dpipelines=simple,uvcvideo"
          ];
        });
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
        gjs-osk = final.callPackage ./packages/gjs-osk.nix { };
        xdg-desktop-portal = prev.xdg-desktop-portal.overrideAttrs (old: {
          # Fallback source builds on GitHub's aarch64 runner can hit a flaky
          # notification sound-fd integration test. Release artifacts still use
          # the normal package output; this only disables build-time checks.
          doCheck = false;
        });
        libadwaita = prev.libadwaita.overrideAttrs (old: {
          # Fallback source builds on GitHub's aarch64 runner can abort in
          # libadwaita's graphical tests. Runtime output is unchanged.
          doCheck = false;
        });
        sdl3 = prev.sdl3.overrideAttrs (old: {
          # The aarch64 GitHub runner can time out in SDL3's testrwlock when
          # cache fallback forces a source build. Keep runtime output unchanged.
          doCheck = false;
        });
        SDL3 = final.sdl3;
      };
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ shengOverlay ];
      };
      homeManagerModule = {
        environment.systemPackages = [
          home-manager.packages.${system}.default
        ];
      };
      mobileEvalFor = {
        extraModules ? [ ],
        desktop ? null,
        includeDefaultUser ? false,
        includeHomeManager ? false,
      }:
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
        ]
        ++ pkgs.lib.optional (desktop == "gnome") ./profiles/gnome-minimal.nix
        ++ pkgs.lib.optional includeDefaultUser ./profiles/default-user.nix
        ++ pkgs.lib.optionals includeHomeManager [
          homeManagerModule
          home-manager.nixosModules.home-manager
          ({ ... }: {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit vars; };
            home-manager.users.${vars.username} = import ./home/user.nix;
          })
        ]
        ++ extraModules
        ++ [
          ./hardware/mobile.nix
        ];
      };
      mobileEval = mobileEvalFor {
        includeDefaultUser = true;
        includeHomeManager = true;
      };
      mobileGnomeEval = mobileEvalFor {
        desktop = "gnome";
        includeDefaultUser = true;
        includeHomeManager = true;
      };
    in
    {
      # Reuse the exact Mobile NixOS evaluations used by the flashable images.
      # This keeps nixos-rebuild generations aligned with the fixed boot image,
      # sheng kernel modules, firmware, hardware services, and desktop profile.
      # Public downstream interface. It evaluates the complete Mobile NixOS
      # platform while leaving users, credentials, Home Manager, and personal
      # packages to the caller's modules.
      lib.${system} = {
        mkShengSystem = extraModules: mobileEvalFor {
          inherit extraModules;
        };
        mkShengGnomeSystem = extraModules: mobileEvalFor {
          desktop = "gnome";
          inherit extraModules;
        };
        # Compatibility alias. mkShengSystem is the desktop-neutral platform.
        mkShengMinimalSystem = extraModules:
          self.lib.${system}.mkShengSystem extraModules;
      };

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

      checks.${system} = {
        publicGnomeSystem =
          (self.lib.${system}.mkShengGnomeSystem [ ]).config.system.build.toplevel;
        publicMinimalSystem =
          (self.lib.${system}.mkShengSystem [ ]).config.system.build.toplevel;
      };
    };
}
