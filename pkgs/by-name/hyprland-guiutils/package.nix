# Hyprland GUI utilities (successor to hyprland-qtutils), not in nixpkgs.
# Mirrors the upstream flake's nix/default.nix against our nixpkgs.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  aquamarine,
  cairo,
  hyprgraphics,
  hyprlang,
  hyprtoolkit,
  hyprutils,
  libdrm,
  libGL,
  pango,
  pixman,
  libxkbcommon,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hyprland-guiutils";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprland-guiutils";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Ee78BRFi+MrmgHmmW+2dZUEI1R3cssEzza0ar3fsNX8=";
  };

  nativeBuildInputs = [ cmake pkg-config ];
  buildInputs = [
    aquamarine
    cairo
    hyprgraphics
    hyprlang
    hyprtoolkit
    hyprutils
    libdrm
    libGL
    libxkbcommon
    pango
    pixman
  ];

  meta = {
    description = "Hyprland GUI utilities (successor to hyprland-qtutils)";
    homepage = "https://github.com/hyprwm/hyprland-guiutils";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
})
