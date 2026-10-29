# `nix flake check` is the gate (§i). Fork checks read only the pinned tree.
{ pkgs, self, inputs ? { } }:

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

  # hl.* used by the shipped Lua/QML is a subset of hl-symbols.txt, and every
  # listed name is registered by the packaged Hyprland (or the titlebars plugin).
  hl-symbols = run "hl-symbols" ''
    python3 -I ${f}/tools/forkcheck.py hlsyms ${pkgs.omarchy-src} ${f}/hl-symbols.txt \
      ${pkgs.hyprland-omarchy.src} ${pkgs.omarchy-hyprland-titlebars.src}
  '';

  # Every shipped Lua file parses with the Lua Hyprland links (5.5).
  fork-lua = run "fork-lua" ''
    find ${pkgs.omarchy-src} -name '*.lua' -print0 | xargs -0 -n1 ${pkgs.lua5_5}/bin/luac -p --
  '';

  # The titlebars .so loads in a (VM) Hyprland built from the same derivation.
  titlebars-smoke = import ../tests/titlebars-smoke.nix { inherit pkgs; };

  # Stage 6 runs inside the build; this keeps it in the check list.
  omarchy-src = pkgs.omarchy-src;
} // import ./shell.nix { inherit pkgs self inputs; }
// import ./desktop.nix { inherit pkgs self inputs; }
// import ./hardware.nix { inherit pkgs self inputs; }
// lib.mapAttrs' (n: v: lib.nameValuePair "pkg-${n}" v)
  (lib.filterAttrs (n: _: n != "default") self.packages.${pkgs.system})
