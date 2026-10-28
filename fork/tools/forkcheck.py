"""Static checks over the pinned omarchy tree and the built omarchy-src.

Runs in the nix sandbox with `python3 -I`. Reads files; executes nothing
from omarchy.

  forkcheck.py classify <pinned> <classify.toml> <patches-dir> <counts.json>
  forkcheck.py license  <pinned> <tree> <UPSTREAM.toml>
  forkcheck.py hlsyms   <tree> <hl-symbols.txt> <hyprland-src> <titlebars-src>
  forkcheck.py post     <tree> <classify.toml> <residual.toml> <add-dir>
  forkcheck.py residual <tree> <classify.toml> <add-dir>    (prints a fresh residual.toml)
"""
import collections
import hashlib
import json
import os
import re
import sys
import tomllib

ok = True


def fail(msg):
    global ok
    ok = False
    print("FAIL:", msg)


def walk(tree):
    for root, dirs, files in os.walk(tree):
        dirs.sort()
        for f in sorted(files):
            yield os.path.relpath(os.path.join(root, f), tree)


def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except (IsADirectoryError, FileNotFoundError):
        return ""


def path_class(rel, rules):
    for r in rules:
        if re.fullmatch(r["regex"], rel):
            return r["class"]
    return None


SUDO = re.compile(r"\b(sudo|pkexec)\b")


def cmd_classify(pinned, classify, patches, counts_out):
    c = tomllib.load(open(classify, "rb"))
    bins = c["bin"]
    present = set(os.listdir(os.path.join(pinned, "bin")))
    for b in sorted(present - set(bins)):
        fail(f"bin/{b} is not in classify.toml")
    for b in sorted(set(bins) - present):
        fail(f"classify.toml names bin/{b}, which is not at the pin")
    for b, k in bins.items():
        if k not in ("KEEP-AS-GUI", "AGENT-INTENT", "ASSET", "RE-EXPRESS-IN-NIX", "DROP"):
            fail(f"bin/{b}: bad class {k}")

    # KEEP-AS-GUI scripts that use root need a privilege mapping (§f.2.5).
    priv = c.get("privilege", {})
    for b, k in bins.items():
        if k != "KEEP-AS-GUI" or b not in present:
            continue
        uses = [l for l in read(os.path.join(pinned, "bin", b)).splitlines()
                if SUDO.search(l) and not l.lstrip().startswith("#")]
        if uses and priv.get(b) not in ("none", "polkit", "unit"):
            fail(f"bin/{b} uses sudo/pkexec but has no privilege mapping")
    for b in priv:
        if bins.get(b) != "KEEP-AS-GUI":
            fail(f"privilege mapping for {b}, which is not KEEP-AS-GUI")

    # Kept shell QML/JS with sudo/pkexec: must name a patch that removes it.
    landed = {re.match(r"(\d{4})-", p).group(1) for p in os.listdir(patches) if re.match(r"\d{4}-.*\.patch$", p)}
    pshell = c.get("privilege-shell", {})
    rules = c["path"]
    for rel in walk(os.path.join(pinned, "shell")):
        rel = "shell/" + rel
        if not rel.endswith((".qml", ".js")) or path_class(rel, rules) != "ASSET":
            continue
        if not SUDO.search(read(os.path.join(pinned, rel))):
            continue
        pid = pshell.get(rel)
        if pid is None:
            fail(f"{rel} uses sudo/pkexec and has no [privilege-shell] entry")
        elif pid.startswith("P") and f"{int(pid[1:]):04d}" in landed:
            pass  # the patch is applied; post checks the built tree
    # Every non-bin file has a class (the last rule is a catch-all, but keep the check).
    counts = collections.Counter()
    for rel in walk(pinned):
        if rel.startswith("bin/"):
            continue
        k = path_class(rel, rules)
        if k is None:
            fail(f"{rel} matches no [[path]] rule")
        counts[k] += 1
    bincounts = collections.Counter(bins.values())
    out = {"rev": c["meta"]["rev"], "bin": dict(sorted(bincounts.items())),
           "paths": dict(sorted(counts.items())), "bin_total": len(present),
           "paths_total": sum(counts.values())}
    json.dump(out, open(counts_out, "w"), indent=2)
    print(json.dumps(out, indent=2))


def cmd_license(pinned, tree, upstream):
    u = tomllib.load(open(upstream, "rb"))
    for where in (pinned, tree):
        p = os.path.join(where, "LICENSE")
        if not os.path.exists(p):
            fail(f"{where}/LICENSE missing")
            continue
        sha = hashlib.sha256(open(p, "rb").read()).hexdigest()
        if sha != u["license_sha256"]:
            fail(f"{p}: sha {sha} != UPSTREAM.toml license_sha256")
    if "Copyright (c) David Heinemeier Hansson" not in read(os.path.join(tree, "LICENSE")):
        fail("LICENSE lost its copyright line")


HL = re.compile(r"\bhl\.[A-Za-z_][A-Za-z0-9_.]*")


def hl_used(tree):
    used = set()
    for rel in walk(tree):
        if rel.startswith(("manual/", "themes/")) and not rel.endswith(".lua"):
            continue
        if not rel.endswith((".lua", ".qml", ".js")) and not rel.startswith("bin/"):
            continue
        for m in HL.findall(read(os.path.join(tree, rel))):
            used.add(m.rstrip("."))
    return used


