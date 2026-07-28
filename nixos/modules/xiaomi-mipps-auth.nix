# ---
# Module: Xiaomi MIPPS Auth Service
# Description: Systemd service for Xiaomi MIPPS authentication
# Scope: Service
# ---

{ config, lib, pkgs, ... }:

let
  cfg = config.services.xiaomi-mipps-auth;
  package = pkgs.callPackage ../packages/xiaomi-mipps-auth.nix { };
  retryPackage = pkgs.writeShellApplication {
    name = "xiaomi-mipps-auth-retry";
    runtimeInputs = [
      package
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      set -u

      find_xiaomi_dir() {
        for path in /sys/class/qcom-battery /sys/devices/platform/pmic-glink/*/xiaomi; do
          [ -e "$path/request_vdm_cmd" ] || continue
          printf '%s\n' "$path"
          return 0
        done
        return 1
      }

      read_node() {
        local root="$1"
        local name="$2"
        [ -e "$root/$name" ] || return 1
        tr -d '\000' < "$root/$name" 2>/dev/null || return 1
      }

      is_complete() {
        local root="$1"
        [ "$(read_node "$root" pd_verifed 2>/dev/null || true)" = "1" ] \
          && [ "$(read_node "$root" fastchg_mode 2>/dev/null || true)" = "1" ]
      }

      is_xiaomi_svid() {
        case "$1" in
          0x2717|2717|10007) return 0 ;;
          *) return 1 ;;
        esac
      }

      is_empty_svid() {
        case "''${1:-}" in
          ""|0|0000|0x0000) return 0 ;;
          *) return 1 ;;
        esac
      }

      is_pd_ready() {
        case "$1" in
          PD|PPS|USB_PD|USB_PD_PPS|PD_PPS) return 0 ;;
          *) return 1 ;;
        esac
      }

      is_nonempty_pdo() {
        case "''${1:-}" in
          ""|0|00000000|0x00000000) return 1 ;;
          *) return 0 ;;
        esac
      }

      has_typec_partner() {
        for path in /sys/class/typec/port*-partner; do
          [ -e "$path" ] && return 0
        done
        return 1
      }

      has_active_usb_data_link() {
        local state=""

        for path in /sys/class/udc/*/state; do
          [ -r "$path" ] || continue
          state="$(read_node "''${path%/*}" "''${path##*/}" 2>/dev/null || true)"
          case "$state" in
            configured|suspended) return 0 ;;
          esac
        done
        return 1
      }

      sync_standard_pd_current() {
        local battmgr="/sys/class/power_supply/qcom-battmgr-usb"
        local ucsi=""
        local negotiated=""
        local current_limit=""
        local target=""

        [ -w "$battmgr/input_current_limit" ] || {
          echo "Standard PD current sync skipped: battery manager ICL is not writable"
          return 0
        }

        for path in /sys/class/power_supply/ucsi-source-psy-*; do
          [ -r "$path/online" ] || continue
          [ "$(read_node "$path" online 2>/dev/null || true)" = "1" ] || continue
          ucsi="$path"
          break
        done

        [ -n "$ucsi" ] || {
          echo "Standard PD current sync skipped: active UCSI source not found"
          return 0
        }

        negotiated="$(read_node "$ucsi" current_now 2>/dev/null || true)"
        current_limit="$(read_node "$battmgr" input_current_limit 2>/dev/null || true)"
        case "$negotiated:$current_limit" in
          *[!0-9:]*|:*|*:) echo "Standard PD current sync skipped: invalid current data"; return 0 ;;
        esac

        target="$negotiated"
        [ "$target" -le 3000000 ] || target=3000000
        if [ "$target" -le "$current_limit" ]; then
          echo "Standard PD current sync unchanged: negotiated=''${negotiated}uA limit=''${current_limit}uA"
          return 0
        fi

        printf '%s\n' "$target" > "$battmgr/input_current_limit"
        current_limit="$(read_node "$battmgr" input_current_limit 2>/dev/null || true)"
        case "$current_limit" in
          ""|*[!0-9]*) echo "Standard PD current sync requested ''${target}uA; readback unavailable"; return 0 ;;
        esac
        if [ "$current_limit" -ge "$target" ]; then
          echo "Standard PD current sync applied: negotiated=''${negotiated}uA limit=''${current_limit}uA"
        else
          echo "Standard PD current sync requested ''${target}uA, but charger firmware retained ''${current_limit}uA"
        fi
      }

      root="$(find_xiaomi_dir || true)"
      if [ -z "$root" ]; then
        echo "MiPPS auth waiting: request_vdm_cmd sysfs node not found"
        exit 1
      fi

      max_attempts=60
      non_pd_grace_attempts=6
      empty_svid_grace_attempts=15
      sleep_seconds=2

      for attempt in $(seq 1 "$max_attempts"); do
        if is_complete "$root"; then
          echo "MiPPS auth already active before attempt $attempt"
          xiaomi-mipps-auth --sysfs "$root" --timeout 3 || true
          exit 0
        fi

        real_type="$(read_node "$root" real_type 2>/dev/null || true)"
        adapter_svid="$(read_node "$root" adapter_svid 2>/dev/null || true)"
        pdo2="$(read_node "$root" pdo2 2>/dev/null || true)"
        echo "MiPPS auth attempt $attempt/$max_attempts: real_type=''${real_type:-unknown} adapter_svid=''${adapter_svid:-unknown} pdo2=''${pdo2:-unknown}"

        if ! has_typec_partner; then
          echo "MiPPS auth skipped: Type-C partner not present"
          exit 0
        fi

        if ! is_pd_ready "$real_type"; then
          # Do not run the authentication helper until PD/PPS is ready. It
          # requests a Type-C data-role swap, which can block for several
          # seconds and disturb a normal USB data connection.
          if [ "$attempt" -ge "$non_pd_grace_attempts" ]; then
            echo "MiPPS auth skipped: PD/PPS not ready after $attempt attempts (real_type=''${real_type:-unknown})"
            exit 0
          fi
          sleep "$sleep_seconds"
          continue
        fi

        if ! is_xiaomi_svid "$adapter_svid"; then
          if is_empty_svid "$adapter_svid"; then
            # Xiaomi SVID discovery may require the helper's Type-C data-role
            # swap. Probe only on a charger with a real PDO and no active USB
            # data link, so a computer connection (including ADB) is not
            # disrupted.
            if is_nonempty_pdo "$pdo2" && ! has_active_usb_data_link; then
              echo "MiPPS auth probing charger identity after PDO discovery"
              xiaomi-mipps-auth --sysfs "$root" --timeout 6 || true

              if is_complete "$root"; then
                echo "MiPPS auth active after identity probe"
                exit 0
              fi

              adapter_svid="$(read_node "$root" adapter_svid 2>/dev/null || true)"
              if is_xiaomi_svid "$adapter_svid"; then
                echo "MiPPS auth discovered Xiaomi SVID after data-role swap; retrying authentication"
                sleep "$sleep_seconds"
                continue
              fi

              echo "MiPPS auth skipped: charger did not expose Xiaomi SVID after safe identity probe"
              sync_standard_pd_current
              exit 0
            fi

            if [ "$attempt" -ge "$empty_svid_grace_attempts" ]; then
              echo "MiPPS auth skipped: Xiaomi SVID not exposed after $attempt attempts; treating this as a standard PD adapter"
              sync_standard_pd_current
              exit 0
            fi
            echo "MiPPS auth waiting: Xiaomi SVID not exposed yet"
            sleep "$sleep_seconds"
            continue
          fi
          echo "MiPPS auth skipped: non-Xiaomi adapter_svid=$adapter_svid"
          sync_standard_pd_current
          exit 0
        fi

        if ! is_nonempty_pdo "$pdo2"; then
          echo "MiPPS auth waiting: PD/PPS PDO not exposed yet"
          sleep "$sleep_seconds"
          continue
        fi

        xiaomi-mipps-auth --sysfs "$root" --timeout 6 || true

        if is_complete "$root"; then
          echo "MiPPS auth active after attempt $attempt"
          exit 0
        fi

        sleep "$sleep_seconds"
      done

      echo "MiPPS auth did not become active after $max_attempts attempts"
      echo "Final status:"
      for name in real_type adapter_svid pdo2 apdo_max power_max fastchg_mode pd_verifed request_vdm_cmd; do
        [ -e "$root/$name" ] || continue
        printf '%s=' "$name"
        read_node "$root" "$name" || true
      done
      exit 1
    '';
  };
