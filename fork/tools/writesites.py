"""Find the places the fork writes files under the human's home (§f.4.9).

Reads a tree (omanix-data or omarchy-src); never executes anything from it.
Shell scripts, Lua, QML/JS and the menu .jsonc are scanned line by line for
writes whose target is a literal home path ($HOME/…, ~/…, ${XDG_*_HOME…}/…):
redirections, sed -i, tee, cp, mv, install, ln -s, touch, truncate, and
omarchy-launch-config-editor (which opens a file for editing). A target
built from a variable the scanner can't resolve is reported as `dynamic`
and is not checked; QML FileView/Process writes that name a path in a
property are matched the same way as text.

usage:
  writesites.py scan TREE                       print every site as JSON
  writesites.py hm-owned TREE HMTARGETS.json fork/writers/
      fail if a site writes an HM-owned target or ~/.local/state/hypr/*.lua,
      unless fork/writers/ lists it as pending (with the patch that fixes it)
  writesites.py writers TREE CLASSIFY.toml fork/writers/
      fail if a KEEP-AS-GUI script writes under ~/.config or ~/.local/state
      without a row in fork/writers/ (checks.runtime-writers)
"""

from __future__ import annotations

import json
import re
import sys
import tomllib
from pathlib import Path

SCAN_DIRS = ("bin", "default", "shell", "config", "applications")
SCAN_SUFFIXES = {"", ".sh", ".lua", ".qml", ".js", ".jsonc", ".py", ".desktop"}

HOME_FORMS = [
    (r"\$\{XDG_CONFIG_HOME:-\$HOME/\.config\}/", ".config/"),
    (r"\$\{XDG_CONFIG_HOME:-~/\.config\}/", ".config/"),
    (r"\$\{XDG_CONFIG_HOME\}/", ".config/"),
    (r"\$XDG_CONFIG_HOME/", ".config/"),
    (r"\$\{XDG_STATE_HOME:-\$HOME/\.local/state\}/", ".local/state/"),
    (r"\$\{XDG_STATE_HOME\}/", ".local/state/"),
    (r"\$XDG_STATE_HOME/", ".local/state/"),
    (r"\$\{HOME\}/", ""),
    (r"\$HOME/", ""),
    (r"~/", ""),
    # QML/JS: home + "/.config/…" and Quickshell.env("HOME") + "/…"
    (r"(?:root\.)?home\s*\+\s*\"/", ""),
]

WRITE_CMDS = r"(?:sed\s+(?:-[a-zA-Z]*i[a-zA-Z]*|--in-place)\b|\btee\b|\bcp\b|\bmv\b|\binstall\b|\bln\s+-[a-zA-Z]*s|\btouch\b|\btruncate\b|omarchy-launch-config-editor)"
PATH_TOKEN = r"(?P<q>[\"']?)(?P<p>(?:\$\{XDG_[A-Z_]+(?::-[^}]*)?\}|\$XDG_[A-Z_]+|\$\{HOME\}|\$HOME|~|(?:root\.)?home\s*\+\s*\")/[^\s\"';|&)<>]*)"


def normalise(raw: str) -> str | None:
    for pat, rep in HOME_FORMS:
        m = re.match(pat, raw)
        if m:
            rest = raw[m.end():]
            rest = rest.rstrip("\\")
            if "$" in rest or "`" in rest:
                return None  # dynamic part
            return rep + rest
    return None


def iter_files(tree: Path):
    for d in SCAN_DIRS:
        base = tree / d
        if not base.exists():
            continue
        for p in sorted(base.rglob("*")):
            if p.is_file() and p.suffix in SCAN_SUFFIXES:
                yield p


MENU_ACTION = re.compile(r'"action"\s*:\s*"((?:[^"\\]|\\.)*)"')


