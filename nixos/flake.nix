{
  description = "NixOS rootfs for Xiaomi Pad 6S Pro (sheng)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      shengSystem = self.nixosConfigurations.sheng.config.system.build.toplevel;
      rootfsExtraCommands = pkgs.writeScript "sheng-rootfs-extra-commands.sh" ''
        mkdir -p dev proc sys tmp var sbin
        chmod 1777 tmp
        ln -sfn ../init sbin/init
      '';
      stage1Initramfs = pkgs.runCommand "sheng-stage1-initramfs.cpio.gz" {
        nativeBuildInputs = [
          pkgs.cpio
          pkgs.gzip
        ];
      } ''
        mkdir -p root/bin root/dev root/proc root/sys root/newroot

        cp ${pkgs.pkgsStatic.busybox}/bin/busybox root/bin/busybox
        chmod +x root/bin/busybox

        for applet in sh mount umount sleep mkdir mdev switch_root cat dmesg; do
          ln -s busybox "root/bin/$applet"
        done

        cat > root/init <<'EOF'
        #!/bin/sh
        export PATH=/bin

        mount -t proc proc /proc
        mount -t sysfs sysfs /sys
        mount -t devtmpfs devtmpfs /dev || mdev -s

        exec >/dev/console 2>&1
        echo "sheng-stage1: waiting for PARTLABEL=linux"
        echo "sheng-stage1: waiting for PARTLABEL=linux" > /dev/kmsg

        ROOTDEV=""
        i=0
        while [ "$i" -lt 60 ]; do
          for dev in /dev/disk/by-partlabel/linux /dev/block/by-name/linux; do
            if [ -e "$dev" ]; then
              ROOTDEV="$dev"
              break
            fi
          done
          if [ -n "$ROOTDEV" ]; then
            break
          fi
          sleep 1
          i=$((i + 1))
        done

        if [ -z "$ROOTDEV" ]; then
          echo "sheng-stage1: linux rootfs was not found"
          echo "sheng-stage1: linux rootfs was not found" > /dev/kmsg
          exec sh
        fi

        echo "sheng-stage1: mounting $ROOTDEV"
        echo "sheng-stage1: mounting $ROOTDEV" > /dev/kmsg
        mount -t ext4 -o rw "$ROOTDEV" /newroot || exec sh

        mkdir -p /newroot/proc /newroot/sys /newroot/dev
        mount --move /proc /newroot/proc
        mount --move /sys /newroot/sys
        mount --move /dev /newroot/dev

        echo "sheng-stage1: switching to NixOS /init"
        echo "sheng-stage1: switching to NixOS /init" > /newroot/dev/kmsg
        exec switch_root /newroot /init
        EOF

        chmod +x root/init
        (cd root && find . -print0 | cpio --null -ov --format=newc | gzip -9) > "$out"
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

        stage1Initramfs = stage1Initramfs;
      };
    };
}
