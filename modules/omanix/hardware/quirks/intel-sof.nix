# quirk intel-sof (fork/hw-quirks.toml; option quirks.intelSof): Sound Open Firmware for Intel audio DSPs (without it PipeWire only has a dummy output).
# Upstream: install/hardware/intel/sof-firmware.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.intelSof;
in
{
  options.omanix.hardware.quirks.intelSof = {
    enable = lib.mkEnableOption "the intel-sof hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    hardware.firmware = [ pkgs.sof-firmware ];
  };
}
