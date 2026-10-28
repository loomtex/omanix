# Apple Studio Display / Pro Display XDR brightness over USB HID. The sudoers
# drop-in from the PKGBUILD is not shipped: the asdcontrol app module adds a
# udev uaccess rule instead (privilege = none, §f.2.5).
{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation (finalAttrs: {
  pname = "asdcontrol";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "omakasui";
    repo = "asdcontrol";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kxzkZeoUZu3dUp/E95h5e8R/BMLakyIgoSug2j0jOR4=";
  };

  makeFlags = [ "CXX=${stdenv.cc.targetPrefix}c++" ];
  installPhase = ''
    runHook preInstall
    install -Dm755 asdcontrol $out/bin/asdcontrol
    runHook postInstall
  '';

  meta = {
    description = "Control the brightness of Apple Studio Display and Pro Display XDR";
    homepage = "https://github.com/omakasui/asdcontrol";
    license = lib.licenses.gpl2Only;
    mainProgram = "asdcontrol";
    platforms = lib.platforms.linux;
  };
})
