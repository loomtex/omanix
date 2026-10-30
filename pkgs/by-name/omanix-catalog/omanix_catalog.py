"""omanix-catalog: assemble and validate a host's catalogs (DESIGN §h.9).

  omanix-catalog assemble <spec.json> <outdir>   build every file
  omanix-catalog validate <dir>                  checks.catalogs
  omanix-catalog size <dir> [--host-max N] [--shared-max N]   checks.catalog-size (U20)

The nix side (modules/omanix/catalog.nix) evaluates the host once and hands
over the effective values; this tool only reshapes them, reads the fork's
data files as text, and writes JSON. Stdlib only; never runs omarchy code.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path

SHARED = ("options/nixos.json", "options/home.json")
REQUIRED = ["options/nixos.json", "options/home.json", "options/host.json", "config.json", "host.json", "home.json",
            "keybinds.json", "menu.json", "themes.json", "apps.json", "persist.json", "secrets.json", "services.json",
            "unlock.json", "commands.json", "preview.json", "hostgen.json", "host.md", "index.json"]


def dump(path: Path, doc) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, indent=1, sort_keys=True, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------- options


def split_options(nixos: dict, home: dict, shared: list[str]):
    """options/nixos.json and options/home.json hold what every host of a
    release shares (nixpkgs, home-manager, loom, nuketown, omanix, …);
    options/host.json the rest: plugin and host-module options."""
    def is_shared(o):
        return o.get("origin") in shared
    out_n, out_h, host = {}, {}, {}
    for scope, src, dst in (("nixos", nixos, out_n), ("home", home, out_h)):
        for name, o in src.items():
            o = {k: v for k, v in o.items() if k not in ("loc",)}
            if scope == "home":
                if name.startswith("<name>."):
                    name = name[len("<name>."):]
                elif name.startswith("home-manager.users."):
                    name = name.split(".", 3)[3]
            if is_shared(o):
                dst[name] = o
            else:
                host[name if scope == "nixos" else f"home-manager.users.<name>.{name}"] = dict(o, scope=scope)
    return out_n, out_h, host


# ---------------------------------------------------------------- keybinds

CALL = re.compile(r'\b(o\.bind_toggle|o\.bind_hold|o\.rebind|o\.bind|hl\.bind|hl\.unbind)\(\s*"([^"]+)"(?:\s*,\s*(?:"([^"]*)"|nil))?\s*,?\s*(.*)$')


def binding_modules(omarchy: Path) -> list[Path]:
    text = (omarchy / "default/hypr/omarchy.lua").read_text()
    mods = re.findall(r'(?:require|require_optional\.module)\("(default\.hypr\.bindings\.[a-z0-9_-]+)"\)', text)
    return [omarchy / (m.replace(".", "/") + ".lua") for m in mods]


def keybinds(omarchy: Path, hm_bindings: Path | None) -> list[dict]:
    """Every bind in the effective chain, read as text (never run):
    {keys, description, dispatcher, source, removed}."""
    out = []
    files = [(f, f"$OMARCHY_PATH/{f.relative_to(omarchy)}") for f in binding_modules(omarchy)]
    if hm_bindings and hm_bindings.exists():
        files.append((hm_bindings, "~/.config/hypr/bindings.lua"))
    for f, label in files:
        if not f.exists():
            continue
        for n, line in enumerate(f.read_text().splitlines(), 1):
            s = line.split("--", 1)[0].strip()
            m = CALL.search(s)
            if not m:
                continue
            fn, chord, desc, rest = m.groups()
            if fn == "hl.unbind":
                for b in out:
                    if b["keys"] == chord and not b.get("removed"):
                        b["removed"] = f"{label}:{n}"
                continue
            out.append({"keys": chord, "description": desc, "dispatcher": rest.rstrip(") ,")[:160],
                        "kind": fn, "source": f"{label}:{n}"})
    return out


# ---------------------------------------------------------------- menu


def strip_jsonc(text: str) -> str:
    out = []
    for line in text.splitlines():
        if line.lstrip().startswith("//"):
            continue
        out.append(line)
    t = "\n".join(out)
    return re.sub(r",(\s*[}\]])", r"\1", t)


def menu(menu_jsonc: Path, intents: Path) -> dict:
    m = json.loads(strip_jsonc(menu_jsonc.read_text()))
    it = json.loads(intents.read_text()) if intents.exists() else {}
    out = {}
    for k, e in m.items():
        if not isinstance(e, dict):
            continue
        row = {"label": e.get("label") or e.get("name"), "kind": "intent" if e.get("intent") else "gui"}
        if e.get("intent"):
            row.update({"text": e["intent"], "skill": e.get("skill")})
        if k in it:
            row["manual"] = it[k].get("manual")
        out[k] = row
    return out


# ---------------------------------------------------------------- commands


def omarchy_commands(bindir: Path) -> list[dict]:
    out = []
    if not bindir.is_dir():
        return out
    for f in sorted(bindir.iterdir()):
        if not f.name.startswith("omarchy-") or not f.is_file():
            continue
        try:
            head = f.read_text(errors="replace")[:2000]
        except OSError:
            continue
        m = re.search(r"^# omarchy:summary=(.*)$", head, re.M)
        if not m:
            continue
        a = re.search(r"^# omarchy:args=(.*)$", head, re.M)
        out.append({"command": f.name, "description": m.group(1).strip(), "args": a.group(1).strip() if a else "",
                    "origin": "omarchy"})
    return out


def commands(omanix_cmds: dict, loom_cmds: list[dict], bindir: Path) -> dict:
    rows = []
    for g, cs in (omanix_cmds.get("commands") or {}).items():
        for n, e in sorted(cs.items()):
            rows.append({"command": "omanix " + (n if g == "core" else f"{g} {n}"), "description": e.get("description", ""),
                         "args": e.get("args", []), "output": e.get("output", {}), "origin": e.get("origin", "omanix")})
    rows += [dict(c, origin="loom") for c in loom_cmds]
    rows += omarchy_commands(bindir)
    return {"exitCodes": omanix_cmds.get("exitCodes", {}), "commands": rows}


# ---------------------------------------------------------------- host.md


def host_md(host: dict, host_opts: dict) -> str:
    lines = [f"# {host.get('name') or 'this host'}: plugins and host modules", "",
             "Generated from catalog/host.json and catalog/options/host.json. Read before changing a plugin.", ""]
    plugins = host.get("plugins") or []
    lines.append("## Plugins (flake inputs)")
    if not plugins:
        lines.append("none")
    for p in plugins:
        roots = sorted({n.split(".")[0] if not n.startswith("home-manager.users") else ".".join(n.split(".")[:4])
                        for n, o in host_opts.items() if o.get("origin") == f"input:{p['input']}"})
        lines.append(f"- `{p['input']}` ({p.get('url') or p.get('original', {}).get('url') or ''} @ {str(p.get('rev') or '')[:12]})"
                     + (f": options under {', '.join('`' + r + '`' for r in roots)}" if roots else ": no options"))
    lines += ["", "## Host modules"]
    for f in host.get("moduleFiles") or []:
        lines.append(f"- `{f}`")
    hopt = sorted((n, o) for n, o in host_opts.items() if str(o.get("origin", "")).startswith("host:"))
    if hopt:
        lines += ["", "## Options declared in this repo"]
        for n, o in hopt[:200]:
            d = (o.get("description") or "").strip().split("\n")[0][:160]
            lines.append(f"- `{n}` ({o.get('type')}): {d}")
    over = host.get("overriddenHomeFiles") or []
    lines += ["", "## Desktop files this host takes over (lib.mkForce on .source)"]
    lines += [f"- `~/{t['target']}` in `{t['file']}`" for t in over] or ["none"]
    pers = host.get("persistAdditions") or []
    lines += ["", "## Persistence added by host modules"]
    lines += [f"- `{p}`" for p in pers] or ["none"]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- assemble


def themes(data: Path, extra: list[str], trusted: list[str]) -> list[dict]:
    # $OMARCHY_PATH/themes is the registry: upstream's themes and the host's
    # omanix.theme.extra, which are listed once, as the host's.
    out = []
    d = data / "themes"
    if d.is_dir():
        for t in sorted(d.iterdir()):
            if t.is_dir() and t.name not in extra:
                out.append({"name": t.name, "origin": "omarchy"})
    out += [{"name": n, "origin": "host", "trusted": n in trusted} for n in extra]
    return out


def assemble(spec: dict, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    nixos = json.loads(Path(spec["optionsNixos"]).read_text())
    home = json.loads(Path(spec["optionsHome"]).read_text())
    on, oh, oh_host = split_options(nixos, home, spec["sharedOrigins"])
    dump(out / "options/nixos.json", on)
    dump(out / "options/home.json", oh)
    dump(out / "options/host.json", oh_host)
    dump(out / "config.json", spec["config"])
    dump(out / "host.json", spec["host"])
    dump(out / "home.json", spec["home"])
    data = Path(spec["omarchy"])
    dump(out / "keybinds.json", keybinds(data, Path(spec["hmBindings"]) if spec.get("hmBindings") else None))
    dump(out / "menu.json", menu(data / "default/omarchy/omarchy-menu.jsonc", data / "default/omanix/intents.json"))
    th = themes(data, spec.get("extraThemes", []), spec.get("trustedThemes", []))
    dump(out / "themes.json", {"default": spec.get("themeDefault"), "lock": spec.get("themeLock", False),
                               "boot": spec.get("themeBoot"), "themes": th})
    for k in ("apps", "persist", "secrets", "services", "unlock", "preview"):
        dump(out / f"{k}.json", spec[k])
    hg = dict(spec["hostgen"])
    hg["theme"] = [t["name"] for t in th if t["origin"] == "omarchy"]
    dump(out / "hostgen.json", hg)
    dump(out / "commands.json", commands(json.loads(Path(spec["commands"]).read_text()), spec.get("loomCommands", []),
                                         data / "bin"))
    (out / "host.md").write_text(host_md(spec["host"], oh_host))
    index(out)


def index(out: Path) -> None:
    files = {}
    for p in sorted(out.rglob("*")):
        if p.is_file() and p.name != "index.json":
            files[str(p.relative_to(out))] = {"sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "bytes": p.stat().st_size}
    dump(out / "index.json", {"schema": "omanix.catalog/v1", "files": files})


# ---------------------------------------------------------------- checks


def validate(d: Path) -> list[str]:
    errs = []
    for f in REQUIRED:
        if not (d / f).exists():
            errs.append(f"missing {f}")
    for p in sorted(d.rglob("*.json")):
        try:
            json.loads(p.read_text())
        except (OSError, json.JSONDecodeError) as e:
            errs.append(f"{p.relative_to(d)}: not JSON ({e})")
    try:
        idx = json.loads((d / "index.json").read_text())["files"]
        on_disk = {str(p.relative_to(d)) for p in d.rglob("*") if p.is_file() and p.name != "index.json"}
        if set(idx) != on_disk:
            errs.append(f"index.json lists {sorted(set(idx) ^ on_disk)} wrongly")
        for f, e in idx.items():
            if (d / f).exists() and hashlib.sha256((d / f).read_bytes()).hexdigest() != e["sha256"]:
                errs.append(f"index.json: {f} sha256 mismatch")
    except (OSError, KeyError, json.JSONDecodeError) as e:
        errs.append(f"index.json: {e}")
    for f in ("options/nixos.json", "options/home.json", "options/host.json"):
        try:
            doc = json.loads((d / f).read_text())
        except (OSError, json.JSONDecodeError):
            continue
        for name, o in list(doc.items())[:100000]:
            for k in ("type", "description", "origin", "declarations"):
                if k not in o:
                    errs.append(f"{f}: {name} has no {k}")
                    break
        if f != "options/host.json" and len(doc) < 50:
            errs.append(f"{f}: only {len(doc)} options")
    try:
        cfg = json.loads((d / "config.json").read_text())
        for k in ("loom", "omanix"):
            if not isinstance(cfg.get(k), dict):
                errs.append(f"config.json: no {k}")
    except (OSError, json.JSONDecodeError):
        pass
    try:
        home = json.loads((d / "home.json").read_text())
        for t, e in home.items():
            for k in ("module", "overlay", "options", "source"):
                if k not in e:
                    errs.append(f"home.json: {t} has no {k}")
    except (OSError, json.JSONDecodeError, AttributeError):
        pass
    try:
        kb = json.loads((d / "keybinds.json").read_text())
        if not kb or not all({"keys", "source"} <= set(b) for b in kb):
            errs.append("keybinds.json: empty or rows without keys/source")
    except (OSError, json.JSONDecodeError):
        pass
    try:
        pv = json.loads((d / "preview.json").read_text())["keys"]
        for k, e in pv.items():
            if e.get("kind") not in ("hypr", "theme", "font", "background"):
                errs.append(f"preview.json: {k} has kind {e.get('kind')!r}")
            if e.get("kind") == "hypr" and e.get("type") not in ("int", "float", "bool", "enum"):
                errs.append(f"preview.json: {k} isn't a scalar type")
    except (OSError, json.JSONDecodeError, KeyError) as e:
        errs.append(f"preview.json: {e}")
    return errs


def size(d: Path, host_max: int, shared_max: int) -> list[str]:
    errs = []
    for p in sorted(d.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(d))
        lim = shared_max if rel in SHARED else host_max
        n = p.stat().st_size
        print(f"{n:>10}  {rel}")
        if n >= lim:
            errs.append(f"{rel}: {n} bytes ≥ {lim}")
    return errs


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv[:1] == ["assemble"] and len(argv) == 3:
        assemble(json.loads(Path(argv[1]).read_text()), Path(argv[2]))
        return 0
    if argv[:1] == ["validate"] and len(argv) == 2:
        errs = validate(Path(argv[1]))
    elif argv[:1] == ["size"] and len(argv) >= 2:
        hm = int(argv[argv.index("--host-max") + 1]) if "--host-max" in argv else 2 * 1024 * 1024
        sm = int(argv[argv.index("--shared-max") + 1]) if "--shared-max" in argv else 15 * 1024 * 1024
        errs = size(Path(argv[1]), hm, sm)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    for e in errs:
        print(f"FAIL: {e}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
