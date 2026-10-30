"""demo-edit: the replay resident's text edits, standing in for a model's
edit tool in the scripted demo (demo/, checks.vm-demo-*). Plain text, no
evaluation: `omanix check` / `omanix set` do that where a scene wants it.

  demo-edit append FILE LINE...   insert LINEs before the module's closing brace
  demo-edit drop FILE TEXT        delete every line containing TEXT
  demo-edit replace FILE OLD NEW  replace OLD by NEW (exactly once)
  demo-edit write FILE LINE...    write FILE (creating directories)
"""

import os
import sys


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    verb, path, rest = argv[0], argv[1], argv[2:]
    if verb == "write":
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w") as f:
            f.write("".join(l + "\n" for l in rest))
        return 0
    with open(path) as f:
        lines = f.read().splitlines()
    if verb == "append":
        end = max(i for i, l in enumerate(lines) if l.strip() == "}")
        lines[end:end] = rest
    elif verb == "drop" and len(rest) == 1:
        kept = [l for l in lines if rest[0] not in l]
        if len(kept) == len(lines):
            print(f"demo-edit: no line of {path} contains {rest[0]!r}", file=sys.stderr)
            return 1
        lines = kept
    elif verb == "replace" and len(rest) == 2:
        text = "\n".join(lines)
        if text.count(rest[0]) != 1:
            print(f"demo-edit: {rest[0]!r} occurs {text.count(rest[0])} times in {path}", file=sys.stderr)
            return 1
        lines = text.replace(rest[0], rest[1]).split("\n")
    else:
        print(__doc__, file=sys.stderr)
        return 2
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
