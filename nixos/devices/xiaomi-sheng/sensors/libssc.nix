{ lib, stdenv, meson, ninja, pkg-config, glib, protobufc, protobuf, libqmi, libmbim }:

stdenv.mkDerivation {
  pname = "libssc";
  version = "0.3.0";

  src = ../../../vendor/libssc;

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
