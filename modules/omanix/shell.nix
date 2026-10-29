# omanix.shell: the Quickshell shell (bar, dock, panels, lock, notifications,
# OSD, polkit agent). Settings merge over upstream's shell.json defaults in
# $OMARCHY_PATH (the default layer); the GUI's own edits are a snapshot in
# ~/.local/state/omanix/shell/shell.json (P1/P2), rebased by session init.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  json = (pkgs.formats.json { }).type;
in
{
  options.omanix.shell = {
    settings = lib.mkOption {
      type = json;
      default = { };
      example = { bar.position = "bottom"; idle.lock = 600; };
      description = "Merged over upstream's shell.json defaults (objects recursively; arrays replace).";
    };
    plugins = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          src = lib.mkOption { type = lib.types.path; description = "The plugin directory (a flake input)."; };
          enable = lib.mkOption { type = lib.types.bool; default = true; description = "Whether the shell loads it."; };
        };
      });
      default = { };
      example = lib.literalExpression "{ my-widget.src = inputs.my-widget; }";
      description = "Third-party Quickshell plugins. Installed into the shell's plugin path in W18; declared here.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.quickshell-omarchy;
      defaultText = lib.literalExpression "pkgs.quickshell-omarchy";
      description = "Quickshell build the shell runs on (rev 2b4501a).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.shell.package ];
  };
}
