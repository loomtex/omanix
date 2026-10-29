# The omanix base (§b.3): the omarchy fork as NixOS + home-manager modules,
# added after loom's bundle by omanix.lib.mkHost. Every omanix.* option is
# declared in the file its path names (loom.lib.checks.layout).
{ omanix }:

{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
in
{
  _file = ./default.nix;

  imports = [
    ./branding.nix
    ./fork.nix
    ./health.nix
    ./home
    ./hooks.nix
    ./hyprland
    ./keybinds.nix
    ./language.nix
    ./login.nix
    ./menu.nix
    ./path.nix
    ./persist.nix
    ./residents.nix
    ./runtime.nix
    ./session.nix
    ./shell.nix
    ./weather.nix
  ];

  options.omanix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this host runs the omanix desktop (the omarchy fork on Hyprland).";
    };
    release = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = omanix.release or "0.1.0-dev";
      description = "The omanix release this build comes from (a tag; `0.1.0-dev` before the first one).";
    };
  };

  config = lib.mkIf cfg.enable {
    # pkgs.omarchy-src, pkgs.omanix-data, pkgs.hyprland-omarchy, … (pkgs/by-name)
    nixpkgs.overlays = [ omanix.overlays.default ];

    environment.etc."omanix/version".text = cfg.release + "\n";   # omarchy-version (W3)
  };
}
