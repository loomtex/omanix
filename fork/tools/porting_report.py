"""Porting report: what moving the fork point to <target> would take (§f.2.7).

  porting_report.py <pinned-src> <target-src> <fork-dir> <out-dir> [--json]

Reads both trees and fork/; executes nothing from either tree. Patch dry
runs use `patch --dry-run` on a scratch copy of only the files a patch
touches. Writes porting-report.md and porting-report.json to <out-dir>.
"""
import collections
import filecmp
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

pinned, target, fork, out = sys.argv[1:5]
as_json = "--json" in sys.argv[5:]

CLASSES = ("KEEP-AS-GUI", "AGENT-INTENT", "ASSET", "RE-EXPRESS-IN-NIX", "DROP")


def walk(tree):
    for root, dirs, files in os.walk(tree):
        dirs[:] = sorted(d for d in dirs if d != ".git")
        for f in sorted(files):
            yield os.path.relpath(os.path.join(root, f), tree)


def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except (FileNotFoundError, IsADirectoryError):
        return ""


classify = tomllib.load(open(os.path.join(fork, "classify.toml"), "rb"))
rules = classify["path"]


def class_of(rel):
    if rel.startswith("bin/"):
        return classify["bin"].get(rel[4:], "UNCLASSIFIED")
    for r in rules:
        if re.fullmatch(r["regex"], rel):
            return r["class"]
    return "UNCLASSIFIED"


# Family rules for a suggested class (§f.2.1, applied by name only).
FAMILY = [
    (r"bin/omarchy-(install|remove|setup|default|pkg-(aur-)?install|theme-install|webapp|tui)-?.*", "AGENT-INTENT"),
    (r"bin/omarchy-(update|migrate|pkg|refresh-(pacman|limine|sddm|plymouth)|dev)-?.*", "DROP"),
    (r"bin/omarchy-(toggle|restart|capture|hyprland|audio|brightness|bluetooth|network|theme-(set|bg)|clipboard|menu-(emoji|clipboard|share))-?.*", "KEEP-AS-GUI"),
    (r"bin/omarchy-(hw|launch|cmd|notification|theme|battery|weather|font|show|state|plugin)-?.*", "ASSET"),
    (r"migrations/.*", "DROP"),
    (r"install/.*", "RE-EXPRESS-IN-NIX"),
    (r"(shell|themes|default|config|manual|applications)/.*", "ASSET"),
]


def suggest(rel):
    for rx, k in FAMILY:
        if re.fullmatch(rx, rel):
            return k
    return "DROP"


# 1-2. classified diff
pin_files = set(walk(pinned))
tgt_files = set(walk(target))
changes = collections.defaultdict(list)
for rel in sorted(pin_files | tgt_files):
    if rel not in tgt_files:
        kind = "removed"
    elif rel not in pin_files:
        kind = "added"
    elif not filecmp.cmp(os.path.join(pinned, rel), os.path.join(target, rel), shallow=False):
        kind = "changed"
    else:
        continue
    k = class_of(rel)
    entry = {"path": rel, "change": kind, "class": k}
    if k == "UNCLASSIFIED" or (kind == "added" and rel.startswith("bin/")):
        entry["suggested"] = suggest(rel)
    changes[k].append(entry)

