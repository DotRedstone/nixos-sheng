{ config, lib, pkgs, ... }:

let
  fastrpc = pkgs.callPackage ./fastrpc.nix { };
  libssc = pkgs.callPackage ./libssc.nix { };
  sheng-sensors-file = pkgs.callPackage ./sheng-sensors-file.nix { };
  qrtr = pkgs.callPackage ./qrtr.nix { };
  pd-mapper = pkgs.callPackage ./pd-mapper.nix { inherit qrtr; };

in
{
  # 1. Overlay to patch iio-sensor-proxy with SSC support
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
  ];

  # 2. Make registry files available where libssc expects them (typically /usr/share/qcom or /etc/qcom)
  # sheng-sensors-file puts them in $out/share/qcom/sm8550/Xiaomi/sheng/registry/
  environment.etc."qcom".source = "${sheng-sensors-file}/share/qcom";

  # 3. Define the root adsprpcd service
  systemd.services.adsprpcd = {
    description = "aDSP RPC root daemon";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "|/dev/fastrpc-adsp";
    serviceConfig = {
      Type = "exec";
      ExecStart = "${fastrpc}/bin/adsprpcd";
      Restart = "on-failure";
      RestartSec = "5";
      Environment = [
        "ADSP_LIBRARY_PATH=/run/current-system/firmware;/lib/firmware;/lib/firmware/qcom/sm8550/sheng"
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
        find . -name "*.jsn.zst" | while read file; do
          mkdir -p "/run/pd-mapper-firmware/$(dirname "$file")"
          zstd -d -f "$file" -o "/run/pd-mapper-firmware/''${file%.zst}"
        done
      '';
      ExecStart = "${pd-mapper}/bin/pd-mapper";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # 5. Define the adsprpcd-sensorspd service to keep the Sensor PD alive
  systemd.services.adsprpcd-sensorspd = {
    description = "sensor_pd aDSP RPC daemon";
    wantedBy = [ "iio-sensor-proxy.service" ];
    after = [ "adsprpcd.service" "pd-mapper.service" ];
    requires = [ "adsprpcd.service" "pd-mapper.service" ];
    before = [ "iio-sensor-proxy.service" ];
    
    # Run only if the fastrpc node exists
    unitConfig.ConditionPathExists = "|/dev/fastrpc-adsp";

    serviceConfig = {
      Type = "exec";
      ExecStart = "${fastrpc}/bin/fastrpc_keepalive \"sensor_pd&_dom=adsp\"";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # 6. Ensure iio-sensor-proxy is enabled
  hardware.sensor.iio.enable = lib.mkDefault true;
}
