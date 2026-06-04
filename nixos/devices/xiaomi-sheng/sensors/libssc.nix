{ lib, stdenv, fetchgit, meson, ninja, pkg-config, glib, protobufc, protobuf, libqmi, libmbim }:

stdenv.mkDerivation {
  pname = "libssc";
  version = "0.3.0";

  src = fetchgit {
    url = "https://codeberg.org/DylanVanAssche/libssc.git";
    rev = "refs/tags/v0.3.0";
    hash = "sha256-RmgjZbNUpF1u2vhX63VUxK9FV98MBcx5d9TExEDup0g=";
  };

  patches = [
    ./wait_for_qmi_service.patch
  ];

  nativeBuildInputs = [ meson ninja pkg-config protobufc protobuf ];
  buildInputs = [ glib protobufc libqmi libmbim ];

  meta = with lib; {
    description = "Library to expose Qualcomm Sensor Core sensors";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
