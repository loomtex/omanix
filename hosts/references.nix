# The reference hosts over a template (§b.2, §e.1): loom.lib.referenceHost
# with omanix's mkHost, the closure-budget guards, and the hardware an
# installer's probes would find. hosts/default.nix uses ./reference (the
# omanix host template plus placeholder sops files, so their closures carry
# the sops machinery a real install has); the installer's test variant uses
# tests/fixtures/host-vm-omanix (lib/installer.nix).
{ inputs, omanix }:

{ template ? ./reference, modules ? [ ] }:

let
  reference = extra: inputs.loom.lib.referenceHost {
    flake = omanix;
    inherit template;
    mkHost = omanix.lib.mkHost;
    modules = [ ./budget.nix ] ++ extra ++ modules;
  };
in
{
  ref-default = reference [ ];
  # Hardware flavors (W17): the quirks hostgen would enable on such machines.
  ref-nvidia = reference [ ./fixtures/nvidia.nix ];
  ref-laptop = reference [ ./fixtures/laptop.nix ];
}
