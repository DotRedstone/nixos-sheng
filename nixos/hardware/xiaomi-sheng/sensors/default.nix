# ---
# Module: Sensors Entry
# Description: Entry point for sensor services and hacks
# Scope: Host
# ---

{ config, lib, pkgs, ... }:

let
  fastrpc = pkgs.callPackage ./fastrpc.nix { };
  libssc = pkgs.callPackage ./libssc.nix { };
  sheng-sensors-file = pkgs.callPackage ./sheng-sensors-file.nix { };
  qrtr = pkgs.callPackage ./qrtr.nix { };
  pd-mapper = pkgs.callPackage ./pd-mapper.nix { inherit qrtr; };
  sheng-devauth = pkgs.callPackage ./devauth.nix { };

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
    "d /usr/lib 0755 root root -"
    "L+ /usr/lib/firmware - - - - /lib/firmware"
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

  # 6. Expose SSC-backed sensors to iio-sensor-proxy.
  services.udev.extraRules = ''
    SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp*", ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel ssc-proximity ssc-light ssc-compass", ENV{ACCEL_MOUNT_MATRIX}="0, 1, 0; -1, 0, 0; 0, 0, -1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="iio-sensor-proxy.service"
  '';

  # 7. Ensure iio-sensor-proxy is enabled and starts after SSC is queryable.
  hardware.sensor.iio.enable = lib.mkDefault true;
  systemd.services.iio-sensor-proxy = {
    after = [ "adsprpcd-sensorspd.service" "systemd-udev-settle.service" ];
    wants = [ "adsprpcd-sensorspd.service" ];
    serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-sheng-ssc" ''
      for _ in $(seq 1 30); do
        if ${libssc}/bin/ssccli --sensor light --timeout 1 >/dev/null 2>&1; then
          exit 0
        fi
        sleep 1
      done

      exit 0
    '';
  };

  # 8. Fake Tablet Mode Switch to coexist with SW_LID
  #
  # GNOME/Mutter 的自动旋转门控逻辑：
  # - 如果系统存在 SW_TABLET_MODE 开关 → 仅当 SW_TABLET_MODE=1 时允许旋转
  # - 如果系统不存在 SW_TABLET_MODE 开关 → Mutter 认为不是平板，禁止旋转
  # - 如果 SW_LID=1（盖板关闭）→ 即使平板模式也会抑制旋转
  #
  # sheng 的 gpio-keys Hall 传感器会上报 SW_LID，导致 Mutter 把平板当笔记本。
  # 此服务通过 uinput 创建虚拟 SW_TABLET_MODE 开关，永久设为 1，告知 Mutter
  # 当前是平板模式，从而在 SW_LID=0（盖板打开）时允许自动旋转。
  boot.kernelModules = [ "uinput" ];
  systemd.services.fake-tablet-mode = let
    python = pkgs.python3.withPackages (p: [ p.evdev ]);
    script = pkgs.writeScript "fake-tablet-mode" ''
      #!${python}/bin/python3
      import sys, signal, time
      import evdev
      from evdev import ecodes, UInput

      def main():
          try:
              cap = {ecodes.EV_SW: [ecodes.SW_TABLET_MODE]}
              ui = UInput(cap, name="Fake Tablet Mode Switch",
                          vendor=0x1234, product=0x5678)
          except Exception as e:
              print(f"FATAL: cannot create uinput device: {e}",
                    file=sys.stderr)
              sys.exit(1)

          def shutdown(sig, frame):
              print("fake-tablet-mode: shutting down", file=sys.stderr)
              ui.close()
              sys.exit(0)
          signal.signal(signal.SIGTERM, shutdown)
          signal.signal(signal.SIGINT, shutdown)

          # 初始化为笔记本模式 (0)，供 Mutter 之后检测到状态变化
          ui.write(ecodes.EV_SW, ecodes.SW_TABLET_MODE, 0)
          ui.syn()
          print("fake-tablet-mode: initialized SW_TABLET_MODE=0", file=sys.stderr)

          # 延迟 20 秒，等待 GDM / GNOME Shell 启动并加载完成
          print("fake-tablet-mode: waiting 20s for GNOME Shell to initialize...", file=sys.stderr)
          time.sleep(20)

          # 切换为平板模式 (1) 触发 GNOME 旋转逻辑
          ui.write(ecodes.EV_SW, ecodes.SW_TABLET_MODE, 1)
          ui.syn()
          print("fake-tablet-mode: toggled SW_TABLET_MODE=1", file=sys.stderr)

          while True:
              time.sleep(86400)

      if __name__ == "__main__":
          main()
    '';
  in {
    description = "Fake Tablet Mode Switch for GNOME Rotation";
    wantedBy = [ "multi-user.target" ];
    before = [ "display-manager.service" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${script}";
      Restart = "always";
      RestartSec = "3s";
    };
  };

}
