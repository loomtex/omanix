# Aether, omarchy's theming app (Go + Wails). Like the PKGBUILD this installs
# the upstream release binary (autoPatchelf'd) with assets from the tagged
# source; a from-source Wails build is future work.
{ lib, stdenv, fetchurl, fetchFromGitHub, autoPatchelfHook, wrapGAppsHook3, webkitgtk_4_1, gtk3, glib }:

let
  version = "4.32.0";
  src = fetchFromGitHub {
    owner = "omacom";
    repo = "aether";
    tag = "v${version}";
    hash = "sha256-Ntu2KRcEPyC4SvlFxW8PgdvijqH8OjljF60UuCvnWzg=";
  };
in
stdenv.mkDerivation {
  pname = "aether";
  inherit version;

  src = fetchurl {
    url = "https://github.com/omacom/aether/releases/download/v${version}/aether-linux-amd64";
    sha256 = "c705a4abef734b17ae37cdbff58a9a796517e6aa5f93ef18b68e3ee99d547ff9";
  };
  dontUnpack = true;

  nativeBuildInputs = [ autoPatchelfHook wrapGAppsHook3 ];
  buildInputs = [ webkitgtk_4_1 gtk3 glib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/aether
    install -Dm644 ${src}/build/linux/aether.desktop $out/share/applications/aether.desktop
    install -Dm644 ${src}/li.oever.aether.url-handler.desktop $out/share/applications/li.oever.aether.url-handler.desktop
    install -Dm644 ${src}/icon.png $out/share/pixmaps/aether.png
    install -Dm644 ${src}/assets/aether-icon-512.png $out/share/icons/hicolor/512x512/apps/aether.png
    runHook postInstall
  '';

  meta = {
    description = "Desktop theming application";
    homepage = "https://github.com/omacom/aether";
    license = lib.licenses.mit;
    mainProgram = "aether";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
