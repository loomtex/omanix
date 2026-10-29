# omanix.fork: the omarchy fork this build runs (§f.2.4, §f.2.9). Read-only.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
in
{
  options.omanix.fork = {
    src = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = pkgs.omanixFork.src;
      defaultText = lib.literalExpression "inputs.omarchy";
      description = "The pinned upstream omarchy tree (D2). Data only; never executed outside nix builds.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = pkgs.omarchy-src;
      defaultText = lib.literalExpression "pkgs.omarchy-src";
      description = "omarchy at the fork point with fork/ applied (drop, add, patch, rewrite).";
    };
    data = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = pkgs.omanix-data.override {
        omarchy-src = cfg.fork.package;
        shellSettings = cfg.shell.settings;
        inherit (cfg) language release;
        # The intent menu (W18, §h.5.2): upstream + intents.toml + menu-extra + omanix.menu.items.
        menu = pkgs.omanix-menu.override {
          omarchy-src = cfg.fork.package;
          items = lib.mapAttrs (_: i: lib.filterAttrs (_: v: v != null) i) cfg.menu.items;
          agent = if config.loom.agent.enable or false then config.loom.agent.name else "your agent";
        };
      };
      defaultText = lib.literalExpression "pkgs.omanix-data with this host's options";
      description = "`$OMARCHY_PATH`: the fork plus the files generated from this host's options (§f.2.9).";
    };
  };
}
