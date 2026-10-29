# omanix.theme.boot: the boot visuals (§f.5), declarative and rebuild-time:
# the Plymouth splash and unlock screen (also loom-askpass's prompt), the
# SDDM greeter theme and Limine's colors, all drawn from one theme's
# colors.toml (lib/theme.nix). Changing it is an AGENT-INTENT ("Set the
# unlock screen to Kanagawa"), not a runtime switch.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  themeLib = import ../../../lib/theme.nix { inherit lib; };
  name = cfg.theme.boot.theme;
  dir = if cfg.theme.extra ? ${name} then cfg.theme.extra.${name}.src else "${pkgs.omanixFork.src}/themes/${name}";
  palette = themeLib.palette dir;

  plymouth = pkgs.omanix-plymouth.override { omanixPalette = palette; };
  sddm = pkgs.omanix-sddm-theme.override { omanixSplash = plymouth; };
in
{
  options.omanix.theme.boot = {
    theme = lib.mkOption {
      type = lib.types.enum cfg.theme.available;
      default = cfg.theme.default;
      defaultText = lib.literalExpression "config.omanix.theme.default";
      example = "kanagawa";
      description = "The theme whose colors the boot splash, the disk unlock prompt, the login greeter and the boot menu use.";
    };
    plymouth = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = plymouth;
      defaultText = lib.literalExpression "pkgs.omanix-plymouth for omanix.theme.boot.theme";
      description = "The Plymouth theme package (theme name `omanix`).";
    };
    sddm = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = sddm;
      defaultText = lib.literalExpression "pkgs.omanix-sddm-theme for omanix.theme.boot.theme";
      description = "The SDDM theme package (theme name `omanix`).";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      boot.plymouth = {
        enable = lib.mkDefault true;
        themePackages = lib.mkDefault [ plymouth ];
        theme = lib.mkDefault "omanix";
      };

      services.displayManager.sddm.theme = lib.mkDefault "omanix";
      environment.systemPackages = lib.mkIf config.services.displayManager.sddm.enable [ sddm ];
    }
    (lib.mkIf config.boot.loader.limine.enable {
      boot.loader.limine.style = lib.mapAttrsRecursive (_: lib.mkDefault) (themeLib.limineStyle palette);
    })
  ]);
}
