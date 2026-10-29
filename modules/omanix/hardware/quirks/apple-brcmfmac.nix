# quirk apple-brcmfmac (fork/hw-quirks.toml; option quirks.appleBrcmfmac): Macs with brcmfmac Wi-Fi: the WPA handshake in software (the firmware's fails in transition mode).
# Upstream: install/hardware/apple/fix-brcmfmac-supplicant.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.appleBrcmfmac;
in
{
  options.omanix.hardware.quirks.appleBrcmfmac = {
    enable = lib.mkEnableOption "the apple-brcmfmac hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.extraModprobeConfig = ''
      options brcmfmac feature_disable=0x82000
    '';
  };
}
