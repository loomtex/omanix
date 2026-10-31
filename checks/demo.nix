# W21's checks: the demo's VM part (DESIGN §j, §i.2; demo/scenes.nix,
# tests/demo.nix). `nix flake check` is the gate.
{ pkgs, self, inputs }:

let
  vm = variant: import ../tests/demo.nix { inherit pkgs variant inputs; inherit (inputs) loom; omanix = self; };
  variants = [ "vm-demo-2" "vm-demo-3" "vm-demo-4" "vm-demo-5" "vm-demo-6" "vm-demo-7" "make-it-stick" "human-commit" ];
in
pkgs.lib.genAttrs variants vm
