{ lib, stdenv, fetchFromGitHub, autoreconfHook, pkg-config, libyaml, makeWrapper }:

stdenv.mkDerivation rec {
  pname = "fastrpc";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "qualcomm";
    repo = "fastrpc";
    rev = "v${version}";
    hash = "sha256-/RXH34zqAxtWty75UHoOvS6fdmB+UfTRtB6G9IZiSWk=";
  };

  nativeBuildInputs = [ autoreconfHook pkg-config makeWrapper ];
  buildInputs = [ libyaml ];

  # Note: The original APKBUILD skips tests
  preAutoreconf = ''
    mkdir -p m4
  '';

  preConfigure = ''
    rm -rf src/fastrpc_test.c
    rm -rf src/fastrpc_test
  '';

  postInstall = ''
    # Clean up test binaries that might cause strip errors
    rm -rf $out/share/fastrpc_test
    rm -f $out/bin/fastrpc_test

    # Wrap binaries so dlopen can confidently find the listener libraries
    for p in adsprpcd cdsprpcd sdsprpcd gdsprpcd; do
      if [ -f $out/bin/$p ]; then
        wrapProgram $out/bin/$p \
          --prefix LD_LIBRARY_PATH : "$out/lib"
      fi
    done
  '';

  meta = with lib; {
    description = "FastRPC Daemon for Qualcomm ADSP";
    homepage = "https://github.com/qualcomm/fastrpc";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
