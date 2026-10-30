"""Human-session verbs (try, reset, edit, intent, repo) and the resident's
side of `omanix try`."""

from __future__ import annotations

import json
import os
import socket
from pathlib import Path

from . import handler
from . import preview
from .common import CliError, EXIT, run, tail


def _agent_refuses(ctx, what: str):
    if ctx.is_agent:
        raise CliError(EXIT.USAGE, f"{what} runs in the human's session; you can't reach it (ask the human, or use the chat chip)")


def _omarchy() -> str:
    return os.environ.get("OMARCHY_PATH", "/run/current-system/omarchy")


# ---------------------------------------------------------------- try


def _ctl(ctx) -> str:
    agent = ctx.cfg.get("agent") or ctx.user
    return f"/run/loom/chat/{agent}.ctl"


def _send_ctl(path: str, msg: dict) -> dict:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10)
    try:
        s.connect(path)
        s.sendall((json.dumps(msg) + "\n").encode())
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        return json.loads(buf.decode() or "{}")
    finally:
        s.close()


@handler("core", "try")
def try_(ctx, a):
    cat = preview.load_allowlist(ctx.catalog)
    if a.reset:
        if ctx.is_agent:
            msg = {"t": "preview-request", "reset": True}
        else:
            preview.reset()
            return {"path": None, "delivered": True, "reset": True, "_text": "previews reverted"}
    else:
        if not a.path or a.value is None:
            raise CliError(EXIT.USAGE, "omanix try <path> <json value> (or --reset)")
        try:
            value = json.loads(a.value)
        except json.JSONDecodeError:
            raise CliError(EXIT.USAGE, f"the value must be JSON: {a.value}")
        try:
            rendered = preview.validate(cat, a.path, value)
        except preview.Refused as e:
            raise CliError(EXIT.USAGE, str(e))
        if not ctx.is_agent:
            # The human previews directly; nothing to allow.
            try:
                preview.apply(cat, a.path, value)
            except preview.Refused as e:
                raise CliError(EXIT.FAILED, str(e))
            return {"path": a.path, "value": value, "delivered": True, "rendered": rendered,
                    "_text": f"previewing {rendered['label']} (omanix try --reset reverts)"}
        msg = {"t": "preview-request", "path": a.path, "value": value}
    # The resident has no Wayland access: the bridge relays the request to
    # the chat panel, which validates it again and asks the human (§h.6).
    try:
        reply = _send_ctl(_ctl(ctx), msg)
    except OSError as e:
        raise CliError(EXIT.RETRY, f"the chat panel isn't reachable ({e})")
    if not reply.get("ok"):
        raise CliError(EXIT.RETRY, f"the bridge didn't take the preview: {reply.get('error')}", {"delivered": False})
    return {"path": a.path, "value": msg.get("value"), "delivered": bool(reply.get("delivered")),
            "_text": "the human sees the preview request" if reply.get("delivered") else "no chat panel is open; nothing shown"}


# ---------------------------------------------------------------- reset / edit / intent


@handler("core", "reset")
def reset(ctx, a):
    _agent_refuses(ctx, "omanix reset")
    targets = ["--all"] if a.all else a.targets
    if not targets:
        raise CliError(EXIT.USAGE, "omanix reset <area|overlay path>… | --all")
    r = run(["omanix-overlay", "reset", *targets], timeout=60)
    if r.returncode != 0:
        raise CliError(EXIT.USAGE if "unknown" in r.stderr else EXIT.FAILED, tail(r.stderr or r.stdout, 10))
    done = [l[len("reset "):] for l in r.stdout.splitlines() if l.startswith("reset ")]
    return {"reset": done, "_text": "\n".join(r.stdout.splitlines()) or "nothing to reset"}


def _home_target(ctx, path: str):
    home = str(ctx.home)
    p = os.path.expanduser(path)
    rel = p[len(home) + 1:] if p.startswith(home + "/") else path
    homej = ctx.catalog_json("home.json", {}) or {}
    files = homej.get("files", homej)
    if rel in files:
        return rel, files[rel]
    for k, v in files.items():
        if isinstance(v, dict) and v.get("overlay") and v["overlay"] == rel:
            return k, v
    return rel, None


