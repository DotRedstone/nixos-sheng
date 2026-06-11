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

  # 6. Expose SSC-backed sensors to iio-sensor-proxy, and strip raw lid switch from logind
  services.udev.extraRules = ''
    # 彻底屏蔽物理 gpio-keys 的开关和输入设备属性，防止 logind 监听它并收到反向的合盖信号
    ACTION=="add|change", SUBSYSTEM=="input", ATTRS{name}=="gpio-keys", ENV{ID_INPUT_SWITCH}="", ENV{ID_INPUT}=""

    SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp*", ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel ssc-proximity ssc-light ssc-compass", ENV{ACCEL_MOUNT_MATRIX}="0, 1, 0; -1, 0, 0; 0, 0, -1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="iio-sensor-proxy.service"
  '';

  # 7. Ensure iio-sensor-proxy is enabled and starts after SSC is queryable.
  hardware.sensor.iio.enable = lib.mkDefault true;
  systemd.services.iio-sensor-proxy = {
    after = [ "adsprpcd-sensorspd.service" "systemd-udev-settle.service" ];
    wants = [ "adsprpcd-sensorspd.service" ];
    serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-sheng-ssc" ''
      for _ in $(seq 1 10); do
        if ${libssc}/bin/ssccli --sensor light --timeout 1 >/dev/null 2>&1; then
          exit 0
        fi
        sleep 1
      done

      exit 0
    '';
  };

  # 8. 平板模式 + 霍尔传感器息屏服务
  #
  # 设计思路：
  # - 虚拟设备只上报 SW_TABLET_MODE=1，不暴露 SW_LID 给 GNOME
  # - GNOME/Mutter 只看到平板模式，旋转永远可用，不受盖板影响
  # - 合盖/开盖息屏亮屏通过直接调 Mutter D-Bus PowerSaveMode 实现
  # - 与 GNOME 的 lid 逻辑完全解耦，避免开机早期合盖导致旋转失效
  boot.kernelModules = [ "uinput" ];
  systemd.services.fake-tablet-mode = let
    python = pkgs.python3.withPackages (p: [ p.evdev ]);
    script = pkgs.writeScript "fake-tablet-mode" ''
      #!${python}/bin/python3
      import sys, signal, time, subprocess, os
      import evdev
      from evdev import ecodes, UInput

      def get_real_lid_device():
          for path in evdev.list_devices():
              try:
                  dev = evdev.InputDevice(path)
                  if dev.name == "gpio-keys":
                      caps = dev.capabilities()
                      if ecodes.EV_SW in caps and ecodes.SW_LID in caps[ecodes.EV_SW]:
                          return dev
              except Exception:
                  continue
          return None

      def find_active_session():
          """找到当前活跃的 GNOME 会话，返回 (uid, username)"""
          try:
              out = subprocess.check_output(
                  ["${pkgs.systemd}/bin/loginctl", "list-sessions", "--no-legend"],
                  text=True, timeout=5
              )
              for line in out.strip().split("\n"):
                  parts = line.split()
                  if len(parts) >= 2:
                      session_id = parts[0]
                      try:
                          state = subprocess.check_output(
                              ["${pkgs.systemd}/bin/loginctl", "show-session", session_id, "-p", "Active", "--value"],
                              text=True, timeout=5
                          ).strip()
                          if state == "yes":
                              uid = subprocess.check_output(
                                  ["${pkgs.systemd}/bin/loginctl", "show-session", session_id, "-p", "User", "--value"],
                                  text=True, timeout=5
                              ).strip()
                              username = subprocess.check_output(
                                  ["${pkgs.coreutils}/bin/id", "-un", uid],
                                  text=True, timeout=5
                              ).strip()
                              return (uid, username)
                      except Exception:
                          continue
          except Exception:
              pass
          return None

      def set_power_save_mode(uid, username, mode):
          """通过 Mutter D-Bus 设置 PowerSaveMode (0=开屏, 3=息屏)"""
          bus = f"unix:path=/run/user/{uid}/bus"
          try:
              subprocess.run(
                  ["/run/wrappers/bin/su", "-s", "/bin/sh", username, "-c",
                   f"DBUS_SESSION_BUS_ADDRESS={bus} ${pkgs.systemd}/bin/busctl --user set-property "
                   f"org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig "
                   f"org.gnome.Mutter.DisplayConfig PowerSaveMode i {mode}"],
                  timeout=5, capture_output=True
              )
              print(f"fake-tablet-mode: set PowerSaveMode={mode}", file=sys.stderr)
          except Exception as e:
              print(f"WARNING: failed to set PowerSaveMode: {e}", file=sys.stderr)

      def main():
          # 查找物理 Hall 传感器输入设备
          real_dev = None
          for _ in range(30):
              real_dev = get_real_lid_device()
              if real_dev is not None:
                  break
              time.sleep(1)

          if real_dev is None:
              print("FATAL: real gpio-keys lid device not found", file=sys.stderr)
              sys.exit(1)

          print(f"fake-tablet-mode: found real lid device at {real_dev.path}", file=sys.stderr)

          # 创建虚拟设备：只上报 SW_TABLET_MODE，不暴露 SW_LID
          try:
              cap = {
                  ecodes.EV_SW: [ecodes.SW_TABLET_MODE]
              }
              ui = UInput(cap, name="Fake Tablet Mode Switch",
                          vendor=0x1234, product=0x5678)
          except Exception as e:
              print(f"FATAL: cannot create uinput device: {e}",
                    file=sys.stderr)
              sys.exit(1)

          # 直接设置 SW_TABLET_MODE=1，告知 GNOME 这是平板
          ui.write(ecodes.EV_SW, ecodes.SW_TABLET_MODE, 1)
          ui.syn()
          print("fake-tablet-mode: set SW_TABLET_MODE=1 (tablet mode, no lid exposed)", file=sys.stderr)

          def shutdown(sig, frame):
              print("fake-tablet-mode: shutting down", file=sys.stderr)
              ui.close()
              sys.exit(0)
          signal.signal(signal.SIGTERM, shutdown)
          signal.signal(signal.SIGINT, shutdown)

          # 循环监听物理 Hall 传感器，直接控制屏幕息屏/亮屏
          try:
              for event in real_dev.read_loop():
                  if event.type == ecodes.EV_SW and event.code == ecodes.SW_LID:
                      session = find_active_session()
                      if session:
                          uid, username = session
                          if event.value == 1:
                              # 合盖 → 息屏
                              print("fake-tablet-mode: lid closed, blanking screen", file=sys.stderr)
                              set_power_save_mode(uid, username, 3)
                          else:
                              # 开盖 → 亮屏
                              print("fake-tablet-mode: lid opened, unblanking screen", file=sys.stderr)
                              set_power_save_mode(uid, username, 0)
                      else:
                          print(f"fake-tablet-mode: lid event={event.value} but no active session", file=sys.stderr)
          except Exception as e:
              print(f"FATAL: error in event read loop: {e}", file=sys.stderr)
              ui.close()
              sys.exit(1)

      if __name__ == "__main__":
          main()
    '';
  in {
    description = "Fake Tablet Mode Switch and Hall Sensor Screen Control";
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
