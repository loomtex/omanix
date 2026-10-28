{ lib, callPackage, kdePackages, qpdf }:
callPackage ../../lib/omacom-qt-app.nix { } {
  pname = "signed";
  version = "0.3.1";
  hash = "sha256-fH5jXdO0uNsRblramzU0lcP3Dvv7pMZjf41FdE3lKjY=";
  buildInputs = [ kdePackages.poppler qpdf ];
  description = "Sign PDFs and fill them in with text and dates";
}
