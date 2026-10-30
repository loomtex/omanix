{
  description = "omanix: omarchy, re-expressed in nix";

  inputs = {
    # D1: the whole omanix stack is on nixos-unstable (Hyprland >= 0.56).
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # loom: platform + agent base (§0.3). LOCAL DEV PIN: the v2-skeleton branch
    # in the sibling checkout (W0, W5, W6, W11). Replace with the silo/github
    # URL (a release tag) once loom v2 is published.
    loom = {
      url = "git+file:///agents/ada/projects/loom?ref=v2-skeleton";
      inputs.nixpkgs.follows = "nixpkgs";
      # U29: one nixpkgs (and one home-manager) node in a host's lock. loom's
      # 26.05 pair only serves loom's own CI (D1); here it follows unstable
      # rather than shipping a second nixpkgs in every install.
      inputs.nixpkgs-2605.follows = "nixpkgs";
      inputs.home-manager-2605.follows = "loom/home-manager";
      inputs.impermanence.inputs.nixpkgs.follows = "nixpkgs";
      inputs.impermanence.inputs.home-manager.follows = "loom/home-manager";
      inputs.nuketown.inputs.nixpkgs-unstable.follows = "nixpkgs";
    };

    # §b.1/§d.2: a host flake says `home-manager.follows = "omanix/home-manager"`,
    # so there is one home-manager (and one nixpkgs) for omanix, loom and plugins.
    home-manager.follows = "loom/home-manager";

    # Hardware quirks that build on nixos-hardware (surface, apple-t2, §f.2.6):
    # a host imports omanix.inputs.nixos-hardware.nixosModules.<x> next to the
    # quirk.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # D2: the fork point. Untrusted data: read and built in the sandbox, never executed.
    omarchy = {
      url = "github:omacom/omarchy/5978d93ae7da0a325b7493501911e3f1266cadd3"; # v4.5.0-rc2
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, loom, omarchy, ... }:
    let
      inherit (nixpkgs) lib;
      # v1 targets x86_64-linux only (§f.2.3).
      systems = [ "x86_64-linux" ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
        config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];
      };
      byName = builtins.attrNames (builtins.readDir ./pkgs/by-name);
      omanixLib = import ./lib { inherit inputs; omanix = self; };
    in
    {
      # loom.lib plus omanix's mkHost, lua, jsonc, menu and fork (§b.2).
      lib = omanixLib;

      # Every pkgs/by-name/<name>/package.nix, plus the fork data they share.
      overlays.default = final: prev: {
        omanixFork = import ./lib/fork.nix { inherit lib omarchy; };
      } // lib.genAttrs byName (name: final.callPackage ./pkgs/by-name/${name}/package.nix { });

      # The omanix base; omanix.lib.mkHost adds it after loom's bundle.
      nixosModules.default = import ./modules/omanix { omanix = self; };

      # `nix flake init -t omanix#host` (§d; the installer renders the same files).
      templates.host = {
        path = ./templates/host;
        description = "An omanix host: plain NixOS + home-manager modules on omanix.lib.mkHost";
      };

      # Reference hosts: fixtures for checks and cache seeds (§b.2).
      nixosConfigurations = import ./hosts { inherit inputs; omanix = self; };

      packages = forAllSystems (system:
        let pkgs = pkgsFor system; in
        lib.genAttrs byName (name: pkgs.${name}) // { default = pkgs.omarchy-src; });

      checks = forAllSystems (system:
        import ./checks { pkgs = pkgsFor system; inherit self inputs; });

      apps = forAllSystems (system: import ./apps { pkgs = pkgsFor system; });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
