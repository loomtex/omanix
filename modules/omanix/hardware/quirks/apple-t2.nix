# quirk apple-t2 (fork/hw-quirks.toml; option quirks.appleT2): T2 Macs: nixos-hardware's apple-t2 (linux-t2, firmware) plus upstream's suspend parameters.
# Upstream: install/hardware/apple/fix-t2.sh.
{ config, lib, pkgs, options, ... }:

let
  q = config.omanix.hardware.quirks.appleT2;
in
{
  options.omanix.hardware.quirks.appleT2 = {
    enable = lib.mkEnableOption "the apple-t2 hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    assertions = [{
      assertion = options.hardware ? apple-t2;
      message = "omanix.hardware.quirks.appleT2 needs nixos-hardware's apple-t2 module in the host's imports (omanix.inputs.nixos-hardware.nixosModules.apple-t2).";
    }];
    boot.kernelParams = [ "pm_async=off" "mem_sleep_default=deep" ];
  };
}
