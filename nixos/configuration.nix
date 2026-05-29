{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ./hardware-sheng.nix
    ./services/sheng-devauth.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  system.stateVersion = "25.11";

  networking.hostName = "nixos-sheng";
  networking.networkmanager.enable = true;
  networking.useDHCP = lib.mkDefault true;

  time.timeZone = "Asia/Shanghai";
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

  console = {
    earlySetup = true;
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  services.kmscon = {
    enable = true;
    hwRender = false;
    extraConfig = ''
      font-size=18
    '';
  };

  environment.systemPackages = with pkgs; [
    android-tools
    curl
    e2fsprogs
    gitMinimal
    iproute2
    kmod
    nano
    pciutils
    util-linux
    usbutils
    vim
    wget
  ];

  systemd.services."serial-getty@ttyMSM0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

  systemd.services."sheng-usb-serial-gadget" = {
    description = "xiaomi-sheng stage-2 USB serial debug gadget";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    path = with pkgs; [
      coreutils
      util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -u

      echo "sheng-usb-serial-gadget: mounting configfs"
      mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

      UDC="$(ls /sys/class/udc | head -n1 || true)"
      if [ -z "$UDC" ]; then
        echo "sheng-usb-serial-gadget: no UDC found"
        exit 1
      fi
      echo "sheng-usb-serial-gadget: selected UDC $UDC"

      G=/sys/kernel/config/usb_gadget/sheng

      if [ -d "$G" ]; then
        echo "sheng-usb-serial-gadget: cleaning old gadget"
        echo "" > "$G/UDC" 2>/dev/null || true
        for link in "$G"/configs/c.1/*; do
          [ -L "$link" ] && rm -f "$link" || true
        done
        rmdir "$G/functions/acm.usb0" 2>/dev/null || true
        rmdir "$G/functions/ffs.adb" 2>/dev/null || true
        rmdir "$G/configs/c.1/strings/0x409" 2>/dev/null || true
        rmdir "$G/configs/c.1" 2>/dev/null || true
        rmdir "$G/strings/0x409" 2>/dev/null || true
        rmdir "$G" 2>/dev/null || true
      fi

      mkdir -p "$G"
      echo 0x18d1 > "$G/idVendor"
      echo 0xd002 > "$G/idProduct"
      echo 0x0200 > "$G/bcdUSB"
      echo 0x0100 > "$G/bcdDevice"

      mkdir -p "$G/strings/0x409"
      echo "xiaomi-sheng" > "$G/strings/0x409/serialnumber"
      echo "DotRedstone" > "$G/strings/0x409/manufacturer"
      echo "NixOS USB Serial" > "$G/strings/0x409/product"

      mkdir -p "$G/configs/c.1/strings/0x409"
      echo "Serial" > "$G/configs/c.1/strings/0x409/configuration"
      echo 250 > "$G/configs/c.1/MaxPower"

      echo "sheng-usb-serial-gadget: creating acm.usb0"
      mkdir -p "$G/functions/acm.usb0"
      ln -s "$G/functions/acm.usb0" "$G/configs/c.1/acm.usb0"
      echo "sheng-usb-serial-gadget: acm.usb0 linked"

      echo "sheng-usb-serial-gadget: binding UDC"
      echo "$UDC" > "$G/UDC"
    '';
  };

  systemd.services."serial-getty@ttyGS0" = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Restart = "always";
  };

  services.udev.extraRules = ''
    ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"
  '';

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;

  boot.kernelParams = [
    "console=tty0"
    "console=ttyMSM0,115200n8"
    "fbcon=map:0"
    "fbcon=rotate:1"
    "ignore_loglevel"
    "loglevel=7"
    "root=PARTLABEL=linux"
    "rootwait"
    "systemd.log_level=debug"
  ];

  boot.supportedFilesystems = [ "ext4" ];
}
