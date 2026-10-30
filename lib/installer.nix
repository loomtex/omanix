# The omanix USB installer (§e.1) on loom.lib.mkInstallerSystem (W14):
# flavor omanix, the omanix host template, this flake pinned in new hosts'
# flake.lock (`original` = the release tag), the reference hosts as the
# offline cache, and omanix's hardware probes and hostgen catalog.
#
#   omanix.lib.installer.system { variant; test; image; cacheDir; cachePublicKey; … }
#   omanix.lib.installer.image  { … }          # system.build.image
#
# The CACHE partition is built here, not by loom's mkBinaryCache: it holds
# what an offline install needs (the reference closures and the build inputs
# of what differs per host, `support`) MINUS what the live store already
# has, because nixos-install copies from the live store and substitutes only
# the rest. A release signs that cache with omanix-cache-1 (D11, the release
# skill, outside nix) and passes the signed copy as `cacheDir`; test images
# sign it with a throwaway key made in a derivation.
{ inputs, omanix }:

let
  inherit (inputs) loom nixpkgs;
  inherit (nixpkgs) lib;
  version = lib.removeSuffix "\n" (builtins.readFile ../VERSION);

  references = import ../hosts/references.nix { inherit inputs omanix; };
  refsFor = test: lib.attrValues (references (lib.optionalAttrs test { template = ../tests/fixtures/host-vm-omanix; }));

  # What a per-host rebuild needs besides loom's installSupport: the omanix
  # derivations that change with the host's answers (hostname, user, theme,
  # quirks): the catalog and the human's home-manager files and profile.
  omanixSupport = ref:
    let
      c = ref.config;
      hm = lib.attrValues (c.home-manager.users or { });
      drvs = [ c.omanix.catalog.package ] ++ map (u: u.home-files) hm ++ map (u: u.home.path) hm;
    in
    map (d: d.inputDerivation) (lib.filter (d: d ? inputDerivation) drvs);

  support = refs: pkgs: lib.unique (lib.concatMap (r: loom.lib.installSupport r pkgs ++ omanixSupport r) refs);

  # A file:// binary cache of closure(roots) minus closure(exclude), with
  # nixpkgs' make-binary-cache layout (nar/<filehash>.nar.zst + narinfo).
  stickCache = { pkgs, roots, exclude, level ? 19 }: pkgs.stdenv.mkDerivation {
    name = "omanix-stick-cache";
    __structuredAttrs = true;
    exportReferencesGraph = { closure = roots; live = exclude; };
    preferLocalBuild = true;
    nativeBuildInputs = [ pkgs.python3 pkgs.nix pkgs.zstd ];
    buildCommand = ''
      python3 -I ${../pkgs/by-name/omanix-release/stick_cache.py} --level ${toString level}
      mkdir -p $out/realisations $out/debuginfo $out/log
    '';
  };

  args =
    { variant ? "offline"          # "offline" | "net"
    , test ? false                 # ttyS0, silo.test, red banner; tests/fixtures/host-vm-omanix
    , image ? true                 # false: the live system only (VM tests boot it directly)
    , cacheDir ? null              # a signed cache (release); null: built here
    , cachePublicKey ? null
    , cacheSigningKey ? null       # test images only: a nix secret key file (it lands in the store)
    , siloKnownHosts ? null
    , modules ? [ ]
    , system ? "x86_64-linux"
    }:
    let refs = refsFor test; ref = lib.head refs; in
    {
      inherit system variant test image siloKnownHosts;
      flavor = "omanix";
      productName = "omanix";
      flake = omanix;
      inputName = "omanix";
      original = { type = "git"; url = "https://silo.loom.farm/omanix.git"; ref = "refs/tags/v${version}"; };
      template = if test then ../tests/fixtures/host-vm-omanix else ../templates/host;
      references = refs;
      modules = [
        ({ config, pkgs, ... }:
          let
            offline = variant == "offline";
            extra = lib.concatMap omanixSupport refs;
            unsigned = stickCache {
              inherit pkgs;
              roots = support refs pkgs;
              exclude = [ config.system.build.toplevel ];
            };
            built = if cacheSigningKey == null then unsigned else
              pkgs.runCommand "omanix-stick-cache-signed" { nativeBuildInputs = [ pkgs.nix ]; } ''
                cp -r ${unsigned} $out && chmod -R u+w $out
                export NIX_STATE_DIR=$TMPDIR/state NIX_CONF_DIR=$TMPDIR HOME=$TMPDIR
                nix --extra-experimental-features nix-command store sign --store "file://$out" \
                  --key-file ${cacheSigningKey} --all
              '';
          in
          {
            _file = ./installer.nix;
            # omanix's probes (modules/omanix/hardware/probes.nix) and the
            # theme/defaults/apps enums, from the reference host's evaluation
            loom.installer.probes = ref.config.loom.installer.probes;
            loom.installer.catalog = builtins.toFile "omanix-hostgen.json" (builtins.toJSON ref.config.omanix.catalog.hostgen);
            # loom adds installSupport; omanix adds what its own per-host
            # derivations need (the live store in VM tests, CACHE in images)
            loom.installer.storePaths = lib.mkIf (offline && !image) extra;
            loom.installer.image = lib.mkIf (offline && image) {
              cache = extra;
              cacheDir = if cacheDir != null then cacheDir else built;
              inherit cachePublicKey;
            };
            # the release skill signs stickCache; configure check reads stickIndex
            # (every store path the stick can supply: live store + CACHE)
            system.build.omanixStickCache = unsigned;
            system.build.omanixStickIndex = pkgs.closureInfo {
              rootPaths = [ config.system.build.toplevel ] ++ lib.optionals offline (support refs pkgs);
            };
          })
      ] ++ modules;
    };
in
rec {
  inherit version support omanixSupport stickCache;
  references = refsFor;
  system = a: loom.lib.mkInstallerSystem (args a);
  image = a: (system (a // { image = true; })).config.system.build.image;
  # loom.lib.installerModules with the omanix arguments (VM tests import these)
  modules = a: loom.lib.installerModules (args a);
}
