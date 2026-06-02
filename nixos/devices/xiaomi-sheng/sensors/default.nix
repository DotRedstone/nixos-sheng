{ config, lib, pkgs, ... }:

let
  fastrpc = pkgs.callPackage ./fastrpc.nix { };
  libssc = pkgs.callPackage ./libssc.nix { };
  sheng-sensors-file = pkgs.callPackage ./sheng-sensors-file.nix { };

  # iio-sensor-proxy with SSC support enabled
  iio-sensor-proxy-ssc = pkgs.iio-sensor-proxy.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or []) ++ [ "-Dssc-support=true" ];
    buildInputs = (old.buildInputs or []) ++ [ libssc ];
  });
in
{
  # 1. Provide the user-space daemon and registry files in system path
  environment.systemPackages = [
    fastrpc
    iio-sensor-proxy-ssc
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

  # 4. Override systemd/udev/dbus packages to use the SSC patched version of iio-sensor-proxy
  systemd.packages = lib.mkForce [ iio-sensor-proxy-ssc ];
  services.dbus.packages = lib.mkForce [ iio-sensor-proxy-ssc ];
  services.udev.packages = lib.mkForce [ iio-sensor-proxy-ssc ];

  # Also ensure iio-sensor-proxy is enabled
  services.hardware.sensor.iio.enable = lib.mkDefault true;
}