# 3. patch queue dry run + add/ replaces headers
PATCH_FILE = re.compile(r"^\+\+\+ b/(\S+)", re.M)
patches = []
pdir = os.path.join(fork, "patches")
patched = {}  # rel -> content after the patches that apply, for the rewrite stage
for name in sorted(os.listdir(pdir)) if os.path.isdir(pdir) else []:
    if not name.endswith(".patch"):
        continue
    text = read(os.path.join(pdir, name))
    files = PATCH_FILE.findall(text)
    with tempfile.TemporaryDirectory() as tmp:
        missing = []
        for rel in files:
            src = os.path.join(target, rel)
            if not os.path.exists(src):
                missing.append(rel)
                continue
            os.makedirs(os.path.dirname(os.path.join(tmp, rel)), exist_ok=True)
            if rel in patched:
                open(os.path.join(tmp, rel), "w").write(patched[rel])
            else:
                shutil.copyfile(src, os.path.join(tmp, rel))
        if missing:
            status, detail = "conflict", "target lacks " + ", ".join(missing)
        else:
            r = subprocess.run(["patch", "--dry-run", "-p1", "--fuzz=0", "-d", tmp, "-i", os.path.join(pdir, name)],
                               capture_output=True, text=True)
            if r.returncode != 0:
                status, detail = "conflict", r.stdout.strip().splitlines()[-1:] or [""]
                detail = detail[0]
            elif "offset" in r.stdout:
                status, detail = "offset", ""
            else:
                status, detail = "clean", ""
            if status != "conflict":
                subprocess.run(["patch", "-s", "-p1", "--fuzz=0", "-d", tmp, "-i", os.path.join(pdir, name)], check=True)
                for rel in files:
                    patched[rel] = read(os.path.join(tmp, rel))
    patches.append({"patch": name, "status": status, "detail": detail})

REPLACES = re.compile(r"replaces upstream (\S+) sha256 ([0-9a-f]{64})")
adds = []
adir = os.path.join(fork, "add")
for rel in walk(adir) if os.path.isdir(adir) else []:
    m = REPLACES.search(read(os.path.join(adir, rel))[:4096])
    if not m:
        continue
    t = os.path.join(target, m.group(1))
    if not os.path.exists(t):
        adds.append({"add": rel, "status": "upstream removed"})
    elif hashlib.sha256(open(t, "rb").read()).hexdigest() != m.group(2):
        adds.append({"add": rel, "status": "upstream changed; re-port"})

# 4. rewrite counts against the target after the patch queue and add/ (shebang
# line excluded, like assemble.py)
rewrites = []
rw = tomllib.load(open(os.path.join(fork, "rewrite.toml"), "rb")).get("rewrite", [])
bodies = {}
for r in rw:
    path = os.path.join(target, r["file"])
    if os.path.exists(os.path.join(adir, r["file"])):
        path = os.path.join(adir, r["file"])
    if r["file"] not in bodies:
        lines = patched[r["file"]].split("\n") if r["file"] in patched else read(path).split("\n")
        bodies[r["file"]] = "\n".join(lines[1:] if lines and lines[0].startswith("#!") else lines)
    body = bodies[r["file"]]
    if r.get("regex"):
        body, got = re.subn(r["from"], r["to"], body)
    else:
        got = body.count(r["from"])
        body = body.replace(r["from"], r["to"])
    bodies[r["file"]] = body
    if got != r["count"]:
        rewrites.append({"file": r["file"], "from": r["from"], "expected": r["count"], "got": got})

# 5. menu ids
def menu_ids(tree):
    text = read(os.path.join(tree, "default/omarchy/omarchy-menu.jsonc"))
    return set(re.findall(r'"id"\s*:\s*"([^"]+)"', text))

pin_ids, tgt_ids = menu_ids(pinned), menu_ids(target)
menu = {"added": sorted(tgt_ids - pin_ids), "removed": sorted(pin_ids - tgt_ids)}

# 6. writers: new write sites into ~/.config (HM-owned) in shipped scripts/QML
WRITE = re.compile(r"(sed -i|>\s*\"?\$HOME/\.config|>\s*~/\.config|cat\s*>|tee\s+\S*\.config|atomicWrite)")
writers = []
for rel in sorted(tgt_files):
    if class_of(rel) not in ("KEEP-AS-GUI", "ASSET") or not rel.startswith(("bin/", "shell/")):
        continue
    new = [l for l in read(os.path.join(target, rel)).splitlines() if WRITE.search(l) and ".config" in l]
    old = set(l for l in read(os.path.join(pinned, rel)).splitlines())
    added = [l.strip() for l in new if l not in old]
    if added:
        writers.append({"path": rel, "lines": added[:5]})

