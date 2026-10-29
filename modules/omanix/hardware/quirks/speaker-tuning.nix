# quirk speaker-tuning (fork/hw-quirks.toml; option quirks.speakerTuning): speaker voicing as a PipeWire filter-chain (upstream's default/audio/tunings).
# Upstream: install/hardware/speaker-tuning.sh.
{ config, lib, pkgs, ... }:

let
  q = config.omanix.hardware.quirks.speakerTuning;
  tunings = builtins.attrNames (lib.filterAttrs (_: t: t == "directory")
    (builtins.readDir "${config.omanix.fork.src}/default/audio/tunings"));
  conf = pkgs.runCommand "omanix-speaker-tuning" { } ''
    d=$out/share/pipewire
    install -Dm644 ${config.omanix.fork.package}/default/audio/filter-chain-host.conf $d/omanix-speaker-tuning.conf
    install -Dm644 ${config.omanix.fork.package}/default/audio/tunings/${q.tuning}/filter-chain.conf \
      $d/omanix-speaker-tuning.conf.d/90-tuning.conf
  '';
in
{
  options.omanix.hardware.quirks.speakerTuning = {
    enable = lib.mkEnableOption "the speaker-tuning hardware quirk (fork/hw-quirks.toml)";
    tuning = lib.mkOption {
      type = lib.types.enum tunings;
      default = "dell-xps-2026";
      example = "dell-xps-2026";
      description = "Which of upstream's tunings (default/audio/tunings/<name>).";
    };
  };

  config = lib.mkIf (config.omanix.enable && q.enable) {
    # A second pipewire instance that hosts only the filter-chain, as
    # upstream's omarchy-speaker-tuning.service; lsp-plugins for the limiter.
    systemd.user.services.omanix-speaker-tuning = {
      description = "omanix speaker tuning filter-chain (${q.tuning})";
      after = [ "pipewire.service" "wireplumber.service" ];
      requires = [ "pipewire.service" ];
      wants = [ "wireplumber.service" ];
      partOf = [ "pipewire.service" ];
      wantedBy = [ "graphical-session.target" ];
      environment = { PIPEWIRE_CONFIG_DIR = "${conf}/share/pipewire"; LV2_PATH = "${pkgs.lsp-plugins}/lib/lv2"; };
      serviceConfig = {
        ExecStart = "${pkgs.pipewire}/bin/pipewire -c omanix-speaker-tuning.conf";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };
}
