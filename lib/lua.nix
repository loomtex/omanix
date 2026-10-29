# Nix values → Lua source, for the HM-owned Hyprland files (§f.4.2).
# Strings are always quoted (never spliced as code); `raw` marks an
# intentional Lua expression, which only omanix's own modules use.
{ lib }:

let
  inherit (lib) concatStringsSep mapAttrsToList isAttrs isList isString isBool isInt isFloat;

  luaKeywords = [ "and" "break" "do" "else" "elseif" "end" "false" "for" "function" "goto" "if" "in"
    "local" "nil" "not" "or" "repeat" "return" "then" "true" "until" "while" ];

  isIdent = s: builtins.match "[A-Za-z_][A-Za-z0-9_]*" s != null && !(builtins.elem s luaKeywords);

  # A Lua long-bracket-free string literal: escape \ " and control characters.
  quote = s: "\"" + lib.replaceStrings [ "\\" "\"" "\n" "\r" "\t" ] [ "\\\\" "\\\"" "\\n" "\\r" "\\t" ] s + "\"";

  key = k: if isIdent k then k else "[${quote k}]";

  toLua = v:
    if v == null then "nil"
    else if isBool v then (if v then "true" else "false")
    else if isInt v || isFloat v then toString v
    else if isString v then quote v
    else if isAttrs v && v ? _lua then v._lua
    else if isList v then "{ " + concatStringsSep ", " (map toLua v) + " }"
    else if isAttrs v then
      "{ " + concatStringsSep ", " (mapAttrsToList (k: x: "${key k} = ${toLua x}") v) + " }"
    else throw "omanix.lib.lua.toLua: unsupported value of type ${builtins.typeOf v}";
in
{
  inherit toLua quote isIdent;

  # An intentional Lua expression, emitted verbatim by toLua.
  raw = code: { _lua = code; };

  # `fn(arg)` with arg serialised.
  call = fn: arg: "${fn}(${toLua arg})";
}
