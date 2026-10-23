# ---
# Module: Hardware Profile (Sheng)
# Description: Board-specific hardware details and firmware loading
# Scope: Host
# ---

{ config, lib, pkgs, ... }:

{
  fileSystems."/" = {
    device = "PARTLABEL=linux";
    fsType = "ext4";
    options = [ "noatime" "errors=remount-ro" ];
  };

  fileSystems."/mnt/vendor/persist" = {
    device = "/dev/disk/by-partlabel/persist";
    fsType = "ext4";
    options = [ "ro" "noatime" ];
  };

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [
    pkgs.sheng-firmware
    pkgs.sheng-touch-firmware
  ];
  hardware.wirelessRegulatoryDatabase = true;

  systemd.tmpfiles.rules = [
    "d /vendor 0755 root root -"
    "d /vendor/etc 0755 root root -"
    "L+ /vendor/etc/sensors - - - - /etc/sensors"
  ];

  boot.initrd.availableKernelModules = [
    "ext4"
    "phy_qcom_qmp_combo"
    "pwrseq_qcom_wcn"
    "qcom_q6v5_pas"
    "qrtr"
  ];

  boot.kernelModules = [
    "qrtr"
  ];

  # Linux 7.3 alternative A/B: allow kernel PCI modalias auto-probing.
  # Do not blacklist ath12k_wifi7 or force legacy 7.1.8 reinitialization.
  # The upstream driver probes from udev; failure to enumerate is part of
  # this experiment, not a reason to silently trigger a second probe.

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  systemd.services.sheng-bluetooth-modules = {
    description = "Load sheng WCN7851 Bluetooth modules";
    wantedBy = [ "bluetooth.service" ];
    before = [ "bluetooth.service" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in bluetooth btqca hci_uart rfkill_gpio; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };

  # Qualcomm's bundled NVM contains a placeholder controller address. Reuse
  # Android's factory-programmed address without ever writing to persist.
  systemd.services.sheng-bluetooth-address = {
    # WCN7851 re-registers with the firmware-provided address after the mgmt
    # public-address operation.  Keep Bluetooth usable until the vendor-side
    # address injection path is implemented as a separately validated fix.
    enable = false;
    description = "Load the factory Bluetooth address for sheng";
    # BlueZ owns hci0 once bluetoothd starts. It will reject the management
    # address change even if `btmgmt power off` was requested first, leaving
    # the bundled placeholder address active. The controller already exists
    # after the module loader, so replace its address before starting BlueZ.
    wantedBy = [ "bluetooth.service" ];
    requires = [ "mnt-vendor-persist.mount" ];
    after = [
      "mnt-vendor-persist.mount"
      "sheng-bluetooth-modules.service"
    ];
    before = [ "bluetooth.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      address_file=/mnt/vendor/persist/bluetooth/.bt_nv.bin
      if [ ! -r "$address_file" ]; then
        echo "Factory Bluetooth address is unavailable; keeping firmware address" >&2
        exit 0
      fi

      read -r -a octets <<< "$(${pkgs.coreutils}/bin/od -An -tx1 -N6 "$address_file")"
      if [ "''${#octets[@]}" -ne 6 ]; then
        echo "Factory Bluetooth address has an invalid length" >&2
        exit 1
      fi
      for octet in "''${octets[@]}"; do
        if [[ ! "$octet" =~ ^[0-9a-fA-F]{2}$ ]]; then
          echo "Factory Bluetooth address contains invalid data" >&2
          exit 1
        fi
      done
      printf -v address '%s:%s:%s:%s:%s:%s' "''${octets[@]}"
      address="''${address^^}"

      for attempt in $(seq 1 50); do
        current="$(${pkgs.bluez}/bin/btmgmt info 2>/dev/null |
          ${pkgs.gawk}/bin/awk '/addr / { print $2; exit }')"
        if [ -n "$current" ]; then
          break
        fi
        sleep 0.1
      done
      if [ -z "$current" ]; then
        echo "Bluetooth controller did not appear" >&2
        exit 1
      fi
      if [ "$current" = "$address" ]; then
        exit 0
      fi

      ${pkgs.bluez}/bin/btmgmt power off || true
      ${pkgs.bluez}/bin/btmgmt public-addr "$address"

      for attempt in $(seq 1 50); do
        current="$(${pkgs.bluez}/bin/btmgmt info 2>/dev/null |
          ${pkgs.gawk}/bin/awk '/addr / { print $2; exit }')"
        if [ "$current" = "$address" ]; then
          echo "Loaded factory Bluetooth address $address"
          exit 0
        fi
        sleep 0.1
      done

      echo "Bluetooth controller did not return with its factory address" >&2
      exit 1
    '';
  };

  systemd.services.sheng-touchscreen-modules = {
    description = "Load sheng Novatek touchscreen modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in spi_geni_qcom nt36532e_ts; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };

  systemd.services.sheng-audio-modules = {
    description = "Load sheng Qualcomm audio modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in \
        soundwire_qcom \
        snd_soc_qcom_common \
        snd_q6dsp_common \
        snd_q6apm \
        q6prm \
        snd_soc_wcd938x \
        snd_soc_wcd938x_sdw \
        snd_soc_cs35l43_i2c
      do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };

  systemd.services.sheng-camera-modules = {
    description = "Load and stabilize sheng camera/media modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "2s";
    };
    script = ''
      for module in i2c_qcom_cci qcom_camss s5kjn1_sheng ov32d40; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done

      camss_power=/sys/bus/platform/devices/acb7000.isp/power
      attempt=0
      while [ "$attempt" -lt 100 ]; do
        attempt=$((attempt + 1))
        if [ -w "$camss_power/control" ]; then
          echo auto > "$camss_power/control"
          read -r runtime_status < "$camss_power/runtime_status"
          if [ "$runtime_status" = suspended ]; then
            exit 0
          fi
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      echo "CAMSS runtime power did not suspend" >&2
      exit 1
    '';
  };

  systemd.services.sheng-led-modules = {
    description = "Load sheng LED/PWM modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in leds_qcom_flash leds_qcom_lpg; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };
}
