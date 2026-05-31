{ config, lib, pkgs, ... }:

{
  fileSystems."/" = {
    device = "PARTLABEL=linux";
    fsType = "ext4";
    options = [ "noatime" "errors=remount-ro" ];
  };

  zramSwap.enable = false;

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.sheng-firmware ];
  hardware.wirelessRegulatoryDatabase = true;

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
}
