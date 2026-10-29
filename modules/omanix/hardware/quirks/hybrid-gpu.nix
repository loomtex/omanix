# quirk hybrid-gpu (fork/hw-quirks.toml; option quirks.hybridGpu): hybrid graphics: supergfxd, so omarchy-toggle-hybrid-gpu can switch modes.
# Upstream: bin/omarchy-toggle-hybrid-gpu, default/systemd/system/supergfxd.service.d.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.hybridGpu;
in
{
  options.omanix.hardware.quirks.hybridGpu = {
    enable = lib.mkEnableOption "the hybrid-gpu hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    services.supergfxd.enable = lib.mkDefault true;
    # default/systemd/system/supergfxd.service.d/delay-start.conf: booting in
    # Integrated mode can freeze when supergfxd races the display manager.
    systemd.services.supergfxd.serviceConfig.ExecStartPre = [ "${pkgs.coreutils}/bin/sleep 5" ];
  };
}
