{ config, lib, pkgs, ... }:

{
  fileSystems."/" = {
    device = "PARTLABEL=linux";
    fsType = "ext4";
    options = [ "noatime" "errors=remount-ro" ];
  };

  zramSwap.enable = true;

  hardware.enableRedistributableFirmware = true;

  boot.initrd.availableKernelModules = [
    "ext4"
    "phy_qcom_qmp_combo"
    "qcom_q6v5_pas"
    "qrtr"
  ];

  boot.kernelModules = [
    "qrtr"
  ];
}
