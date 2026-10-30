# Test host only (W19's VM tests): the template carries no secrets/user.yaml,
# so the human has no password yet; and the revision is pinned so the VM's
# evaluation of each commit matches the one the test prebuilt (offline).
{ lib, ... }:

{
  users.allowNoPasswordLogin = true;
  system.configurationRevision = lib.mkForce null;
}
