{ stdenv
, lib
, fetchurl
, dpkg
, autoPatchelfHook
}:

stdenv.mkDerivation rec {
  pname = "xiaomi-devauth";
  version = "1.0.0";

  # Download the sheng-devauth package from code002-2's repository release
  src = fetchurl {
    url = "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/kernel-7.0/sheng-devauth.deb";
    hash = "sha256:bc238fea615173624ee7868d0c17d9f4db62e13c1bcb85db76747b9d5961b0b9";
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
