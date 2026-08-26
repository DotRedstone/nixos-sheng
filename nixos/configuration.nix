# ---
# Module: System Configuration
# Description: Overall system configuration for the device
# Scope: System
# ---

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/hardware.nix
    ./modules/sheng-boot-slot.nix
    ./modules/sheng-devauth.nix
    ./modules/sheng-offline-charging.nix
    ./modules/sheng-fingerprint.nix
    ./modules/sheng-rootfs-health.nix
    ./modules/xiaomi-mipps-auth.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  system.stateVersion = "25.11";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = lib.mkDefault "nixos-sheng";
  networking.networkmanager = {
    enable = true;
    # Managing the P2P device can leave WCN7850 scans stuck after Wi-Fi is
    # toggled, making every 5 GHz BSS disappear until the driver is reloaded.
    unmanaged = [ "interface-name:p2p-dev-wlp1s0" ];
    wifi = {
      # The sheng firmware can stop returning off-channel 5 GHz scan results
      # after a randomized scan or a power-save transition.
      scanRandMacAddress = false;
      powersave = false;
    };
  };
  # Connectivity is managed asynchronously and no sheng boot service requires
  # network-online.target. Waiting for carrier delayed graphical.target by
  # roughly 18 seconds in the measured baseline.
  systemd.services.NetworkManager-wait-online.wantedBy = lib.mkForce [ ];
  networking.useDHCP = lib.mkDefault true;

  # GNOME enables Avahi for local-network discovery. Keep its NSS side wired
  # up as well so .local lookups do not fail despite the daemon being active.
  services.avahi.nssmdns4 = true;

  time.timeZone = lib.mkDefault "Asia/Shanghai";
  services.timesyncd = {
    enable = lib.mkDefault true;
    servers = lib.mkDefault [
      "ntp.aliyun.com"
      "cn.pool.ntp.org"
      "time.cloudflare.com"
    ];
  };
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  # Bring-up hacks removed for better security
  # security.sudo.wheelNeedsPassword = false;

  services.openssh.enable = lib.mkDefault true;

  # Keep enough persistent history for cross-boot hardware diagnosis without
  # letting verbose bring-up logs grow with the full root partition.
  services.journald.extraConfig = ''
    SystemMaxUse=512M
    MaxRetentionSec=14day
  '';

  services.getty = {
    helpLine = ''
      NixOS sheng debug console
      Useful checks: dmesg -w, journalctl -b, ip addr, lsmod
    '';
  };

  # Suspend currently times out in the sheng kernel. Ignoring short power-key
  # presses prevents GDM/logind from disconnecting the device for about 40s.
  services.logind.settings.Login.HandlePowerKey = "ignore";
  # 盖板事件由 fake-tablet-mode 服务直接处理（D-Bus 息屏），logind 不介入。
  services.logind.settings.Login.HandleLidSwitch = "ignore";
  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
  services.logind.settings.Login.HandleLidSwitchDocked = "ignore";

  # 彻底禁用 suspend 功能，防止 GNOME 界面出现休眠按钮，避免误触导致设备内核假死
  systemd.sleep.settings = {
    Sleep = {
      AllowSuspend = "no";
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspendThenHibernate = "no";
    };
  };

  services.xiaomi-mipps-auth.enable = true;
  services.sheng-fingerprint.enable = true;
  services.sheng-fingerprint.wakeUnlock = true;

  console = {
    earlySetup = true;
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  services.kmscon = {
    enable = true;
    config = {
      hwaccel = false;
      "font-size" = 18;
    };
  };

  environment.systemPackages = let
    sheng-check = pkgs.writeShellScriptBin "sheng-check" (
      builtins.readFile ./scripts/sheng-check.sh
    );
    sheng-reboot-generation-menu = pkgs.writeShellScriptBin "sheng-reboot-generation-menu" ''
      set -eu

      if [ "$(id -u)" -ne 0 ]; then
        echo "Run this command with sudo." >&2
        exit 1
      fi

      install -d -m 0755 /var/lib/sheng-boot-menu
      : > /var/lib/sheng-boot-menu/requested
      sync
      systemctl reboot
    '';
    sheng-nixos-rebuild = pkgs.writeShellScriptBin "sheng-nixos-rebuild" ''
      set -eu

      if [ "$(id -u)" -ne 0 ]; then
        echo "Run this command with sudo." >&2
        exit 1
      fi

      if [ "$#" -ne 1 ]; then
        echo "Usage: sheng-nixos-rebuild PATH#CONFIGURATION" >&2
        exit 2
      fi

      case "$1" in
        *#*) flake_path="''${1%%#*}" ;;
        *)
          echo "The flake reference must include #CONFIGURATION." >&2
          exit 2
          ;;
      esac

      flake_path="$(realpath "$flake_path")"
      flake_ref="$flake_path#''${1#*#}"
      repo_root="$(${pkgs.gitMinimal}/bin/git -c safe.directory='*' \
        -C "$flake_path" rev-parse --show-toplevel)"

      export HOME=/root
      mkdir -p "$HOME"
      if ! ${pkgs.gitMinimal}/bin/git config --global --get-all safe.directory \
          | grep -Fxq "$repo_root"; then
        ${pkgs.gitMinimal}/bin/git config --global --add safe.directory "$repo_root"
      fi

      unit="sheng-nixos-rebuild-$(date +%Y%m%d-%H%M%S)"
      echo "Starting $unit.service"
      echo "Follow progress with: journalctl -fu $unit.service"

      # Activation restarts adbd when its unit changes. Run the complete rebuild
      # under PID 1 so losing the invoking ADB session cannot abort the switch.
      systemd-run \
        --unit="$unit" \
        --description="Build and activate a sheng stage-2 generation" \
        --collect \
        --property=Type=exec \
        --property=TimeoutStartSec=infinity \
        --setenv=HOME=/root \
        --setenv=USER=root \
        --setenv=LOGNAME=root \
        --setenv=PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gitMinimal pkgs.nix pkgs.systemd ]} \
        ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --flake "$flake_ref"
    '';
    sheng-alsa-ucm = pkgs.runCommand "sheng-alsa-ucm" { } ''
      install -Dm0644 ${./hardware/audio/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf} \
        $out/share/alsa/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf
      install -Dm0644 ${./hardware/audio/ucm2/Xiaomi/sheng/HiFi.conf} \
        $out/share/alsa/ucm2/Xiaomi/sheng/HiFi.conf
    '';
  in with pkgs; [
    sheng-check
    sheng-nixos-rebuild
    sheng-reboot-generation-menu
    sheng-alsa-ucm
    alsa-ucm-conf
    alsa-utils
    e2fsprogs
    bluez
    iio-sensor-proxy
    kmod
    libssc
    libinput
    libcamera-sheng
    util-linux
    gitMinimal # Required for nixos-rebuild to process git+file:// flakes via sudo
  ];

  environment.pathsToLink = [ "/share/alsa" ];
  environment.variables.ALSA_CONFIG_UCM2 = "/run/current-system/sw/share/alsa/ucm2";
  systemd.user.settings.Manager.DefaultEnvironment =
    "ALSA_CONFIG_UCM2=/run/current-system/sw/share/alsa/ucm2";
  systemd.user.services.pipewire.environment.LD_LIBRARY_PATH =
    lib.makeLibraryPath [ pkgs.libcamera-sheng ];

  systemd.packages = [ pkgs.iio-sensor-proxy ];
  services.dbus.packages = [ pkgs.iio-sensor-proxy ];
  services.udev.packages = [ pkgs.iio-sensor-proxy ];

  services.udev.extraRules = ''
    ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1", ENV{ID_INPUT_TOUCHSCREEN_INTEGRATION}="internal"
    SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_PATH}=="platform-1d84000.ufshc-scsi-*", ENV{UDISKS_IGNORE}="1"
    SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
  '';

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    extraConfig = {
      pipewire."91-sheng-audio-quality" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.allowed-rates" = [ 48000 96000 ];
        };
      };
      client."91-sheng-audio-quality" = {
        "stream.properties" = {
          "resample.quality" = 10;
          "channelmix.normalize" = false;
        };
      };
      pipewire-pulse."91-sheng-audio-quality" = {
        "stream.properties" = {
          "resample.quality" = 10;
          "channelmix.normalize" = false;
        };
      };
    };
    wireplumber.extraConfig."91-sheng-disable-bluez-midi" = {
      "wireplumber.profiles".main."monitor.bluez-midi" = "disabled";
    };
    wireplumber.extraConfig."92-sheng-speaker-eq" = {
      "wireplumber.profiles" = {
        main = {
          "filter.sink.sheng-speaker-eq" = "required";
        };
      };
      "wireplumber.components" = [
        {
          name = "libpipewire-module-filter-chain";
          type = "pw-module";
          arguments = {
            "node.name" = "filter.sink.sheng-speaker-eq";
            "node.description" = "Sheng Speaker Enhanced";
            "media.name" = "Sheng Speaker Enhanced";
            "filter.graph" = {
              nodes = [
                {
                  type = "builtin";
                  name = "preamp";
                  label = "linear";
                  control = {
                    Mult = 0.8;
                    Add = 0.0;
                  };
                }
                {
                  type = "builtin";
                  name = "warmth";
                  label = "bq_lowshelf";
                  control = {
                    Freq = 180.0;
                    Q = 0.8;
                    Gain = 1.5;
                  };
                }
                {
                  type = "builtin";
                  name = "mud_cut";
                  label = "bq_peaking";
                  control = {
                    Freq = 520.0;
                    Q = 1.0;
                    Gain = -1.4;
                  };
                }
                {
                  type = "builtin";
                  name = "presence_tame";
                  label = "bq_peaking";
                  control = {
                    Freq = 3600.0;
                    Q = 1.1;
                    Gain = -0.9;
                  };
                }
                {
                  type = "builtin";
                  name = "air";
                  label = "bq_highshelf";
                  control = {
                    Freq = 8500.0;
                    Q = 0.7;
                    Gain = 0.7;
                  };
                }
              ];
              links = [
                { output = "preamp:Out"; input = "warmth:In"; }
                { output = "warmth:Out"; input = "mud_cut:In"; }
                { output = "mud_cut:Out"; input = "presence_tame:In"; }
                { output = "presence_tame:Out"; input = "air:In"; }
              ];
            };
            "audio.channels" = 2;
            "audio.position" = [ "FL" "FR" ];
            "capture.props" = {
              "media.class" = "Audio/Sink";
              "filter.smart" = true;
              "filter.smart.name" = "filter.sink.sheng-speaker-eq";
              "filter.smart.target" = {
                "node.name" = "alsa_output.platform-sound.HiFi__Speaker__sink";
              };
            };
            "playback.props" = {
              "node.passive" = true;
              "media.role" = "DSP";
            };
          };
          provides = "filter.sink.sheng-speaker-eq";
        }
      ];
    };
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=CN
  '';
  # FastRPC is built into the boot image. The userspace-only rebuild flow may
  # retain an older fastrpc.ko in the rootfs module tree; never load it twice.
  boot.blacklistedKernelModules = [ "fastrpc" ];

  boot.kernelParams = [
    "console=tty0"
    "console=ttyMSM0,115200n8"
    "root=PARTLABEL=linux"
    "rootwait"
    "logo.nologo"
    "loglevel=4"
    "systemd.show_status=true"
    "udev.log_level=info"
    "rd.udev.log_level=info"
    "vt.global_cursor_default=1"
    "androidboot.force_normal_boot=1"
  ];

  boot.consoleLogLevel = 4;
  boot.initrd.verbose = true;

  boot.supportedFilesystems = [ "ext4" ];

  # Disable default xterm
  services.xserver.desktopManager.xterm.enable = false;
}
