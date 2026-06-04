{ config, lib, pkgs, ... }:

let
  fastrpc = pkgs.callPackage ./fastrpc.nix { };
  libssc = pkgs.callPackage ./libssc.nix { };
  sheng-sensors-file = pkgs.callPackage ./sheng-sensors-file.nix { };
  qrtr = pkgs.callPackage ./qrtr.nix { };
  pd-mapper = pkgs.callPackage ./pd-mapper.nix { inherit qrtr; };
  sheng-devauth = pkgs.callPackage ./devauth.nix { inherit (pkgs) sheng-firmware; };

in
{
  # 1. Overlay to patch iio-sensor-proxy with SSC support
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    (final: prev: {
      iio-sensor-proxy = prev.iio-sensor-proxy.overrideAttrs (old: {
        mesonFlags = (old.mesonFlags or []) ++ [ "-Dssc-support=enabled" ];
        buildInputs = (old.buildInputs or []) ++ [ libssc ];
      });
    })
  ];

  # 2. Provide the user-space daemon and registry files in system path
  environment.systemPackages = [
    fastrpc
    sheng-sensors-file
    qrtr
    pd-mapper
    sheng-devauth
  ];

  # 2b. sns_reg_config hardcodes paths to /usr/share/qcom/..., but NixOS uses read-only store paths.
  #     We must make it writable because ADSP sensor registry writes a temp.json cache to this dir.
  #     Copy the static files to /var/lib/qcom and symlink /usr/share/qcom to it.
  systemd.tmpfiles.rules = [
    "C /var/lib/qcom - - - - ${sheng-sensors-file}/share/qcom"
    "z /var/lib/qcom 0755 root root - -"
    "d /usr/share 0755 root root -"
    "L+ /usr/share/qcom - - - - /var/lib/qcom"
  ];

  # 3. Define the root adsprpcd service
  systemd.services.adsprpcd = {
    description = "aDSP RPC root daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    unitConfig.ConditionPathExists = "|/dev/fastrpc-adsp";
    serviceConfig = {
      Type = "exec";
      ExecStart = "${fastrpc}/bin/adsprpcd";
      Restart = "on-failure";
      RestartSec = "5";
      Environment = [
        "ADSP_LIBRARY_PATH=/usr/share/qcom/sm8550/Xiaomi/sheng;/run/pd-mapper-firmware;/run/pd-mapper-firmware/qcom/sm8550/sheng;/run/pd-mapper-firmware/rfsa/adsp;/run/current-system/firmware;/lib/firmware;/lib/firmware/qcom/sm8550/sheng;/run/current-system/firmware/rfsa/adsp"
      ];
    };
  };

  # 4. Define the pd-mapper service to serve firmware requests over QRTR
  systemd.services.pd-mapper = {
    description = "Qualcomm Protection Domain Mapper";
    wantedBy = [ "multi-user.target" ];
    after = [ "adsprpcd.service" ];
    before = [ "adsprpcd-sensorspd.service" ];
    path = [ pkgs.zstd pkgs.coreutils pkgs.findutils ];
    serviceConfig = {
      Type = "exec";
      ExecStartPre = pkgs.writeShellScript "pd-mapper-prep" ''
        mkdir -p /run/pd-mapper-firmware
        # Mirror the directory structure and decompress ZSTD JSON files
        cd /run/current-system/firmware
        find -L ./qcom -name "*.zst" | while read file; do
          mkdir -p "/run/pd-mapper-firmware/$(dirname "$file")"
          zstd -d -f "$file" -o "/run/pd-mapper-firmware/''${file%.zst}"
        done
      '';
      ExecStart = "${pd-mapper}/bin/pd-mapper";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # 4b. Define xiaomi_devauth service for Nanosic Authentication
  systemd.services.sheng-devauth = {
    description = "Xiaomi Proprietary Sensor and Keyboard Authentication Daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "adsprpcd.service" "systemd-modules-load.service" ];
    before = [ "adsprpcd-sensorspd.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${sheng-devauth}/bin/xiaomi_devauth";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # 5. Define the adsprpcd-sensorspd service (sensor PD fastrpc channel)
  systemd.services.adsprpcd-sensorspd = {
    description = "sensorspd aDSP RPC daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "adsprpcd.service" "pd-mapper.service" "sheng-devauth.service" "systemd-tmpfiles-setup.service" ];
    requires = [ "adsprpcd.service" "pd-mapper.service" ];
    before = [ "iio-sensor-proxy.service" ];

    # Run only if the fastrpc node exists
    unitConfig.ConditionPathExists = "|/dev/fastrpc-adsp";

    serviceConfig = {
      Type = "exec";
      ExecStart = "${fastrpc}/bin/adsprpcd sensorspd";
      Restart = "on-failure";
      RestartSec = "5";
      Environment = [
        "ADSP_LIBRARY_PATH=/usr/share/qcom/sm8550/Xiaomi/sheng;/run/pd-mapper-firmware;/run/pd-mapper-firmware/qcom/sm8550/sheng;/lib/firmware/qcom/sm8550/sheng"
      ];
    };
  };

  # 6. Ensure iio-sensor-proxy is enabled
  hardware.sensor.iio.enable = lib.mkDefault true;
}
