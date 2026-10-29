# JSONC (JSON with // and /* */ comments and trailing commas) → Nix values,
# for upstream's .jsonc files (menu extensions, shell defaults). One regex
# split that keeps string literals and drops comments, then
# builtins.fromJSON. checks.jsonc-equivalence compares it against python's
# parser on every shipped .jsonc file.
{ lib }:

let
  inherit (lib) concatStrings;

  # Strings first, so "//" or "/*" inside a string is never a comment.
  token = ''("([^"\\]|\\.)*")|(//[^
]*)|(/\*([^*]|\*+[^*/])*\*+/)'';

  strip = text:
    concatStrings (map
      (x:
        if builtins.isString x then x
        else let str = builtins.elemAt x 0; in if str == null then "" else str)
      (builtins.split token text));

  # ", }" / ", ]" outside strings. Applied per non-string segment.
  dropTrailingCommas = text:
    concatStrings (map
      (x:
        if builtins.isString x then
          concatStrings (map (y: if builtins.isList y then builtins.elemAt y 0 + builtins.elemAt y 1 else y)
            (builtins.split ",([[:space:]]*)([]}])" x))
        else builtins.elemAt x 0)
      (builtins.split ''("([^"\\]|\\.)*")'' text));

  fromJSONC = text: builtins.fromJSON (dropTrailingCommas (strip text));
in
{
  inherit strip fromJSONC;
  readJSONC = path: fromJSONC (builtins.readFile path);
}
