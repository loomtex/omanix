"""Verbs that edit the working copy: set, unset, app, persist, plugin,
secret, hw probe. Each edits files and checks the result by evaluating
it; none commits, builds or switches (§h.8)."""

from __future__ import annotations

import getpass
import json
import os
import re
import sys
from pathlib import Path

from . import handler
from . import nixedit
from .cmd_info import resolve, shadowed_by
from .common import CliError, EXIT, run, split_path, option_hm, nix_env, offline, tail


# ---------------------------------------------------------------- file edits


def nixfmt_clean(path: Path) -> bool:
    r = run(["nixfmt", "--check", str(path)])
    return r.returncode == 0


class FileEdit:
    """Edit one file; format with nixfmt only if it was nixfmt-clean
    before (so a hand-formatted file isn't reflowed); revert on demand."""

    def __init__(self, path: Path):
        self.path = path
        self.old = path.read_bytes() if path.exists() else None
        self.formatted = False

    def apply(self, fn):
        src = self.old if self.old is not None else b""
        tree = nixedit.parse(src)
        new = fn(tree, src)
        if new == src:
            return False
        nixedit.parse(new)          # still parses
        clean = self.old is not None and nixfmt_clean(self.path)
        self.path.write_bytes(new)
        if clean:
            r = run(["nixfmt", str(self.path)])
            self.formatted = r.returncode == 0
        return True

    def revert(self):
        if self.old is None:
            self.path.unlink(missing_ok=True)
        else:
            self.path.write_bytes(self.old)


def _parse_value(text: str):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        raise CliError(EXIT.USAGE, f"the value must be JSON (strings in quotes): {text}")


def _host_defs(w):
    return [d for d in w["definitions"] if d["origin"]["kind"] == "host"]


def _guard(w, path: str):
    if w["kind"] == "missing":
        raise CliError(EXIT.FAILED, f"there is no option {path} (search: omanix options <words>)")
    if w["kind"] == "group":
        raise CliError(EXIT.USAGE, f"{path} is a group of options; set one of: {', '.join(w.get('children', []))}")
    if w.get("readOnly"):
        raise CliError(EXIT.USAGE, f"{path} is read-only (computed by its module)")
    hd = _host_defs(w)
    bad = [d for d in hd if not d.get("editable")]
    if len(hd) > 1 or bad:
        where = [{"where": d.get("where"), "note": d.get("note")} for d in hd]
        raise CliError(EXIT.USAGE, f"{path} is defined in {len(hd)} host place(s) that aren't one literal; edit by hand:\n"
                       + "\n".join(f"  {d['where']}" + (f" ({d['note']})" if d.get("note") else "") for d in hd),
                       {"definitions": where})
    return hd


def _same(a, b) -> bool:
    if isinstance(a, float) or isinstance(b, float):
        try:
            return float(a) == float(b)
        except (TypeError, ValueError):
            return False
    return a == b


