{ stdenv
, lib
, fetchurl
, dpkg
, autoPatchelfHook
}:

stdenv.mkDerivation rec {
  pname = "xiaomi-devauth";
  version = "1.0.0";

  # Download the sheng-devauth package from code002-2's repository
  src = fetchurl {
    url = "https://raw.githubusercontent.com/code002-2/Xiaomi-pad-6s-pro-Linux/main/rootfs-patches/sheng-devauth.deb";
    hash = "sha256:4bdefc04d5056c111ccc9da6f77ead447d90e2355168823c5e9af973dfe8ac3d";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
  ];

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/bin
    cp usr/bin/xiaomi_devauth $out/bin/
    chmod +x $out/bin/xiaomi_devauth
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "Xiaomi Proprietary Sensor and Keyboard Authentication Daemon";
    platforms = [ "aarch64-linux" ];
    license = licenses.unfree;
  };
}
