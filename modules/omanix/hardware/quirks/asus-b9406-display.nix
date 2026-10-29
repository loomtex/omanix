# quirk asus-b9406-display (fork/hw-quirks.toml; option quirks.asusB9406Display): ASUS ExpertBook B9406 (Xe3): Panel Replay off, its wake path is broken on this panel.
# Upstream: install/hardware/asus/fix-asus-ptl-b9406-display.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.asusB9406Display;
in
{
  options.omanix.hardware.quirks.asusB9406Display = {
    enable = lib.mkEnableOption "the asus-b9406-display hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.kernelParams = [ "xe.enable_panel_replay=0" ];
  };
}
