# omanix.menu.items: host entries in the default menu (§h.5). They are added
# to $OMARCHY_PATH's intent menu by pkgs.omanix-menu (fork.nix → omanix-data),
# which also hides the omanix.menu.hidden rows (theme/default.nix: the lock);
# the HM-owned ~/.config/omarchy/extensions/omarchy-menu.jsonc stays
# upstream's comment-only template.
{ config, lib, ... }:

let
  cfg = config.omanix;
  item = lib.types.submodule {
    options = {
      label = lib.mkOption { type = lib.types.str; description = "Visible row title."; };
      icon = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Nerd Font glyph."; };
      action = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Shell command to run (null: a submenu or a link)."; };
      intent = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Ask the agent instead of running a command: the id of an intent row (its text and skill), or the text that pre-fills the chat (`{label}` is the row's label)."; };
      skill = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "The resident skill an intent row names."; };
      target = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "An existing submenu id to open."; };
      when = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Shell condition; the row is hidden when it fails."; };
      after = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Place the entry after this id (and its children); null appends it."; };
    };
  };
in
{
  options.omanix.menu.items = lib.mkOption {
    type = lib.types.attrsOf item;
    default = { };
    example = lib.literalExpression ''{ "personal.notes" = { icon = "󰎞"; label = "Notes"; action = "omarchy-launch-editor ~/notes"; }; }'';
    description = "Extra entries for the default menu. IDs are dotted paths (`personal.notes` sits under `personal`).";
  };

  options.omanix.menu.hidden = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    internal = true;
    description = "Menu row ids shown with `\"when\": \"false\"` (set by omanix modules, e.g. the theme lock). An id that is not in the menu fails the build.";
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (id: i: {
      assertion = lib.length (lib.filter (x: x != null) [ i.action i.intent i.target ]) <= 1;
      message = "omanix.menu.items.${id}: set at most one of action, intent, target.";
    }) cfg.menu.items;

    home-manager.users.${config.loom.user.name}.xdg.configFile."omarchy/extensions/omarchy-menu.jsonc".source =
      "${cfg.fork.package}/config/omarchy/extensions/omarchy-menu.jsonc";

    omanix.home.files.".config/omarchy/extensions/omarchy-menu.jsonc" = { module = "menu.nix"; };
  };
}
