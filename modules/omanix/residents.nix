# The residents on the omanix desktop (§a.3 C5, §h):
# - the approval broker restarts inside the graphical session, so it sees
#   WAYLAND_DISPLAY (loom.agent.restartBrokerWithSession);
# - the human's approval prompter is omanix's card (approval.nix, W18);
# - the resident may read the typed runtime summary (group omanix-resident,
#   runtime.nix).
{ config, lib, ... }:

let
  cfg = config.omanix;
  agent = config.loom.agent;
in
{
  config = lib.mkIf (cfg.enable && agent.enable) {
    loom.agent.restartBrokerWithSession = lib.mkDefault true;
    users.groups.omanix-resident.members = [ agent.name ];
  };
}