def scan(tree: Path) -> list[dict]:
    sites = []
    redirect = re.compile(r"(?<![<>=&])>{1,2}\s*" + PATH_TOKEN)
    cmd = re.compile(WRITE_CMDS)
    tok = re.compile(PATH_TOKEN)
    for f in iter_files(tree):
        try:
            text = f.read_text(errors="replace")
        except OSError:
            continue
        rel = str(f.relative_to(tree))
        is_menu = rel.endswith(".jsonc")
        for n, line in enumerate(text.splitlines(), 1):
            s = line.strip()
            if not s or s.startswith(("#", "--", "//")):
                continue
            if is_menu:
                # A menu row runs only its "action"; its key, label, intent text
                # and when/disabled tests don't write ("install.service.x" isn't
                # an install(1) call).
                line = " ; ".join(MENU_ACTION.findall(line))
                if not line:
                    continue
            hits = []
            for m in redirect.finditer(line):
                hits.append(("redirect", m.group("p")))
            if cmd.search(line):
                kind = cmd.search(line).group(0).split()[0]
                toks = [m.group("p") for m in tok.finditer(line)]
                # for cp/mv/install/ln the destination is the last path
                if kind in ("cp", "mv", "install", "ln") and toks:
                    toks = toks[-1:]
                hits += [(kind, t) for t in toks]
            for kind, raw in hits:
                target = normalise(raw)
                sites.append({"file": rel, "line": n, "kind": kind, "raw": raw,
                              "target": target if target is not None else "dynamic"})
    return sites


def load_writers(path: Path) -> dict:
    """fork/writers/*.toml merged ([[writer]] and [[pending]] tables)."""
    files = sorted(path.glob("*.toml")) if path.is_dir() else [path]
    out: dict = {"writer": [], "pending": []}
    for f in files:
        d = tomllib.loads(f.read_text())
        for k in out:
            out[k] += d.get(k, [])
    return out


def owned(target: str, hm: set[str]) -> str | None:
    t = target.rstrip("/")
    if t in hm:
        return t
    # a write to a directory that contains HM files (e.g. cp -r into ~/.config/hypr/)
    for h in hm:
        if h.startswith(t + "/") and t.count("/") >= 1:
            return h
    return None


def cmd_hm_owned(tree: Path, hm_json: Path, writers_toml: Path) -> int:
    hm = set(json.loads(hm_json.read_text()))
    writers = load_writers(writers_toml)
    pending = {(w["file"], w["target"]) for w in writers.get("pending", [])}
    bad, seen_pending = [], set()
    for s in scan(tree):
        t = s["target"]
        if t == "dynamic":
            continue
        hit = owned(t, hm)
        if hit is None and not (t.startswith(".local/state/hypr/") and t.endswith(".lua")):
            continue
        key = (s["file"], t)
        if key in pending:
            seen_pending.add(key)
            continue
        bad.append(f"{s['file']}:{s['line']}: {s['kind']} writes ~/{t}" + (f" (HM-owned: {hit})" if hit else " (shadows an HM file)"))
    stale = sorted(pending - seen_pending)
    for f, t in stale:
        bad.append(f"fork/writers: pending entry {f} -> ~/{t} no longer matches a write site; remove it")
    if bad:
        print("\n".join(bad))
        return 1
    print(f"hm-owned-readonly: ok ({len(seen_pending)} pending sites listed in fork/writers)")
    return 0


def cmd_writers(tree: Path, classify_toml: Path, writers_toml: Path) -> int:
    classes = tomllib.loads(classify_toml.read_text())["bin"]
    writers = load_writers(writers_toml)
    listed = {w["script"] for w in writers.get("writer", [])}
    bad = []
    by_script: dict[str, set[str]] = {}
    for s in scan(tree):
        if not s["file"].startswith("bin/"):
            continue
        script = s["file"].removeprefix("bin/")
        if classes.get(script) != "KEEP-AS-GUI":
            continue
        t = s["target"]
        if t == "dynamic" or not t.startswith((".config/", ".local/state/")):
            continue
        by_script.setdefault(script, set()).add(t)
    for script, targets in sorted(by_script.items()):
        if script not in listed:
            bad.append(f"bin/{script}: KEEP-AS-GUI writer with no row in fork/writers (writes {', '.join(sorted(targets))})")
    for w in writers.get("writer", []):
        if w["script"] not in by_script and not w.get("dynamic", False):
            bad.append(f"fork/writers: {w['script']} has a row but no write site was found (set dynamic = true if its paths are computed)")
    if bad:
        print("\n".join(bad))
        return 1
    print(f"runtime-writers: ok ({len(by_script)} writers)")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[0] == "scan":
        print(json.dumps(scan(Path(argv[1])), indent=1))
        return 0
    if len(argv) == 4 and argv[0] == "hm-owned":
        return cmd_hm_owned(Path(argv[1]), Path(argv[2]), Path(argv[3]))
    if len(argv) == 4 and argv[0] == "writers":
        return cmd_writers(Path(argv[1]), Path(argv[2]), Path(argv[3]))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
