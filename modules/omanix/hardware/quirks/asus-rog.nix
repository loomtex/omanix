# quirk asus-rog (fork/hw-quirks.toml; option quirks.asusRog): ASUS ROG: asusd, a soft mixer for the speakers, sane ALC285 levels.
# Upstream: install/hardware/asus-rog.sh, install/user/hardware/asus/fix-{audio-mixer,mic}.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.asusRog;
  softMixer = pkgs.runCommand "omanix-asus-soft-mixer" { } ''
    install -Dm644 ${config.omanix.fork.package}/default/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf \
      $out/share/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf
  '';
  levels = pkgs.writeShellScript "omanix-asus-alc285" ''
    PATH=${lib.makeBinPath [ pkgs.alsa-utils pkgs.gnugrep pkgs.coreutils ]}
    for codec in /proc/asound/card*/codec*; do
      grep -q ALC285 "$codec" 2>/dev/null || continue
      card=''${codec#/proc/asound/card}; card=''${card%%/*}
      amixer -c "$card" set Master 80% unmute || true
      amixer -c "$card" set 'Internal Mic Boost' 0 || true
      amixer -c "$card" set Capture 70% unmute || true
      break
    done
    touch /var/lib/omanix/quirks/asus-alc285
  '';
in
{
  options.omanix.hardware.quirks.asusRog = {
    enable = lib.mkEnableOption "the asus-rog hardware quirk (fork/hw-quirks.toml)";
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    services.asusd.enable = lib.mkDefault true;
    environment.systemPackages = [ pkgs.asusctl ];
    services.pipewire.wireplumber.configPackages = [ softMixer ];

    # Once per machine, as upstream's install step: Master unmuted at 80 %,
    # the internal mic's boost off (it clips) and capture at 70 %.
    systemd.services.omanix-asus-alc285 = {
      description = "omanix: ASUS ROG ALC285 mixer levels (once)";
      wantedBy = [ "sound.target" ];
      after = [ "sound.target" ];
      unitConfig.ConditionPathExists = "!/var/lib/omanix/quirks/asus-alc285";
      serviceConfig = { Type = "oneshot"; ExecStart = levels; StateDirectory = "omanix/quirks"; };
    };
    loom.persist.system.directories = [ "/var/lib/omanix/quirks" ];   # "done once" survives reboots
  };
}