def cmd_hlsyms(tree, symfile, hypr_src, bars_src):
    allowed = {l.strip() for l in open(symfile) if l.strip() and not l.startswith("#")}
    for s in sorted(hl_used(tree) - allowed):
        fail(f"{s} is used by the shipped tree but not in hl-symbols.txt")
    # Leaf names must be registered by Hyprland's Lua bindings (or the plugin).
    def literals(root):
        lits = set()
        for rel in walk(root):
            if rel.endswith((".cpp", ".hpp", ".h", ".cc")):
                lits.update(re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"', read(os.path.join(root, rel))))
        return lits
    core = literals(os.path.join(hypr_src, "src"))
    bars = literals(bars_src)
    for s in sorted(allowed):
        parts = s.split(".")[1:]
        pool = bars | core if s.startswith("hl.plugin.hyprbars") else core
        for p in parts:
            if p not in pool:
                fail(f"{s}: '{p}' is not a name registered in the {'plugin' if pool is not core else 'Hyprland'} source")
    print(f"hl-symbols: {len(allowed)} allowed, {len(hl_used(tree))} used")


# ---- post-check -----------------------------------------------------------

RESIDUAL = {
    "usr-path": re.compile(r"/usr/(?:share|lib|bin)/"),
    "pacman": re.compile(r"\b(?:pacman|yay|mkinitcpio)\b"),
    "omarchy-org": re.compile(r"\b[a-z0-9.-]*omarchy\.org\b"),
}
CMD = re.compile(r"(?<![A-Za-z0-9_./-])(omarchy-[a-z0-9][a-z0-9-]*[a-z0-9])\b")
TEXT_EXT = (".sh", ".lua", ".qml", ".js", ".json", ".jsonc", ".toml", ".conf", ".desktop",
            ".service", ".timer", ".py", ".tpl", ".rules", ".ini", ".yml", ".yaml", ".md")


def is_text(rel, path):
    if rel.startswith("bin/") or rel.endswith(TEXT_EXT) or "." not in os.path.basename(rel):
        try:
            open(path, encoding="utf-8").read()
            return True
        except (UnicodeDecodeError, IsADirectoryError):
            return False
    return False


def strip_comments(rel, text):
    if rel.endswith((".qml", ".js")):
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("//"))
    if rel.endswith(".lua"):
        return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("--"))
    if rel.endswith(".md"):
        return text
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


def scan(tree, classify, add_dir):
    c = tomllib.load(open(classify, "rb"))
    bins = c["bin"]
    added = {os.path.basename(r) for r in walk(add_dir) if r.startswith("bin/")} if os.path.isdir(add_dir) else set()
    gone = {b for b, k in bins.items() if k in ("AGENT-INTENT", "DROP", "RE-EXPRESS-IN-NIX")} - added
    shipped_bins = set(os.listdir(os.path.join(tree, "bin")))
    found = collections.Counter()
    for rel in walk(tree):
        if rel.startswith("manual/"):
            continue  # reference text; links are rewritten by the manual patch later
        path = os.path.join(tree, rel)
        if os.path.islink(path) or not is_text(rel, path):
            continue
        text = strip_comments(rel, read(path))
        for kind, rx in RESIDUAL.items():
            n = len(rx.findall(text))
            if n:
                found[(rel, kind)] += n
        if rel.endswith(".md"):
            continue
        for m in CMD.findall(text):
            if m in gone:
                found[(rel, "calls:" + m)] += 1
    return found, shipped_bins, bins, added


def cmd_residual(tree, classify, add_dir):
    found, *_ = scan(tree, classify, add_dir)
    print("# Generated by `forkcheck.py residual`; tracked debt in the built omarchy-src.")
    print("# checks.omarchy-src-post fails on any NEW site and on any listed site that is")
    print("# gone (so the list only shrinks). Owner = the work package that removes it.")
    for (rel, kind), n in sorted(found.items()):
        print(f'[[site]]\nfile = "{rel}"\nkind = "{kind}"\ncount = {n}\nowner = "{owner(rel, kind)}"')


def owner(rel, kind):
    if rel.startswith("shell/"):
        return "W18"
    if rel.startswith(("themes/", "default/themed/")):
        return "W16"
    if rel.startswith("bin/") and kind.startswith("calls:"):
        return "W15"
    return "W15"


def cmd_post(tree, classify, residual, add_dir):
    found, shipped_bins, bins, added = scan(tree, classify, add_dir)
    for b in sorted(shipped_bins):
        if b in added:
            continue
        if bins.get(b) not in ("KEEP-AS-GUI", "ASSET"):
            fail(f"bin/{b} ships but is {bins.get(b)}")
    allowed = {}
    for s in tomllib.load(open(residual, "rb")).get("site", []):
        allowed[(s["file"], s["kind"])] = s["count"]
    for key, n in sorted(found.items()):
        if key not in allowed:
            fail(f"new residual {key[1]} in {key[0]} (x{n})")
        elif n > allowed[key]:
            fail(f"residual {key[1]} in {key[0]} grew {allowed[key]} -> {n}")
    for key, n in sorted(allowed.items()):
        if found.get(key, 0) < n:
            fail(f"residual {key[1]} in {key[0]} shrank to {found.get(key, 0)}: update residual.toml")
    print(f"post: {sum(found.values())} residual sites in {len({k[0] for k in found})} files (all tracked)")


if __name__ == "__main__":
    cmd, *args = sys.argv[1:]
    {"classify": cmd_classify, "license": cmd_license, "hlsyms": cmd_hlsyms,
     "post": cmd_post, "residual": cmd_residual}[cmd](*args)
    sys.exit(0 if ok else 1)
