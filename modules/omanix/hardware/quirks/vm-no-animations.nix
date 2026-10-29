# quirk vm-no-animations (fork/hw-quirks.toml; option quirks.vmNoAnimations): no animations and opaque windows in a VM (the GPU is usually the CPU there).
# Upstream: install/user/hardware/vm-no-animations.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.vmNoAnimations;
  seed = pkgs.writeShellScript "omanix-vm-no-animations" ''
    flag="''${XDG_STATE_HOME:-$HOME/.local/state}/omanix/done/vm-no-animations"
    [ -e "$flag" ] && exit 0
    dir="''${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr"
    mkdir -p "$dir" "$(dirname "$flag")"
    for t in no-animations window-opaque; do
      [ -e "$dir/$t.lua" ] || cp --no-preserve=mode ${config.omanix.fork.package}/default/hypr/toggles/$t.lua "$dir/"
    done
    touch "$flag"
  '';
in
{
  options.omanix.hardware.quirks.vmNoAnimations = {
    enable = lib.mkEnableOption "the vm-no-animations hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    # Runtime state, seeded once at the first login, so the human can toggle
    # them back (omarchy-toggle-animations, Window Opacity).
    systemd.user.services.omanix-quirk-vm-no-animations = {
      description = "omanix: first login in a VM: animations and transparency off";
      wantedBy = [ "graphical-session-pre.target" ];
      before = [ "graphical-session-pre.target" ];
      after = [ "omanix-session-init.service" ];
      unitConfig.ConditionUser = config.loom.user.name;
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = seed; };
    };
  };
}
