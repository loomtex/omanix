"""Read-only verbs: context, options, where, explain, status, doctor,
why-failed."""

from __future__ import annotations

import glob
import json
import os
import re
from pathlib import Path

from . import handler
from . import nixedit
from .common import CliError, EXIT, run, split_path, option_hm, tail

# runtime.json keys and overlays that shadow a declared option (§f.4.6).
SHADOWS = [
    ("omanix.fonts.monospace", "monospace", ["kitty.conf", "alacritty.toml", "ghostty.conf", "foot.ini", "fontconfig/fonts.conf"]),
    ("omanix.theme.default", "theme", []),
    ("omanix.theme.background", "wallpaper", []),
    ("omanix.hyprland.monitors", None, ["hypr/monitors.lua"]),
    ("omanix.hyprland.gdkScale", None, ["hypr/monitors.lua"]),
    ("omanix.input", "keyboard", ["hypr/input.lua", "xcompose"]),
    ("omanix.keybinds", None, ["hypr/bindings.lua"]),
    ("omanix.hyprland.settings", None, ["hypr/looknfeel.lua", "hypr/hyprland.lua"]),
    ("omanix.hyprland.extraLua", None, ["hypr/hyprland.lua"]),
    ("omanix.shell.settings", "shellKeys", []),
    ("omanix.apps.chromium.features", None, ["chromium-flags.conf"]),
]


def shadowed_by(path: str, runtime: dict | None) -> list[dict]:
    """Runtime state that wins over `path` in this session."""
    if not runtime:
        return []
    out = []
    ov = runtime.get("overlays") or {}
    for opt, key, overlays in SHADOWS:
        if not (path == opt or path.startswith(opt + ".") or opt.startswith(path + ".")):
            continue
        if key and runtime.get(key) not in (None, [], {}, ""):
            if key == "theme" or key == "wallpaper":
                continue   # the theme state always exists; it's the picker's, not an override
            out.append({"kind": "runtime", "key": key, "value": runtime.get(key)})
        for o in overlays:
            if o in ov and not ov[o].get("empty", True):
                out.append({"kind": "overlay", "overlay": o, "sha256": ov[o].get("sha256"),
                            "clear": f"omanix reset {o}"})
    return out


# ---------------------------------------------------------------- context


def _generation():
    cur = os.path.realpath("/run/current-system")
    prof = os.path.realpath("/nix/var/nix/profiles/system")
    num = None
    link = os.readlink("/nix/var/nix/profiles/system") if os.path.islink("/nix/var/nix/profiles/system") else ""
    m = re.match(r"system-(\d+)-link", link)
    if m:
        num = int(m.group(1))
    rev = None
    for f in ("/run/current-system/configuration-revision",):
        try:
            rev = Path(f).read_text().strip() or None
        except OSError:
            pass
    if rev is None:
        r = run(["nixos-version", "--configuration-revision"], soft=True)
        rev = r.stdout.strip() or None if r.returncode == 0 else None
    return {"current": cur, "boot": prof, "number": num, "configurationRevision": rev, "pendingReboot": cur != prof}


def _plugins(repo: Path) -> list[dict]:
    try:
        lock = json.loads((repo / "flake.lock").read_text())
    except (OSError, json.JSONDecodeError):
        return []
    root = lock["nodes"][lock["root"]].get("inputs", {})
    out = []
    for name, node in sorted(root.items()):
        if name in ("omanix", "nixpkgs", "home-manager") or isinstance(node, list):
            continue
        n = lock["nodes"].get(node, {})
        orig = n.get("original", {})
        out.append({"input": name, "original": orig, "rev": n.get("locked", {}).get("rev"),
                    "narHash": n.get("locked", {}).get("narHash")})
    return out


def _last_switch(cfg: dict):
    d = cfg.get("recordsDir") or "/var/lib/loom/switches"
    try:
        ns = sorted(int(x) for x in os.listdir(d) if x.isdigit())
    except OSError:
        return None
    if not ns:
        return None
    rd = Path(d) / str(ns[-1])
    card, res = {}, {}
    try:
        card = json.loads((rd / "card.json").read_text())
    except (OSError, json.JSONDecodeError):
        pass
    try:
        res = json.loads((rd / "result.json").read_text())
    except (OSError, json.JSONDecodeError):
        pass
    return {"n": ns[-1], "title": card.get("title"), "request": card.get("request"), "tip": card.get("tip"),
            "status": res.get("status", "running"), "reason": res.get("reason")}


