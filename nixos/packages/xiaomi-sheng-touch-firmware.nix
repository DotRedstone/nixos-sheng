{ lib, stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation {
  pname = "xiaomi-sheng-touch-firmware";
  version = "OS3.0.7.0.WNXCNXM";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/ianchb/sheng-firmware/3e9ced7fed3fe2591914c16a7b9e8010e0a244a8/novatek/novatek_nt36532_n81a_fw_csot.bin";
    hash = "sha256-dQUIu011Ry01zlhS7IRw1mr6a/SkJ0wTazdZA0Jg71k=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm0644 "$src" \
      "$out/lib/firmware/novatek/novatek_nt36532_n81a_fw_csot.bin"

    runHook postInstall
  '';

  meta = {
    description = "Factory NT36532E touch firmware for Xiaomi sheng";
    homepage = "https://github.com/ianchb/sheng-firmware";
    license = lib.licenses.unfreeRedistributableFirmware;
    platforms = [ "aarch64-linux" ];
  };
}
