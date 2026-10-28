# omarchy's LazyVim config: LazyVim/starter plus omarchy's overrides
# (vendored from omacom-io/omarchy-pkgs pkgbuilds/omarchy-nvim, MIT).
#
# Deviation from the PKGBUILD: plugins are NOT pre-fetched (that needs the
# network inside the build). lazy.nvim installs them on first start, as plain
# LazyVim does. The config is data for the HM nvim module (W15/W17); the
# theme link (lua/plugins/theme.lua -> current omarchy theme) is made there.
{ lib, stdenvNoCC, fetchFromGitHub }:

stdenvNoCC.mkDerivation {
  pname = "omarchy-nvim";
  version = "2026.9.21-unstable-803bc18";

  src = fetchFromGitHub {
    owner = "LazyVim";
    repo = "starter";
    rev = "803bc181d7c0d6d5eeba9274d9be49b287294d99";
    hash = "sha256-QrpnlDD4r1X4C8PqBhQ+S3ar5C+qDrU1Jm/lPqyMIFM=";
  };

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/omarchy-nvim
    cp -r . $out/share/omarchy-nvim/config
    cp -r ${./config}/. $out/share/omarchy-nvim/config/
    rm -rf $out/share/omarchy-nvim/config/.git
    runHook postInstall
  '';

  meta = {
    description = "omarchy's LazyVim configuration (config only; plugins install on first start)";
    homepage = "https://github.com/LazyVim/starter";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
