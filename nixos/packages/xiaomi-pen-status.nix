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
    rev = "b70ba9a9ed8fa82a6578c6608b0de91567e85278";
    hash = "sha256-qxo6u6a3/ElsGnj3CZGJRf7HhEZgI3o75P6qbvSHRPA=";
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