def _sek(ctx):
    r = run(["loom", "keys", "rotate", "encryption-key", "--status", "--json"], timeout=30, soft=True)
    if r.returncode != 0:
        return None
    try:
        d = json.loads(r.stdout)
        return {"inProgress": bool(d.get("inProgress")), "state": d.get("state")}
    except json.JSONDecodeError:
        return None


def _skills(ctx) -> list[str]:
    for d in [ctx.cfg.get("skills"), str(ctx.home / ".claude/skills")]:
        if d and os.path.isdir(d):
            return sorted(x for x in os.listdir(d) if os.path.isfile(os.path.join(d, x, "SKILL.md")))
    return []


def _working_copy(ctx):
    try:
        repo = ctx.repo()
    except CliError:
        return {"path": str(ctx.default_repo()), "exists": False}
    head = ctx.git("rev-parse", "HEAD", check=False) or None
    dirty = [l[3:] for l in ctx.git("status", "--porcelain", check=False).splitlines() if l.strip()]
    dep = ctx.deployed()
    ahead = behind = None
    if dep and head:
        if run(["git", "-C", str(repo), "cat-file", "-e", f"{dep}^{{commit}}"]).returncode != 0:
            run(["git", "-C", str(repo), "fetch", "-q", ctx.mirror, "refs/heads/master"])
        r = run(["git", "-C", str(repo), "rev-list", "--left-right", "--count", f"{dep}...{head}"])
        if r.returncode == 0:
            behind, ahead = (int(x) for x in r.stdout.split())
    return {"path": str(repo), "exists": True, "head": head, "deployed": dep, "ahead": ahead, "behind": behind,
            "dirty": dirty, "branch": ctx.git("rev-parse", "--abbrev-ref", "HEAD", check=False)}


@handler("core", "context")
def context(ctx, a):
    cfg = ctx.cfg
    cat = ctx.catalog_json("config.json", {}) or {}
    loomc = cat.get("loom", {})
    host = {"id": (loomc.get("host") or {}).get("id"), "name": (loomc.get("host") or {}).get("name"),
            "release": (cat.get("omanix") or {}).get("release"), "user": cfg.get("human"), "agent": cfg.get("agent")}
    wc = _working_copy(ctx)
    plugins = _plugins(Path(wc["path"])) if wc.get("exists") else []
    fb = cfg.get("firstbootDir") or "/persist/var/lib/loom/firstboot"
    steps = {}
    for f in sorted(glob.glob(os.path.join(fb, "*.done"))):
        steps[os.path.basename(f)[:-5]] = True
    rt = ctx.runtime()
    runtime = None
    if rt:
        runtime = {"theme": rt.get("theme"), "monospace": rt.get("monospace"), "keyboard": rt.get("keyboard"),
                   "toggles": rt.get("toggles"), "monitors": rt.get("monitors"),
                   "nonEmptyOverlays": sorted(k for k, v in (rt.get("overlays") or {}).items() if not v.get("empty", True))}
    index = ctx.catalog_json("index.json", {}) or {}
    out = {
        "host": host,
        "generation": _generation(),
        "workingCopy": wc,
        "plugins": plugins,
        "lastSwitch": _last_switch(cfg),
        "runtime": runtime,
        "enrollment": {"published": steps.get("repo-publish", False), "steps": sorted(steps)},
        "sekRotation": _sek(ctx),
        "catalog": {"dir": str(ctx.catalog), "files": sorted((index.get("files") or {}).keys())},
        "skills": _skills(ctx),
    }
    lines = [
        f"host {host['name']} ({host['id']}), omanix {host['release']}; human {host['user']}, agent {host['agent']}",
        f"generation {out['generation']['number']}: {out['generation']['current']}",
        f"working copy {wc['path']}: " + (f"head {str(wc.get('head'))[:12]}, deployed {str(wc.get('deployed'))[:12]}, "
                                         f"ahead {wc.get('ahead')}, behind {wc.get('behind')}, "
                                         f"{len(wc.get('dirty') or [])} uncommitted" if wc.get("exists") else "missing"),
        "plugins: " + (", ".join(p["input"] for p in plugins) or "none"),
        "last switch: " + (f"#{out['lastSwitch']['n']} {out['lastSwitch']['title']} [{out['lastSwitch']['status']}]"
                           if out["lastSwitch"] else "none"),
        "runtime overlays: " + (", ".join(runtime["nonEmptyOverlays"]) or "none" if runtime else "no session"),
        "key rotation: " + ("in progress (" + str(out["sekRotation"]["state"]) + ")" if out["sekRotation"] and out["sekRotation"]["inProgress"] else "none"),
        f"catalogs: {out['catalog']['dir']} ({len(out['catalog']['files'])} files); skills: {len(out['skills'])}",
    ]
    out["_text"] = "\n".join(lines)
    return out


