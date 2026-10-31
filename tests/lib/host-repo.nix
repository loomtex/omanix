# What a VM needs to evaluate and build an omanix host flake offline
# (W19's VM tests; the same idea as loom W14's hostFlakeLock/installSupport,
# which supersede this once merged):
#   lock      a host flake.lock whose `omanix` input is this omanix source
#             (type path + narHash) with omanix's own lock nodes embedded,
#             so every input is already in the store
#   sources   every flake source that lock can need (register them in the VM)
#   support   a host's toplevel plus the inputs of the derivations that
#             differ per host commit (etc, system-path, toplevel, the HM
#             generation, catalogs), so they rebuild without a network
{ lib, omanix }:

rec {
  lock = { follows ? [ "nixpkgs" "home-manager" ], extraNodes ? { }, extraRoot ? { } }:
    let
      inner = builtins.fromJSON (builtins.readFile (omanix.outPath + "/flake.lock"));
      innerRoot = inner.nodes.${inner.root};
      rebase = inputs: lib.mapAttrs (_: v: if builtins.isList v then [ "omanix" ] ++ v else v) inputs;
      # A node whose source isn't the one omanix's flake.lock names (an
      # `--override-input`, say loom) is locked as a path to the source
      # omanix actually evaluated with, so the VM has it.
      actual =
        let
          walk = name: flake:
            let node = inner.nodes.${name}; in
            { ${name} = flake; } // lib.foldl' (acc: i:
              let v = node.inputs.${i}; in
              if builtins.isString v && flake ? inputs && flake.inputs ? ${i} then acc // walk v flake.inputs.${i} else acc)
              { } (lib.attrNames (node.inputs or { }));
        in removeAttrs (walk inner.root omanix) [ inner.root ];
      # Only those: a path lock is hashed again by every eval, slowly over
      # the VM's 9p store.
      relock = name: node: node // lib.optionalAttrs (actual ? ${name} && actual.${name} ? narHash
                                                     && actual.${name}.narHash != (node.locked.narHash or null)) {
        locked = { type = "path"; path = actual.${name}.outPath; inherit (actual.${name}) narHash; };
      };
      embedded = lib.mapAttrs (name: node: relock name node // lib.optionalAttrs (node ? inputs) { inputs = rebase node.inputs; })
        (removeAttrs inner.nodes [ inner.root ]);
    in
    {
      version = 7;
      root = "root";
      nodes = embedded // extraNodes // {
        omanix = {
          inputs = rebase (innerRoot.inputs or { });
          locked = { type = "path"; path = omanix.outPath; narHash = omanix.narHash; };
          original = { type = "git"; url = "https://silo.loom.farm/omanix.git"; ref = "refs/tags/v0.1.0"; };
        };
        root.inputs = { omanix = "omanix"; } // lib.genAttrs follows (i: [ "omanix" i ]) // extraRoot;
      };
    };

  sources = flake:
    let go = f: [ f.outPath ] ++ lib.concatMap go (lib.attrValues (f.inputs or { }));
    in lib.unique (go flake);

  support = host: pkgs:
    let
      c = host.config;
      hm = lib.attrValues (c.home-manager.users or { });
      drvs = [ c.system.build.toplevel c.system.build.etc c.system.path c.omanix.catalog.package ]
        ++ map (u: u.home.activationPackage) hm
        ++ map (u: u.home-files) hm
        ++ map (u: u.home.path) hm
        ++ [ (pkgs.writeShellApplication { name = "omanix-support"; text = "true"; })
             (pkgs.writeText "omanix-support" "")
             (pkgs.runCommand "omanix-support" { } "touch $out") ];
    in
    [ c.system.build.toplevel ] ++ map (d: d.inputDerivation) (lib.filter (d: d ? inputDerivation) drvs);
}
