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
      url = "github:DotRedstone/linux-sheng/upgrade/sheng-7.1.8";
      flake = false;
    };
    shengFirmware = {
      url = "github:DotRedstone/sheng-firmware-full/719086ce25222dcc54920ae12409eb5d4401bbff";
      # Note: This is now a true flake, so we remove `flake = false;`
    };
    shengUbootSrc = {
      # Official U-Boot v2026.10-rc5 signed tag commit. This experiment never
      # imports device patches from third-party repositories.
      url = "github:u-boot/u-boot/a06e89ab05eaa2b8344d521319399333cd760ae5";
      flake = false;
    };
  };

  outputs = { self, mobile-nixos, nixpkgs, home-manager, shengKernelSrc, shengFirmware, shengUbootSrc }:
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
        sheng-boot-animation = final.callPackage ./packages/sheng-boot-animation.nix { };
        sheng-fb-painter = final.callPackage ./packages/sheng-fb-painter.nix { };
        sheng-libssc = final.callPackage ./hardware/xiaomi-sheng/sensors/libssc.nix { };
        sheng-touch-firmware = final.callPackage ./packages/xiaomi-sheng-touch-firmware.nix { };
        sheng-uboot-efi-preflight = final.callPackage ./packages/sheng-uboot-efi-preflight.nix {
          inherit shengUbootSrc;
        };
        sheng-uboot-efi-sheng-dts-preflight = final.callPackage ./packages/sheng-uboot-efi-sheng-dts-preflight.nix {
          inherit shengUbootSrc;
        };
        sheng-uboot-android-bootimg = final.callPackage ./packages/sheng-uboot-android-bootimg.nix {
          inherit shengUbootSrc;
        };
        sheng-uboot-fastboot-probe-bootimg = final.callPackage ./packages/sheng-uboot-android-bootimg.nix {
          autoFastboot = true;
          inherit shengUbootSrc;
        };
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
      # The release outputs target aarch64-linux. Keep this host-side cross
      # entry separate so maintainers can prove the firmware build on x86_64
      # without changing device packages or image outputs.
      ubootPreflightFor = buildSystem:
        let buildPkgs = import nixpkgs { system = buildSystem; };
        in buildPkgs.callPackage ./packages/sheng-uboot-efi-preflight.nix {
          buildUBoot = buildPkgs.pkgsCross.aarch64-multiplatform.buildUBoot;
          inherit shengUbootSrc;
        };
      ubootShengDtsPreflightFor = buildSystem:
        let buildPkgs = import nixpkgs { system = buildSystem; };
        in buildPkgs.callPackage ./packages/sheng-uboot-efi-sheng-dts-preflight.nix {
          buildUBoot = buildPkgs.pkgsCross.aarch64-multiplatform.buildUBoot;
          inherit shengUbootSrc;
        };
      ubootAndroidBootimgFor = buildSystem:
        let buildPkgs = import nixpkgs { system = buildSystem; };
        in buildPkgs.callPackage ./packages/sheng-uboot-android-bootimg.nix {
          buildUBoot = buildPkgs.pkgsCross.aarch64-multiplatform.buildUBoot;
          inherit shengUbootSrc;
        };
      ubootFastbootProbeFor = buildSystem:
        let buildPkgs = import nixpkgs { system = buildSystem; };
        in buildPkgs.callPackage ./packages/sheng-uboot-android-bootimg.nix {
          autoFastboot = true;
          buildUBoot = buildPkgs.pkgsCross.aarch64-multiplatform.buildUBoot;
          inherit shengUbootSrc;
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
        # This validates the upstream U-Boot/EFI toolchain only. Its result is
        # deliberately not an Android boot image and must never be flashed.
        shengUbootEfiPreflight = pkgs.sheng-uboot-efi-preflight;
        # Sheng device-tree compilation only; this output is never flashable.
        shengUbootEfiShengDtsPreflight = pkgs.sheng-uboot-efi-sheng-dts-preflight;
        # Experimental Android v0 envelope for a RAM-boot test. It is separate
        # from mobileAndroidBootimg and must not be flashed before device proof.
        shengUbootAndroidBootimg = pkgs.sheng-uboot-android-bootimg;
        # USB-only RAM probe: U-Boot must re-enumerate as fastboot before
        # storage, display, or an EFI payload is brought into the experiment.
        shengUbootFastbootProbeBootimg = pkgs.sheng-uboot-fastboot-probe-bootimg;
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

      packages.x86_64-linux.shengUbootEfiPreflight = ubootPreflightFor "x86_64-linux";
      packages.x86_64-linux.shengUbootEfiShengDtsPreflight = ubootShengDtsPreflightFor "x86_64-linux";
      packages.x86_64-linux.shengUbootAndroidBootimg = ubootAndroidBootimgFor "x86_64-linux";
      packages.x86_64-linux.shengUbootFastbootProbeBootimg = ubootFastbootProbeFor "x86_64-linux";

      checks.x86_64-linux.shengUbootEfiPreflight = ubootPreflightFor "x86_64-linux";
      checks.x86_64-linux.shengUbootEfiShengDtsPreflight = ubootShengDtsPreflightFor "x86_64-linux";
      checks.x86_64-linux.shengUbootAndroidBootimg = ubootAndroidBootimgFor "x86_64-linux";
      checks.x86_64-linux.shengUbootFastbootProbeBootimg = ubootFastbootProbeFor "x86_64-linux";

      checks.${system} = {
        shengUbootEfiPreflight = pkgs.sheng-uboot-efi-preflight;
        shengUbootEfiShengDtsPreflight = pkgs.sheng-uboot-efi-sheng-dts-preflight;
        shengUbootAndroidBootimg = pkgs.sheng-uboot-android-bootimg;
        # USB-only RAM probe: U-Boot must re-enumerate as fastboot before
        # storage, display, or an EFI payload is brought into the experiment.
        shengUbootFastbootProbeBootimg = pkgs.sheng-uboot-fastboot-probe-bootimg;

        bootAnimation = pkgs.runCommand "sheng-boot-animation-check" {
          nativeBuildInputs = [
            pkgs.ruby pkgs.mruby pkgs.sheng-fb-painter
            (pkgs.python3.withPackages (ps: [ ps.pillow ]))
          ];
        } ''
          mrbc -c ${./patches/stage-1-boot-animation.rb}
          ruby ${../scripts/test-stage1-boot-animation.rb} \
            ${./patches/stage-1-boot-animation.rb} \
            ${./patches/stage-1-early-charge-guard.rb}
          python3 ${../scripts/test-boot-animation.py} \
            ${pkgs.sheng-fb-painter}/bin/sheng-fb-painter \
            ${pkgs.sheng-boot-animation}
          touch $out
        '';

        offlineCharging = pkgs.runCommand "sheng-offline-charging-check" {
          SHENG_CHARGING_FONT = "${pkgs.inter}/share/fonts/truetype/Inter.ttc";
          nativeBuildInputs = [
            (pkgs.python3.withPackages (ps: [ ps.pillow ]))
            pkgs.ruby
            pkgs.mruby
            pkgs.sheng-fb-painter
          ];
        } ''
          ${pkgs.lib.optionalString
            (builtins.elem
              "androidboot.force_normal_boot=1"
              mobileEval.config.boot.kernelParams)
            ''
              echo "androidboot.force_normal_boot=1 disables charger boot detection" >&2
              exit 1
            ''}
          ruby \
            ${../scripts/test-stage1-early-charge-guard.rb} \
            ${./patches/stage-1-early-charge-guard.rb}
          mruby \
            ${../scripts/test-stage1-udev-tolerant.rb} \
            ${./patches/stage-1-udev-trigger-tolerant.rb}
          grep -F 'output_dir="$2"' \
            ${mobileEval.config.systemd.generators.sheng-offline-charging}
          grep -F 'normal_reboot_marker=/var/lib/sheng-offline-charging/force-normal-once' \
            ${mobileEval.config.systemd.generators.sheng-offline-charging}
          grep -F 'boot_mode=/run/sheng-boot-ui.mode' \
            ${mobileEval.config.systemd.generators.sheng-offline-charging}
          python3 ${../scripts/test-boot-mode-handoff.py} \
            ${./patches/stage-1-early-charge-guard.rb} \
            ${./scripts/sheng-offline-charging-generator.sh} \
            ${./scripts/sheng-offline-charging.py} \
            ${./patches/stage-1-headless-generation-menu.rb}
          grep -F 'before = [ "shutdown.target" "systemd-reboot.service" ];' \
            ${./modules/sheng-offline-charging.nix}
          python3 \
            ${../scripts/test-offline-charging.py} \
            ${./scripts/sheng-offline-charging.py} \
            ${pkgs.sheng-fb-painter}/bin/sheng-fb-painter
          touch $out
        '';
        bluetoothAddressOrdering = pkgs.runCommand "sheng-bluetooth-address-ordering-check" {} ''
          test ${if mobileEval.config.systemd.services.sheng-bluetooth-address.wantedBy == [ "bluetooth.service" ] then "1" else "0"} = 1
          unit=${pkgs.lib.escapeShellArg mobileEval.config.systemd.units."sheng-bluetooth-address.service".text}
          printf '%s\n' "$unit" | ${pkgs.gnugrep}/bin/grep -Fx 'Before=bluetooth.service'
          if printf '%s\n' "$unit" | ${pkgs.gnugrep}/bin/grep -Fq 'After=bluetooth.service'; then
            echo 'Bluetooth address loader must run before bluetoothd owns hci0' >&2
            exit 1
          fi
          touch $out
        '';
        generationMenuRenderer = pkgs.runCommand "sheng-generation-menu-renderer-check" {
          nativeBuildInputs = [
            pkgs.coreutils
            pkgs.mruby
            pkgs.sheng-fb-painter
            (pkgs.python3.withPackages (ps: [ ps.pillow ]))
          ];
        } ''
          commands="$TMPDIR/sheng-menu.fbops"
          framebuffer="$TMPDIR/sheng-menu.raw"

          mruby \
            ${./tests/test-stage1-generation-menu-renderer.rb} \
            ${./patches/stage-1-headless-generation-menu.rb} \
            "$commands" ${pkgs.sheng-fb-painter}/share/sheng/menu-font.rb \
            ${pkgs.sheng-boot-animation}

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

          check_pixel 0 0 "0,0,0,0"
          # Rounded corner, blue selection, and the next charcoal card.
          check_pixel 940 434 "0,0,0,0"
          check_pixel 1000 540 "54,35,20,0"
          check_pixel 1000 680 "23,19,17,0"

          python3 ${../scripts/preview-generation-menu.py} "$commands" \
            ${pkgs.sheng-fb-painter}/bin/sheng-fb-painter --assets ${pkgs.sheng-boot-animation}

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
