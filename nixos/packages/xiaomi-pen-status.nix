{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
}:

stdenv.mkDerivation {
  pname = "xiaomi-pen-status";
  version = "0.2.3-unstable-2026-07-24";

  src = fetchFromGitHub {
    owner = "ianchb";
    repo = "xiaomi-pen-status";
    rev = "fcf349109d2e69aedf7170479cc38b102ba1d4c0";
    hash = "sha256-UwRYo4nSElw14HRsuNlR7XimSA26RLmsB4iivf9IT6Y=";
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
    homepage = "https://github.com/ianchb/xiaomi-pen-status";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "xiaomi-pen-status";
  };
}
