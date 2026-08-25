{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  buildPackages,
  autoPatchelfHook,
  meson,
  ninja,
  pkg-config,
  glib,
  gusb,
  pixman,
  cairo,
  libgudev,
  openssl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "xiaomi-sheng-fingerprint";
  version = "0-unstable-2026-08-25";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-sheng-fingerprint";
    rev = "76e7301163b0e708f609c9864b3e5833e9f57402";
    hash = "sha256-EgP2w+60JpeTrHJf0AKN9Vmo/SdEpKXtv/j4mtkwmF4=";
  };

  libfprintSrc = fetchurl {
    url = "https://deb.debian.org/debian/pool/main/libf/libfprint/libfprint_1.94.10.orig.tar.xz";
    hash = "sha256-/1gnCL54RJgrp221c2rs3kqygThfu1W5mvX3S7FIS1I=";
  };

  fpcTrustedApp = fetchurl {
    url = "https://raw.githubusercontent.com/ianchb/sheng-firmware/2c1e2729a085c7f0470c855d236e49455c4601f0/fpcsheng.elf";
    hash = "sha256-JptAO4E5LJMDbfqzeyQIVw2Y99kAoKspeZAFsafKCMQ=";
  };

  patches = [
    ../patches/xiaomi-sheng-fingerprint/0001-qualify-finger-before-immediate-capture.patch
  ];

  nativeBuildInputs = [
    autoPatchelfHook
    meson
    ninja
    pkg-config
    buildPackages.glib
    buildPackages.patchelf
  ];

  postPatch = ''
    substituteInPlace scripts/build-libfprint.sh \
      --replace-fail \
        'meson setup "$WORK_DIR/build" "$WORK_DIR/src" \' \
        'meson setup "$WORK_DIR/build" "$WORK_DIR/src" ''${MESON_CROSS_FILE_FLAGS:-} \'
  '';

  buildInputs = [
    glib
    gusb
    pixman
    cairo
    libgudev
    openssl
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    ${lib.optionalString (!stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      cat > "$TMPDIR/meson-cross.ini" <<EOF
      [binaries]
      c = '$CC'
      cpp = '$CXX'
      ar = '$AR'
      strip = '$STRIP'
      pkg-config = '$PKG_CONFIG'
      exe_wrapper = '${stdenv.hostPlatform.emulator buildPackages}'

      [host_machine]
      system = 'linux'
      cpu_family = '${stdenv.hostPlatform.parsed.cpu.name}'
      cpu = '${stdenv.hostPlatform.parsed.cpu.name}'
      endian = '${if stdenv.hostPlatform.isLittleEndian then "little" else "big"}'

      [properties]
      needs_exe_wrapper = true
      EOF
      export MESON_CROSS_FILE_FLAGS="--cross-file=$TMPDIR/meson-cross.ini"
    ''}

    sha256sum -c prebuilt/aarch64/SHA256SUMS
    scripts/build-backend.sh "$PWD/build/backend"
    LIBFPRINT_TARBALL=${finalAttrs.libfprintSrc} \
      PATCHELF=${lib.getExe buildPackages.patchelf} \
      scripts/build-libfprint.sh \
        "$PWD/build/backend" "$PWD/build/libfprint"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -d "$out/lib/xiaomi-sheng-fingerprint" \
      "$out/lib/qtee-listeners" "$out/libexec" "$out/lib/firmware"

    install -m0644 build/libfprint/libfprint-2.so.2.0.0 \
      "$out/lib/xiaomi-sheng-fingerprint/"
    install -m0644 build/backend/libfpc1553-qtee.so \
      "$out/lib/xiaomi-sheng-fingerprint/"
    ln -s libfprint-2.so.2.0.0 \
      "$out/lib/xiaomi-sheng-fingerprint/libfprint-2.so.2"
    ln -s libfprint-2.so.2 \
      "$out/lib/xiaomi-sheng-fingerprint/libfprint-2.so"

    install -m0755 prebuilt/aarch64/qteesupplicant "$out/libexec/"
    install -m0755 prebuilt/aarch64/sfs_config \
      "$out/libexec/fpc-sfs-config"

    for listener in prebuilt/aarch64/qtee-listeners/*.so.1.0.0; do
      name="$(basename "$listener")"
      install -m0644 "$listener" "$out/lib/qtee-listeners/$name"
      ln -s "$name" "$out/lib/qtee-listeners/''${name%.0.0}"
    done

    install -m0644 ${finalAttrs.fpcTrustedApp} \
      "$out/lib/firmware/fpcsheng.elf"

    runHook postInstall
  '';

  meta = {
    description = "FPC1553 QTEE and libfprint support for Xiaomi sheng";
    homepage = "https://github.com/ianchb/xiaomi-sheng-fingerprint";
    license = with lib.licenses; [
      asl20
      bsd3
      lgpl21Plus
      unfreeRedistributableFirmware
    ];
    platforms = [ "aarch64-linux" ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
})
