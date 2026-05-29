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

  isModular = true;
  isCompressed = "gz";
  isImageGzDtb = false;
  enableRemovingWerror = true;
  nativeBuildInputs = [
    buildPackages.lld
    buildPackages.llvmPackages.clang
    buildPackages.llvmPackages.llvm
    pkgs.buildPackages.python3
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

    echo "--- mobile-nixos network validation related ---"
    grep -nE '^CONFIG_BRIDGE=|^CONFIG_BRIDGE_NETFILTER=|^CONFIG_NF_TABLES=|^CONFIG_NETFILTER_XTABLES=|^CONFIG_IP6_NF_IPTABLES=' build/.config || true

    echo "--- compiler identity ---"
    command -v clang || true
    clang --version | head -3 || true
    clang -print-target-triple || true
    clang -print-resource-dir || true
  '';
}
