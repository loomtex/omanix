# $OMARCHY_PATH (§f.2.9): omarchy-src, symlinked file by file, plus the files
# omanix generates from the host's options. The modules override the
# arguments (modules/omanix/path.nix); the default build is the reference
# configuration.
#
# Generated:
#   default/hypr/omanix-overlay.lua      the overlay loader (§f.4.3)
#   config/omarchy/shell.json            upstream defaults ⊕ omanix.shell.settings (lists atomic)
#   default/omarchy/omarchy-menu.jsonc   the intent menu (omanix-menu, W18: with omanix.menu.items,
#                                        and the omanix.menu.hidden rows hidden), or upstream menu + menuText
#   default/omanix/intents.json          intent rows by id (omanix-menu)
#   default/omanix/language              omanix.language (OMARCHY_LANGUAGE_FILE)
#   default/omanix/release               omanix.release
#   themes/                              the theme registry (W16, omanix-themes)
#   bin/omarchy-theme-set                with omanix.theme.lock: a guard that
#                                        only sets the declared theme (W16)
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
  menu ? null, # an omanix-menu output (omarchy-menu.jsonc + intents.json); wins over menuText
  omanixThemes ? null, # the theme registry (W16); null keeps omarchy-src's themes/
  omanixThemeLock ? null, # omanix.theme.lock: the only theme omarchy-theme-set may set
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
  menuFile = if menuText == null || menu != null then null else writeText "omarchy-menu.jsonc" menuText;

  # omanix.theme.lock (§f.5): the picker and the menu still call
  # omarchy-theme-set; only the declared theme gets through.
  themeGuard = writeText "omarchy-theme-set" ''
    #!/bin/sh
    # omanix: generated (omanix.theme.lock). The theme is fixed by the host
    # configuration (omanix.theme.default); this refuses any other.
    want=$(printf '%s' "''${1-}" | sed -E 's/<[^>]+>//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    if [ "$want" != ${lib.escapeShellArg omanixThemeLock} ]; then
      msg="The theme is locked to ${omanixThemeLock} by this computer's configuration. Ask ''${OMANIX_AGENT_NAME:-your agent} to change omanix.theme."
      echo "omarchy-theme-set: $msg" >&2
      command -v notify-send >/dev/null && notify-send -u normal "Theme locked" "$msg" >/dev/null 2>&1
      exit 1
    fi
    exec ${omarchy-src}/bin/omarchy-theme-set "$@"
  '';
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

    # The shell is copied, not linked: its plugin registry scans for manifests
    # with `find -type f`, which skips symlinks (no plugin, the menu included,
    # would load), and QML resolves imports next to the file it really is.
    # Modes are kept (helpers like plugins/clipboard/capture.sh are run
    # directly and need their exec bit), then made writable for the edits.
    rm -rf $out/shell
    cp -r ${omarchy-src}/shell $out/shell
    chmod -R u+w $out/shell

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

    ${lib.optionalString (menuFile != null) ''
      rm $out/default/omarchy/omarchy-menu.jsonc
      install -m644 ${menuFile} $out/default/omarchy/omarchy-menu.jsonc
    ''}
    ${lib.optionalString (menu != null) ''
      rm $out/default/omarchy/omarchy-menu.jsonc
      install -m644 ${menu}/omarchy-menu.jsonc $out/default/omarchy/omarchy-menu.jsonc
      install -Dm644 ${menu}/intents.json $out/default/omanix/intents.json
    ''}

    ${lib.optionalString (omanixThemes != null) ''
      rm -rf $out/themes
      mkdir $out/themes
      cp -rs --no-preserve=mode ${omanixThemes}/. $out/themes/
    ''}

    ${lib.optionalString (omanixThemeLock != null) ''
      rm $out/bin/omarchy-theme-set
      install -m755 ${themeGuard} $out/bin/omarchy-theme-set
      patchShebangs $out/bin/omarchy-theme-set
    ''}

    mkdir -p $out/default/omanix
    printf '%s\n' ${lib.escapeShellArg language} > $out/default/omanix/language
    printf '%s\n' ${lib.escapeShellArg release} > $out/default/omanix/release
  ''
