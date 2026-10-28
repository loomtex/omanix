{ lib, callPackage, ffmpeg }:
callPackage ../../lib/omacom-qt-app.nix { } {
  pname = "omacut";
  version = "0.7.2";
  hash = "sha256-bNu2S0BPDCjm9PQQUCSC7UGuACpP9vXbbHILlaSoI0s=";
  qtModules = [ "qtmultimedia" ];
  buildInputs = [ ffmpeg ];
  description = "Dead-simple video length trimmer";
}
