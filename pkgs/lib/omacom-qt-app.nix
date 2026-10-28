# Builder shared by omacom's qmake + Qt 6 apps (omacalc, omacut, omawrite,
# hype, signed, monologue). Mirrors their PKGBUILDs: `qmake <name>.pro && make`,
# then install the binary, icon, desktop file and licenses.
{ lib, stdenv, fetchFromGitHub, qt6, pkg-config }:

{
  pname,
  version,
  hash,
  owner ? "omacom",
  qtModules ? [ ],
  buildInputs ? [ ],
  description,
  licenses ? [ lib.licenses.mit ],
  extraLicenseFiles ? [ ],
}:

stdenv.mkDerivation {
  inherit pname version;

  src = fetchFromGitHub {
    inherit owner hash;
    repo = pname;
    tag = "v${version}";
  };

  nativeBuildInputs = [ qt6.qmake qt6.wrapQtAppsHook pkg-config ];
  buildInputs = [ qt6.qtbase qt6.qtdeclarative qt6.qtwayland ] ++ map (m: qt6.${m}) qtModules ++ buildInputs;

  qmakeFlags = [ "${pname}.pro" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 ${pname} $out/bin/${pname}
    install -Dm644 pkgbuild/${pname}.svg $out/share/icons/hicolor/scalable/apps/${pname}.svg
    install -Dm644 pkgbuild/${pname}.desktop $out/share/applications/${pname}.desktop
    install -Dm644 LICENSE $out/share/licenses/${pname}/LICENSE
    ${lib.concatMapStrings (f: "install -Dm644 ${f} $out/share/licenses/${pname}/${baseNameOf f}\n") extraLicenseFiles}
    runHook postInstall
  '';

  meta = {
    inherit description;
    homepage = "https://github.com/${owner}/${pname}";
    license = licenses;
    mainProgram = pname;
    platforms = lib.platforms.linux;
  };
}
