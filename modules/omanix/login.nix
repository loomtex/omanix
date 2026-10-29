# omanix.login: the greeter. SDDM on Wayland, its compositor run with
# upstream's greeter Lua, and the omanix SDDM theme (theme/boot.nix) (U34:
# verified by the desktop-boots greeter variant; the fallback is greetd with
# the same config).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
in
{
  options.omanix.login.greeter = lib.mkOption {
    type = lib.types.enum [ "sddm" ];
    default = "sddm";
    description = "The login greeter (SDDM, Wayland, on Hyprland).";
  };

  config = lib.mkIf (cfg.enable && cfg.login.greeter == "sddm") {
    services.displayManager.sddm = {
      enable = lib.mkDefault true;
      wayland.enable = lib.mkDefault true;
      wayland.compositorCommand = lib.mkDefault
        "${cfg.hyprland.package}/bin/Hyprland --config ${cfg.fork.data}/default/sddm/hyprland.lua";
      package = lib.mkDefault pkgs.kdePackages.sddm;
    };

    # Upstream's theme has only a password field: it logs in as SDDM's last
    # user, which a fresh install doesn't have ("user unknown"). Seed it with
    # the human once (tmpfiles `f` never overwrites; /var/lib/sddm persists).
    services.displayManager.sddm.settings.Users.RememberLastUser = lib.mkDefault true;
    systemd.tmpfiles.rules = [
      "d /var/lib/sddm 0750 sddm sddm -"
      "f /var/lib/sddm/state.conf 0600 sddm sddm - [Last]\\nUser=${config.loom.user.name}\\n"
    ];
  };
}
