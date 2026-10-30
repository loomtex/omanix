# Host-level state to keep across reboots (`omanix persist add <path>` writes here):
#   loom.persist.system.directories = [ "/var/lib/<svc>" ];
# The persist audit fails `omanix check` when an enabled service's state isn't covered.
{ ... }:

{ }
