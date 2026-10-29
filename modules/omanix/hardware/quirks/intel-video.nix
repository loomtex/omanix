# quirk intel-video (fork/hw-quirks.toml; option quirks.intelVideo): Intel video acceleration (VA-API, oneVPL).
# Upstream: install/hardware/intel/video-acceleration.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.intelVideo;
in
{
  options.omanix.hardware.quirks.intelVideo = {
    enable = lib.mkEnableOption "the intel-video hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    hardware.graphics.extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt intel-vaapi-driver ];
    environment.sessionVariables.LIBVA_DRIVER_NAME = lib.mkDefault "iHD";
  };
}
