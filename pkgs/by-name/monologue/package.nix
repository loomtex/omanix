{ lib, callPackage, ffmpeg, libpulseaudio }:
callPackage ../../lib/omacom-qt-app.nix { } {
  pname = "monologue";
  version = "0.3.1";
  hash = "sha256-sQm/n0kHl13JQ3iOcOM5rZcP9xqrPpw6EKTVBLWha/I=";
  qtModules = [ "qtmultimedia" ];
  buildInputs = [ ffmpeg libpulseaudio ];
  description = "Record your camera with one key";
}