def set_value(ctx, path_s: str, value, *, unset: bool = False) -> dict:
    path = split_path(path_s)
    inner, hm = option_hm(path)
    repo = ctx.repo()
    w = resolve(ctx, path_s)
    hd = _guard(w, path_s)
    if unset:
        if not hd:
            return {"path": path_s, "action": "unchanged", "file": None, "line": None, "value": w.get("value")}
        d = hd[0]
        fe = FileEdit(repo / d["file"])
        def fn(tree, src):
            ms = [m for m in nixedit.find_in_module(tree, inner) if m.kind == "value"]
            return nixedit.delete_binding(src, ms[0])
        fe.apply(fn)
        after = ctx.nix_eval({"op": "value", "paths": [inner], "hm": hm})
        return {"path": path_s, "action": "deleted", "file": d["file"], "line": d.get("line"),
                "formatted": fe.formatted, "value": after.get(".".join(inner))}

    if hd:
        d = hd[0]
        rel = d["file"]
        if _same(d.get("value"), value) and _same(w.get("value"), value):
            return {"path": path_s, "value": value, "action": "unchanged", "file": rel, "line": d.get("line"),
                    "shadowedBy": shadowed_by(path_s, ctx.runtime())}
        fe = FileEdit(repo / rel)
        def fn(tree, src):
            ms = [m for m in nixedit.find_in_module(tree, inner) if m.kind == "value"]
            return nixedit.replace_value(src, ms[0], value)
        action = "rewrote"
    else:
        rel = "home.nix" if hm else "configuration.nix"
        fe = FileEdit(repo / rel)
        def fn(tree, src):
            return nixedit.insert_path(tree, src, inner, value)
        action = "appended"
    try:
        fe.apply(fn)
    except nixedit.EditError as e:
        raise CliError(EXIT.USAGE, f"{rel}: {e}; edit by hand")
    # Evaluate; a mismatch means something else wins: put the file back.
    try:
        after = ctx.nix_eval({"op": "value", "paths": [inner], "hm": hm})
    except CliError as e:
        fe.revert()
        raise CliError(EXIT.FAILED, f"after the edit the host doesn't evaluate; reverted {rel}.\n{e.message}")
    got = after.get(".".join(inner))
    if got == "<error>":
        # say why: evaluate it plainly for the message
        full = (["home-manager", "users", ctx.info().get("user") or "_"] if hm else []) + inner
        attr = ctx.cfg.get("hostAttr", "nixosConfigurations.host") + ".config." + nixedit.attrpath(full)
        r = run(["nix", "eval", "--json", "--no-write-lock-file", f"{ctx.flakeref()}#{attr}"], env=nix_env(), timeout=900)
        fe.revert()
        raise CliError(EXIT.FAILED, f"{path_s} doesn't evaluate with {json.dumps(value)}; reverted {rel}:\n" + tail(r.stderr, 15))
    if not _same(got, value):
        fe.revert()
        others = [x for x in w["definitions"] if x["origin"]["kind"] != "host"]
        raise CliError(EXIT.FAILED,
                       f"{path_s} evaluates to {json.dumps(got)} after the edit, not {json.dumps(value)}; reverted {rel}. "
                       "Winning definition(s): " + ", ".join(f"{x['where']} (prio {x.get('priority')})" for x in others),
                       {"evaluated": got, "definitions": others})
    line = None
    try:
        tree = nixedit.parse((repo / rel).read_bytes())
        ms = nixedit.find_in_module(tree, inner)
        line = ms[0].line if ms else None
    except nixedit.EditError:
        pass
    return {"path": path_s, "value": value, "action": action, "file": rel, "line": line, "formatted": fe.formatted,
            "shadowedBy": shadowed_by(path_s, ctx.runtime())}


@handler("core", "set")
def cmd_set(ctx, a):
    out = set_value(ctx, a.path, _parse_value(a.value))
    sh = out["shadowedBy"]
    out["_text"] = (f"{out['action']} {out['path']} = {json.dumps(out['value'])} in {out['file']}"
                    + (f":{out['line']}" if out.get("line") else "")
                    + ("".join(f"\nnote: {s.get('overlay') or s.get('key')} overrides it in the running session ({s.get('clear', '')})" for s in sh)))
    return out


@handler("core", "unset")
def cmd_unset(ctx, a):
    out = set_value(ctx, a.path, None, unset=True)
    out["_text"] = f"{out['action']} {out['path']}" + (f" in {out['file']}" if out.get("file") else "")
    return out


# ---------------------------------------------------------------- app


def _pkg_check(ctx, attr: str):
    if not re.fullmatch(r"[A-Za-z0-9_+.-]+", attr):
        raise CliError(EXIT.USAGE, f"not a package attribute: {attr}")
    r = run(["nix", "eval", "--json", "--no-write-lock-file", f"{ctx.flakeref()}#nixosConfigurations.host.pkgs.{attr}.meta.mainProgram"],
            env=nix_env(), timeout=600)
    if r.returncode != 0:
        if "does not provide attribute" in r.stderr or "missing attribute" in r.stderr or "attribute '" in r.stderr and "missing" in r.stderr:
            r2 = run(["nix", "eval", "--json", "--no-write-lock-file", f"{ctx.flakeref()}#nixosConfigurations.host.pkgs.{attr}.name"],
                     env=nix_env(), timeout=600)
            if r2.returncode == 0:
                return None
            raise CliError(EXIT.FAILED, f"nixpkgs has no package {attr}")
        raise CliError(EXIT.RETRY if offline(r.stderr) else EXIT.FAILED, tail(r.stderr, 20))
    return json.loads(r.stdout)