in
{
  options.services.xiaomi-mipps-auth.enable =
    lib.mkEnableOption "Xiaomi MiPPS/PPS charger authentication";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      package
      retryPackage
    ];

    systemd.services.xiaomi-mipps-auth = {
      description = "Xiaomi MiPPS/PPS charger authentication";
      unitConfig.ConditionPathExistsGlob =
        "/sys/devices/platform/pmic-glink/*/xiaomi/request_vdm_cmd";
      serviceConfig = {
        # Let boot finish while PD/SVID discovery continues in this service.
        Type = "simple";
        ExecStart = "${pkgs.util-linux}/bin/flock -n -E 0 /run/xiaomi-mipps-auth.lock ${retryPackage}/bin/xiaomi-mipps-auth-retry";
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = 180;
      };
    };

    services.udev.extraRules = ''
      # Delegate Xiaomi MiPPS authentication to systemd after a USB-C partner attaches.
      ACTION=="add", SUBSYSTEM=="typec", KERNEL=="port*-partner", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xiaomi-mipps-auth.service"
      # Some adapters expose their Xiaomi SVID/PDOs only after the USB power_supply
      # node changes from SDP/unknown to PD/PPS. Retry when that state changes.
      ACTION=="change", SUBSYSTEM=="power_supply", KERNEL=="qcom-battmgr-usb", ATTR{online}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xiaomi-mipps-auth.service"
    '';
  };
}
