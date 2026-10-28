{
  description = "omanix: omarchy, re-expressed in nix";

  inputs = {
    # D1: the whole omanix stack is on nixos-unstable (Hyprland >= 0.56).
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # D2: the fork point. Untrusted data: read and built in the sandbox, never executed.
    omarchy = {
      url = "github:omacom/omarchy/5978d93ae7da0a325b7493501911e3f1266cadd3"; # v4.5.0-rc2
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, omarchy }:
    let
      inherit (nixpkgs) lib;
      # v1 targets x86_64-linux only (§f.2.3).
      systems = [ "x86_64-linux" ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
      byName = builtins.attrNames (builtins.readDir ./pkgs/by-name);
    in
    {
      # Every pkgs/by-name/<name>/package.nix, plus the fork data they share.
      overlays.default = final: prev: {
        omanixFork = import ./lib/fork.nix { inherit lib omarchy; };
      } // lib.genAttrs byName (name: final.callPackage ./pkgs/by-name/${name}/package.nix { });

      packages = forAllSystems (system:
        let pkgs = pkgsFor system; in
        lib.genAttrs byName (name: pkgs.${name}) // { default = pkgs.omarchy-src; });

      checks = forAllSystems (system:
        import ./checks { pkgs = pkgsFor system; inherit self; });

      apps = forAllSystems (system: import ./apps { pkgs = pkgsFor system; });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
