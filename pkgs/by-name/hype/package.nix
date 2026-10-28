{ lib, callPackage, zlib, libwebp, sourceHighlight }:
callPackage ../../lib/omacom-qt-app.nix { } {
  pname = "hype";
  version = "0.6.0";
  hash = "sha256-lDrDfo0LqGbWD8X7rejOYf9nKqyNNZh6wMlL9wRRJoU=";
  qtModules = [ "qtmultimedia" "qtsvg" "qtimageformats" ];
  buildInputs = [ zlib libwebp sourceHighlight ];
  description = "Markdown presentations";
}
