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

  # 3. Define the root sdsprpcd service
  systemd.services.sdsprpcd = {
    description = "SDSP RPC root daemon";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "|/dev/fastrpc-sdsp";
    serviceConfig = {
      Type = "exec";
      ExecStart = "${fastrpc}/bin/sdsprpcd";
      Restart = "on-failure";
      RestartSec = "5";
      Environment = [
        "DSP_LIBRARY_PATH=/run/current-system/firmware;/lib/firmware;/lib/firmware/qcom/sm8550/sheng"
      ];
    };
  };

  # 4. Define the sdsprpcd-sensorspd service to keep the Sensor PD alive
  systemd.services.sdsprpcd-sensorspd = {
    description = "sensorspd SDSP RPC daemon";
    wantedBy = [ "iio-sensor-proxy.service" ];
    after = [ "sdsprpcd.service" ];
    requires = [ "sdsprpcd.service" ];
    before = [ "iio-sensor-proxy.service" ];
    
    # Run only if the fastrpc node exists
    unitConfig.ConditionPathExists = "|/dev/fastrpc-sdsp";

    serviceConfig = {
      Type = "exec";
      ExecStart = "${fastrpc}/bin/sdsprpcd sensorspd sdsp";
      Restart = "on-failure";
      RestartSec = "5";
    };
  };

  # 5. Ensure iio-sensor-proxy is enabled
  hardware.sensor.iio.enable = lib.mkDefault true;
}
