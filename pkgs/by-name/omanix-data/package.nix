# $OMARCHY_PATH (§f.2.9): omarchy-src, symlinked file by file, plus the files
# omanix generates from the host's options. The modules override the
# arguments (modules/omanix/path.nix); the default build is the reference
# configuration.
#
# Generated:
#   default/hypr/omanix-overlay.lua      the overlay loader (§f.4.3)
#   config/omarchy/shell.json            upstream defaults ⊕ omanix.shell.settings (lists atomic)
#   default/omarchy/omarchy-menu.jsonc   upstream menu + omanix.menu.items
#   default/omanix/language              omanix.language (OMARCHY_LANGUAGE_FILE)
#   default/omanix/release               omanix.release
{
  lib,
  runCommand,
  python3,
  omarchy-src,
  writeText,
  shellSettings ? { },
  language ? "en",
  release ? "0.1.0-dev",
  menuText ? null, # the merged menu (lib.menu.appendItems), or null for upstream's
}:

let
  overlayLoader = writeText "omanix-overlay.lua" ''
    -- omanix: generated. Loads the runtime overlay for one HM-owned Hyprland
    -- file (DESIGN §f.4.3). dofile, not require: it re-runs on every reload,
    -- and an error shows in Hyprland's error bar like upstream user files.
    local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
    return function(name)
      local f = state_home .. "/omanix/overlay/hypr/" .. name .. ".lua"
      local h = io.open(f, "r")
      if not h then return end
      h:close()
      dofile(f)
    end
  '';
  settingsJson = writeText "omanix-shell-settings.json" (builtins.toJSON shellSettings);
  menu = if menuText == null then null else writeText "omarchy-menu.jsonc" menuText;
in
runCommand "omanix-data-${release}"
  {
    nativeBuildInputs = [ python3 ];
    passthru = { inherit omarchy-src; };
    meta.description = "OMARCHY_PATH for omanix: the fork plus generated files";
  }
  ''
    mkdir $out
    cp -rs --no-preserve=mode ${omarchy-src}/. $out/
    chmod -R u+w $out

    install -Dm644 ${overlayLoader} $out/default/hypr/omanix-overlay.lua

    rm $out/config/omarchy/shell.json
    python3 -I - ${omarchy-src}/config/omarchy/shell.json ${settingsJson} $out/config/omarchy/shell.json <<'EOF'
    import json, sys
    base, extra, out = sys.argv[1:4]
    def merge(a, b):
        # Objects merge recursively; arrays and scalars from b replace a (§f.4.7).
        if isinstance(a, dict) and isinstance(b, dict):
            r = dict(a)
            for k, v in b.items():
                r[k] = merge(a[k], v) if k in a else v
            return r
        return b
    with open(base) as f: d = json.load(f)
    with open(extra) as f: e = json.load(f)
    with open(out, "w") as f:
        json.dump(merge(d, e), f, indent=2, ensure_ascii=False)
        f.write("\n")
    EOF

    ${lib.optionalString (menu != null) ''
      rm $out/default/omarchy/omarchy-menu.jsonc
      install -m644 ${menu} $out/default/omarchy/omarchy-menu.jsonc
    ''}

    mkdir -p $out/default/omanix
    printf '%s\n' ${lib.escapeShellArg language} > $out/default/omanix/language
    printf '%s\n' ${lib.escapeShellArg release} > $out/default/omanix/release
  ''
