{ lib, callPackage }:
callPackage ../../lib/omacom-qt-app.nix { } {
  pname = "omacalc";
  version = "0.3.1";
  owner = "omacom-io";
  hash = "sha256-Q1LGLTmMz8jqPGptyp8oZKr3iCM2YTR0f/NbmPY8AFQ=";
  description = "Dead-simple calculator";
  licenses = with lib.licenses; [ mit ofl ];
  extraLicenseFiles = [ "fonts/OFL.txt" ];
}
