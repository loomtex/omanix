# quirk intel-thermald (fork/hw-quirks.toml; option quirks.intelThermald): thermald on Intel laptops (Sandy Bridge and newer).
# Upstream: install/hardware/intel/thermald.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.intelThermald;
in
{
  options.omanix.hardware.quirks.intelThermald = {
    enable = lib.mkEnableOption "the intel-thermald hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    services.thermald.enable = lib.mkDefault true;
  };
}
