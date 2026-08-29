{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
}:

stdenv.mkDerivation {
  pname = "xiaomi-pen-status";
  version = "0.3.0-unstable-2026-08-29";

  src = fetchFromGitHub {
    owner = "DotRedstone";
    repo = "xiaomi-pen-status";
    rev = "22f762b5dda09b8cba2a8682e76cdb5176786b3a";
    hash = "sha256-fq5uCMFfmAR0K6AmwzL7IlQj7MyR7EWskTW2n1/zXZo=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtsvg
  ];

  installPhase = ''
    runHook preInstall

    install -Dm0755 xiaomi-pen-status "$out/bin/xiaomi-pen-status"
    install -Dm0644 xiaomi-pen-status.desktop \
      "$out/share/applications/xiaomi-pen-status.desktop"
    install -Dm0644 xiaomi-pen-status.svg \
      "$out/share/icons/hicolor/scalable/apps/xiaomi-pen-status.svg"

    install -d "$out/etc/xdg/autostart"
    substitute xiaomi-pen-status.desktop \
      "$out/etc/xdg/autostart/xiaomi-pen-status.desktop" \
      --replace-fail "Exec=xiaomi-pen-status --show" \
                     "Exec=xiaomi-pen-status"

    runHook postInstall
  '';

  meta = {
    description = "Xiaomi Focus Pen status and Bluetooth auto-connection utility";
    homepage = "https://github.com/DotRedstone/xiaomi-pen-status";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "xiaomi-pen-status";
  };
}
