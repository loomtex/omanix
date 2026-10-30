"""check / plan / propose / update (§h.8, §g.3, §g.6). Builds run as the
caller through nix-daemon with IFD off; switching is loom's (`loom
propose` → approval card → `loom-switch`)."""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path

from . import handler
from . import nixedit
from .cmd_edit import FileEdit, _tags, _with_tag
from .common import CliError, EXIT, run, nix_env, offline, tail


def _state(ctx) -> Path:
    d = Path(os.environ.get("XDG_CACHE_HOME") or ctx.home / ".cache") / "omanix"
    d.mkdir(parents=True, exist_ok=True)
    return d


def keys_sync(ctx) -> dict:
    repo = ctx.repo()
    gen = (ctx.nix_eval({"op": "keys"}) or {}).get("generated")
    if gen is None:
        return {"ok": True, "skipped": "no loom.keys on this host", "differs": []}
    differs = []
    for f, text in sorted(gen.items()):
        p = repo / f
        if not p.exists():
            differs.append({"file": f, "problem": "missing (never delete it; run `loom keys sync`)"})
        elif p.read_text() != text:
            differs.append({"file": f, "problem": "differs from keys.nix (run `loom keys sync`)"})
    return {"ok": not differs, "differs": differs}


def build(ctx, timeout=7200) -> dict:
    attr = ctx.cfg.get("hostAttr", "nixosConfigurations.host")
    r = run(["nix", "build", "--no-link", "--print-out-paths", "--no-write-lock-file",
             f"{ctx.flakeref()}#{attr}.config.system.build.toplevel"], env=nix_env(), timeout=timeout)
    if r.returncode != 0:
        code = EXIT.RETRY if offline(r.stderr) else EXIT.FAILED
        return {"ok": False, "out": None, "log": tail(r.stderr, 80), "_code": code}
    return {"ok": True, "out": r.stdout.strip().splitlines()[-1], "log": tail(r.stderr, 10)}


def do_check(ctx, no_build=False) -> tuple[dict, int]:
    repo = ctx.repo()
    untracked = [l[3:] for l in ctx.git("status", "--porcelain", check=False).splitlines()
                 if l.startswith("??") and l.endswith(".nix")]
    head = ctx.git("rev-parse", "HEAD", check=False) or None
    clean = not [l for l in ctx.git("status", "--porcelain", "--untracked-files=no", check=False).splitlines() if l.strip()]
    try:
        ev = ctx.nix_eval({"op": "assertions"})
        evr = {"ok": not ev["failed"], "failed": ev["failed"], "warnings": ev["warnings"]}
    except CliError as e:
        evr = {"ok": False, "failed": [], "warnings": [], "error": e.message}
        out = {"eval": evr, "keysSync": {"ok": None, "differs": []}, "build": {"ok": False, "skipped": True},
               "untracked": untracked}
        return out, e.code
    ks = keys_sync(ctx) if evr["ok"] else {"ok": None, "differs": []}
    if no_build or not evr["ok"]:
        b = {"ok": None if no_build else False, "skipped": True}
    else:
        b = build(ctx)
    code = EXIT.OK
    if not evr["ok"] or ks.get("ok") is False:
        code = EXIT.FAILED
    elif b.get("ok") is False:
        code = b.pop("_code", EXIT.FAILED)
    b.pop("_code", None)
    out = {"eval": evr, "keysSync": ks, "build": b, "head": head, "clean": clean, "untracked": untracked}
    if b.get("ok"):
        (_state(ctx) / "last-check.json").write_text(json.dumps(
            {"repo": str(repo), "head": head, "clean": clean, "out": b["out"], "time": int(time.time())}))
    return out, code


