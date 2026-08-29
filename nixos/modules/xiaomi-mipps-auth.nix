# ---
# Module: Xiaomi MIPPS Auth Service
# Description: Systemd service for Xiaomi MIPPS authentication
# Scope: Service
# ---

{ config, lib, pkgs, ... }:

let
  cfg = config.services.xiaomi-mipps-auth;
  package = pkgs.callPackage ../packages/xiaomi-mipps-auth.nix { };
  usbDeviceRolePackage = pkgs.writeShellApplication {
    name = "sheng-usb-device-role";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -u

      typec_role_path=""
      for path in /sys/class/typec/port*/data_role; do
        [ -w "$path" ] || continue
        typec_role_path="$path"
        break
      done

      if [ -n "$typec_role_path" ]; then
        typec_role="$(cat "$typec_role_path" 2>/dev/null || true)"
        case "$typec_role" in
          *"[device]"*) ;;
          *)
            printf '%s\n' device > "$typec_role_path" 2>/dev/null || true
            for _typec_wait in $(seq 1 20); do
              case "$(cat "$typec_role_path" 2>/dev/null || true)" in
                *"[device]"*) break ;;
              esac
              sleep 0.1
            done
            echo "Type-C data role restored: $typec_role -> $(cat "$typec_role_path" 2>/dev/null || echo unknown)"
            ;;
        esac
      fi

      role_path=""
      for path in /sys/class/usb_role/*/role; do
        [ -w "$path" ] || continue
        role_path="$path"
        break
      done

      if [ -z "$role_path" ]; then
        echo "USB device-role recovery skipped: role switch is unavailable"
        exit 0
      fi

      role="$(cat "$role_path" 2>/dev/null || true)"
      if [ "$role" != "device" ]; then
        printf '%s\n' device > "$role_path"
        for _role_wait in $(seq 1 20); do
          [ "$(cat "$role_path" 2>/dev/null || true)" = "device" ] && break
          sleep 0.1
        done
        echo "USB data role restored: $role -> $(cat "$role_path" 2>/dev/null || echo unknown)"
      else
        echo "USB data role already device"
      fi

      # FunctionFS may have started while no UDC was available. Re-enabling
      # adbd binds the existing gadget as soon as the device role is active.
      systemctl try-restart adbd.service
    '';
  };
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

      current_attach_token() {
        for path in /sys/class/typec/port*-partner; do
          [ -e "$path" ] || continue
          stat -Lc '%d:%i:%Z' "$path" 2>/dev/null
          return
        done
        return 1
      }

      mark_attach_complete() {
        [ -n "''${attach_token:-}" ] || return 0
        mkdir -p "$(dirname "$completed_attach_file")"
        printf '%s\n' "$attach_token" > "$completed_attach_file"
        rm -f "$failed_attach_file"
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
        local advertised=""
        local negotiated=""
        local current_limit=""
        local target=""
        local target_source=""

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

        advertised="$(read_node "$ucsi" current_max 2>/dev/null || true)"
        negotiated="$(read_node "$ucsi" current_now 2>/dev/null || true)"
        current_limit="$(read_node "$battmgr" input_current_limit 2>/dev/null || true)"
        case "$advertised:$negotiated:$current_limit" in
          *[!0-9:]*|*::*|:*|*:) echo "Standard PD current sync skipped: invalid current data"; return 0 ;;
        esac

        if [ "$advertised" -gt 0 ]; then
          target="$advertised"
          target_source="advertised"
        else
          target="$negotiated"
          target_source="negotiated"
        fi
        [ "$target" -le 3000000 ] || target=3000000
        if [ "$target" -le "$current_limit" ]; then
          echo "Standard PD current sync unchanged: advertised=''${advertised}uA negotiated=''${negotiated}uA limit=''${current_limit}uA"
          return 0
        fi

        printf '%s\n' "$target" > "$battmgr/input_current_limit"
        current_limit="$(read_node "$battmgr" input_current_limit 2>/dev/null || true)"
        case "$current_limit" in
          ""|*[!0-9]*) echo "Standard PD current sync requested ''${target}uA from $target_source current; readback unavailable"; return 0 ;;
        esac
        if [ "$current_limit" -ge "$target" ]; then
          echo "Standard PD current sync applied: advertised=''${advertised}uA negotiated=''${negotiated}uA limit=''${current_limit}uA"
        else
          echo "Standard PD current sync requested ''${target}uA from $target_source current, but charger firmware retained ''${current_limit}uA"
        fi
      }

      root="$(find_xiaomi_dir || true)"
      if [ -z "$root" ]; then
        echo "MiPPS auth waiting: request_vdm_cmd sysfs node not found"
        exit 1
      fi

      completed_attach_file=/run/xiaomi-mipps-auth/completed-attach
      failed_attach_file=/run/xiaomi-mipps-auth/failed-attach
      attach_token="$(current_attach_token || true)"
      if [ -n "$attach_token" ] \
        && [ -r "$completed_attach_file" ] \
        && [ "$(cat "$completed_attach_file")" = "$attach_token" ]; then
        echo "MiPPS auth skipped: authentication already completed for this Type-C attach"
        exit 0
      fi
      if is_complete "$root"; then
        mark_attach_complete
        echo "MiPPS auth already active before attempt 1"
        exit 0
      fi
      if [ -n "$attach_token" ] \
        && [ -r "$failed_attach_file" ] \
        && [ "$(cat "$failed_attach_file")" = "$attach_token" ]; then
        echo "MiPPS auth skipped: handshake already exhausted for this Type-C attach"
        exit 0
      fi

      # A Type-C partner event also starts sheng-usb-device-role. Give adbd a
      # short window to bind its gadget before deciding this is a charger. A
      # configured data link is a computer connection and must never be torn
      # down by the authentication helper's host-role request.
      for _data_wait in $(seq 1 30); do
        if has_active_usb_data_link; then
          echo "MiPPS auth skipped: active USB data link"
          exit 0
        fi
        sleep 0.2
      done

      max_attempts=60
      max_helper_attempts=3
      helper_attempts=0
      # A partner add event is the only hotplug trigger. Keep waiting long
      # enough for charger_pd to publish PD/PPS after a cold boot.
      non_pd_grace_attempts=30
      empty_svid_grace_attempts=15
      stale_svid_grace_attempts=6
      sleep_seconds=2

      for attempt in $(seq 1 "$max_attempts"); do
        if is_complete "$root"; then
          mark_attach_complete
          echo "MiPPS auth already active before attempt $attempt"
          # Authentication completion emits another power_supply change event.
          # Do not invoke the helper again from that event: its data-role swap
          # can tear down the freshly authenticated Type-C partner.
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
            if ! has_active_usb_data_link; then
              sync_standard_pd_current
            fi
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
                mark_attach_complete
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
          # Xiaomi identity/authentication values survive some detach events.
          # A configured USB data link with no charger PDO is a standard PD
          # host connection, not the previously attached Xiaomi charger.
          if has_active_usb_data_link && [ "$attempt" -ge "$stale_svid_grace_attempts" ]; then
            echo "MiPPS auth skipped: stale Xiaomi SVID with no PDO on an active USB data link; treating this as standard PD"
            sync_standard_pd_current
            exit 0
          fi
          echo "MiPPS auth waiting: PD/PPS PDO not exposed yet"
          sleep "$sleep_seconds"
          continue
        fi

        helper_attempts=$((helper_attempts + 1))
        vdm_before="$(read_node "$root" request_vdm_cmd 2>/dev/null || true)"
        xiaomi-mipps-auth --sysfs "$root" --timeout 6 || true

        # Completion flags can lag behind the final VDM write. Give firmware
        # time to publish them before deciding that another handshake is
        # necessary.
        for _completion_wait in $(seq 1 5); do
          if is_complete "$root"; then
            echo "MiPPS auth active after attempt $attempt"
            mark_attach_complete
            exit 0
          fi
          sleep 1
        done

        if [ "$helper_attempts" -ge "$max_helper_attempts" ]; then
          vdm_after="$(read_node "$root" request_vdm_cmd 2>/dev/null || true)"
          echo "MiPPS auth stopped after $helper_attempts handshakes: VDM did not complete (before=''${vdm_before:-unknown} after=''${vdm_after:-unknown})"
          if [ -n "$attach_token" ]; then
            mkdir -p "$(dirname "$failed_attach_file")"
            printf '%s\n' "$attach_token" > "$failed_attach_file"
          fi
          sync_standard_pd_current
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
      after = [ "sheng-usb-device-role.service" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        ConditionPathExistsGlob =
          "/sys/devices/platform/pmic-glink/*/xiaomi/request_vdm_cmd";
        # Keep rapid detach/attach cycles eligible; flock and the per-attach
        # completion token make duplicate partner events harmless.
        StartLimitIntervalSec = 0;
      };
      serviceConfig = {
        # Let boot finish while PD/SVID discovery continues in this service.
        Type = "simple";
        ExecStart = "${pkgs.util-linux}/bin/flock -n -E 0 /run/xiaomi-mipps-auth.lock ${retryPackage}/bin/xiaomi-mipps-auth-retry";
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStartSec = 180;
      };
    };

    systemd.services.sheng-usb-device-role = {
      description = "Restore the sheng USB device role for ADB";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${usbDeviceRolePackage}/bin/sheng-usb-device-role";
      };
    };

    services.udev.extraRules = ''
      # Restore the gadget role first, then let MiPPS distinguish a computer
      # from a charger by whether the UDC reaches the configured state.
      ACTION=="add", SUBSYSTEM=="typec", KERNEL=="port*-partner", TAG+="systemd", ENV{SYSTEMD_WANTS}+="sheng-usb-device-role.service xiaomi-mipps-auth.service"
    '';
  };
}