def _home_packages(ctx, attr: str, remove: bool = False):
    repo = ctx.repo()
    fe = FileEdit(repo / "home.nix")
    def fn(tree, src):
        body = nixedit.module_body(tree)
        ms = [m for m in nixedit.find(body, ["home", "packages"]) if m.kind == "value"]
        if not ms:
            if remove:
                raise nixedit.EditError("home.packages isn't set in home.nix")
            return nixedit.insert_path(tree, src, ["home", "packages"], nixedit.Raw(f"[ pkgs.{attr} ]"))
        lst = nixedit.list_node(ms[0].value)
        if lst is None:
            raise nixedit.EditError("home.packages isn't a list literal")
        withp = nixedit._unparen(ms[0].value).type == "with_expression"
        el = attr if withp else f"pkgs.{attr}"
        elems = nixedit.list_elements(lst)
        if remove:
            for cand in (el, attr, f"pkgs.{attr}"):
                if cand in elems:
                    return nixedit.list_remove(src, lst, cand)
            raise nixedit.EditError(f"{attr} isn't in home.packages")
        if el in elems or f"pkgs.{attr}" in elems:
            return src
        return nixedit.list_append(src, lst, el)
    try:
        changed = fe.apply(fn)
    except nixedit.EditError as e:
        raise CliError(EXIT.USAGE, f"home.nix: {e}; edit by hand")
    try:
        ctx.nix_eval({"op": "value", "paths": [["home", "packages"]], "hm": True})
    except CliError as e:
        fe.revert()
        raise CliError(EXIT.FAILED, "after the edit the host doesn't evaluate; reverted home.nix.\n" + e.message)
    return changed


def _omarchy_apps(ctx) -> dict:
    apps = ctx.catalog_json("apps.json", {}) or {}
    return apps.get("apps", apps)


@handler("app", "add")
def app_add(ctx, a):
    name = a.name
    if a.url:
        v = {"url": a.url, **({"icon": a.icon} if a.icon else {})}
        out = set_value(ctx, f'omanix.apps.webapps."{name}"' if not nixedit.IDENT.match(name) else f"omanix.apps.webapps.{name}", v)
        return {"name": name, "kind": "webapp", "path": out["path"], "file": out["file"], "_text": f"web app {name} → {out['file']}"}
    if a.command:
        v = {"command": a.command, **({"icon": a.icon} if a.icon else {})}
        out = set_value(ctx, f"omanix.apps.tuis.{name}", v)
        return {"name": name, "kind": "tui", "path": out["path"], "file": out["file"], "_text": f"TUI {name} → {out['file']}"}
    apps = _omarchy_apps(ctx)
    if name in apps:
        out = set_value(ctx, f"omanix.apps.{name}.enable", True)
        return {"name": name, "kind": "omarchy", "path": out["path"], "file": out["file"], "_text": f"omanix.apps.{name}.enable = true in {out['file']}"}
    main = _pkg_check(ctx, name)
    changed = _home_packages(ctx, name)
    return {"name": name, "kind": "package", "path": "home.packages", "file": "home.nix", "mainProgram": main, "changed": changed,
            "_text": f"home.packages += {name} (home.nix)" + (f"; run it as `{main}`" if main else "")}


@handler("app", "remove")
def app_remove(ctx, a):
    name = a.name
    apps = _omarchy_apps(ctx)
    for kind, base in (("webapp", "omanix.apps.webapps"), ("tui", "omanix.apps.tuis")):
        try:
            w = resolve(ctx, f"{base}.{name}")
        except CliError:
            continue
        if any(d["origin"]["kind"] == "host" for d in w["definitions"]):
            out = set_value(ctx, f"{base}.{name}", None, unset=True)
            return {"name": name, "kind": kind, "file": out["file"], "_text": f"removed {kind} {name} from {out['file']}"}
    if name in apps:
        p = f"omanix.apps.{name}.enable"
        out = set_value(ctx, p, None, unset=True)
        if out.get("value") is not False:
            out = set_value(ctx, p, False)
        return {"name": name, "kind": "omarchy", "file": out["file"], "_text": f"{p} = false"}
    _home_packages(ctx, name, remove=True)
    return {"name": name, "kind": "package", "file": "home.nix", "_text": f"home.packages -= {name}"}


# ---------------------------------------------------------------- persist


