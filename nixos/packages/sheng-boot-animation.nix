# ---
# Module: Sheng Boot Animation
# Description: Bake rounded boot animation frames for the native framebuffer painter
# Scope: System
# ---
{ runCommand, buildPackages, inter }:
runCommand "sheng-boot-animation" {
  nativeBuildInputs = [ (buildPackages.python3.withPackages (ps: [ ps.pillow ])) ];
} ''
  python3 ${./build-boot-animation.py} ${inter}/share/fonts/truetype/Inter.ttc $out
''
