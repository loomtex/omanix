{ lib, callPackage }:
callPackage ../../lib/omacom-qt-app.nix { } {
  pname = "omawrite";
  version = "0.7.2";
  hash = "sha256-kjbiI5Wo/vX9Fs3XnN1K3PWPOtOIX85ZLFOL1HBl6t0=";
  description = "Dead-simple Markdown writing app";
  licenses = with lib.licenses; [ mit ofl ];
  extraLicenseFiles = [ "fonts/OFL.txt" ];
}