# ---------------------------------------------------------------- options


def _option_files(ctx):
    d = ctx.catalog / "options"
    return sorted(d.glob("*.json")) if d.is_dir() else []


def _iter_options(ctx):
    for f in _option_files(ctx):
        try:
            doc = json.loads(f.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        scope = f.stem
        for name, o in doc.items():
            yield scope, name, o


def _brief(o, name, scope):
    def txt(v):
        if isinstance(v, dict) and "text" in v:
            return v["text"]
        return v
    return {"path": name, "scope": scope, "type": o.get("type"), "default": txt(o.get("default")),
            "origin": o.get("origin"), "description": (o.get("description") or "")[:600], "readOnly": o.get("readOnly", False)}


@handler("core", "options")
def options(ctx, a):
    words = [w.lower() for w in a.query]
    res = []
    for scope, name, o in _iter_options(ctx):
        if a.origin and o.get("origin") != a.origin:
            continue
        hay = (name + " " + (o.get("description") or "")).lower()
        if all(w in hay for w in words):
            score = sum(3 for w in words if w in name.lower())
            res.append((-score, len(name), _brief(o, name, scope)))
    res.sort(key=lambda t: (t[0], t[1]))
    results = [r[2] for r in res[: a.limit]]
    text = "\n".join(f"{r['path']}  ({r['type']}; {r['origin']})\n    {r['description'][:160]}" for r in results)
    if not _option_files(ctx):
        text = f"no option catalogs in {ctx.catalog}"
    return {"query": " ".join(a.query), "results": results, "total": len(res), "_text": text}


def catalog_entry(ctx, path: str):
    for scope, name, o in _iter_options(ctx):
        if name == path:
            return _brief(o, name, scope)
    return None


# ---------------------------------------------------------------- where


def locate(ctx, repo: Path, defn: dict, inner: list[str]) -> dict:
    """file:line of a host definition, and whether `omanix set` can edit it."""
    rel = defn["origin"]["file"]
    f = repo / rel
    out = {"file": rel, "line": None, "literal": False, "editable": False}
    try:
        src = f.read_bytes()
        tree = nixedit.parse(src)
        ms = nixedit.find_in_module(tree, inner)
    except (OSError, nixedit.EditError) as e:
        out["note"] = str(e)
        return out
    vals = [m for m in ms if m.kind == "value"]
    if ms:
        out["line"] = ms[0].line
    if len(vals) == 1 and len(ms) == 1:
        out["literal"] = nixedit.is_literal(vals[0].value)
        out["editable"] = out["literal"]
    elif len(ms) > 1:
        out["note"] = "defined in several places in this file: " + ", ".join(f"{rel}:{m.line}" for m in ms)
    elif ms and ms[0].kind != "value":
        out["note"] = "defined through an expression"
    return out


def resolve(ctx, target: str) -> dict:
    path = split_path(target)
    inner, hm = option_hm(path)
    w = ctx.nix_eval({"op": "where", "path": inner, "hm": hm})
    repo = ctx.repo()
    defs = []
    for d in w.get("definitions", []):
        e = {"origin": d["origin"], "priority": d.get("priority"), "value": d.get("value"), "opaque": d.get("opaque", False)}
        o = d["origin"]
        if o["kind"] == "host":
            e.update(locate(ctx, repo, d, inner))
            if d.get("opaque"):
                e["editable"] = False
            e["where"] = f"{e['file']}:{e['line']}" if e.get("line") else e["file"]
        elif o["kind"] == "input":
            e["where"] = f"input:{o['input']}/{o['file']}"
            e["editable"] = False
        else:
            e["where"] = o["file"]
            e["editable"] = False
        defs.append(e)
    w["definitions"] = defs
    w["hm"] = hm
    w["target"] = target
    return w


def _home_file(ctx, target: str) -> dict | None:
    t = target
    for pre in ("~/", str(ctx.home) + "/", "$HOME/"):
        if t.startswith(pre):
            t = t[len(pre):]
    homej = ctx.catalog_json("home.json", {}) or {}
    files = homej.get("files", homej)
    if t in files:
        f = files[t]
    else:
        # an overlay path (hypr/monitors.lua) or a bare name
        hit = [(k, v) for k, v in files.items() if isinstance(v, dict) and (v.get("overlay") == t or k.endswith("/" + t))]
        if len(hit) != 1:
            return None
        t, f = hit[0]
    rt = ctx.runtime() or {}
    ov = f.get("overlay")
    st = (rt.get("overlays") or {}).get(ov) if ov else None
    return {"target": target, "kind": "file", "file": t, "module": f.get("module"), "options": f.get("options", []),
            "source": f.get("source"), "overlay": ov,
            "overlayPath": f"~/.local/state/omanix/overlay/{ov}" if ov else None,
            "include": f.get("include"),
            "overlayEmpty": None if st is None else st.get("empty"),
            "shadowedBy": [] if not st or st.get("empty", True) else [{"kind": "overlay", "overlay": ov, "clear": f"omanix reset {ov}"}],
            "editable": False,
            "note": "read-only (home-manager); set the option(s) in the host repo, or use the overlay for this session"}


@handler("core", "where")
def where(ctx, a):
    if "/" in a.target or a.target.startswith("~") or a.target.startswith("."):
        hf = _home_file(ctx, a.target)
        if hf is None:
            raise CliError(EXIT.FAILED, f"{a.target} isn't a file omanix owns (see catalog/home.json)")
        hf["_text"] = (f"{hf['file']}: owned by modules/omanix/{hf['module']} → {', '.join(hf['options']) or 'its module'}\n"
                       f"overlay: {hf['overlayPath'] or 'none'}" + (" (not empty: wins this session)" if hf["shadowedBy"] else ""))
        return hf
    w = resolve(ctx, a.target)
    w["shadowedBy"] = shadowed_by(a.target, ctx.runtime())
    lines = [f"{a.target}: {w['kind']}" + (f" ({w.get('type')})" if w.get("type") else "")]
    for d in w["definitions"]:
        tag = "editable" if d.get("editable") else ("expression" if d["origin"]["kind"] == "host" else "read-only")
        lines.append(f"  {d['where']}  prio {d.get('priority')}  {tag}  = {json.dumps(d.get('value'))[:120]}")
    if w["kind"] == "group":
        lines.append("  options: " + ", ".join(w.get("children", [])))
    lines.append(f"  value: {json.dumps(w.get('value'))[:200]}")
    for s in w["shadowedBy"]:
        lines.append(f"  shadowed this session by {s.get('overlay') or s.get('key')}")
    w["_text"] = "\n".join(lines)
    return w


@handler("core", "explain")
def explain(ctx, a):
    w = resolve(ctx, a.option)
    w["catalog"] = catalog_entry(ctx, a.option)
    w["shadowedBy"] = shadowed_by(a.option, ctx.runtime())
    c = w["catalog"] or {}
    lines = [f"{a.option}  ({c.get('type') or w.get('type')}; {c.get('origin') or '?'})",
             (c.get("description") or w.get("description") or "").strip()[:800],
             f"default: {c.get('default')}", f"value: {json.dumps(w.get('value'))[:300]}"]
    for d in w["definitions"]:
        lines.append(f"  defined at {d['where']} (prio {d.get('priority')})")
    w["_text"] = "\n".join(l for l in lines if l)
    return w


# ---------------------------------------------------------------- status / doctor / why-failed


def _failed_units():
    out = []
    for scope in ([], ["--user"]):
        r = run(["systemctl", *scope, "--failed", "--plain", "--no-legend", "--no-pager"], timeout=20, soft=True)
        for l in r.stdout.splitlines():
            if l.strip():
                out.append({"unit": l.split()[0], "scope": "user" if scope else "system"})
    return out


@handler("core", "status")
def status(ctx, a):
    secrets_dir = Path("/run/secrets")
    sec = {"decrypted": secrets_dir.is_dir(), "names": sorted(os.listdir(secrets_dir)) if secrets_dir.is_dir() and os.access(secrets_dir, os.R_OK) else []}
    r = run(["systemctl", "is-failed", "sops-install-secrets.service"], timeout=10, soft=True)
    sec["failed"] = r.stdout.strip() == "failed"
    rt = ctx.runtime()
    shadow = []
    if rt:
        for o, v in sorted((rt.get("overlays") or {}).items()):
            if not v.get("empty", True):
                shadow.append({"overlay": o, "clear": f"omanix reset {o}"})
    failed = _failed_units()
    out = {"failedUnits": failed, "secrets": sec, "shadowing": shadow, "generation": _generation(),
           "lastSwitch": _last_switch(ctx.cfg)}
    out["_text"] = "\n".join([
        "failed units: " + (", ".join(u["unit"] for u in failed) or "none"),
        "secrets: " + ("failed to decrypt" if sec["failed"] else "ok" if sec["decrypted"] else "none"),
        "runtime overlays: " + (", ".join(s["overlay"] for s in shadow) or "none"),
    ])
    return out


@handler("core", "doctor")
def doctor(ctx, a):
    if ctx.is_agent:
        raise CliError(EXIT.USAGE, "doctor reads the human's session; ask the human to run it (or read `omanix status`)")
    r = run(["omanix-overlay", "doctor"], timeout=60, soft=True)
    problems = [l for l in r.stdout.splitlines() if l.strip() and l.strip() != "nothing to report"]
    overlays = [p.split(": ", 1)[1] for p in problems if p.startswith("overlay not empty: ")]
    declared = {}
    for o in overlays:
        declared[o] = [opt for opt, _, ovs in SHADOWS if o in ovs]
    # HM links that don't point into the current generation
    homej = ctx.catalog_json("home.json", {}) or {}
    files = homej.get("files", homej)
    gen = None
    hm = run(["systemctl", "show", "-p", "ExecStart", "--value", f"home-manager-{ctx.user}.service"], soft=True)
    m = re.search(r"(/nix/store/[^ ;]*-home-manager-generation)", hm.stdout)
    if m:
        gen = os.path.realpath(m.group(1) + "/home-files")
    bad = []
    for t in sorted(files):
        p = ctx.home / t
        if not p.is_symlink():
            bad.append({"target": t, "problem": "not a link" if p.exists() else "missing"})
        elif gen and not os.readlink(p).startswith(gen + "/") and t != ".config/btop/themes/current.theme":
            bad.append({"target": t, "problem": "links into another generation"})
    reclaim = ctx.home / ".local/state/loom/clobbered"
    reclaimed = sorted(str(p.relative_to(reclaim)) for p in reclaim.rglob("*") if p.is_file()) if reclaim.is_dir() else []
    for b in bad:
        problems.append(f"HM file {b['target']}: {b['problem']}")
    if reclaimed:
        problems.append(f"{len(reclaimed)} reclaimed file(s) in {reclaim}")
    out = {"problems": problems, "overlays": [{"overlay": o, "shadows": declared[o], "clear": f"omanix reset {o}"} for o in overlays],
           "hmLinks": bad, "reclaimed": reclaimed[:200]}
    out["_text"] = "\n".join(problems) or "nothing to report"
    return out


def _journal(unit: str, user: bool = False, n: int = 60) -> str:
    r = run(["journalctl", *(["--user"] if user else []), "-u", unit, "-n", str(n), "--no-pager", "-o", "short-iso"], timeout=30, soft=True)
    return r.stdout.strip() or r.stderr.strip()


@handler("core", "why-failed")
def why_failed(ctx, a):
    sw = _last_switch(ctx.cfg)
    if a.unit:
        user = False
        log = _journal(a.unit)
        if not log or "No entries" in log:
            log, user = _journal(a.unit, True), True
        return {"subject": a.unit, "kind": "unit", "log": tail(log, 80), "_text": tail(log, 80)}
    if sw and (a.last or sw["status"] in ("rolled-back", "rolledback", "failed")):
        rd = Path(ctx.cfg.get("recordsDir") or "/var/lib/loom/switches") / str(sw["n"])
        res = {}
        try:
            res = json.loads((rd / "result.json").read_text())
        except (OSError, json.JSONDecodeError):
            pass
        log = ""
        cur = res.get("journalCursor") or res.get("cursor")
        if cur:
            log = run(["journalctl", "--after-cursor", cur, "-n", "80", "--no-pager"], timeout=30, soft=True).stdout
        subject = f"switch #{sw['n']}: {sw['title']} [{sw['status']}]"
        return {"subject": subject, "kind": "switch", "switch": sw, "check": res.get("check"), "reason": res.get("reason"),
                "log": tail(log, 80), "_text": subject + "\n" + (res.get("reason") or "") + "\n" + tail(log, 80)}
    failed = _failed_units()
    if not failed:
        return {"subject": None, "kind": "none", "log": "", "_text": "nothing has failed"}
    u = failed[0]
    log = _journal(u["unit"], u["scope"] == "user")
    return {"subject": u["unit"], "kind": "unit", "scope": u["scope"], "log": tail(log, 80), "_text": f"{u['unit']}:\n" + tail(log, 80)}