def _check_text(out):
    ev, ks, b = out["eval"], out["keysSync"], out["build"]
    lines = []
    if ev.get("error"):
        lines.append("eval: " + ev["error"])
    for f in ev.get("failed", []):
        lines.append("assertion: " + f)
    for w in ev.get("warnings", []):
        lines.append("warning: " + w)
    for d in ks.get("differs", []):
        lines.append(f"keys: {d['file']} {d['problem']}")
    if b.get("ok"):
        lines.append(f"built {b['out']}")
    elif b.get("log"):
        lines.append("build failed:\n" + b["log"])
    for u in out.get("untracked", []):
        lines.append(f"note: {u} is untracked; `git add` it or nix won't see it")
    return "\n".join(lines) or "ok"


@handler("core", "check")
def check(ctx, a):
    out, code = do_check(ctx, a.no_build)
    out["_text"] = _check_text(out)
    out["_exit"] = code
    return out


@handler("core", "plan")
def plan(ctx, a):
    out, code = do_check(ctx)
    nvd = None
    if out["build"].get("ok"):
        r = run(["nvd", "diff", "/run/current-system", out["build"]["out"]], timeout=300)
        nvd = r.stdout.strip() if r.returncode == 0 else ("nvd failed: " + tail(r.stderr, 5))
    dep = ctx.deployed()
    stat = ""
    if dep:
        repo = ctx.repo()
        if run(["git", "-C", str(repo), "cat-file", "-e", f"{dep}^{{commit}}"]).returncode != 0:
            run(["git", "-C", str(repo), "fetch", "-q", ctx.mirror, "refs/heads/master"])
        stat = ctx.git("diff", "--stat", dep, check=False)
    out.update({"nvd": nvd, "gitStat": stat, "deployed": dep})
    out["_text"] = _check_text(out) + ("\n\n" + nvd if nvd else "") + ("\n\n" + stat if stat else "")
    out["_exit"] = code
    return out


# ---------------------------------------------------------------- propose


def _result(rc: int, err: str) -> str:
    if rc == 0:
        return "applied"
    if rc == 4:
        return "rolled-back"
    if rc == 5:
        return "refused"
    if "Request denied" in err or "denied" in err.lower().split("\n")[-1]:
        return "denied"
    return "failed"


def _code(result: str) -> int:
    return {"applied": EXIT.OK, "rolled-back": EXIT.ROLLED_BACK, "refused": EXIT.RETRY,
            "waiting": EXIT.APPROVAL}.get(result, EXIT.FAILED)


def do_propose(ctx, request: str | None, ref: str = "HEAD", wait: bool = True) -> dict:
    repo = ctx.repo()
    tip = ctx.git("rev-parse", "--verify", f"{ref}^{{commit}}")
    dirty = [l for l in ctx.git("status", "--porcelain", "--untracked-files=no", check=False).splitlines() if l.strip()]
    args = ["loom", "propose", "--repo", str(repo), "--ref", tip]
    if request:
        args += ["--request", request]
    last = {}
    try:
        last = json.loads((_state(ctx) / "last-check.json").read_text())
    except (OSError, json.JSONDecodeError):
        pass
    reused = None
    if last.get("repo") == str(repo) and last.get("head") == tip and last.get("clean") and os.path.exists(last.get("out", "")):
        args += ["--out", last["out"]]
        reused = last["out"]
    out = {"tip": tip, "request": request, "reusedBuild": reused, "uncommitted": [l[3:] for l in dirty]}
    if wait:
        r = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        res = _result(r.returncode, r.stderr)
        out.update({"result": res, "loomExit": r.returncode, "log": tail(r.stderr + r.stdout, 40)})
        return out
    log = _state(ctx) / f"propose-{time.strftime('%Y%m%dT%H%M%S')}-{tip[:12]}.log"
    fh = open(log, "w")
    p = subprocess.Popen(args, stdout=fh, stderr=subprocess.STDOUT, start_new_session=True)
    while True:
        time.sleep(1)
        text = log.read_text()
        if p.poll() is not None:
            res = _result(p.returncode, text)
            out.update({"result": res, "loomExit": p.returncode, "log": tail(text, 40)})
            return out
        if "waiting for approval" in text:
            out.update({"result": "waiting", "pid": p.pid, "logFile": str(log), "log": tail(text, 10)})
            return out


