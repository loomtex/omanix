# Fixture-only: what W4 (loom.disk, loom.boot) provides on a real host, so a
# reference host's toplevel evaluates and builds. The same stand-in as
# loom's tests/lib/eval-stub.nix. Delete when W4 lands.
{ lib, ... }:

{
  fileSystems."/" = lib.mkDefault { device = "none"; fsType = "tmpfs"; };
  boot.loader.grub.enable = lib.mkDefault false;
  users.allowNoPasswordLogin = true;
}
