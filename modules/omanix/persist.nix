# Desktop state that survives the tmpfs root (§f.1): what the greeter and
# the desktop services keep under /var/lib. The human's home is a persistent
# subvolume (loom.home), so nothing under ~ is listed here.
{ config, lib, ... }:

let
  cfg = config.omanix;
in
{
  config = lib.mkIf cfg.enable {
    loom.persist.system.directories = lib.optional config.services.displayManager.sddm.enable
      { directory = "/var/lib/sddm"; user = "sddm"; group = "sddm"; mode = "0750"; };
  };
}