@handler("core", "edit")
def edit(ctx, a):
    _agent_refuses(ctx, "omanix edit")
    rel, f = _home_target(ctx, a.path)
    ov_dir = Path(os.environ.get("XDG_STATE_HOME") or ctx.home / ".local/state") / "omanix/overlay"
    agent = ctx.cfg.get("agent")
    if f is None:
        out = {"path": a.path, "kind": "unknown", "open": None,
               "hint": "not a file omanix owns; edit it directly" + (f", or ask {agent}" if agent else "")}
        out["_text"] = out["hint"]
        out["_exit"] = EXIT.FAILED
        return out
    if f.get("overlay"):
        target = ov_dir / f["overlay"]
        if not target.exists():
            run(["omanix-overlay", "init"], timeout=60)
        out = {"path": a.path, "kind": "overlay", "file": rel, "open": str(target), "overlay": f["overlay"],
               "options": f.get("options", []), "module": f.get("module"),
               "_text": f"{rel} is read-only; opening its overlay {target} (this session; make it stick to keep it)"}
    else:
        out = {"path": a.path, "kind": "read-only", "file": rel, "open": str(ctx.home / rel),
               "options": f.get("options", []), "module": f.get("module"),
               "hint": "set " + (", ".join(f.get("options") or []) or f"the option in modules/omanix/{f.get('module')}")
               + " in the host repo (omanix repo open)" + (f", or ask {agent}" if agent else ""),
               "_text": ""}
        out["_text"] = f"{rel} is read-only (home-manager). To change it: {out['hint']}"
    if not a.print:
        if out["kind"] == "read-only":
            run(["omarchy-notification-send", "-u", "low", "Read-only file", out["hint"]], timeout=10)
        r = run(["omarchy-launch-editor", out["open"]], capture=False)
        out["launched"] = r.returncode == 0
    return out


@handler("core", "intent")
def intent(ctx, a):
    _agent_refuses(ctx, "omanix intent")
    try:
        intents = json.loads((Path(_omarchy()) / "default/omanix/intents.json").read_text())
    except (OSError, json.JSONDecodeError):
        raise CliError(EXIT.FAILED, "intents.json is missing ($OMARCHY_PATH/default/omanix/intents.json)")
    if a.id not in intents:
        raise CliError(EXIT.USAGE, f"no intent {a.id!r}")
    e = intents[a.id]
    r = run(["omarchy-shell", "omanix.chat", "intent", a.id], timeout=20)
    if r.returncode != 0:
        raise CliError(EXIT.RETRY, "the shell isn't running: " + tail(r.stderr, 5))
    return {"id": a.id, "text": e.get("text"), "skill": e.get("skill"), "reply": r.stdout.strip(),
            "_text": f"composer: {e.get('text')}"}


# ---------------------------------------------------------------- repo


def ensure_repo(ctx, create: bool) -> tuple[Path, bool]:
    p = ctx.default_repo() if not ctx._repo else Path(ctx._repo).expanduser()
    if (p / ".git").exists() or not create:
        return p, False
    r = run(["git", "-c", "safe.directory=*", "clone", "-q", ctx.mirror, str(p)], timeout=300)
    if r.returncode != 0:
        raise CliError(EXIT.FAILED, f"couldn't clone the host repo from {ctx.mirror}: {tail(r.stderr, 5)}")
    run(["git", "-C", str(p), "remote", "rename", "origin", "mirror"])
    url = ctx.cfg.get("fetchUrl")
    if url:
        run(["git", "-C", str(p), "remote", "add", "origin", url])
        if ctx.cfg.get("pushUrl"):
            run(["git", "-C", str(p), "remote", "set-url", "--push", "origin", ctx.cfg["pushUrl"]])
    return p, True


@handler("repo", "path")
def repo_path(ctx, a):
    p, created = ensure_repo(ctx, a.ensure)
    return {"path": str(p), "exists": (p / ".git").exists(), "created": created, "_text": str(p)}


@handler("repo", "open")
def repo_open(ctx, a):
    if ctx.is_agent:
        raise CliError(EXIT.USAGE, "your working copy is ~/projects/host; repo open is the human's")
    p, created = ensure_repo(ctx, True)
    target = p
    line = None
    if a.file:
        cand = p / a.file
        if cand.exists():
            target = cand
        elif "." in a.file and "/" not in a.file:
            from .cmd_info import resolve
            ctx._repo = str(p)
            try:
                w = resolve(ctx, a.file)
                hd = [d for d in w["definitions"] if d["origin"]["kind"] == "host"]
                if hd:
                    target, line = p / hd[0]["file"], hd[0].get("line")
                else:
                    target = p / ("home.nix" if w.get("hm") else "configuration.nix")
            except CliError:
                target = p / "configuration.nix"
        else:
            raise CliError(EXIT.USAGE, f"no file {a.file} in {p}")
    out = {"path": str(p), "created": created, "open": str(target), "line": line,
           "_text": f"{target}" + (f":{line}" if line else "")}
    if not a.print:
        args = ["omarchy-launch-editor", str(target)]
        r = run(args, capture=False)
        out["launched"] = r.returncode == 0
    return out
