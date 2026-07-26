# ---
# Module: GJS OSK Package
# Description: GNOME JavaScript On-Screen Keyboard package
# Scope: Package
# ---

{ fetchFromGitHub
, glib
, lib
, stdenvNoCC
}:

stdenvNoCC.mkDerivation rec {
  pname = "gnome-shell-extension-gjs-osk";
  version = "f2b8f31";

  src = fetchFromGitHub {
    owner = "Vishram1123";
    repo = "gjs-osk";
    rev = "f2b8f31e56c611463b746822dee18cfc8c47f287";
    hash = "sha256-tmhXlRNBYkceHZqIlx0CCfTPVr/pTUWa5Z6hqaqwZno=";
  };

  nativeBuildInputs = [
    glib
  ];

  installPhase = ''
    runHook preInstall

    extensionDir="$out/share/gnome-shell/extensions/gjsosk@vishram1123.com"
    mkdir -p "$extensionDir"
    cp -R "$src/gjsosk@vishram1123.com/." "$extensionDir/"
    chmod -R u+w "$extensionDir"
    substituteInPlace "$extensionDir/prefs.js" \
      --replace-fail "{{VERSION}}" "${version}"
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
