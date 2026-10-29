# quirk asus-z13-touchpad (fork/hw-quirks.toml; option quirks.asusZ13Touchpad): ROG Flow Z13: the detachable keyboard's touchpad counts as internal, so disable-while-typing pairs it.
# Upstream: install/hardware/asus/fix-z13-touchpad.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.asusZ13Touchpad;
in
{
  options.omanix.hardware.quirks.asusZ13Touchpad = {
    enable = lib.mkEnableOption "the asus-z13-touchpad hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    services.udev.extraRules = ''
      ACTION=="add|change", KERNEL=="event*", ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="1a30", ENV{ID_INPUT_TOUCHPAD}=="1", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="internal"
    '';
  };
}
