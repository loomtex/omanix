# owe: omarchy's video wallpaper engine (owed daemon + owe-idle hook). The
# user unit's ExecStart points at the store path instead of ~/.local/bin.
{
  lib, stdenv, fetchFromGitHub, meson, ninja, pkg-config, wayland-scanner,
  wayland, wayland-protocols, libGL, libepoxy, mpv-unwrapped, ffmpeg, systemd, socat, python3,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "owe";
  version = "0.2.12";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "owe";
    tag = "v${finalAttrs.version}";
    hash = "sha256-h281d5V8UTy+VlruwcyjSun1068gP+RFamflgRTb+6U=";
  };

  nativeBuildInputs = [ meson ninja pkg-config wayland-scanner python3 ];
  buildInputs = [ wayland wayland-protocols libGL libepoxy mpv-unwrapped ffmpeg systemd ];
  mesonBuildType = "release";

  postInstall = ''
    install -Dm755 $src/hooks/owe-idle $out/bin/owe-idle
    install -Dm644 $src/hooks/theme-set.d/10-owe-sync $out/share/owe/10-owe-sync
    install -Dm644 $src/config/config.toml $out/share/doc/owe/config.toml.example
    install -d $out/lib/systemd/user
    sed 's|%h/.local/bin/owed|'"$out"'/bin/owed|' $src/systemd/owed.service > $out/lib/systemd/user/owed.service
  '';

  postFixup = ''
    wrapProgram $out/bin/owe-idle --prefix PATH : ${lib.makeBinPath [ socat ]} 2>/dev/null || true
  '';

  meta = {
    description = "Wallpaper engine for omarchy (mp4, gif, stills)";
    homepage = "https://github.com/omacom/owe";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
