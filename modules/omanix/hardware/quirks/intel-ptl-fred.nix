# quirk intel-ptl-fred (fork/hw-quirks.toml; option quirks.intelPtlFred): FRED on Intel Panther Lake.
# Upstream: install/hardware/intel/fred.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.intelPtlFred;
in
{
  options.omanix.hardware.quirks.intelPtlFred = {
    enable = lib.mkEnableOption "the intel-ptl-fred hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.kernelParams = [ "fred=on" ];
  };
}