@handler("persist", "add")
def persist_add(ctx, a):
    p = a.path.rstrip("/") or "/"
    if not p.startswith("/") or ".." in p.split("/"):
        raise CliError(EXIT.USAGE, f"not an absolute path: {a.path}")
    repo = ctx.repo()
    kind = "files" if a.file else "directories"
    fe = FileEdit(repo / "modules/persist.nix")
    path = ["loom", "persist", "system", kind]
    def fn(tree, src):
        body = nixedit.module_body(tree)
        ms = [m for m in nixedit.find(body, path) if m.kind == "value"]
        if ms:
            lst = nixedit.list_node(ms[0].value)
            if lst is None:
                raise nixedit.EditError(f"{'.'.join(path)} isn't a list literal")
            if nixedit.nix_string(p) in nixedit.list_elements(lst):
                return src
            return nixedit.list_append(src, lst, nixedit.nix_string(p))
        return nixedit.insert_path(tree, src, path, [p])
    try:
        changed = fe.apply(fn)
    except nixedit.EditError as e:
        raise CliError(EXIT.USAGE, f"modules/persist.nix: {e}; edit by hand")
    return {"path": p, "file": "modules/persist.nix", "kind": kind, "changed": changed,
            "_text": (f"loom.persist.system.{kind} += {p} (modules/persist.nix)" if changed else f"{p} is already persisted")}


def _persisted(ctx) -> list[str]:
    pj = ctx.catalog_json("persist.json", {}) or {}
    return list(pj.get("system", {}).get("directories", [])) + list(pj.get("system", {}).get("files", [])) \
        + list(pj.get("ephemeralOk", []))


@handler("persist", "audit")
def persist_audit(ctx, a):
    r = run(["findmnt", "-n", "-o", "FSTYPE", "/"])
    fstype = r.stdout.strip()
    covered = _persisted(ctx)
    def is_covered(p):
        return any(p == c or p.startswith(c.rstrip("/") + "/") for c in covered)
    found = []
    roots = ["/var/lib", "/etc"]
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            if any(x in dirpath for x in ("/etc/static", "/var/lib/nixos")):
                dirnames[:] = []
                continue
            for n in list(dirnames):
                full = os.path.join(dirpath, n)
                if os.path.ismount(full) or is_covered(full):
                    dirnames.remove(n)
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                if os.path.islink(full) or is_covered(full):
                    continue
                try:
                    if os.path.realpath(full).startswith("/nix/store/"):
                        continue
                except OSError:
                    continue
                found.append(full)
            if len(found) > 2000:
                break
    units = {}
    for f in found:
        m = re.match(r"/var/lib/(?:private/)?([^/]+)", f)
        if m:
            units.setdefault(m.group(1), []).append(f)
    uncovered = [{"path": f"/var/lib/{k}", "files": len(v), "persist": f"omanix persist add /var/lib/{k}"} for k, v in sorted(units.items())]
    uncovered += [{"path": f, "files": 1, "persist": f"omanix persist add --file {f}"} for f in found if f.startswith("/etc/")][:100]
    return {"root": fstype or "unknown", "uncovered": uncovered,
            "_text": (f"/ is {fstype}; " + (f"{len(uncovered)} uncovered:\n" + "\n".join(f"  {u['path']} ({u['files']} files): {u['persist']}" for u in uncovered)
                                            if uncovered else "everything written is persisted"))}


# ---------------------------------------------------------------- secret


@handler("secret", "set")
def secret_set(ctx, a):
    if ctx.is_agent:
        raise CliError(EXIT.USAGE, "secret values never pass through an agent: ask the human to run "
                       f"`omanix secret set {a.file} {a.name}` in their terminal (it reads the value without echoing it)")
    f = a.file[:-5] if a.file.endswith(".yaml") else a.file
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", f) or not re.fullmatch(r"[A-Za-z0-9_.-]+", a.name):
        raise CliError(EXIT.USAGE, "file and name: letters, digits, '-', '_' and '.' only")
    if sys.stdin.isatty():
        if ctx.json:
            raise CliError(EXIT.USAGE, "--json: pipe the value on stdin")
        value = getpass.getpass(f"value for {a.name} (not shown): ")
    else:
        value = sys.stdin.read()
        if value.endswith("\n"):
            value = value[:-1]
    if not value:
        raise CliError(EXIT.USAGE, "empty value")
    repo = ctx.repo()
    rel = f"secrets/{f}.yaml"
    path = repo / rel
    if not (repo / ".sops.yaml").exists():
        raise CliError(EXIT.FAILED, ".sops.yaml is missing (loom keys sync writes it)")
    created = not path.exists()
    if created:
        path.parent.mkdir(parents=True, exist_ok=True)
        r = run(["sops", "encrypt", "--input-type", "json", "--output-type", "yaml", "--filename-override", rel,
                 "--output", rel, "/dev/stdin"], cwd=str(repo), input=json.dumps({a.name: value}))
    else:
        r = run(["sops", "set", "--value-stdin", rel, json.dumps([a.name])], cwd=str(repo), input=json.dumps(value))
    del value
    if r.returncode != 0:
        if not created and ("decrypt" in r.stderr.lower() or "no key" in r.stderr.lower() or "failed to get the data key" in r.stderr.lower()):
            raise CliError(EXIT.FAILED, f"{rel} exists and none of your keys can open it to add {a.name} "
                           "(sops re-encrypts the whole file). Put it in a new file, or run this where your age key is.")
        raise CliError(EXIT.FAILED, f"sops: {tail(r.stderr, 10)}")
    return {"file": rel, "name": a.name, "created": created,
            "_text": f"{'created' if created else 'updated'} {rel}: {a.name} (encrypted). Commit it, then propose."}


