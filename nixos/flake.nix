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
        gadget-tool = prev.gadget-tool.overrideAttrs (old: {
          cmakeFlags = (old.cmakeFlags or []) ++ [
            "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
          ];
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
        overlays = [ shengOverlay ];
      };
      shengSystem = self.nixosConfigurations.sheng.config.system.build.toplevel;
      mobileEval = import "${mobile-nixos}/lib/eval-with-configuration.nix" {
        inherit pkgs;
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
      mobileKernelPackage =
        mobileEval.config.mobile.outputs.stage-0.mobile.boot.stage-1.kernel.package;
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
        debianStyleBootimg = pkgs.runCommand "sheng-debian-style-bootimg" {
          nativeBuildInputs = with pkgs.buildPackages; [
            findutils
            mkbootimg
          ];
        } ''
          mkdir -p $out

          image="$(find ${mobileKernelPackage} -type f -name Image.gz | head -n 1 || true)"
          dtb="$(find ${mobileKernelPackage} -type f -name sm8550-xiaomi-sheng.dtb | head -n 1 || true)"

          if [ -z "$image" ] || [ -z "$dtb" ]; then
            echo "Unable to find Image.gz or sm8550-xiaomi-sheng.dtb in ${mobileKernelPackage}" >&2
            echo "Kernel package contents:" >&2
            find ${mobileKernelPackage} -maxdepth 5 -print | sort >&2
            exit 1
          fi

          cat "$image" "$dtb" > zImage_sheng
          mkbootimg \
            --kernel zImage_sheng \
            --cmdline "root=PARTLABEL=linux" \
            --base 0x00000000 \
            --kernel_offset 0x00008000 \
            --tags_offset 0x01e00000 \
            --pagesize 4096 \
            --id \
            -o $out/boot_sheng_nixos_debian_style.img
        '';
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
