# install/hardware/set-wireless-regdom.sh: the wireless regulatory database,
# and the regulatory domain upstream derived from the time zone at install
# (the installer writes it here; null leaves the kernel's world domain).
{ config, lib, ... }:

let
  regdom = config.omanix.hardware.wireless.regdom;
in
{
  options.omanix.hardware.wireless.regdom = lib.mkOption {
    type = lib.types.nullOr (lib.types.strMatching "[A-Z]{2}");
    default = null;
    example = "US";
    description = "Wireless regulatory domain (ISO country code), as upstream set it from the time zone.";
  };

  config = lib.mkIf config.omanix.enable {
    hardware.wirelessRegulatoryDatabase = lib.mkDefault true;
    boot.extraModprobeConfig = lib.mkIf (regdom != null) ''
      options cfg80211 ieee80211_regdom=${regdom}
    '';
  };
}