# ---------------------------------------------------------------- hw


@handler("hw", "probe")
def hw_probe(ctx, a):
    r = run(["omanix-hw-probe", "--json", *(["--all"] if a.all else [])], timeout=60)
    if r.returncode != 0:
        raise CliError(EXIT.FAILED, tail(r.stderr, 20))
    quirks = json.loads(r.stdout).get("quirks", [])
    written = []
    if a.write:
        repo = ctx.repo()
        fe = FileEdit(repo / "hardware.nix")
        def fn(tree, src):
            for q in quirks:
                path = ["omanix", "hardware", "quirks", q, "enable"]
                if not [m for m in nixedit.find_in_module(tree, path) if m.kind == "value"]:
                    src = nixedit.insert_path(tree, src, path, True)
                    tree = nixedit.parse(src)
                    written.append(q)
            return src
        try:
            fe.apply(fn)
        except nixedit.EditError as e:
            raise CliError(EXIT.USAGE, f"hardware.nix: {e}; edit by hand")
    return {"quirks": quirks, "written": written,
            "_text": ("quirks: " + (", ".join(quirks) or "none")) + (f"\nenabled in hardware.nix: {', '.join(written)}" if written else "")}


# ---------------------------------------------------------------- plugin


def _flake_json(args, ctx=None, timeout=300):
    r = run(["nix", *args], env=nix_env(), timeout=timeout)
    if r.returncode != 0:
        raise CliError(EXIT.RETRY if offline(r.stderr) else EXIT.FAILED, tail(r.stderr, 20))
    return json.loads(r.stdout)


def _remote_url(ref: str) -> str | None:
    m = re.match(r"github:([^/]+)/([^/?#]+)", ref)
    if m:
        return f"https://github.com/{m.group(1)}/{m.group(2)}"
    m = re.match(r"git\+(.*?)(\?.*)?$", ref)
    if m:
        u = m.group(1)
        return u[len("file://"):] if u.startswith("file://") else u
    if ref.startswith("/") or ref.startswith("path:"):
        return ref.removeprefix("path:")
    return None


def _tags(ref: str) -> list[str]:
    url = _remote_url(ref)
    if not url:
        return []
    r = run(["git", "ls-remote", "--tags", "--refs", url], timeout=60)
    if r.returncode != 0:
        return []
    tags = [l.split("refs/tags/", 1)[1] for l in r.stdout.splitlines() if "refs/tags/" in l]
    def key(t):
        return [int(x) if x.isdigit() else -1 for x in re.findall(r"\d+|[A-Za-z]+", t)]
    return sorted(tags, key=key)


def _has_ref(ref: str) -> bool:
    return bool(re.match(r"github:[^/]+/[^/?]+/", ref)) or "ref=" in ref or "rev=" in ref


def _with_tag(ref: str, tag: str) -> str:
    if ref.startswith("github:"):
        return ref.rstrip("/") + "/" + tag
    sep = "&" if "?" in ref else "?"
    return f"{ref}{sep}ref=refs/tags/{tag}"


def _owner(ref: str) -> str | None:
    m = re.match(r"github:([^/]+)/", ref)
    if m:
        return "github:" + m.group(1).lower()
    m = re.match(r"git\+\w+://(?:[^@/]+@)?([^/]+)/([^/]+)/", ref)
    if m:
        return f"{m.group(1)}/{m.group(2)}".lower()
    return None


