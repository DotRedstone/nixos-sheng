{ lib, stdenv, fetchFromGitHub, autoreconfHook, yaml-cpp }:

stdenv.mkDerivation rec {
  pname = "fastrpc";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "qualcomm";
    repo = "fastrpc";
    rev = "v${version}";
    hash = "sha256-/RXH34zqAxtWty75UHoOvS6fdmB+UfTRtB6G9IZiSWk=";
  };

  nativeBuildInputs = [ autoreconfHook ];
  buildInputs = [ yaml-cpp ];

  # Note: The original APKBUILD skips tests
  preConfigure = ''
    rm -rf src/fastrpc_test.c
    rm -rf src/fastrpc_test
  '';

  installPhase = ''
    make DESTDIR=$out install
    # The default install places adsprpcd in sbin or doesn't install it. 
    # APKBUILD explicitly installs it to bin.
    install -Dm755 src/adsprpcd $out/bin/adsprpcd
    
    # Clean up test binaries that might cause strip errors
    rm -rf $out/usr/share/fastrpc_test
    rm -f $out/usr/bin/fastrpc_test
  '';

  meta = with lib; {
    description = "FastRPC Daemon for Qualcomm ADSP";
    homepage = "https://github.com/qualcomm/fastrpc";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
