{ lib, stdenv, fetchurl, pkg-config, qrtr, xz }:

stdenv.mkDerivation rec {
  pname = "pd-mapper";
  version = "1.0";

  src = fetchurl {
    url = "https://github.com/linux-msm/pd-mapper/archive/5ecd2fe926aca7abfe40724177f63b942cff3947.tar.gz";
    sha256 = "08972b8813d08da5e20d27e57c5989398a0b750be92cd4398b5b21190c6ccdd0";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ qrtr xz ];

  postPatch = ''
    substituteInPlace pd-mapper.c \
      --replace-fail "/lib/firmware/" "/run/current-system/firmware/"
  '';

  makeFlags = [ "prefix=$(out)" "servicedir=$(out)/lib/systemd/system" "CC=${stdenv.cc.targetPrefix}cc" ];

  meta = with lib; {
    description = "Qualcomm Protection Domain Mapper";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