def _lock_owners(repo: Path) -> set[str]:
    try:
        lock = json.loads((repo / "flake.lock").read_text())
    except (OSError, json.JSONDecodeError):
        return set()
    out = set()
    for n in lock["nodes"].values():
        o = n.get("original") or {}
        if o.get("type") == "github":
            out.add("github:" + o.get("owner", "").lower())
        elif o.get("url"):
            m = re.match(r"\w+://(?:[^@/]+@)?([^/]+)/([^/]+)/", o["url"])
            if m:
                out.add(f"{m.group(1)}/{m.group(2)}".lower())
    return out


def _inspect(ctx, ref: str) -> dict:
    meta = _flake_json(["flake", "metadata", "--json", "--no-write-lock-file", ref])
    show = _flake_json(["flake", "show", "--json", "--no-write-lock-file", "--all-systems", ref], timeout=600)
    locks = meta.get("locks") or {}
    root = (locks.get("nodes") or {}).get(locks.get("root", "root"), {})
    outputs = {k: sorted(v.keys()) if isinstance(v, dict) else [] for k, v in show.items()}
    tags = _tags(ref)
    try:
        repo = ctx.repo()
        owners = _lock_owners(repo)
    except CliError:
        owners = set()
    own = _owner(ref)
    return {"flakeref": ref, "description": meta.get("description"), "locked": meta.get("locked"),
            "outputs": outputs, "inputs": sorted((root.get("inputs") or {}).keys()),
            "latestTag": tags[-1] if tags else None, "ownerInLock": bool(own and own in owners), "owner": own}


@handler("plugin", "inspect")
def plugin_inspect(ctx, a):
    d = _inspect(ctx, a.flakeref)
    d["_text"] = "\n".join([
        f"{a.flakeref}: {d.get('description') or ''}",
        *(f"  {k}: {', '.join(v)}" for k, v in d["outputs"].items() if v),
        f"  inputs: {', '.join(d['inputs']) or 'none'}",
        f"  latest tag: {d['latestTag'] or 'none'}",
        f"  owner already in this host's lock: {'yes' if d['ownerInLock'] else 'no'}",
    ])
    return d


FOLLOWS = {"nixpkgs": "nixpkgs", "home-manager": "home-manager", "omanix": "omanix"}


def _input_name(ref: str) -> str:
    m = re.search(r"([A-Za-z0-9_.-]+?)(?:\.git)?(?:[/?#].*)?$", re.sub(r"^[a-z+]+:(//)?", "", ref).split("?")[0].rstrip("/").split("/")[-1] or "plugin")
    n = re.sub(r"[^A-Za-z0-9_-]", "-", m.group(1) if m else "plugin")
    if ref.startswith("github:"):
        parts = ref[len("github:"):].split("/")
        if len(parts) >= 2:
            n = re.sub(r"[^A-Za-z0-9_-]", "-", parts[1])
    return n if nixedit.IDENT.match(n) else "p-" + n


def _lock(ctx, repo: Path):
    r = run(["nix", "flake", "lock"], cwd=str(repo), env=nix_env(), timeout=900)
    if r.returncode != 0:
        raise CliError(EXIT.RETRY if offline(r.stderr) else EXIT.FAILED, "nix flake lock: " + tail(r.stderr, 20))


def _lock_nodes(repo: Path) -> set[str]:
    try:
        return set(json.loads((repo / "flake.lock").read_text())["nodes"])
    except (OSError, json.JSONDecodeError, KeyError):
        return set()


