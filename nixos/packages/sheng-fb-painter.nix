{ stdenv, buildPackages, inter }:

stdenv.mkDerivation {
  pname = "sheng-fb-painter";
  version = "1";

  dontUnpack = true;
  nativeBuildInputs = [ (buildPackages.python3.withPackages (ps: [ ps.pillow ps.fonttools ])) ];

  buildPhase = ''
    runHook preBuild
    python3 ${./build-menu-font.py} ${inter}/share/fonts/truetype/Inter.ttc \
      menu-font.h menu-font.rb
    $CC -O2 -std=c11 -Wall -Wextra -Werror -I. \
      ${./sheng-fb-painter.c} \
      -o sheng-fb-painter
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 sheng-fb-painter $out/bin/sheng-fb-painter
    install -Dm644 menu-font.rb $out/share/sheng/menu-font.rb
    runHook postInstall
  '';
}
