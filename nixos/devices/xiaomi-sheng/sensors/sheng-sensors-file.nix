{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "sheng-sensors-file";
  version = "main";

  src = fetchFromGitHub {
    owner = "alghiffaryfa19";
    repo = "sheng-sensors-file";
    rev = "main";
    hash = lib.fakeHash;
  };

  installPhase = ''
    mkdir -p $out
    cp -a usr/* $out/
  '';

  meta = with lib; {
    description = "Sensor configuration files for Xiaomi Pad 6S Pro (sheng)";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