@handler("plugin", "add")
def plugin_add(ctx, a):
    repo = ctx.repo()
    info = _inspect(ctx, a.flakeref)
    ref = a.flakeref
    if not _has_ref(ref) and not ref.startswith("path:") and not ref.startswith("/"):
        if info["latestTag"]:
            ref = _with_tag(ref, info["latestTag"])
        elif not a.branch:
            raise CliError(EXIT.USAGE, f"{a.flakeref} has no release tag; pass --branch to follow its default branch (the card shows it)")
    name = a.name or _input_name(a.flakeref)
    if not nixedit.IDENT.match(name):
        raise CliError(EXIT.USAGE, f"input name {name!r} isn't a Nix identifier; pass --name")
    follows = sorted(i for i in info["inputs"] if i in FOLLOWS)
    value = {"url": ref}
    if follows:
        value["inputs"] = {i: {"follows": FOLLOWS[i]} for i in follows}
    nixos = a.module in info["outputs"].get("nixosModules", [])
    homeo = "homeModules" if a.module in info["outputs"].get("homeModules", []) else (
        "homeManagerModules" if a.module in info["outputs"].get("homeManagerModules", []) else None)
    want_nixos = nixos and not a.home
    want_home = homeo is not None
    if not want_nixos and not want_home:
        raise CliError(EXIT.FAILED, f"{a.flakeref} has no nixosModules.{a.module} or homeModules.{a.module}")
    before = _lock_nodes(repo)
    edits = []
    fe = FileEdit(repo / "flake.nix")
    def fn(tree, src):
        body = nixedit.module_body(tree)
        if [m for m in nixedit.find(body, ["inputs", name])]:
            raise nixedit.EditError(f"there is already an input {name} (use --name)")
        return nixedit.insert_path(tree, src, ["inputs", name], value)
    try:
        fe.apply(fn)
        edits.append(fe)
        imports = []
        if want_nixos:
            e = FileEdit(repo / "modules/plugins.nix")
            expr = f"inputs.{name}.nixosModules.{nixedit.attr_name(a.module)}"
            e.apply(lambda t, s: nixedit.import_add(t, s, expr))
            edits.append(e)
            imports.append({"file": "modules/plugins.nix", "expr": expr})
        if want_home:
            e = FileEdit(repo / "home.nix")
            expr = f"inputs.{name}.{homeo}.{nixedit.attr_name(a.module)}"
            def hfn(t, s):
                s = nixedit.ensure_formal(t, s, "inputs")
                return nixedit.import_add(nixedit.parse(s), s, expr)
            e.apply(hfn)
            edits.append(e)
            imports.append({"file": "home.nix", "expr": expr})
        lock_old = (repo / "flake.lock").read_bytes() if (repo / "flake.lock").exists() else None
        _lock(ctx, repo)
    except (nixedit.EditError, CliError) as e:
        for x in reversed(edits):
            x.revert()
        if isinstance(e, CliError):
            raise
        raise CliError(EXIT.USAGE, f"{e}; edit by hand")
    added = sorted(_lock_nodes(repo) - before)
    return {"input": name, "url": ref, "follows": follows, "imports": imports, "lockNodes": added,
            "branch": not _has_ref(ref) and a.branch,
            "_text": f"input {name} = {ref}" + (f" (follows {', '.join(follows)})" if follows else "")
            + "".join(f"\n  import {i['expr']} in {i['file']}" for i in imports)
            + f"\n  lock nodes added: {', '.join(added) or 'none'}\nNext: omanix check, commit, omanix propose."}


@handler("plugin", "remove")
def plugin_remove(ctx, a):
    repo = ctx.repo()
    name = a.input
    removed = []
    for rel in ("modules/plugins.nix", "home.nix"):
        p = repo / rel
        if not p.exists():
            continue
        src = p.read_bytes()
        tree = nixedit.parse(src)
        body = nixedit.module_body(tree)
        for m in nixedit.find(body, ["imports"]):
            lst = nixedit.list_node(m.value) if m.kind == "value" else None
            if lst is None:
                continue
            for el in nixedit.list_elements(lst):
                if el.startswith(f"inputs.{name}."):
                    fe = FileEdit(p)
                    fe.apply(lambda t, s, el=el: nixedit.import_remove(t, s, el))
                    removed.append(f"{rel}: {el}")
    fe = FileEdit(repo / "flake.nix")
    def fn(tree, src):
        ms = nixedit.find(nixedit.module_body(tree), ["inputs", name])
        if not ms:
            raise nixedit.EditError(f"no input {name} in flake.nix")
        for m in ms:
            src = nixedit.delete_binding(src, m)
            break
        return src
    try:
        fe.apply(fn)
    except nixedit.EditError as e:
        raise CliError(EXIT.FAILED, str(e))
    removed.append(f"flake.nix: inputs.{name}")
    before = _lock_nodes(repo)
    _lock(ctx, repo)
    gone = sorted(before - _lock_nodes(repo))
    removed += [f"flake.lock: {n}" for n in gone]
    return {"input": name, "removed": removed,
            "_text": "removed:\n" + "\n".join(f"  {r}" for r in removed) + "\nLeftover option values now fail `omanix check` with file:line."}
