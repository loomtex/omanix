# `configure check` (§e.2 step 4): the installer-written rows of a mint
# commit, filled with the reference host's placeholders (hosts/reference
# machine.nix, loom.lib.referenceHost), so the minted host evaluates to the
# shape of an install. Only for computing cacheMiss; never committed.
{ lib, ... }:

{
  loom.disk = {
    device = lib.mkDefault "/dev/disk/by-id/nvme-Example_SSD_0000000000000000";
    unlock.methods = lib.mkDefault [ "recovery" "passphrase" ];
    btrfsUuid = lib.mkDefault "00000000-0000-4000-8000-000000000000";
  };
  loom.boot.secureBoot.enable = lib.mkDefault false;
  loom.secrets.recipients = {
    host = lib.mkDefault "age19d2vspt8g0frrzgueqtmg9qx9mv73kzvvm3m67vgy0wwdcw6ag9quupmfj";
    recovery = lib.mkDefault "age1mdlg6348khh02r2qlrlrmkhl4dn4r8x9r75ewjs6at9uflzhvqpsp7vhm5";
  };
  loom.secrets.recovery.fingerprint = lib.mkDefault "5be1c0a4d3f2e1b0";
  system.stateVersion = lib.mkDefault "26.05";
  users.allowNoPasswordLogin = true;
}
