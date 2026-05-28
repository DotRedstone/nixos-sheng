{ mobile-nixos
, shengKernelSrc
, buildPackages
, ...
}:

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
  ];
  makeFlags = [
    "CC=clang"
    "LLVM=1"
    "KCFLAGS=-Wno-error=unused-command-line-argument"
    "KCPPFLAGS=-Wno-error=unused-command-line-argument"
  ];

  postConfigure = ''
    echo "===== effective io_uring config ====="
    grep -n "IO_URING" build/.config || true
    echo "===== effective bpf config ====="
    grep -n "BPF" build/.config | head -80 || true
  '';
}
