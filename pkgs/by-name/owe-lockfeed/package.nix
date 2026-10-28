# owe's QML plugin (Owe.LockFeed) that the Quickshell lock screen imports.
{ lib, stdenv, cmake, qt6, owe }:

stdenv.mkDerivation {
  pname = "owe-lockfeed";
  inherit (owe) version src;
  sourceRoot = "${owe.src.name}/qml-plugin";

  nativeBuildInputs = [ cmake ];
  buildInputs = [ qt6.qtbase qt6.qtdeclarative ];
  dontWrapQtApps = true;
  cmakeFlags = [ (lib.cmakeBool "BUILD_TESTING" false) ];

  # Install where Quickshell's QML import path looks (lib/qt-6/qml).
  postInstall = ''
    mkdir -p $out/${qt6.qtbase.qtQmlPrefix}
    mv $out/lib/qt6/qml/Owe $out/${qt6.qtbase.qtQmlPrefix}/
    rm -rf $out/lib/qt6
  '';

  meta = owe.meta // { description = "owe lock-screen frame feed (QML plugin)"; };
}
