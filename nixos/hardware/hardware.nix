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

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 100;
  };

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.sheng-firmware ];
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
    "qcom-hv-haptics"
  ];

  # WCN7850 occasionally exposes only 2.4 GHz after its first firmware boot.
  # Prevent PCI modalias autoload so the service below can complete the known
  # good two-pass initialization before NetworkManager starts scanning.
  boot.blacklistedKernelModules = [ "ath12k_wifi7" ];

  systemd.services.sheng-wifi-modules = {
    description = "Load sheng Wi-Fi PCIe/MHI/ath12k modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    before = [
      "NetworkManager.service"
      "wpa_supplicant.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in pwrseq_qcom_wcn mhi mhi_pci_generic qrtr_mhi mhi_wwan_ctrl mhi_wwan_mbim mhi_net cfg80211; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done

      # The first WCN firmware cycle can leave all 5 GHz BSSes invisible even
      # after the regulatory domain settles. A driver-only second cycle fixes
      # it without rebooting the tablet or resetting shared Bluetooth power.
      ${pkgs.kmod}/bin/modprobe ath12k_wifi7
      for attempt in $(seq 1 10); do
        if [ -e /sys/class/net/wlan0 ] || [ -e /sys/class/net/wlp1s0 ]; then
          break
        fi
        sleep 1
      done
      sleep 2

      ${pkgs.kmod}/bin/modprobe -r ath12k_wifi7 || true
      ${pkgs.kmod}/bin/modprobe -r ath12k || true
      sleep 1
      ${pkgs.kmod}/bin/modprobe ath12k_wifi7

      for attempt in $(seq 1 15); do
        if [ -e /sys/class/net/wlan0 ] || [ -e /sys/class/net/wlp1s0 ]; then
          exit 0
        fi
        sleep 1
      done

      echo "WCN7850 interface did not return after the recovery cycle" >&2
      exit 1
    '';
  };

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
