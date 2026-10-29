"""checks.jsonc-equivalence: parse a .jsonc file independently of lib/jsonc.nix
(a character scanner: strings, // and /* */ comments, trailing commas) and
compare with the JSON the nix parser produced.

usage: jsonc.py FILE.jsonc NIX_RESULT.json
"""

import json
import sys


def strip(text: str) -> str:
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def drop_trailing_commas(text: str) -> str:
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
            continue
        if c == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] in "}]":
                i += 1
                continue
        out.append(c)
        i += 1
    return "".join(out)


def main(argv):
    with open(argv[0]) as f:
        ours = json.loads(drop_trailing_commas(strip(f.read())))
    with open(argv[1]) as f:
        theirs = json.load(f)
    if ours != theirs:
        print(f"{argv[0]}: lib/jsonc.nix disagrees with the reference parser", file=sys.stderr)
        return 1
    print(f"{argv[0]}: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
