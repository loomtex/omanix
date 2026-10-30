# This machine: written by the installer; changed by `loom unlock` and `loom keys rotate`.
{
  loom.host = {
    id = "5c2757de0e0a4dca819bee2974c03c1c";
    name = "example";
  };
  loom.hardware.facts = builtins.fromJSON (builtins.readFile ./hardware.json);
  loom.disk = {
    device = "/dev/disk/by-id/nvme-Example_SSD_0000000000000000";
    btrfsUuid = "0f2c9a1e-5b7d-4c3a-9e8f-1a2b3c4d5e6f";
    unlock.methods = [ "recovery" "passphrase" ];
  };
  loom.boot.secureBoot.enable = false;
  loom.secrets.recipients = {
    host = "age19d2vspt8g0frrzgueqtmg9qx9mv73kzvvm3m67vgy0wwdcw6ag9quupmfj";
    recovery = "age1mdlg6348khh02r2qlrlrmkhl4dn4r8x9r75ewjs6at9uflzhvqpsp7vhm5";
  };
  loom.secrets.recovery.fingerprint = "5be1c0a4d3f2e1b0";
  system.stateVersion = "26.05";
}
