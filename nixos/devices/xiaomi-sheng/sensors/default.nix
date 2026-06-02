{ config, lib, pkgs, ... }:

let
  fastrpc = pkgs.callPackage ./fastrpc.nix { };
  libssc = pkgs.callPackage ./libssc.nix { };
  sheng-sensors-file = pkgs.callPackage ./sheng-sensors-file.nix { };

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
  ];

  # 2. Make registry files available where libssc expects them (typically /usr/share/qcom or /etc/qcom)
  # sheng-sensors-file puts them in $out/share/qcom/sm8550/Xiaomi/sheng/registry/
  environment.etc."qcom".source = "${sheng-sensors-file}/share/qcom";

  # 3. Define the adsprpcd-sensorspd service to keep the Sensor PD alive
  systemd.services.adsprpcd-sensorspd = {
    description = "sensorspd aDSP RPC daemon";
    wantedBy = [ "iio-sensor-proxy.service" ];
    before = [ "iio-sensor-proxy.service" ];
    
    # Run only if the fastrpc node exists
    unitConfig.ConditionPathExists = "|/dev/fastrpc-adsp";

    serviceConfig = {
      Type = "exec";
      ExecStart = "${fastrpc}/bin/adsprpcd sensorspd";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # 5. Ensure iio-sensor-proxy is enabled
  hardware.sensor.iio.enable = lib.mkDefault true;
}
