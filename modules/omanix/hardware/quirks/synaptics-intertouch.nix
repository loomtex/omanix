# quirk synaptics-intertouch (fork/hw-quirks.toml; option quirks.synapticsIntertouch): Synaptics touchpads: InterTouch (SMBus) instead of PS/2.
# Upstream: install/hardware/fix-synaptic-touchpad.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.synapticsIntertouch;
in
{
  options.omanix.hardware.quirks.synapticsIntertouch = {
    enable = lib.mkEnableOption "the synaptics-intertouch hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.extraModprobeConfig = ''
      options psmouse synaptics_intertouch=1
    '';
  };
}
