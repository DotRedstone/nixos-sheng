# ---
# Module: Sheng U-Boot EFI Update
# Description: Installs validated EFI payloads and mirrors NixOS generations onto the dedicated linux-boot ESP.
# Scope: System
# Notes:
# - 普通 nixos-rebuild 只更新世代条目，不覆盖 EFI 内核或 stage-1。
# - 新载荷通过校验后才切换默认项；旧载荷仍留在 ESP 供回退。
# ---
{ config, lib, pkgs, ... }:

let
  cfg = config.services.sheng-uboot-efi;
  shengEfiGenerations = pkgs.writeShellApplication {
    name = "sheng-efi-generations";
    runtimeInputs = with pkgs; [ coreutils findutils gawk gnugrep gnused util-linux ];
    text = builtins.readFile ../scripts/sheng-efi-generations.sh;
  };
  shengEfi = pkgs.writeShellApplication {
    name = "sheng-efi";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gawk
      gnugrep
      gnused
      util-linux
    ];
    text = ''
      usage() {
        cat >&2 <<'USAGE'
      Usage:
        sheng-efi status
        sheng-efi install /path/to/sheng-uboot-efi-esp/esp
        sheng-efi rollback
        sheng-efi sync-generations

      install accepts only a validated shengUbootEfiEsp/esp tree. It first
      writes and verifies the new versioned payload, then switches the
      systemd-boot default. sync-generations mirrors available NixOS system
      profiles into EFI menu entries without replacing the kernel payload.
      Neither command touches Android partitions.
      USAGE
        exit 2
      }

      require_root() {
        if [ "$(id -u)" -ne 0 ]; then
          echo "Run this command as root." >&2
          exit 1
        fi
      }

      esp=${lib.escapeShellArg cfg.espPath}
      state=${lib.escapeShellArg cfg.statePath}

      check_esp() {
        local source partlabel
        # /boot is intentionally a systemd automount on the Mobile NixOS
        # rootfs.  Read its directory before findmnt; merely resolving its
        # path leaves the autofs placeholder in place.
        ls -1 "$esp" >/dev/null
        # The automount itself remains visible too, so select the backing
        # vfat mount rather than treating findmnt's two rows as one value.
        source="$(findmnt -rn -o SOURCE,FSTYPE --target "$esp" 2>/dev/null \
          | awk '$2 == "vfat" { print $1; exit }')"
        if [ -z "$source" ]; then
          echo "$esp is not a mounted FAT ESP." >&2
          exit 1
        fi
        partlabel="$(blkid -s PARTLABEL -o value "$source" 2>/dev/null || true)"
        if [ "$partlabel" != linux-boot ]; then
          echo "$source is not the linux-boot partition (PARTLABEL=$partlabel)." >&2
          exit 1
        fi
      }

      verify_manifest() {
        local directory=$1
        (
          cd "$directory"
          sha256sum -c manifest.sha256
        )
      }

      rebuild_manifest() {
        (
          cd "$esp"
          find EFI loader -type f ! -path 'loader/random-seed' -print0 | sort -z | xargs -0 sha256sum > manifest.sha256.new
          mv manifest.sha256.new manifest.sha256
          sync
        )
      }

      status() {
        check_esp
        echo "ESP: $(findmnt -n -o SOURCE,FSTYPE --target "$esp")"
        if [ -f "$esp/manifest.sha256" ]; then
          verify_manifest "$esp"
        else
          echo "No manifest at $esp/manifest.sha256" >&2
          exit 1
        fi
        echo "Entries:"
        find "$esp/loader/entries" -maxdepth 1 -type f -name 'nixos-sheng-*.conf' -printf '  %f\n' | sort
        echo "Default:"
        awk '$1 == "default" { print "  " $2 }' "$esp/loader/loader.conf"
        if [ -f "$state/previous-loader.conf" ]; then
          echo "Rollback default:"
          awk '$1 == "default" { print "  " $2 }' "$state/previous-loader.conf"
        fi
        if [ -f "$state/last-boot-success" ]; then
          echo "Last boot marked successful:"
          cat "$state/last-boot-success"
        fi
      }

      install_payload() {
        local supplied=$1 source entry entries version payload linux_path initrd_path dtb_path
        local staging backup_loader backup_manager previous_default previous_linux previous_base candidate
        local expected_kernel current_kernel kernel_version

        source="$(readlink -f -- "$supplied")"
        if [ "$source" = "$esp" ] || [ ! -d "$source" ]; then
          echo "Install source must be a separate esp directory." >&2
          exit 2
        fi
        if [ -L "$source" ] || find "$source" -type l -print -quit | grep -q .; then
          echo "EFI payload must not contain symbolic links." >&2
          exit 1
        fi
        for required in \
          manifest.sha256 \
          EFI/BOOT/BOOTAA64.EFI \
          loader/loader.conf \
          loader/entries.srel; do
          test -f "$source/$required" || {
            echo "EFI payload is missing $required." >&2
            exit 1
          }
        done
        verify_manifest "$source"

        mapfile -t entries < <(find "$source/loader/entries" -maxdepth 1 -type f -name 'nixos-sheng-*.conf' -printf '%f\n' | sort)
        if [ "''${#entries[@]}" -ne 1 ]; then
          echo "EFI payload must contain exactly one nixos-sheng boot entry." >&2
          exit 1
        fi
        entry="''${entries[0]}"
        if ! awk -v expected="$entry" '$1 == "default" && $2 == expected { found = 1 } END { exit !found }' \
          "$source/loader/loader.conf"; then
          echo "EFI payload default does not select its only Sheng boot entry." >&2
          exit 1
        fi
        version="''${entry#nixos-sheng-}"
        version="''${version%.conf}"
        if [ -z "$version" ] || ! printf '%s' "$version" | grep -Eq '^[A-Za-z0-9._-]+$'; then
          echo "Unsafe EFI payload version: $version" >&2
          exit 1
        fi
        payload="EFI/NixOS/sheng-$version"

        linux_path="$(awk '$1 == "linux" { print $2 }' "$source/loader/entries/$entry")"
        initrd_path="$(awk '$1 == "initrd" { print $2 }' "$source/loader/entries/$entry")"
        dtb_path="$(awk '$1 == "devicetree" { print $2 }' "$source/loader/entries/$entry")"
        if [ "$linux_path" != "/$payload/linux" ] || \
           [ "$initrd_path" != "/$payload/initrd" ] || \
           [ "$dtb_path" != "/$payload/sm8550-xiaomi-sheng.dtb" ]; then
          echo "EFI entry paths are not a Sheng versioned payload." >&2
          exit 1
        fi
        for required in linux initrd sm8550-xiaomi-sheng.dtb kernel.store-path; do
          test -s "$source/$payload/$required" || {
            echo "EFI payload is missing $payload/$required." >&2
            exit 1
          }
        done
        expected_kernel="$(cat "$source/$payload/kernel.store-path")"
        if [ ! -e /run/current-system/kernel ]; then
          echo "The current system kernel is unavailable for EFI payload verification." >&2
          exit 1
        fi
        current_kernel="$(dirname "$(readlink -f /run/current-system/kernel)")"
        kernel_version="$(printf '%s\n' "$version" | cut -d- -f1)"
        if [ "$expected_kernel" != "$current_kernel" ] || [ "$(uname -r)" != "$kernel_version" ]; then
          echo "EFI payload kernel does not match the running system closure." >&2
          exit 1
        fi

        check_esp
        install -d -m 0700 "$state"
        exec 9>"$state/install.lock"
        flock -x 9

        # Install all files which the new BLS entry references before changing
        # loader.conf. A power loss before the final rename therefore leaves
        # the existing default boot path intact.
        staging="$esp/.sheng-efi-stage-$version-$$"
        trap 'rm -rf "$staging"' EXIT
        rm -rf "$staging"
        install -d -m 0755 "$staging/$payload" "$staging/loader/entries" "$staging/EFI/BOOT"
        install -m 0644 "$source/$payload/linux" "$staging/$payload/linux"
        install -m 0644 "$source/$payload/initrd" "$staging/$payload/initrd"
        install -m 0644 "$source/$payload/sm8550-xiaomi-sheng.dtb" "$staging/$payload/sm8550-xiaomi-sheng.dtb"
        install -m 0644 "$source/$payload/kernel.store-path" "$staging/$payload/kernel.store-path"
        install -m 0644 "$source/loader/entries/$entry" "$staging/loader/entries/$entry"
        install -m 0644 "$source/loader/entries.srel" "$staging/loader/entries.srel"
        install -m 0644 "$source/EFI/BOOT/BOOTAA64.EFI" "$staging/EFI/BOOT/BOOTAA64.EFI"
        install -m 0644 "$source/loader/loader.conf" "$staging/loader/loader.conf"
        install -m 0644 "$source/manifest.sha256" "$staging/manifest.sha256"
        verify_manifest "$staging"

        if [ -e "$esp/$payload" ] || [ -e "$esp/loader/entries/$entry" ]; then
          echo "EFI payload $version is already installed; refusing to overwrite it." >&2
          exit 1
        fi
        install -d -m 0755 "$esp/$(dirname "$payload")"
        mv "$staging/$payload" "$esp/$(dirname "$payload")/"
        mv "$staging/loader/entries/$entry" "$esp/loader/entries/"
        install -m 0644 "$staging/loader/entries.srel" "$esp/loader/entries.srel"
        # FAT has no journal.  Ensure the files referenced by the prospective
        # default reach the device before the default itself can change.
        sync

        # Keep a known loader-manager and configuration copy both on the ESP
        # and in persistent rootfs state. The old BLS entry and its payload
        # are deliberately retained.
        backup_loader="$state/previous-loader.conf"
        backup_manager="$state/previous-BOOTAA64.EFI"
        if [ -f "$esp/loader/loader.conf" ]; then
          if [ ! -s "$esp/EFI/BOOT/BOOTAA64.EFI" ]; then
            echo "Cannot back up the previous EFI boot manager." >&2
            exit 1
          fi
          install -m 0600 "$esp/loader/loader.conf" "$backup_loader"
          install -m 0644 "$esp/loader/loader.conf" "$esp/loader/loader.conf.previous"
          previous_default="$(awk '$1 == "default" { print $2; exit }' "$backup_loader")"
          previous_linux="$(awk '$1 == "linux" { print $2; exit }' "$esp/loader/entries/$previous_default")"
          previous_base=
          for candidate in "$esp"/loader/entries/nixos-sheng-*.conf; do
            [ -f "$candidate" ] || continue
            case "$(basename "$candidate")" in nixos-sheng-generation-*.conf) continue ;; esac
            if [ "$(awk '$1 == "linux" { print $2; exit }' "$candidate")" = "$previous_linux" ]; then
              previous_base="$(basename "$candidate")"
              break
            fi
          done
          if [ -z "$previous_base" ]; then
            echo "Cannot identify the previous immutable EFI payload." >&2
            exit 1
          fi
          printf '%s\n' "$previous_base" > "$state/previous-payload-entry"
          install -m 0600 "$esp/EFI/BOOT/BOOTAA64.EFI" "$backup_manager.new"
          cmp "$esp/EFI/BOOT/BOOTAA64.EFI" "$backup_manager.new"
          mv "$backup_manager.new" "$backup_manager"
        fi
        if [ -f "$esp/EFI/BOOT/BOOTAA64.EFI" ]; then
          install -m 0644 "$esp/EFI/BOOT/BOOTAA64.EFI" "$esp/EFI/BOOT/BOOTAA64.EFI.previous"
        fi
        mv "$staging/EFI/BOOT/BOOTAA64.EFI" "$esp/EFI/BOOT/BOOTAA64.EFI.new"
        mv "$esp/EFI/BOOT/BOOTAA64.EFI.new" "$esp/EFI/BOOT/BOOTAA64.EFI"
        mv "$staging/loader/loader.conf" "$esp/loader/loader.conf.new"
        mv "$esp/loader/loader.conf.new" "$esp/loader/loader.conf"
        rebuild_manifest
        ${shengEfiGenerations}/bin/sheng-efi-generations "$esp"
        printf '%s\n' "$version" > "$state/pending-version"
        sync
        trap - EXIT
        rm -rf "$staging"
        echo "Installed and selected EFI payload: $version"
        echo "The previous default is retained; run 'sheng-efi rollback' before reboot if needed."
      }

      rollback() {
        local previous_manager
        check_esp
        if [ ! -s "$state/previous-loader.conf" ]; then
          echo "No previous EFI loader configuration has been recorded." >&2
          exit 1
        fi
        install -d -m 0700 "$state"
        exec 9>"$state/install.lock"
        flock -x 9
        previous_manager="$state/previous-BOOTAA64.EFI"
        # Existing installations may only have the ESP-side backup. Prefer
        # the persistent copy made by newer installations when both exist.
        if [ ! -s "$previous_manager" ]; then
          previous_manager="$esp/EFI/BOOT/BOOTAA64.EFI.previous"
        fi
        if [ ! -s "$previous_manager" ]; then
          echo "No previous EFI boot manager has been recorded." >&2
          exit 1
        fi
        if [ -s "$state/previous-payload-entry" ]; then
          previous_base="$(cat "$state/previous-payload-entry")"
          case "$previous_base" in
            nixos-sheng-*.conf) ;;
            *) echo "Invalid previous EFI payload entry." >&2; exit 1 ;;
          esac
          test -f "$esp/loader/entries/$previous_base" || {
            echo "Previous EFI payload entry is missing." >&2
            exit 1
          }
          awk -v selected="$previous_base" '
            $1 == "default" { print "default " selected; next }
            { print }
          ' "$state/previous-loader.conf" > "$esp/loader/loader.conf.new"
        else
          install -m 0644 "$state/previous-loader.conf" "$esp/loader/loader.conf.new"
        fi
        install -m 0644 "$previous_manager" "$esp/EFI/BOOT/BOOTAA64.EFI.new"
        cmp "$previous_manager" "$esp/EFI/BOOT/BOOTAA64.EFI.new"
        sync
        mv "$esp/EFI/BOOT/BOOTAA64.EFI.new" "$esp/EFI/BOOT/BOOTAA64.EFI"
        mv "$esp/loader/loader.conf.new" "$esp/loader/loader.conf"
        rebuild_manifest
        ${shengEfiGenerations}/bin/sheng-efi-generations "$esp"
        rm -f "$state/pending-version"
        echo "Restored the previous EFI boot manager and default entry."
      }

      mark_successful() {
        check_esp
        install -d -m 0700 "$state"
        {
          date --iso-8601=seconds
          awk '$1 == "default" { print $2 }' "$esp/loader/loader.conf"
        } > "$state/last-boot-success"
        rm -f "$state/pending-version"
      }

      require_root
      case "''${1:-}" in
        status)
          [ "$#" -eq 1 ] || usage
          status
          ;;
        install)
          [ "$#" -eq 2 ] || usage
          install_payload "$2"
          ;;
        rollback)
          [ "$#" -eq 1 ] || usage
          rollback
          ;;
        sync-generations)
          [ "$#" -eq 1 ] || usage
          check_esp
          ${shengEfiGenerations}/bin/sheng-efi-generations "$esp"
          ;;
        mark-successful)
          [ "$#" -eq 1 ] || usage
          mark_successful
          ;;
        *) usage ;;
      esac
    '';
  };
in
{
  options.services.sheng-uboot-efi = {
    enable = lib.mkEnableOption "the managed U-Boot EFI payload update path";
    espPath = lib.mkOption {
      type = lib.types.str;
      default = "/boot";
      description = "Mounted dedicated linux-boot EFI system partition.";
    };
    statePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sheng-efi";
      description = "Persistent state containing the previous EFI loader configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ shengEfi shengEfiGenerations ];

    systemd.tmpfiles.rules = [
      "d ${cfg.statePath} 0700 root root -"
    ];

    systemd.services.sheng-efi-sync-generations = {
      description = "Mirror Sheng NixOS generations into the EFI boot menu";
      after = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${shengEfi}/bin/sheng-efi sync-generations";
      };
    };

    systemd.paths.sheng-efi-sync-generations = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = "/nix/var/nix/profiles";
    };

    systemd.services.sheng-efi-mark-successful = {
      description = "Record a successful Sheng U-Boot EFI boot";
      after = [ "local-fs.target" "multi-user.target" ];
      wants = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathIsMountPoint = cfg.espPath;
      unitConfig.ConditionPathExists = "/sys/firmware/efi";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${shengEfi}/bin/sheng-efi mark-successful";
      };
    };
  };
}
