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
  omanixThemes ? null, # the theme registry (W16); null keeps omarchy-src's themes/
  omanixThemeLock ? null, # omanix.theme.lock: the only theme omarchy-theme-set may set
  omanixHiddenMenuItems ? [ ], # menu ids hidden with "when": "false" (W16: theme lock)
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

    ${lib.optionalString (omanixHiddenMenuItems != [ ]) ''
      m=$out/default/omarchy/omarchy-menu.jsonc
      python3 -I - "$(readlink -f $m)" $m.new ${lib.escapeShellArgs omanixHiddenMenuItems} <<'EOF'
      import json, re, sys
      src, out, *hide = sys.argv[1:]
      row = re.compile(r'^(\s*)("(?:[^"\\]|\\.)*")(\s*:\s*)(\{.*\})(,?)\s*$')
      lines, seen = [], set()
      for line in open(src, encoding="utf-8").read().split("\n"):
          m = row.match(line)
          if m and json.loads(m.group(2)) in hide:
              obj = json.loads(m.group(4))
              obj["when"] = "false"
              line = m.group(1) + m.group(2) + m.group(3) + json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + m.group(5)
              seen.add(json.loads(m.group(2)))
          lines.append(line)
      missing = sorted(set(hide) - seen)
      if missing:
          sys.exit("omanix-data: menu rows to hide not found: " + ", ".join(missing))
      open(out, "w", encoding="utf-8").write("\n".join(lines))
      EOF
      rm $m && mv $m.new $m
    ''}

    mkdir -p $out/default/omanix
    printf '%s\n' ${lib.escapeShellArg language} > $out/default/omanix/language
    printf '%s\n' ${lib.escapeShellArg release} > $out/default/omanix/release
  ''
