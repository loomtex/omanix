# omanix.menu.items: host entries in the default menu (§h.5). They are spliced
# into $OMARCHY_PATH's omarchy-menu.jsonc (fork.nix → omanix-data); the
# HM-owned ~/.config/omarchy/extensions/omarchy-menu.jsonc stays upstream's
# comment-only template. W18 builds the intent menu on top of this.
{ config, lib, ... }:

let
  cfg = config.omanix;
  item = lib.types.submodule {
    options = {
      label = lib.mkOption { type = lib.types.str; description = "Visible row title."; };
      icon = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Nerd Font glyph."; };
      action = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Shell command to run (null: a submenu or a link)."; };
      intent = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "An agent intent id (W18), instead of action."; };
      target = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "An existing submenu id to open."; };
      when = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Shell condition; the row is hidden when it fails."; };
      after = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Reserved for ordering (W18); ignored in v1."; };
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
