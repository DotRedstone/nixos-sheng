{ stdenv }:

stdenv.mkDerivation {
  pname = "sheng-fb-painter";
  version = "1";

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -std=c11 -Wall -Wextra -Werror \
      ${./sheng-fb-painter.c} \
      -o sheng-fb-painter
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 sheng-fb-painter $out/bin/sheng-fb-painter
    runHook postInstall
  '';
}
