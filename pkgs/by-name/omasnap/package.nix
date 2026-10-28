{
  lib, stdenv, fetchFromGitHub, cmake, ninja, pkg-config, qt6, kdePackages,
  wayland, wayland-protocols, wayland-scanner, libdeflate, tesseract, wl-clipboard,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "omasnap";
  version = "1.24.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omasnap";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ntlb7Nwrg7nuvBsTsbv9Va3TOSyPLqzEimP4tGb5rAE=";
  };

  nativeBuildInputs = [ cmake ninja pkg-config wayland-scanner qt6.wrapQtAppsHook ];
  buildInputs = [
    qt6.qtbase qt6.qtwayland kdePackages.layer-shell-qt
    wayland wayland-protocols libdeflate tesseract
  ];
  cmakeBuildType = "Release";

  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail /usr/share/wayland-protocols ${wayland-protocols}/share/wayland-protocols
  '';

  # OCR and copy-to-clipboard shell out at runtime.
  qtWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ tesseract wl-clipboard ]}" ];

  meta = {
    description = "Native Wayland screenshot and annotation overlay for Hyprland";
    homepage = "https://github.com/omacom/omasnap";
    license = with lib.licenses; [ mit ofl ];
    mainProgram = "omasnap";
    platforms = lib.platforms.linux;
  };
})
