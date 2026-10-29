# quirk intel-wifi7-eht (fork/hw-quirks.toml; option quirks.intelWifi7Eht): Wi-Fi 7 (EHT) off on Intel BE200/BE211, whose EHT receive path is broken.
# Upstream: install/hardware/intel/fix-wifi7-eht.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.intelWifi7Eht;
in
{
  options.omanix.hardware.quirks.intelWifi7Eht = {
    enable = lib.mkEnableOption "the intel-wifi7-eht hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.extraModprobeConfig = ''
      options iwlwifi disable_11be=Y
    '';
  };
}
