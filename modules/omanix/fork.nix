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
        menuText =
          if cfg.menu.items == { } then null
          else (import ../../lib/menu.nix { inherit lib; }).appendItems
            (builtins.readFile "${cfg.fork.package}/default/omarchy/omarchy-menu.jsonc")
            cfg.menu.items;
      };
      defaultText = lib.literalExpression "pkgs.omanix-data with this host's options";
      description = "`$OMARCHY_PATH`: the fork plus the files generated from this host's options (§f.2.9).";
    };
  };
}
