# omanix.keybinds: ~/.config/hypr/bindings.lua (HM, read-only), loaded after
# the fork's default bindings. Chat is SUPER + A (P9).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  lua = import ../../lib/lua.nix { inherit lib; };
  homeLib = import ../../lib/home { inherit lib; };
  user = config.loom.user.name;

  actionKinds = [ "launch" "webapp" "tui" "menu" "panel" "ipc" "omarchy" "intent" ];

  bindType = lib.types.submodule ({ name, ... }: {
    options = {
      keys = lib.mkOption {
        type = lib.types.str;
        example = "SUPER + SHIFT + R";
        description = "The chord, in upstream's `MOD + MOD + KEY` form.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Shown in the keybindings menu.";
      };
      action = lib.mkOption {
        type = lib.types.either lib.types.str (lib.types.attrsOf lib.types.str);
        example = { launch = "nautilus"; };
        description = ''
          A shell command, or one of ${lib.concatStringsSep ", " actionKinds} as
          upstream's o.bind tables take them (`{ launch = "x"; }`, `{ webapp = url; }`,
          `{ panel = "omarchy.audio"; }`). `{ intent = id; }` asks the agent (W18/W19).
        '';
      };
      replaces = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "SUPER + SHIFT + F";
        description = "A default chord this bind removes first (o.rebind when it is the same chord).";
      };
    };
  });

  toDispatcher = a:
    if builtins.isString a then a
    else if a ? intent then "omanix intent ${lib.escapeShellArg a.intent}"
    else a;

  bindLine = name: b:
    lib.optionalString (b.replaces != null) "hl.unbind(${lua.quote b.replaces})\n"
    + "o.bind(${lua.quote b.keys}, ${lua.quote b.description}, ${lua.toLua (toDispatcher b.action)})";

  text = homeLib.withOverlay
    (homeLib.banner "--" "omanix.keybinds (modules/omanix/keybinds.nix)"
      + lib.concatMapStrings (k: "hl.unbind(${lua.quote k})\n") cfg.keybinds.unbind
      + lib.concatStringsSep "\n" (lib.mapAttrsToList bindLine cfg.keybinds.binds)
      + "\n" + cfg.hyprland.fileLua.bindings)
    (homeLib.include.lua "bindings");
in
{
  options.omanix.keybinds = {
    defaults = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Load the fork's default bindings (omarchy_default_bindings).";
    };
    preinstalled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Load the bindings for the preinstalled apps and web apps (omarchy_preinstalled_bindings).";
    };
    binds = lib.mkOption {
      type = lib.types.attrsOf bindType;
      default = { };
      example = lib.literalExpression ''{ ssh = { keys = "SUPER + SHIFT + R"; description = "SSH"; action = "alacritty -e ssh my-server"; }; }'';
      description = "Extra bindings, loaded after the defaults.";
    };
    unbind = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "SUPER + SHIFT + B" ];
      description = "Default chords to remove.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (n: b: {
      assertion = builtins.isString b.action || (builtins.length (builtins.attrNames b.action) >= 1
        && lib.any (k: b.action ? ${k}) actionKinds);
      message = "omanix.keybinds.binds.${n}.action: a command string or one of { ${lib.concatStringsSep " | " actionKinds} = …; }.";
    }) cfg.keybinds.binds;

    home-manager.users.${user}.xdg.configFile."hypr/bindings.lua".text = text;
    omanix.home.files.".config/hypr/bindings.lua" = { module = "keybinds.nix"; overlay = "hypr/bindings.lua"; };
  };
}
