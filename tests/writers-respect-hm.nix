# writers-respect-hm (§i.2): the KEEP-AS-GUI writers that remain write
# runtime state and overlays, never the read-only HM files.
#
# Each case is tests/writers-respect-hm/<NN-name>.py (a block of test script,
# run in file-name order) with an optional <NN-name>.nix (a NixOS module the
# node imports, for what the case needs installed). Around them, this file
# records every HM target's link before and asserts after that none changed
# and that configerrors stays empty. W16: glass, chromium flags; W17: apps,
# defaults (U35), font set, text size and the kv settle, keyboard layout
# (U28). The .nix modules are merged into the one node, so a case's
# declarations must not contradict another case's.
{ pkgs, loom, omanix }:

let
  inherit (pkgs) lib;
  d = import ./lib/desktop.nix { inherit pkgs loom omanix; };
  dir = ./writers-respect-hm;
  files = builtins.attrNames (builtins.readDir dir);
  cases = lib.sort (a: b: a < b) (lib.filter (lib.hasSuffix ".py") files);
  modules = map (f: dir + "/${f}") (lib.filter (lib.hasSuffix ".nix") files);
in
pkgs.testers.runNixOSTest {
  name = "omanix-writers-respect-hm";
  node.pkgsReadOnly = false;
  node.specialArgs = { inputs = { }; inherit loom omanix; };

  nodes.machine = { ... }: {
    imports = [ (d.node { }) ] ++ modules;
  };

  testScript = ''
    ${d.helpers}
    OVERLAY = f"{HOME}/.local/state/omanix/overlay"
    STATE = f"{HOME}/.local/state/omarchy/current"

    def s(cmd):
        return machine.succeed(as_user(cmd))

    wait_desktop()
    machine.sleep(5)
    links = assert_hm_links(hm_links())

    ${lib.concatMapStrings (f: ''
      # ---- ${f}
      ${builtins.readFile (dir + "/${f}")}
    '') cases}

    with subtest("every HM target is still the same read-only link; the Lua config loads"):
        assert_hm_unchanged(links)
        for t in links:
            if t != ".config/btop/themes/current.theme":   # an out-of-store link into theme state, by design
                machine.fail(as_user(f"echo >> {HOME}/{t}"))
        configerrors_empty()
  '';
}
