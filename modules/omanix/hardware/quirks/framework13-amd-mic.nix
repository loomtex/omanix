# quirk framework13-amd-mic (fork/hw-quirks.toml; option quirks.framework13AmdMic): Framework Laptop 13 (AMD): the card profile with both microphones.
# Upstream: install/user/hardware/framework/fix-f13-amd-audio-input.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.framework13AmdMic;
in
{
  options.omanix.hardware.quirks.framework13AmdMic = {
    enable = lib.mkEnableOption "the framework13-amd-mic hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    services.pipewire.wireplumber.extraConfig."90-omanix-framework13-mic" = {
      "monitor.alsa.rules" = [{
        matches = [{ "device.product.name" = "~Family 17h/19h*"; }];
        actions.update-props."device.profile" = "HiFi (Mic1, Mic2, Speaker)";
      }];
    };
  };
}
