# Desktop health checks for the switch watchdog (loom.switch.watchdog, W8
# runs them after `switch-to-configuration test` and the per-session
# `hyprctl reload`): the compositor answers, the new Lua loaded without
# errors, and the shell is running.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  hyprctl = "${cfg.hyprland.package}/bin/hyprctl";
in
{
  config = lib.mkIf cfg.enable {
    loom.switch.watchdog.checks = {
      hyprland-ipc = {
        as = "session";
        command = "${hyprctl} -j monitors >/dev/null";
      };
      hyprland-configerrors = {
        as = "session";
        # `hyprctl configerrors` prints one empty line when there are none.
        command = "test -z \"$(${hyprctl} configerrors | tr -d '[:space:]')\"";
      };
      omanix-shell = {
        as = "session";
        command = "${pkgs.procps}/bin/pgrep -u \"$(id -u)\" -f 'quickshell .*-p ${cfg.path}/shell' >/dev/null";
      };
    };
  };
}
