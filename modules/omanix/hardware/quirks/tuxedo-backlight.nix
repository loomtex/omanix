# quirk tuxedo-backlight (fork/hw-quirks.toml; option quirks.tuxedoBacklight): TUXEDO and Slimbook laptops: tuxedo-drivers (keyboard backlight); the conflicting clevo_xsm_wmi off.
# Upstream: install/hardware/fix-tuxedo-backlight.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.tuxedoBacklight;
in
{
  options.omanix.hardware.quirks.tuxedoBacklight = {
    enable = lib.mkEnableOption "the tuxedo-backlight hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    hardware.tuxedo-drivers.enable = lib.mkDefault true;
    boot.blacklistedKernelModules = [ "clevo_xsm_wmi" ];
  };
}
