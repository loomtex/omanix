# quirk asus-b9406-touchpad (fork/hw-quirks.toml; option quirks.asusB9406Touchpad): ASUS ExpertBook B9406: libinput ignores the touchpad's bogus pressure axes.
# Upstream: install/hardware/asus/fix-asus-ptl-b9406-touchpad.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.asusB9406Touchpad;
in
{
  options.omanix.hardware.quirks.asusB9406Touchpad = {
    enable = lib.mkEnableOption "the asus-b9406-touchpad hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    environment.etc."libinput/local-overrides.quirks".text = ''
      [ASUS ExpertBook B9406 Touchpad]
      MatchBus=i2c
      MatchUdevType=touchpad
      MatchVendor=0x093A
      MatchProduct=0x4F05
      MatchDMIModalias=dmi:*svnASUS*:pn*B9406*
      AttrEventCode=-ABS_MT_PRESSURE;-ABS_PRESSURE;
    '';
  };
}
