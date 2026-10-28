# The fork's data, for packages and checks: the pinned upstream tree plus the
# files under fork/. Nothing here evaluates or executes upstream code.
{ lib, omarchy }:

let
  forkDir = lib.fileset.toSource {
    root = ../fork;
    fileset = ../fork;
  };
  upstream = builtins.fromTOML (builtins.readFile ../fork/UPSTREAM.toml);
in
{
  inherit forkDir upstream;
  src = omarchy;
  version = lib.removePrefix "v" upstream.tag;
  classify = builtins.fromTOML (builtins.readFile ../fork/classify.toml);
}
