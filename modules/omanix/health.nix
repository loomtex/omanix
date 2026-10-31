# Desktop health checks for the switch watchdog (loom.switch.watchdog, W8
# runs them after `switch-to-configuration test` and the per-session
# `hyprctl reload`): the compositor answers, it still drives a real output
# (a monitor rule that disables the only screen leaves Hyprland on its
# headless FALLBACK output: a black screen with a healthy IPC), the new Lua
# loaded without errors, and the shell is running. Each is baseline-relative
# (loom), so a host that has no screen at the baseline isn't held to it.
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
      hyprland-display = {
        as = "session";
        command = "${hyprctl} -j monitors | ${pkgs.jq}/bin/jq -e 'map(select(.name != \"FALLBACK\" and (.disabled | not))) | length > 0' >/dev/null";
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
