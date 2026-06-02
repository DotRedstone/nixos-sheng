{ lib, stdenv, fetchgit, meson, ninja, pkg-config, glib, protobufc, libqmi, libmbim }:

stdenv.mkDerivation {
  pname = "libssc";
  version = "0.3.0";

  src = fetchgit {
    url = "https://codeberg.org/DylanVanAssche/libssc.git";
    rev = "refs/tags/0.3.0";
    hash = lib.fakeHash;
  };

  patches = [
    ./wait_for_qmi_service.patch
  ];

  nativeBuildInputs = [ meson ninja pkg-config protobufc ];
  buildInputs = [ glib protobufc libqmi libmbim ];

  meta = with lib; {
    description = "Library to expose Qualcomm Sensor Core sensors";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
