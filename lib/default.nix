# omanix.lib = loom.lib // { mkHost; lua; jsonc; menu; fork; } (§b.2).
{ inputs, omanix }:

let
  inherit (inputs) nixpkgs loom;
  inherit (nixpkgs) lib;
in
loom.lib // {
  # omanix.lib.mkHost: loom's mkHost with the omanix base and omanix's
  # nixpkgs + home-manager (D1: nixos-unstable).
  mkHost = import ./mk-host.nix { inherit loom omanix nixpkgs; };

  lua = import ./lua.nix { inherit lib; };
  jsonc = import ./jsonc.nix { inherit lib; };
  menu = import ./menu.nix { inherit lib; };
  home = import ./home { inherit lib; };
  fork = import ./fork.nix { inherit lib; inherit (inputs) omarchy; };

  # loom's force-allowlist plus omanix's own entries (checks.priorities).
  forceAllowlist = loom.lib.forceAllowlist ++ import ./force-allowlist.nix;
}
