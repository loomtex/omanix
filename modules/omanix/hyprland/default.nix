# omanix.hyprland: the compositor package and the HM-owned Hyprland Lua
# (§f.4.1, §f.4.2). Load order, identical to upstream with "user" = nix:
#   bootstrap → default.hypr.omarchy (defaults, theme) → HM hypr.{monitors,
#   input,bindings,looknfeel,autostart} (each ends with its overlay) →
#   default.hypr.toggles → HM tail (window rules, extraLua) → hyprland overlay.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  hcfg = cfg.hyprland;
  user = config.loom.user.name;
  lua = import ../../../lib/lua.nix { inherit lib; };
  homeLib = import ../../../lib/home { inherit lib; };
  up = "${cfg.fork.package}/config/hypr";

  titlebars = pkgs.omarchy-hyprland-titlebars.override { hyprland = hcfg.package; };

  windowRule = name: r:
    let rules = lib.filterAttrs (n: v: n != "match" && v != null) r; in
    "o.window(${lua.toLua r.match}, ${lua.toLua rules}) -- ${name}";

  hyprlandLua = homeLib.withOverlay (homeLib.banner "--" "omanix.hyprland (modules/omanix/hyprland/default.nix)" + ''
    dofile((os.getenv("OMARCHY_PATH") or "/run/current-system/omarchy") .. "/default/hypr/bootstrap.lua")

    omarchy_default_bindings = ${lua.toLua cfg.keybinds.defaults}
    omarchy_preinstalled_bindings = ${lua.toLua cfg.keybinds.preinstalled}

    require("default.hypr.omarchy")

    require("hypr.monitors")
    require("hypr.input")
    require("hypr.bindings")
    require("hypr.looknfeel")
    require("hypr.autostart")

    require("default.hypr.toggles")

    -- A switch reloads Hyprland once, after HM activation (§f.2.9).
    hl.config({ misc = { disable_autoreload = true } })

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList windowRule hcfg.windowRules)}
    ${hcfg.extraLua}
  '') (homeLib.include.lua "hyprland");

  # A file that is upstream's template plus the omanix slots, then its overlay.
  luaFile = name: body: homeLib.withOverlay
    (homeLib.banner "--" "omanix (modules/omanix/hyprland)" + body + "\n" + hcfg.fileLua.${name})
    (homeLib.include.lua name);

  looknfeel = lib.optionalString (hcfg.settings != { }) "hl.config(${lua.toLua hcfg.settings})\n";
in
{
  imports = [ ./monitors.nix ];

  options.omanix.hyprland = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hyprland-omarchy;
      defaultText = lib.literalExpression "pkgs.hyprland-omarchy";
      description = "Hyprland (0.56.2 + omarchy-pkgs patches). Plugins are built against exactly this package.";
    };
    settings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      example = { general.gaps_in = 2; decoration.rounding = 8; };
      description = "`hl.config` in ~/.config/hypr/looknfeel.lua (after the theme).";
    };
    windowRules = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        freeformType = (pkgs.formats.json { }).type;
        options.match = lib.mkOption {
          type = lib.types.either lib.types.str (lib.types.attrsOf lib.types.str);
          description = "A class regex, or { class; title; tag; … }.";
        };
      });
      default = { };
      example = { qemu = { match = "qemu"; workspace = "5"; }; };
      description = "`o.window(match, rules)` lines in the HM tail of hyprland.lua (float, size, workspace, opacity, …).";
    };
    extraLua = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = "hl.config({ cursor = { inactive_timeout = 5 } })";
      description = "Lua at the end of ~/.config/hypr/hyprland.lua, after the toggles and window rules (it runs as the human).";
    };
    fileLua = lib.mkOption {
      type = lib.types.submodule {
        options = lib.genAttrs [ "monitors" "input" "bindings" "looknfeel" "autostart" ] (f: lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Lua at the end of ~/.config/hypr/${f}.lua, before its overlay.";
        });
      };
      default = { };
      example = { looknfeel = "o.transparent_window(\"my-app\")"; };
      description = "Free Lua per HM Hyprland file (where 'make it stick' puts what it can't type, §f.4.6).";
    };
    gdkScale = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      example = 1;
      description = "GDK_SCALE for GTK and XWayland apps (whole numbers only).";
    };
    titlebars.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Build the titlebars plugin against omanix.hyprland.package (floating workspace mode).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."omanix/hyprland-titlebars.so" = lib.mkIf hcfg.titlebars.enable {
      source = "${titlebars}/${titlebars.pluginPath}";
    };

    home-manager.users.${user}.xdg.configFile = {
      "hypr/hyprland.lua".text = hyprlandLua;
      "hypr/looknfeel.lua".text = luaFile "looknfeel" looknfeel;
      # input.lua is input.nix's, autostart.lua apps/default.nix's.
      "hypr/hyprsunset.conf".text = homeLib.withOverlay (builtins.readFile "${cfg.fork.src}/config/hypr/hyprsunset.conf")
        (homeLib.include.hyprlang config.users.users.${user}.home "hypr/hyprsunset.conf");
      "hypr/xdph.conf".source = "${up}/xdph.conf";
    };

    omanix.home.files = {
      ".config/hypr/hyprland.lua" = { module = "hyprland/default.nix"; overlay = "hypr/hyprland.lua"; };
      ".config/hypr/looknfeel.lua" = { module = "hyprland/default.nix"; overlay = "hypr/looknfeel.lua"; };
      ".config/hypr/hyprsunset.conf" = { module = "hyprland/default.nix"; overlay = "hypr/hyprsunset.conf"; };
      ".config/hypr/xdph.conf" = { module = "hyprland/default.nix"; };
    };
  };
}
