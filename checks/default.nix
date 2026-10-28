# `nix flake check` is the gate (§i). Fork checks read only the pinned tree.
{ pkgs, self }:

let
  inherit (pkgs) lib omanixFork python3;
  f = omanixFork.forkDir;
  run = name: script: pkgs.runCommand "omanix-check-${name}" { nativeBuildInputs = [ python3 ]; } ''
    ${script}
    touch $out
  '';
in
{
  # Every bin script at the pin has exactly one class; privilege mappings exist.
  fork-classify = run "fork-classify" ''
    python3 -I ${f}/tools/forkcheck.py classify ${omanixFork.src} ${f}/classify.toml ${f}/patches counts.json
  '';

  # The upstream LICENSE ships unmodified and is never dropped.
  fork-license = run "fork-license" ''
    python3 -I ${f}/tools/forkcheck.py license ${omanixFork.src} ${pkgs.omarchy-src} ${f}/UPSTREAM.toml
    grep -q 'Copyright (c) David Heinemeier Hansson' ${../LICENSES/omarchy-MIT.txt}
    grep -q 'omarchy' ${f}/NOTICE
  '';

  # Stage 6 runs inside the build; this keeps it in the check list.
  omarchy-src = pkgs.omarchy-src;
}
// lib.mapAttrs' (n: v: lib.nameValuePair "pkg-${n}" v)
  (lib.filterAttrs (n: _: n != "default") self.packages.${pkgs.system})
