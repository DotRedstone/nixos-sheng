{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  glib,
  libssc,
}:

stdenv.mkDerivation {
  pname = "xiaomi-sheng-thp";
  version = "0-unstable-2026-08-29";

  src = fetchFromGitHub {
    owner = "DotRedstone";
    repo = "xiaomi-sheng-thp";
    rev = "c0b7c469430de2f200dc04e5ebd9d50691a10148";
    hash = "sha256-4FqEXEyJp03CzG9885AjQY45uwyaliKl0XikBc0tFBI=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ glib libssc ];

  postPatch = ''
    substituteInPlace Makefile \
      --replace-fail "/usr/include/libssc" "${libssc}/include/libssc"
  '';

  preBuild = ''
    export CXXFLAGS="-O3 -std=c++20 -Wall -Wextra -Werror"
  '';

  installPhase = ''
    runHook preInstall

    install -Dm0755 build/xiaomi-sheng-thp \
      "$out/libexec/xiaomi-sheng-thp/xiaomi-sheng-thp"
    install -Dm0644 README.md "$out/share/doc/xiaomi-sheng-thp/README.md"
    install -Dm0644 LICENSE "$out/share/licenses/xiaomi-sheng-thp/LICENSE"

    runHook postInstall
  '';

  meta = {
    description = "Userspace touch and Focus Pen processor for Xiaomi sheng";
    homepage = "https://github.com/DotRedstone/xiaomi-sheng-thp";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-linux" ];
    mainProgram = "xiaomi-sheng-thp";
  };
}
