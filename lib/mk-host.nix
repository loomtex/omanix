# omanix.lib.mkHost (§b.3): loom.lib.mkHost with the omanix base after
# loom's bundle, on omanix's nixpkgs and loom's home-manager (which follows
# it). Same arguments as loom's; the output is a plain nixosSystem.
{ loom, omanix, nixpkgs }:

args@{ self, specialArgs ? { }, ... }:
loom.lib.mkHost (args // {
  baseModules = [ omanix.nixosModules.default ] ++ (args.baseModules or [ ]);
  inherit nixpkgs;
  home-manager = loom.inputs.home-manager;
  specialArgs = { inherit omanix; } // specialArgs;
})
