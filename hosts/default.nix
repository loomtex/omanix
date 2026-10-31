# Reference hosts (§b.2): fixtures for the checks and the seeds of the
# release cache (./references.nix). vm-test keeps W15's eval stub (the demo
# and test VMs).
{ inputs, omanix }:

let
  loomTemplate = inputs.loom.outPath + "/templates/host";
in
import ./references.nix { inherit inputs omanix; } { } // {
  vm-test = omanix.lib.mkHost {
    self = loomTemplate;
    modules = [ (loomTemplate + "/configuration.nix") ./eval-stub.nix ./fixtures/vm-test.nix ];
  };
}
