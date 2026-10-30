"""Shared plumbing: the host config (/etc/omanix/cli.json), the working
copy, `nix eval` of it, output and exit codes."""

from __future__ import annotations

import argparse
import json
import os
import pwd
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = os.environ.get("OMANIX_CLI_CONFIG", "/etc/omanix/cli.json")


class EXIT:
    OK = 0
    FAILED = 1
    USAGE = 2
    APPROVAL = 3
    ROLLED_BACK = 4
    RETRY = 5


class CliError(Exception):
    def __init__(self, code: int, message: str, data: dict | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.data = data or {}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise CliError(EXIT.USAGE, f"{self.prog}: {message}")


def registry() -> dict:
    """commands.json: the package's own, or the host's (with extension
    commands from omanix.cli.commands) when cli.json names one."""
    cfg = load_config()
    path = cfg.get("commands") or os.environ.get("OMANIX_COMMANDS_JSON")
    for p in [path, HERE / "commands.json", HERE.parent / "commands.json"]:
        if p and Path(p).exists():
            return json.loads(Path(p).read_text())
    raise SystemExit("omanix: commands.json is missing")


_CFG: dict | None = None


def load_config() -> dict:
    global _CFG
    if _CFG is None:
        try:
            _CFG = json.loads(Path(CONFIG).read_text())
        except (OSError, json.JSONDecodeError):
            _CFG = {}
        # loom's switch path: the mirror and the switch records.
        try:
            sw = json.loads(Path(os.environ.get("LOOM_SWITCH_CONFIG", "/etc/loom/switch.json")).read_text())
            _CFG.setdefault("mirror", sw.get("mirror"))
            _CFG.setdefault("recordsDir", sw.get("recordsDir"))
        except (OSError, json.JSONDecodeError):
            pass
    return _CFG


def emit(ctx, data: dict, code: int) -> None:
    if ctx.json:
        doc = {"ok": code == EXIT.OK, "command": ctx.cmd, "exit": code}
        doc.update({k: v for k, v in data.items() if not k.startswith("_")})
        print(json.dumps(doc, indent=2, ensure_ascii=False, default=str))
    else:
        text = data.pop("_text", None) if isinstance(data, dict) else None
        if text is None:
            text = human(data)
        if text:
            print(text)


def human(d, indent: int = 0) -> str:
    pad = "  " * indent
    if isinstance(d, dict):
        out = []
        for k, v in d.items():
            if k.startswith("_"):
                continue
            if isinstance(v, (dict, list)) and v:
                out.append(f"{pad}{k}:")
                out.append(human(v, indent + 1))
            else:
                out.append(f"{pad}{k}: {json.dumps(v) if not isinstance(v, str) else v}")
        return "\n".join(x for x in out if x)
    if isinstance(d, list):
        return "\n".join(f"{pad}- {json.dumps(x, ensure_ascii=False) if not isinstance(x, str) else x}" for x in d)
    return f"{pad}{d}"


def emit_error(as_json: bool, cmd: str, code: int, message: str, data: dict | None = None) -> None:
    if as_json:
        doc = {"ok": False, "command": cmd, "exit": code, "error": message}
        doc.update(data or {})
        print(json.dumps(doc, indent=2, ensure_ascii=False, default=str))
    else:
        print(f"omanix {cmd}: {message}" if not message.startswith("omanix") else message, file=sys.stderr)


def run(args, cwd=None, check=False, input=None, env=None, timeout=None, capture=True, soft=False):
    """subprocess.run; soft=True turns a missing program into a failed run."""
    if soft and shutil.which(args[0]) is None:
        return subprocess.CompletedProcess(args, 127, "", f"{args[0]}: not installed")
    try:
        return subprocess.run(args, cwd=cwd, input=input, text=True, env=env, timeout=timeout,
                              capture_output=capture, check=check)
    except FileNotFoundError as e:
        raise CliError(EXIT.FAILED, f"{args[0]} is not installed ({e})")
    except subprocess.TimeoutExpired:
        raise CliError(EXIT.RETRY, f"{args[0]} timed out")


def nix_env() -> dict:
    env = dict(os.environ)
    extra = "experimental-features = nix-command flakes\nallow-import-from-derivation = false"
    env["NIX_CONFIG"] = (env.get("NIX_CONFIG", "") + "\n" + extra).strip()
    return env


def offline(stderr: str) -> bool:
    s = stderr.lower()
    return any(x in s for x in ("unable to download", "could not resolve host", "couldn't resolve host",
                                "network is unreachable", "failed to connect", "temporary failure in name resolution",
                                "connection refused", "unable to access 'http", "timed out"))


class Ctx:
    def __init__(self, args, cmd: str):
        self.args = args
        self.cmd = cmd
        self.json = bool(getattr(args, "json", False))
        self.cfg = load_config()
        self.uid = os.getuid()
        self.user = pwd.getpwuid(self.uid).pw_name
        self.home = Path(os.environ.get("HOME") or pwd.getpwuid(self.uid).pw_dir)
        self._repo = getattr(args, "repo", None) or os.environ.get("OMANIX_HOST_REPO")
        self._info = None

    # ---- who and where --------------------------------------------------
    @property
    def is_agent(self) -> bool:
        return self.uid in self.cfg.get("agentUids", [])

    @property
    def catalog(self) -> Path:
        return Path(os.environ.get("OMANIX_CATALOG") or self.cfg.get("catalog") or "/run/current-system/sw/share/omanix/catalog")

    def catalog_json(self, rel: str, default=None):
        try:
            return json.loads((self.catalog / rel).read_text())
        except (OSError, json.JSONDecodeError):
            return default

    def default_repo(self) -> Path:
        if self.is_agent:
            return self.home / "projects/host"
        return self.home / (self.cfg.get("humanRepo") or "omanix-host")

    def repo(self, must=True) -> Path:
        if self._repo:
            p = Path(self._repo).expanduser().resolve()
        else:
            r = run(["git", "rev-parse", "--show-toplevel"])
            top = Path(r.stdout.strip()) if r.returncode == 0 else None
            if top and (top / "flake.nix").exists() and (top / "configuration.nix").exists():
                p = top
            else:
                p = self.default_repo()
        if must and not (p / "flake.nix").exists():
            hint = "omanix repo path --ensure" if not self.is_agent else "clone it from the mirror"
            raise CliError(EXIT.FAILED, f"no host repo working copy at {p} ({hint})")
        return p

    def git(self, *args, check=True, repo=None):
        r = run(["git", "-c", "safe.directory=*", "-C", str(repo or self.repo()), *args])
        if check and r.returncode != 0:
            raise CliError(EXIT.FAILED, f"git {' '.join(args)}: {r.stderr.strip()}")
        return r.stdout.strip()

    @property
    def mirror(self) -> str:
        return self.cfg.get("mirror") or "/persist/var/lib/loom/host"

    def deployed(self) -> str | None:
        r = run(["git", "-c", "safe.directory=*", "-C", self.mirror, "rev-parse", "--verify", "-q", "refs/heads/master"])
        return r.stdout.strip() or None if r.returncode == 0 else None

    # ---- evaluation ------------------------------------------------------
    def flakeref(self) -> str:
        return f"git+file://{self.repo()}"

    def nix_eval(self, req: dict, timeout: int = 900):
        """Run eval.nix against nixosConfigurations.host of the working copy."""
        expr = (HERE / "eval.nix").read_text()
        reqs = json.dumps(req).replace("\\", "\\\\").replace('"', '\\"').replace("${", "\\${")
        apply = f'h: ({expr}) {{ host = h; req = builtins.fromJSON "{reqs}"; }}'
        attr = self.cfg.get("hostAttr", "nixosConfigurations.host")
        r = run(["nix", "eval", "--json", "--no-write-lock-file", f"{self.flakeref()}#{attr}", "--apply", apply],
                env=nix_env(), timeout=timeout)
        if r.returncode != 0:
            err = r.stderr.strip()
            code = EXIT.RETRY if offline(err) else EXIT.FAILED
            raise CliError(code, "the working copy doesn't evaluate:\n" + tail(err, 60), {"evalError": tail(err, 60)})
        return json.loads(r.stdout)

    def info(self) -> dict:
        if self._info is None:
            self._info = self.nix_eval({"op": "info"})
        return self._info

    def runtime(self) -> dict | None:
        p = self.cfg.get("runtimeJson") or f"/run/omanix/session/{self.cfg.get('humanUid', 1000)}/runtime.json"
        try:
            return json.loads(Path(os.environ.get("OMANIX_RUNTIME_JSON", p)).read_text())
        except (OSError, json.JSONDecodeError):
            return None


def tail(text: str, n: int) -> str:
    lines = text.strip().splitlines()
    return "\n".join(lines[-n:])


def which(cmd: str) -> str | None:
    return shutil.which(cmd)


def split_path(s: str) -> list[str]:
    """omanix.apps.webapps."My App".url → ['omanix','apps','webapps','My App','url']"""
    out, cur, q = [], "", False
    i = 0
    while i < len(s):
        c = s[i]
        if c == '"':
            q = not q
        elif c == "." and not q:
            out.append(cur)
            cur = ""
        else:
            cur += c
        i += 1
    out.append(cur)
    if q or any(p == "" for p in out):
        raise CliError(EXIT.USAGE, f"not an option path: {s}")
    return out


def option_hm(path: list[str]) -> tuple[list[str], bool]:
    """(path inside its module, is it the human's HM config)."""
    if len(path) > 3 and path[0] == "home-manager" and path[1] == "users":
        return path[3:], True
    if path and path[0] == "home":
        return path, True
    return path, False
