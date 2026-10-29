# omanix.hyprland.monitors → ~/.config/hypr/monitors.lua (HM, read-only).
# The panel's scale changes go to the overlay (omanix-overlay hypr-scale, P4);
# "make it stick" moves them here.
{ config, lib, ... }:

let
  cfg = config.omanix;
  hcfg = cfg.hyprland;
  lua = import ../../../lib/lua.nix { inherit lib; };
  homeLib = import ../../../lib/home { inherit lib; };

  monitor = lib.types.submodule {
    options = {
      output = lib.mkOption { type = lib.types.str; example = "DP-2"; description = "Output name; \"\" matches every output."; };
      mode = lib.mkOption { type = lib.types.str; default = "preferred"; example = "2560x1440@144"; description = "Resolution and refresh rate."; };
      position = lib.mkOption { type = lib.types.str; default = "auto"; example = "0x0"; description = "Position in the layout."; };
      scale = lib.mkOption { type = lib.types.either lib.types.number (lib.types.enum [ "auto" ]); default = "auto"; description = "Hyprland scale (fractions allowed)."; };
      vrr = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Variable refresh rate mode (0 off, 1 on, 2 fullscreen only)."; };
      transform = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Rotation (1 = 90°, 3 = 270°)."; };
    };
  };

  # Upstream's catch-all when nothing is declared.
  monitors = if hcfg.monitors == [ ] then [ { output = ""; mode = "preferred"; position = "auto"; scale = "auto"; vrr = null; transform = null; } ] else hcfg.monitors;

  line = m: "hl.monitor(${lua.toLua (lib.filterAttrs (_: v: v != null) m)})";
in
{
  options.omanix.hyprland.monitors = lib.mkOption {
    type = lib.types.listOf monitor;
    default = [ ];
    example = [ { output = "DP-2"; mode = "2560x1440@144"; position = "0x0"; scale = 1; } ];
    description = "Monitor rules; empty means upstream's `scale = \"auto\"` for every output.";
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${config.loom.user.name}.xdg.configFile."hypr/monitors.lua".text =
      homeLib.withOverlay
        (homeLib.banner "--" "omanix.hyprland.monitors (modules/omanix/hyprland/monitors.nix)"
          + lib.concatMapStringsSep "\n" line monitors + "\n"
          + ''hl.env("GDK_SCALE", ${lua.quote (toString hcfg.gdkScale)})'' + "\n"
          + hcfg.fileLua.monitors)
        (homeLib.include.lua "monitors");

    omanix.home.files.".config/hypr/monitors.lua" = { module = "hyprland/monitors.nix"; overlay = "hypr/monitors.lua"; };
  };
}
