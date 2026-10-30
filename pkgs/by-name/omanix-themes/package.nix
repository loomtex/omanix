# The theme registry (§f.5): `$OMARCHY_PATH/themes` in omanix-data. Every
# upstream theme from omarchy-src, plus omanix.theme.extra, plus what nix
# draws for each:
#
#   backgrounds/0-omanix.png  a plain background in the theme's color, for a
#                             theme that ships none (U23: upstream wallpapers
#                             and intro videos are unattributed at the pin and
#                             dropped, fork/drop-paths.txt)
#   unlock.png                the omanix wordmark in the theme's accent
#   preview-unlock.png        a still of the unlock screen (omanix-plymouth)
#
# An extra theme that is not `trusted` is staged the way upstream's
# omarchy-theme-set stages a theme cloned from a repo: no symlinks, no Lua
# (Hyprland and Neovim run it), no terminal configs and no vscode.json (they
# name programs to run). Theme files are linked, never copied.
{
  lib,
  runCommand,
  imagemagick,
  omarchy-src,
  omanixFork,
  omanix-plymouth,
  # { <slug> = { src = <path>; trusted = bool; }; }
  omanixExtraThemes ? { },
}:

let
  themeLib = import ../../../lib/theme.nix { inherit lib; };
  upstreamNames = builtins.attrNames (lib.filterAttrs (_: t: t == "directory")
    (builtins.readDir "${omanixFork.src}/themes"));

  # name -> { eval = dir for colors.toml (source, no IFD); link = dir to link; trusted }
  themes = lib.genAttrs upstreamNames (n: {
    eval = "${omanixFork.src}/themes/${n}";
    link = "${omarchy-src}/themes/${n}";
    trusted = true;
  }) // lib.mapAttrs (_: e: { eval = e.src; link = e.src; inherit (e) trusted; }) omanixExtraThemes;

  denied = [ "alacritty.toml" "foot.ini" "ghostty.conf" "kitty.conf" "vscode.json" ];

  one = name: t:
    let
      palette = themeLib.palette t.eval;
      splash = omanix-plymouth.override { omanixPalette = palette; };
    in
    ''
      d=$out/${name}
      mkdir -p "$d"
      ${if t.trusted then ''
        cp -rs --no-preserve=mode ${t.link}/. "$d/"
      '' else ''
        # untrusted: regular files only; no symlink, no Lua, no denied name
        (cd ${t.link} && find . -type f ! -name '*.lua' ${lib.concatMapStrings (n: "! -path ./${n} ") denied} -print0) |
          while IFS= read -r -d "" f; do
            mkdir -p "$d/$(dirname "$f")"
            ln -s "${t.link}/$f" "$d/$f"
          done
      ''}
      if [ ! -d "$d/backgrounds" ] || [ -z "$(ls -A "$d/backgrounds")" ]; then
        mkdir -p "$d/backgrounds"
        magick -size 3840x2160 'xc:${palette.background}' -strip "$d/backgrounds/0-omanix.png"
      fi
      [ -e "$d/unlock.png" ] || ln -s ${splash}/share/omanix-plymouth/omanix/logo.png "$d/unlock.png"
      [ -e "$d/preview-unlock.png" ] || ln -s ${splash}/share/omanix-plymouth/omanix/preview-unlock.png "$d/preview-unlock.png"
    '';
in
runCommand "omanix-themes"
  {
    nativeBuildInputs = [ imagemagick ];
    passthru = {
      names = builtins.attrNames themes;
      palettes = lib.mapAttrs (_: t: themeLib.palette t.eval) themes;
    };
    meta.description = "omanix theme registry: omarchy's themes and the host's extras";
  }
  (lib.concatStrings (lib.mapAttrsToList one themes))
