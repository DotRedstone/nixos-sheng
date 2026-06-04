{ stdenv
, lib
, sheng-firmware
}:

# xiaomi_devauth is a precompiled aarch64 binary shipped inside sheng-firmware-full.
# We simply copy it out into its own derivation so that systemd can reference it.
# No patching is needed because the binary is statically linked.
stdenv.mkDerivation {
  pname = "xiaomi-devauth";
  version = "1.0.0";

  # No build required
  dontUnpack = true;
  dontBuild = true;
  dontFixup = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ${sheng-firmware}/bin/xiaomi_devauth $out/bin/xiaomi_devauth
    chmod +x $out/bin/xiaomi_devauth
    runHook postInstall
  '';

  meta = with lib; {
    description = "Xiaomi Proprietary Sensor and Keyboard Authentication Daemon";
    platforms = [ "aarch64-linux" ];
    license = licenses.unfree;
  };
}
