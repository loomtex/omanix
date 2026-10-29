# omanix.path: OMARCHY_PATH = /run/current-system/omarchy (§f.2.9). A switch
# retargets it atomically; it is set for login shells, PAM sessions (and so
# the systemd user manager) and uwsm.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  bootstrap = "${cfg.path}/default/bash/env-bootstrap";
in
{
  options.omanix.path = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "/run/current-system/omarchy";
    description = "Where the running generation's omarchy tree is (`$OMARCHY_PATH`).";
  };

  config = lib.mkIf cfg.enable {
    system.systemBuilderCommands = ''
      ln -s ${cfg.fork.data} $out/omarchy
    '';

    environment.sessionVariables = {
      OMARCHY_PATH = cfg.path;
      OMARCHY_LANGUAGE_FILE = "${cfg.path}/default/omanix/language";
    };

    # env-bootstrap puts $OMARCHY_PATH/bin on PATH and resets stale values (P15).
    environment.extraInit = ''
      [ -r ${bootstrap} ] && . ${bootstrap}
    '';

    # uwsm doesn't source /etc/profile; it reads the uwsm env files in the XDG
    # config dirs. Upstream's 10-omarchy pulls in the same bootstrap.
    environment.etc."xdg/uwsm/env".text = ''
      # omanix: generated (modules/omanix/path.nix)
      [ -r ${cfg.path}/default/uwsm/env.d/10-omarchy ] && . ${cfg.path}/default/uwsm/env.d/10-omarchy
      export OMARCHY_LANGUAGE_FILE=${cfg.path}/default/omanix/language
    '';
  };
}
