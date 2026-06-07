{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ./hardware-sheng.nix
    ./services/sheng-devauth.nix
    ./services/xiaomi-mipps-auth.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  system.stateVersion = "25.11";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "nixos-sheng";
  networking.networkmanager = {
    enable = true;
    # Managing the P2P device can leave WCN7850 scans stuck after Wi-Fi is
    # toggled, making every 5 GHz BSS disappear until the driver is reloaded.
    unmanaged = [ "interface-name:p2p-dev-wlp1s0" ];
  };
  networking.useDHCP = lib.mkDefault true;

  time.timeZone = "Asia/Shanghai";
  services.timesyncd = {
    enable = true;
    servers = [
      "ntp.aliyun.com"
      "cn.pool.ntp.org"
      "time.cloudflare.com"
    ];
  };
  i18n.defaultLocale = "en_US.UTF-8";

  # Bring-up only: replace or remove this once stage-2 access is stable.
  users.users.root.initialPassword = "123456";
  users.users.luser = {
    isNormalUser = true;
    initialPassword = "luser";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" "render" ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };

  services.getty = {
    autologinUser = "luser";
    helpLine = ''
      NixOS sheng debug console
      Useful checks: dmesg -w, journalctl -b, ip addr, lsmod
    '';
  };

  # Suspend currently times out in the sheng kernel. Ignoring short power-key
  # presses prevents GDM/logind from disconnecting the device for about 40s.
  services.logind.settings.Login.HandlePowerKey = "ignore";

  services.xiaomi-mipps-auth.enable = true;

  console = {
    earlySetup = true;
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  services.kmscon = {
    enable = true;
    hwRender = false;
    config = {
      "font-size" = 18;
    };
  };

  environment.systemPackages = let
    sheng-check = pkgs.writeShellScriptBin "sheng-check" (builtins.readFile ./scripts/sheng-check.sh);
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
    sheng-alsa-ucm = pkgs.runCommand "sheng-alsa-ucm" { } ''
      install -Dm0644 ${./audio/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf} \
        $out/share/alsa/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf
      install -Dm0644 ${./audio/ucm2/Xiaomi/sheng/HiFi.conf} \
        $out/share/alsa/ucm2/Xiaomi/sheng/HiFi.conf
    '';
  in with pkgs; [
    sheng-check
    sheng-reboot-generation-menu
    sheng-alsa-ucm
    alsa-ucm-conf
    alsa-utils
    curl
    e2fsprogs
    evtest
    gitMinimal
    bluez
    brightnessctl
    iio-sensor-proxy
    iproute2
    iw
    kmod
    libssc
    libinput
    nano
    pciutils
    util-linux
    usbutils
    v4l-utils
    vim
    wget
  ];

  environment.variables.ALSA_CONFIG_UCM2 = "/run/current-system/sw/share/alsa/ucm2";
  systemd.user.extraConfig = ''
    DefaultEnvironment=ALSA_CONFIG_UCM2=/run/current-system/sw/share/alsa/ucm2
  '';

  systemd.packages = [ pkgs.iio-sensor-proxy ];
  services.dbus.packages = [ pkgs.iio-sensor-proxy ];
  services.udev.packages = [ pkgs.iio-sensor-proxy ];

  systemd.services.iio-sensor-proxy.wantedBy = [ "multi-user.target" ];

  services.udev.extraRules = ''
    ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"
    SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_PATH}=="platform-1d84000.ufshc-scsi-*", ENV{UDISKS_IGNORE}="1"
  '';

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=CN
  '';

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
}
