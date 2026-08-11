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

  systemd.services.sheng-wifi-modules = {
    description = "Load sheng Wi-Fi PCIe/MHI/ath12k modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in pwrseq_qcom_wcn mhi mhi_pci_generic qrtr_mhi mhi_wwan_ctrl mhi_wwan_mbim mhi_net ath12k; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
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

      # Repeated CAMSS runtime ICC votes can time out in RPMh and block the
      # shared UFS interconnect path. Keep CAMSS active after it binds.
      camss_power=/sys/bus/platform/devices/acb7000.isp/power
      attempt=0
      while [ "$attempt" -lt 100 ]; do
        attempt=$((attempt + 1))
        if [ -w "$camss_power/control" ]; then
          echo on > "$camss_power/control"
          read -r runtime_status < "$camss_power/runtime_status"
          if [ "$runtime_status" = active ]; then
            exit 0
          fi
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      echo "CAMSS runtime power did not become active" >&2
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
