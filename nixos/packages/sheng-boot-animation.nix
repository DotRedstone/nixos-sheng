# ---
# Module: Sheng Boot Animation
# Description: Bake blue snowflake boot frames and corner credits at two resolutions
# Scope: System
# ---
{ runCommand, buildPackages, inter }:
runCommand "sheng-boot-animation" {
  nativeBuildInputs = [ (buildPackages.python3.withPackages (ps: [ ps.pillow ])) ];
} ''
  python3 ${./build-boot-animation.py} ${inter}/share/fonts/truetype/Inter.ttc $out
''
