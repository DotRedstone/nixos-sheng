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
  version = "0-unstable-2026-07-24";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-sheng-thp";
    rev = "34046210932d654a4c0df0121ecc31c008f8148c";
    hash = "sha256-+eSthfDjeP4nueqDuR88ZuWsWFs/4yxMH6iSlnujJpA=";
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
    homepage = "https://github.com/ianchb/xiaomi-sheng-thp";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-linux" ];
    mainProgram = "xiaomi-sheng-thp";
  };
}
