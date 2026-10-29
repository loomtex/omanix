# The default menu is upstream's omarchy-menu.jsonc, whose key order is the
# menu order; a Nix attrset would sort it. Host items (omanix.menu.items) are
# therefore spliced in as text before the final closing brace, as JSON
# entries. W18's intent menu (lib/menu.nix build of intents.toml) extends this.
{ lib }:

let
  entry = id: item:
    "  ${builtins.toJSON id}: ${builtins.toJSON (lib.filterAttrs (n: v: v != null && n != "after") item)},";
in
{
  # text: the menu .jsonc; items: { <id> = { label; icon; action | target; when; … }; }
  appendItems = text: items:
    if items == { } then text
    else
      let
        # Split on "}" rather than one regex over the whole file (std::regex
        # recursion on a 70 KB match).
        parts = lib.splitString "}" text;
        tail = lib.last parts;
      in
      if builtins.length parts < 2 || builtins.match "[[:space:]]*" tail == null
      then throw "omanix.lib.menu.appendItems: the menu does not end with a closing brace"
      else lib.concatStringsSep "}" (lib.init parts)
        + "\n  // omanix.menu.items (host configuration)\n"
        + lib.concatStringsSep "\n" (lib.mapAttrsToList entry items)
        + "\n}\n";
}
