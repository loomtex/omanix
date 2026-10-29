# quirk lenovo-yoga-pro7-bass (fork/hw-quirks.toml; option quirks.lenovoYogaPro7Bass): Lenovo Yoga Pro 7 14IAH10: route audio to both amplifiers (bass speakers).
# Upstream: install/hardware/lenovo/fix-yoga-pro7-bass-speakers.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.lenovoYogaPro7Bass;
in
{
  options.omanix.hardware.quirks.lenovoYogaPro7Bass = {
    enable = lib.mkEnableOption "the lenovo-yoga-pro7-bass hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    boot.extraModprobeConfig = ''
      options snd-sof-intel-hda-generic hda_model=alc287-yoga9-bass-spk-pin
    '';
  };
}
