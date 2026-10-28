"""omarchy-src build stages that need logic: drop, add, rewrite (§f.2.4).

Runs inside the nix build sandbox with `python3 -I`. It reads and copies
files from the pinned omarchy tree; it never executes any of them.

  assemble.py drop    <tree> <drop.txt>
  assemble.py add     <tree> <add-dir> <pinned-src>
  assemble.py rewrite <tree> <rewrite.toml>
"""
import fnmatch
import hashlib
import os
import re
import shutil
import sys
import tomllib


def die(msg):
    sys.exit(f"omarchy-src: {msg}")


def walk(tree):
    for root, dirs, files in os.walk(tree):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(root, f)
            yield os.path.relpath(p, tree)


def drop_patterns(path):
    pats = []
    for line in open(path):
        line = line.split("#", 1)[0].strip()
        if line:
            pats.append(line)
    return pats



def cmd_drop(tree, drop_txt):
    pats = drop_patterns(drop_txt)
    used = set()
    n = 0
    for rel in list(walk(tree)):
        if rel == "LICENSE":
            continue  # never dropped (checks.fork-license)
        for pat in pats:
            parts = rel.split("/")
            if any(fnmatch.fnmatchcase("/".join(parts[:i]), pat) for i in range(1, len(parts) + 1)):
                used.add(pat)
                os.remove(os.path.join(tree, rel))
                n += 1
                break
    unused = [p for p in pats if p not in used]
    if unused:
        die("drop.txt patterns match nothing at the pin: " + ", ".join(unused))
    # prune empty directories
    for root, dirs, files in os.walk(tree, topdown=False):
        if root != tree and not os.listdir(root):
            os.rmdir(root)
    print(f"drop: removed {n} files with {len(pats)} patterns")


REPLACES = re.compile(r"replaces upstream (\S+) sha256 ([0-9a-f]{64})")


def cmd_add(tree, add_dir, pinned):
    n = 0
    if not os.path.isdir(add_dir):
        print("add: nothing to add")
        return
    for rel in walk(add_dir):
        src = os.path.join(add_dir, rel)
        dst = os.path.join(tree, rel)
        upstream = os.path.join(pinned, rel)
        if os.path.lexists(upstream):
            head = open(src, errors="replace").read(4096)
            m = REPLACES.search(head)
            if not m or m.group(1) != rel:
                die(f"add/{rel} collides with upstream but has no 'replaces upstream {rel} sha256 …' header")
            sha = hashlib.sha256(open(upstream, "rb").read()).hexdigest()
            if sha != m.group(2):
                die(f"add/{rel}: replaces sha {m.group(2)} but the pinned file is {sha}")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.lexists(dst):
            os.remove(dst)
        shutil.copyfile(src, dst)
        os.chmod(dst, 0o755 if os.access(src, os.X_OK) else 0o644)
        n += 1
    print(f"add: {n} files")


def cmd_rewrite(tree, rewrite_toml):
    spec = tomllib.load(open(rewrite_toml, "rb"))
    bad = []
    for r in spec.get("rewrite", []):
        path = os.path.join(tree, r["file"])
        if not os.path.exists(path):
            bad.append(f"{r['file']}: missing")
            continue
        lines = open(path, encoding="utf-8", errors="surrogateescape").read().split("\n")
        # Never touch the shebang; patchShebangs owns it.
        start = 1 if lines and lines[0].startswith("#!") else 0
        body = "\n".join(lines[start:])
        if r.get("regex"):
            body, got = re.subn(r["from"], r["to"], body)
        else:
            got = body.count(r["from"])
            body = body.replace(r["from"], r["to"])
        if got != r["count"]:
            bad.append(f"{r['file']}: {r['from']!r} expected {r['count']} got {got}")
            continue
        out = "\n".join(lines[:start] + [body]) if start else body
        open(path, "w", encoding="utf-8", errors="surrogateescape").write(out)
    if bad:
        die("rewrite count mismatch:\n  " + "\n  ".join(bad))
    print(f"rewrite: {len(spec.get('rewrite', []))} rules")


if __name__ == "__main__":
    cmd, *args = sys.argv[1:]
    {"drop": cmd_drop, "add": cmd_add, "rewrite": cmd_rewrite}[cmd](*args)
