# install/hardware/bluetooth.sh: BlueZ on (its own condition skips machines
# without an adapter); AutoEnable stays at its default, as upstream decided.
{ config, lib, ... }:

{
  options.omanix.hardware.bluetooth.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Bluetooth (BlueZ; the shell's Bluetooth panel and bt-agent).";
  };

  config = lib.mkIf (config.omanix.enable && config.omanix.hardware.bluetooth.enable) {
    hardware.bluetooth.enable = lib.mkDefault true;
    loom.persist.system.directories = [ { directory = "/var/lib/bluetooth"; mode = "0700"; } ];   # pairings
  };
}