@handler("core", "propose")
def propose(ctx, a):
    out = do_propose(ctx, a.request, a.ref, wait=not a.no_wait)
    out["_exit"] = _code(out["result"])
    msg = {"applied": "Applied.", "denied": "The human denied it.", "rolled-back": "Applied, failed its health checks, rolled back.",
           "refused": "loom-switch refused it (no card).", "waiting": "The card is up; the human decides.",
           "failed": "The proposal failed."}[out["result"]]
    out["_text"] = msg + ("\n" + out["log"] if out.get("log") else "")
    if out.get("uncommitted"):
        out["_text"] += "\nnote: uncommitted changes are not part of the proposal: " + ", ".join(out["uncommitted"])
    return out


# ---------------------------------------------------------------- update


def _url_of(repo: Path, name: str):
    src = (repo / "flake.nix").read_bytes()
    tree = nixedit.parse(src)
    body = nixedit.module_body(tree)
    for path in (["inputs", name, "url"], ["inputs", name]):
        for m in nixedit.find(body, path):
            if m.kind == "value" and nixedit._unparen(m.value).type == "string_expression":
                return nixedit.literal_value(m.value), path
    return None, None


def _tag_of(url: str):
    m = re.search(r"[?&]ref=refs/tags/([^&]+)", url) or re.match(r"github:[^/]+/[^/]+/(v?\d[^/?]*)", url)
    return m.group(1) if m else None


def _locked(repo: Path, name: str):
    try:
        lock = json.loads((repo / "flake.lock").read_text())
        node = lock["nodes"][lock["nodes"][lock["root"]]["inputs"][name]]
        return node.get("locked", {}).get("rev") or node.get("locked", {}).get("narHash")
    except (OSError, KeyError, json.JSONDecodeError, TypeError):
        return None


@handler("core", "update")
def update(ctx, a):
    repo = ctx.repo()
    name = a.input
    url, path = _url_of(repo, name)
    if url is None:
        raise CliError(EXIT.USAGE, f"flake.nix has no input {name} with a literal url")
    before = _locked(repo, name)
    tag = _tag_of(url)
    frm, to = tag or (before or "")[:12], None
    edits = []
    if tag:
        tags = _tags(url)
        if not tags:
            raise CliError(EXIT.RETRY, f"couldn't list the tags of {url} (offline?)")
        newest = tags[-1]
        if newest != tag:
            new_url = url.replace(f"refs/tags/{tag}", f"refs/tags/{newest}") if "refs/tags/" in url else url.replace(f"/{tag}", f"/{newest}")
            fe = FileEdit(repo / "flake.nix")
            fe.apply(lambda t, s: nixedit.replace_value(s, [m for m in nixedit.find(nixedit.module_body(t), path) if m.kind == "value"][0], new_url))
            edits.append(fe)
        to = newest
    r = run(["nix", "flake", "update", name], cwd=str(repo), env=nix_env(), timeout=1800)
    if r.returncode != 0:
        for e in edits:
            e.revert()
        raise CliError(EXIT.RETRY if offline(r.stderr) else EXIT.FAILED, "nix flake update: " + tail(r.stderr, 20))
    after = _locked(repo, name)
    changed = after != before
    to = to or (after or "")[:12]
    out = {"input": name, "from": frm, "to": to, "changed": changed, "proposed": False}
    if not changed:
        out["_text"] = f"{name} is up to date ({frm})"
        return out
    ctx.git("add", "flake.nix", "flake.lock")
    ctx.git("commit", "-q", "-m", f"update: {name} {frm} → {to}")
    out["commit"] = ctx.git("rev-parse", "HEAD")
    if a.no_propose:
        out["_text"] = f"committed update: {name} {frm} → {to}; propose with omanix propose"
        return out
    p = do_propose(ctx, f"Update {name} to {to}")
    out.update({"proposed": True, "result": p["result"], "log": p.get("log")})
    out["_exit"] = _code(p["result"])
    out["_text"] = f"update: {name} {frm} → {to}: {p['result']}"
    return out
