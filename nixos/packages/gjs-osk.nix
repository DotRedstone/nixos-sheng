{ fetchurl
, glib
, lib
, stdenvNoCC
, unzip
}:

stdenvNoCC.mkDerivation {
  pname = "gnome-shell-extension-gjs-osk";
  version = "375b7db";

  src = fetchurl {
    url = "https://github.com/Vishram1123/gjs-osk/releases/download/375b7db/gjsosk%40vishram1123_main.zip";
    hash = "sha256-VXuIOgt046Cy8rf0EctMgBRrGiVAPmKOXmAgX//CMoM=";
  };

  nativeBuildInputs = [
    glib
    unzip
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    extensionDir="$out/share/gnome-shell/extensions/gjsosk@vishram1123.com"
    mkdir -p "$extensionDir"
    unzip -q "$src" -d "$extensionDir"
    glib-compile-schemas "$extensionDir/schemas"

    runHook postInstall
  '';

  meta = {
    description = "Movable on-screen keyboard for GNOME Shell";
    homepage = "https://github.com/Vishram1123/gjs-osk";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
