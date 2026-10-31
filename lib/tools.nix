# The user-facing tools behind scripts/*.sh and apps (§b.2, §e.2, §e.4,
# §e.10): configure, flash-usb (loom-flash pinned to release/allowed_signers)
# and verify-release.
{ pkgs, omanix }:

let
  inherit (omanix.inputs) loom;
  inherit (omanix.lib.installer) version;
  ref = omanix.nixosConfigurations.ref-default;
  loomPkg = p: args: pkgs.callPackage "${loom}/pkgs/${p}" args;
  hostLock = pkgs.writeText "flake.lock" (builtins.toJSON (loom.lib.hostFlakeLock {
    flake = omanix;
    name = "omanix";
    original = { type = "git"; url = "https://silo.loom.farm/omanix.git"; ref = "refs/tags/v${version}"; };
  }));
in
rec {
  loom-mint = loomPkg "loom-mint" { };
  loom-enroll = loomPkg "loom-enroll" { };
  loom-flash = loomPkg "loom-flash" { releaseSigners = ../release/allowed_signers; };
  omanix-configure = pkgs.callPackage ../pkgs/configure {
    inherit loom-mint loom-enroll;
    settings = {
      flavor = "omanix";
      template = "${../templates/host}";
      catalog = builtins.toFile "omanix-hostgen.json" (builtins.toJSON ref.config.omanix.catalog.hostgen);
      hostLock = "${hostLock}";
      checkModule = "${../pkgs/configure/check-module.nix}";
      silo = "ssh://git@silo.loom.farm";
      inherit version;
    };
  };
  inherit (pkgs) omanix-release;
}
