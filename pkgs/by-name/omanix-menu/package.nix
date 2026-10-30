# The intent menu (DESIGN §h.5.2): upstream's omarchy-menu.jsonc with
# fork/intents.toml applied, fork/menu-extra.jsonc and the host's
# omanix.menu.items added, and the omanix.menu.hidden rows hidden. Built in
# the sandbox by fork/tools/menu.py, which reads the pinned menu as data.
#
#   $out/omarchy-menu.jsonc   $OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc
#   $out/intents.json         $OMARCHY_PATH/default/omanix/intents.json
{
  lib,
  runCommand,
  python3,
  writeText,
  omanixFork,
  omarchy-src,
  items ? { }, # omanix.menu.items (nulls already dropped)
  agent ? "ada", # the resident's name, for "Ask ada…" and "Asks ada"
  hidden ? [ ], # omanix.menu.hidden: row ids shown with "when": "false" (the theme lock's)
}:

let
  f = omanixFork.forkDir;
  hostItems = writeText "omanix-menu-items.json" (builtins.toJSON items);
  hiddenIds = writeText "omanix-menu-hidden.json" (builtins.toJSON hidden);
in
runCommand "omanix-menu"
  {
    nativeBuildInputs = [ python3 ];
    meta.description = "The omanix intent menu";
  }
  ''
    python3 -I ${f}/tools/menu.py build \
      ${omarchy-src}/default/omarchy/omarchy-menu.jsonc ${f}/intents.toml ${f}/menu-extra.jsonc \
      ${hostItems} ${lib.escapeShellArg agent} $out ${hiddenIds}
  ''
