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
      url = "github:DotRedstone/linux-sheng/feat/stylus-thp";
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
        libcamera-sheng = prev.libcamera.overrideAttrs (old: {
          version = "0.7.2";
          src = final.fetchurl {
            url = "https://gitlab.freedesktop.org/camera/libcamera/-/archive/v0.7.2/libcamera-v0.7.2.tar.bz2";
            hash = "sha256-bzXdR53WNKHsUIUvqXFsnagabAevk7vymQ97vYKfDf0=";
          };
          mesonFlags = (old.mesonFlags or [ ]) ++ [
            "-Dapps-output-dng=disabled"
            "-Dcam-jpeg=disabled"
            "-Dcam-output-kms=disabled"
            "-Dcam-output-sdl2=disabled"
            "-Dlibdw=disabled"
            "-Dpipelines=simple,uvcvideo"
            "-Dsoftisp-gpu=disabled"
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
        sheng-fb-painter = final.callPackage ./packages/sheng-fb-painter.nix { };
        sheng-libssc = final.callPackage ./hardware/xiaomi-sheng/sensors/libssc.nix { };
        sheng-touch-firmware = final.callPackage ./packages/xiaomi-sheng-touch-firmware.nix { };
        xiaomi-sheng-thp = final.callPackage ./packages/xiaomi-sheng-thp.nix {
          libssc = final.sheng-libssc;
        };
        xiaomi-pen-status = final.callPackage ./packages/xiaomi-pen-status.nix { };
        xiaomi-sheng-fingerprint = final.callPackage ./packages/xiaomi-sheng-fingerprint.nix { };
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
        stage2Only ? false,
      }:
        let vars = import ./vars.nix; in
        import "${mobile-nixos}/lib/eval-with-configuration.nix" {
        inherit pkgs;
        device = ./hardware/xiaomi-sheng;
        configuration = [
          {
            _module.args = {
              inherit vars stage2Only;
            };
          }
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
      mobileStage2Eval = mobileEvalFor {
        desktop = "gnome";
        includeDefaultUser = true;
        includeHomeManager = true;
        stage2Only = true;
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
        sheng-stage2 = mobileStage2Eval;
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
        xiaomiShengThp = pkgs.xiaomi-sheng-thp;
        xiaomiPenStatus = pkgs.xiaomi-pen-status;
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
        generationMenuRenderer = pkgs.runCommand "sheng-generation-menu-renderer-check" {
          nativeBuildInputs = [
            pkgs.coreutils
            pkgs.mruby
            pkgs.sheng-fb-painter
          ];
        } ''
          commands="$TMPDIR/sheng-menu.fbops"
          framebuffer="$TMPDIR/sheng-menu.raw"

          mruby \
            ${./tests/test-stage1-generation-menu-renderer.rb} \
            ${./patches/stage-1-headless-generation-menu.rb} \
            "$commands"

          truncate -s $((2032 * 12288)) "$framebuffer"
          started_at="$(date +%s%N)"
          timeout 4 sheng-fb-painter \
            --file "$framebuffer" 3048 2032 12288 32 "$commands"
          elapsed_ms=$((($(date +%s%N) - started_at) / 1000000))
          test "$elapsed_ms" -lt 3000

          check_pixel() {
            offset=$((($2 * 12288) + ($1 * 4)))
            read -r blue green red alpha < <(od -An -v -tu1 -j "$offset" -N 4 "$framebuffer")
            test "$blue,$green,$red,$alpha" = "$3"
          }

          check_pixel 0 0 "11,10,8,0"
          check_pixel 600 57 "199,210,115,0"
          check_pixel 600 300 "67,67,35,0"
          check_pixel 2400 450 "29,27,24,0"
          test "$(sha256sum "$framebuffer" | cut -d' ' -f1)" = \
            "16eab7f3420f865c18e5398bb15d553d4d890357bf59820ed38bd71015465128"

          echo "native framebuffer render completed in ''${elapsed_ms}ms"
          touch $out
        '';
        publicGnomeSystem =
          (self.lib.${system}.mkShengGnomeSystem [ ]).config.system.build.toplevel;
        publicMinimalSystem =
          (self.lib.${system}.mkShengSystem [ ]).config.system.build.toplevel;
      };
    };
}
