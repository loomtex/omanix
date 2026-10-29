# quirk asus-ptl-backlight (fork/hw-quirks.toml; option quirks.asusPtlBacklight): ASUS Panther Lake laptops: DPCD backlight control (PWM does nothing on these panels).
# Upstream: install/hardware/asus/fix-asus-ptl-display-backlight.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.asusPtlBacklight;
in
{
  options.omanix.hardware.quirks.asusPtlBacklight = {
    enable = lib.mkEnableOption "the asus-ptl-backlight hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.kernelParams = [ "xe.enable_dpcd_backlight=1" ];
  };
}
