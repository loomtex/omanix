# omanix.audio: PipeWire with ALSA, PulseAudio and JACK, WirePlumber
# (upstream's base list), and the root half of omarchy-restart-audio
# (fork/add: privilege = unit): `omanix-usbreset@<vid:pid>.service`, which
# the active local user may start through polkit.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  user = config.loom.user.name;

  usbreset = pkgs.writeShellScript "omanix-usbreset" ''
    id=$1
    if [[ ! $id =~ ^[0-9a-f]{4}:[0-9a-f]{4}$ ]]; then
      echo "omanix-usbreset: refusing '$id' (want vid:pid)" >&2
      exit 2
    fi
    exec ${pkgs.usbutils}/bin/usbreset "$id"
  '';
in
{
  options.omanix.audio.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "PipeWire audio as omarchy sets it up (ALSA, PulseAudio and JACK clients, WirePlumber).";
  };

  config = lib.mkIf (cfg.enable && cfg.audio.enable) {
    services.pulseaudio.enable = lib.mkDefault false;
    security.rtkit.enable = lib.mkDefault true;
    services.pipewire = {
      enable = lib.mkDefault true;
      alsa.enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
      jack.enable = lib.mkDefault true;
      wireplumber.enable = lib.mkDefault true;
    };
    environment.systemPackages = with pkgs; [ alsa-utils pamixer wireplumber usbutils ];

    systemd.services."omanix-usbreset@" = {
      description = "omanix: reset the USB audio device %i (omarchy-restart-audio)";
      serviceConfig = { Type = "oneshot"; ExecStart = "${usbreset} %i"; };
    };
    security.polkit.extraConfig = ''
      // omanix (audio.nix): omarchy-restart-audio resets a stuck USB audio device
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            /^omanix-usbreset@[0-9a-f]{4}:[0-9a-f]{4}\.service$/.test(action.lookup("unit")) &&
            action.lookup("verb") == "start" &&
            subject.local && subject.active && subject.user == "${user}") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
