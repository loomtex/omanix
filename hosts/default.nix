# Reference hosts (§b.2): fixtures for the checks and seeds for the binary
# cache. Each is loom's host template through omanix.lib.mkHost, plus what
# the work packages that own disks and boot (W4) will provide; see
# ./eval-stub.nix.
{ inputs, omanix }:

let
  template = inputs.loom.outPath + "/templates/host";

  ref = extra: omanix.lib.mkHost {
    self = template;
    modules = [ (template + "/configuration.nix") ./eval-stub.nix ] ++ extra;
  };
in
{
  ref-default = ref [ ];
  # Hardware flavors (W17): the quirks hostgen would enable on such machines.
  ref-nvidia = ref [ ./fixtures/nvidia.nix ];
  ref-laptop = ref [ ./fixtures/laptop.nix ];
  vm-test = ref [ ./fixtures/vm-test.nix ];
}
