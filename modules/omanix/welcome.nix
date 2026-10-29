# omanix.welcome: the first-boot checklist and tour (§h.7), drawn by the
# fork's shell/plugins/omanix-welcome (W18).
{ config, lib, ... }:

let
  cfg = config.omanix;
in
{
  options.omanix.welcome.autoOpen = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Open the welcome checklist at the first login (until it is dismissed). It can always be reopened from the menu (Learn › Welcome).";
  };

  config = lib.mkIf cfg.enable {
    environment.etc."omanix/welcome.json".text = builtins.toJSON { inherit (cfg.welcome) autoOpen; };
  };
}
