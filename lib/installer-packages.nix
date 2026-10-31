# packages.<sys>.{installer-offline,installer-net,installer-test,base-cache,stick-index}
# (§b.2, §e.1). CI and checks build these unsigned; a release builds the
# images from a signed tag with the signed cache (omanix-release build, D11).
#
#   installer-offline  the release image's shape, CACHE unsigned: it doesn't
#                      install offline (require-sigs) until a release signs it
#   installer-net      no CACHE: substitutes from the network
#   installer-test     ttyS0, silo.test, red banner; CACHE signed with a
#                      throwaway key made in a derivation
#   base-cache         the unsigned CACHE contents the release signs
#   stick-index        every store path an offline stick supplies (live store
#                      + CACHE): `configure check` reports cacheMiss against it
{ pkgs, omanix }:

let
  inherit (omanix.lib) installer;
  offline = installer.system { };
  testKey = pkgs.runCommand "omanix-test-cache-key" { nativeBuildInputs = [ pkgs.nix ]; } ''
    mkdir $out
    export NIX_STATE_DIR=$TMPDIR/state NIX_CONF_DIR=$TMPDIR HOME=$TMPDIR
    nix --extra-experimental-features nix-command key generate-secret --key-name omanix-test-cache-1 > $out/secret
    echo "extra-trusted-public-keys = $(nix --extra-experimental-features nix-command key convert-secret-to-public < $out/secret)" > $out/trust.conf
  '';
in
{
  installer-offline = offline.config.system.build.image;
  installer-net = installer.image { variant = "net"; };
  installer-test = installer.image {
    test = true;
    cacheSigningKey = "${testKey}/secret";
    # the public key is only known after the build: included, not read (no IFD)
    modules = [{ nix.extraOptions = "!include ${testKey}/trust.conf"; }];
  };
  base-cache = offline.config.system.build.omanixStickCache;
  stick-index = offline.config.system.build.omanixStickIndex;
}
