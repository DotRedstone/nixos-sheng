{ mobile-nixos
, shengKernelSrc
, buildPackages
, ...
}:

let
  pkgs = buildPackages;
  llvmPkgs = pkgs.llvmPackages;
in
mobile-nixos.kernel-builder-clang {
  version = "7.0.0";
  modDirVersion = "7.0.0";
  src = shengKernelSrc;
  configfile = ./config.aarch64;
  patches = [
    ./0001-disable-dp0-sheng.patch
  ];

  isModular = true;
  isCompressed = "gz";
  isImageGzDtb = false;
  enableRemovingWerror = true;
  nativeBuildInputs = [
    buildPackages.lld
    buildPackages.llvmPackages.clang
    buildPackages.llvmPackages.llvm
    pkgs.buildPackages.python3
    pkgs.buildPackages.zstd
  ];
  makeFlags = [
    "LLVM=1"
    "CC=${llvmPkgs.clang-unwrapped}/bin/clang"
    "LD=${pkgs.lld}/bin/ld.lld"
    "AR=${llvmPkgs.llvm}/bin/llvm-ar"
    "NM=${llvmPkgs.llvm}/bin/llvm-nm"
    "OBJCOPY=${llvmPkgs.llvm}/bin/llvm-objcopy"
    "OBJDUMP=${llvmPkgs.llvm}/bin/llvm-objdump"
    "READELF=${llvmPkgs.llvm}/bin/llvm-readelf"
    "STRIP=${llvmPkgs.llvm}/bin/llvm-strip"
    "KCFLAGS=-Wno-error=unused-command-line-argument"
    "KCPPFLAGS=-Wno-error=unused-command-line-argument"
  ];

  postConfigure = ''
    echo "===== effective kernel config diagnostics ====="

    echo "--- io_uring ---"
    grep -nE '^CONFIG_IO_URING=|^# CONFIG_IO_URING is not set' build/.config || true

    echo "--- rootfs essentials ---"
    grep -nE '^CONFIG_EXT4_FS=|^CONFIG_BLK_DEV_INITRD=|^CONFIG_DEVTMPFS=|^CONFIG_TMPFS=' build/.config || true

    echo "--- compat / neon ---"
    grep -nE '^CONFIG_COMPAT=|^# CONFIG_COMPAT is not set|^CONFIG_COMPAT_VDSO=|^# CONFIG_COMPAT_VDSO is not set|^CONFIG_KUSER_HELPERS=|^# CONFIG_KUSER_HELPERS is not set|^CONFIG_KERNEL_MODE_NEON=|^# CONFIG_KERNEL_MODE_NEON is not set' build/.config || true

    echo "--- gpio shared proxy ---"
    grep -nE '^CONFIG_HAVE_SHARED_GPIOS=|^CONFIG_GPIO_SHARED=|^CONFIG_GPIO_SHARED_PROXY=' build/.config || true

    echo "--- mobile-nixos network validation related ---"
    grep -nE '^CONFIG_BRIDGE=|^CONFIG_BRIDGE_NETFILTER=|^CONFIG_NF_TABLES=|^CONFIG_NETFILTER_XTABLES=|^CONFIG_IP6_NF_IPTABLES=' build/.config || true

    echo "--- usb/input config ---"
    grep -nE '^(CONFIG_USB=|CONFIG_USB_COMMON=|CONFIG_USB_XHCI_HCD=|CONFIG_USB_XHCI_PLATFORM=|CONFIG_USB_DWC3=|CONFIG_USB_DWC3_QCOM=|CONFIG_USB_ROLE_SWITCH=|CONFIG_TYPEC=|CONFIG_TYPEC_UCSI=|CONFIG_UCSI_PMIC_GLINK=|CONFIG_QCOM_PMIC_GLINK=|CONFIG_QCOM_PMIC_GLINK_ALT_MODE=|CONFIG_QCOM_PDR_HELPERS=|CONFIG_QCOM_PD_MAPPER=|CONFIG_QRTR=|CONFIG_HID=|CONFIG_HID_GENERIC=|CONFIG_USB_HID=|CONFIG_INPUT_EVDEV=|CONFIG_USB_STORAGE=)' build/.config || true

    echo "--- compiler identity ---"
    command -v clang || true
    clang --version | head -3 || true
    clang -print-target-triple || true
    clang -print-resource-dir || true
  '';
}
