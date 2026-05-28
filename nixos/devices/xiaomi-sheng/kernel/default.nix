{ mobile-nixos
, shengKernelSrc
, buildPackages
, ...
}:

mobile-nixos.kernel-builder-clang {
  version = "7.0.0";
  modDirVersion = "7.0.0-sm8550-g1c2d6f012c0a";
  src = shengKernelSrc;
  configfile = ./config.aarch64;

  isModular = true;
  isCompressed = "gz";
  isImageGzDtb = false;
  enableRemovingWerror = true;
  nativeBuildInputs = [
    buildPackages.lld
  ];
  makeFlags = [
    "LLVM=1"
    "KCFLAGS=-Wno-error=unused-command-line-argument"
  ];
}
