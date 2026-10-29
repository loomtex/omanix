# quirk bcm43xx (fork/hw-quirks.toml): Broadcom BCM4360/BCM4331 Wi-Fi: the wl driver (unfree; the host must allow broadcom-sta).
# Upstream: install/hardware/fix-bcm43xx.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.bcm43xx;
in
{
  options.omanix.hardware.quirks.bcm43xx = {
    enable = lib.mkEnableOption "the bcm43xx hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
    boot.kernelModules = [ "wl" ];
    boot.blacklistedKernelModules = [ "b43" "bcma" "ssb" "brcmsmac" ];
  };
}
