# quirk nouveau-cursor (fork/hw-quirks.toml; option quirks.nouveauCursor): software cursors under nouveau (the hardware cursor plane is invisible on many older NVIDIA GPUs).
# Upstream: install/user/hardware/fix-nouveau-cursor.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.nouveauCursor;
in
{
  options.omanix.hardware.quirks.nouveauCursor = {
    enable = lib.mkEnableOption "the nouveau-cursor hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    # Into the HM looknfeel.lua (hl.config), not appended by a script.
    omanix.hyprland.settings.cursor.no_hardware_cursors = lib.mkDefault true;
  };
}