# 7. runtime deps: hl.* symbols beyond the allowed list
allowed = {l.strip() for l in read(os.path.join(fork, "hl-symbols.txt")).splitlines() if l.strip() and not l.startswith("#")}
used = set()
for rel in tgt_files:
    if rel.endswith((".lua", ".qml", ".js")) or rel.startswith("bin/"):
        used.update(m.rstrip(".") for m in re.findall(r"\bhl\.[A-Za-z_][A-Za-z0-9_.]*", read(os.path.join(target, rel))))
deps = {"new_hl_symbols": sorted(used - allowed)}

# 8. hardware, 9. themes
hardware = [c["path"] for cs in changes.values() for c in cs
            if c["path"].startswith(("install/hardware/", "install/user/hardware/")) and c["change"] == "added"]
themes = sorted({c["path"].split("/")[1] for cs in changes.values() for c in cs
                 if c["path"].startswith("themes/") and c["change"] in ("added", "changed")})

# 10. summary
counts = {k: len(v) for k, v in sorted(changes.items())}
effort = {
    "files_changed": sum(counts.values()),
    "unclassified": counts.get("UNCLASSIFIED", 0),
    "patch_conflicts": sum(p["status"] == "conflict" for p in patches),
    "patch_offsets": sum(p["status"] == "offset" for p in patches),
    "add_replacements_to_report": len(adds),
    "rewrite_mismatches": len(rewrites),
    "menu_ids_added": len(menu["added"]),
    "new_writers": len(writers),
    "new_hl_symbols": len(deps["new_hl_symbols"]),
}
report = {"pinned": classify["meta"]["rev"], "target": target, "effort": effort, "changes_by_class": counts,
          "changes": changes, "patches": patches, "adds": adds, "rewrites": rewrites, "menu": menu,
          "writers": writers, "deps": deps, "hardware": hardware, "themes": themes}

os.makedirs(out, exist_ok=True)
json.dump(report, open(os.path.join(out, "porting-report.json"), "w"), indent=2)

md = [f"# omanix porting report: {classify['meta']['rev'][:7]} -> {os.environ.get('PORTING_TARGET_REF', os.path.basename(target))}", "",
      "## Effort", ""] + [f"- {k}: {v}" for k, v in effort.items()] + ["", "## Changed files by class", ""]
for k, v in counts.items():
    md.append(f"### {k} ({v})")
    for c in changes[k][:200]:
        s = f" (suggest {c['suggested']})" if "suggested" in c else ""
        md.append(f"- {c['change']}: `{c['path']}`{s}")
    if len(changes[k]) > 200:
        md.append(f"- ... {len(changes[k]) - 200} more (see porting-report.json)")
    md.append("")
md += ["## Patch queue", ""] + [f"- {p['patch']}: {p['status']} {p['detail']}" for p in patches]
md += ["", "## add/ replacements", ""] + ([f"- {a['add']}: {a['status']}" for a in adds] or ["- all match"])
md += ["", "## Rewrites", ""] + ([f"- {r['file']}: {r['from']} expected {r['expected']} got {r['got']}" for r in rewrites] or ["- all counts match"])
md += ["", "## Menu", "", f"- added: {', '.join(menu['added']) or 'none'}", f"- removed: {', '.join(menu['removed']) or 'none'}"]
md += ["", "## New writers into ~/.config", ""] + ([f"- `{w['path']}`: " + "; ".join(f"`{l}`" for l in w["lines"]) for w in writers] or ["- none"])
md += ["", "## Runtime deps", "", f"- new hl.* symbols: {', '.join(deps['new_hl_symbols']) or 'none'}"]
md += ["", "## Hardware", ""] + ([f"- {h}" for h in hardware] or ["- none"])
md += ["", "## Themes", "", f"- {', '.join(themes) or 'none'}", ""]
open(os.path.join(out, "porting-report.md"), "w").write("\n".join(md))

print(json.dumps(effort, indent=2) if as_json else "\n".join(md[:14]))
print(f"\nwrote {out}/porting-report.md and porting-report.json", file=sys.stderr)
