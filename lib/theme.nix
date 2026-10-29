# Theme palettes for what nix renders at build time (boot visuals, registry
# backgrounds; §f.5): `fromTOML` on a theme's colors.toml, with the subset of
# omarchy-theme-color's fallbacks those need. Reads source paths only (the
# pinned omarchy input or an omanix.theme.extra flake input), never a build
# output, so evaluating it is no IFD.
{ lib }:

let
  hex = v: builtins.isString v && builtins.match "#[0-9A-Fa-f]{6}" v != null;
in
rec {
  # The palette of the theme in `dir` (a directory holding colors.toml):
  # lowercase "#rrggbb" strings.
  palette = dir:
    let
      raw = builtins.fromTOML (builtins.readFile (dir + "/colors.toml"));
      pick = keys: fallback:
        let found = lib.findFirst (k: hex (raw.${k} or null)) null keys;
        in if found != null then lib.toLower raw.${found} else fallback;
      background = pick [ "background" "bg" "color0" ] null;
      foreground = pick [ "foreground" "fg" "color7" ] null;
      p = {
        inherit background foreground;
        accent = pick [ "accent" "blue" "color4" ] foreground;
        red = pick [ "red" "color1" ] "#f7768e";
        green = pick [ "green" "color2" ] "#9ece6a";
        yellow = pick [ "yellow" "color3" ] "#e0af68";
        blue = pick [ "blue" "color4" ] "#7aa2f7";
        magenta = pick [ "magenta" "purple" "color5" ] "#bb9af7";
        cyan = pick [ "cyan" "color6" ] "#7dcfff";
        muted = pick [ "muted" "color8" "dark_foreground" ] foreground;
        lighter_background = pick [ "lighter_background" "lighter_bg" ] background;
        bright_foreground = pick [ "bright_foreground" "bright_fg" "color15" ] foreground;
      };
      bright = n: k: def: pick [ "bright_${k}" n ] def;
    in
    if background == null || foreground == null
    then throw "omanix theme ${toString dir}: colors.toml needs a #rrggbb background and foreground"
    else p // {
      bright_red = bright "color9" "red" p.red;
      bright_green = bright "color10" "green" p.green;
      bright_yellow = bright "color11" "yellow" p.yellow;
      bright_blue = bright "color12" "blue" p.blue;
      bright_magenta = bright "color13" "magenta" p.magenta;
      bright_cyan = bright "color14" "cyan" p.cyan;
    };

  # "#rrggbb" -> "rrggbb"
  bare = c: lib.removePrefix "#" c;

  # Limine's style from a palette (nixpkgs boot.loader.limine.style; colors
  # are RRGGBB without '#'). Same layout as upstream's default/limine/limine.conf.
  limineStyle = p: {
    wallpapers = [ ];
    backdrop = bare p.background;
    interface = {
      branding = "omanix";
      brandingColor = bare p.accent;
      helpColor = bare p.accent;
      helpColorBright = bare p.accent;
    };
    graphicalTerminal = {
      palette = lib.concatMapStringsSep ";" bare
        [ p.background p.red p.green p.yellow p.blue p.magenta p.cyan p.foreground ];
      brightPalette = lib.concatMapStringsSep ";" bare
        [ p.muted p.bright_red p.bright_green p.bright_yellow p.bright_blue p.bright_magenta p.bright_cyan p.bright_foreground ];
      foreground = bare p.bright_foreground;
      background = bare p.background;
      brightForeground = bare p.bright_foreground;
      brightBackground = bare p.lighter_background;
    };
  };
}
