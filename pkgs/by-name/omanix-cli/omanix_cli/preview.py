"""omanix-preview: the human-session helper behind `omanix try` (§h.6).

The resident never reaches the human's Wayland session. When it asks to
preview a value, this helper (run by the human: the chat panel, or `omanix
try` in the human's own terminal) checks the path against the typed
allowlist in catalog/preview.json and the value against its type, and
renders the change itself from a fixed template: numbers as numbers,
booleans as booleans, enum values only from the list, theme and font names
only after checking them against the registry. No text from the request is
ever evaluated or spliced into Lua.

  omanix-preview check <path> <json>   print what would be applied
  omanix-preview apply <path> <json>   apply it (records how to revert)
  omanix-preview reset                 revert every preview
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

LUA_KEY = re.compile(r"^[a-z][a-z0-9_]*$")
FONT = re.compile(r"^[A-Za-z0-9 ._+-]{1,64}$")
THEME = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")


class Refused(Exception):
    pass


def load_allowlist(catalog) -> dict:
    p = Path(os.environ.get("OMANIX_PREVIEW_JSON") or Path(catalog) / "preview.json")
    try:
        return json.loads(p.read_text()).get("keys", {})
    except (OSError, json.JSONDecodeError):
        return {}


def _state_file() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "omanix-preview.json"


def _themes() -> list[str]:
    r = subprocess.run(["omarchy-theme-list"], capture_output=True, text=True)
    names = []
    for l in r.stdout.splitlines():
        n = l.strip().lower().replace(" ", "-")
        if n:
            names.append(n)
    return names


def _fonts() -> list[str]:
    r = subprocess.run(["omarchy-font-list"], capture_output=True, text=True)
    return [l.strip() for l in r.stdout.splitlines() if l.strip()]


def _lua_scalar(spec: dict, value):
    t = spec.get("type")
    if t == "bool":
        if not isinstance(value, bool):
            raise Refused(f"{spec['label']}: wants true or false")
        return "true" if value else "false"
    if t == "int":
        if isinstance(value, bool) or not isinstance(value, int):
            raise Refused(f"{spec['label']}: wants a whole number")
    elif t == "float":
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise Refused(f"{spec['label']}: wants a number")
    elif t == "enum":
        if value not in spec.get("values", []):
            raise Refused(f"{spec['label']}: not one of {', '.join(map(str, spec.get('values', [])))}")
        return json.dumps(value)   # a value from the catalog's own list
    else:
        raise Refused(f"{spec['label']}: can't be previewed")
    lo, hi = spec.get("min"), spec.get("max")
    if (lo is not None and value < lo) or (hi is not None and value > hi):
        raise Refused(f"{spec['label']}: must be between {lo} and {hi}")
    return str(int(value)) if t == "int" else repr(float(value))


def validate(allow: dict, path: str, value) -> dict:
    """What would be applied, or Refused. Returns {label, kind, lua?, arg?}."""
    spec = allow.get(path)
    if spec is None:
        raise Refused(f"{path} can't be previewed (not in catalog/preview.json)")
    spec = dict(spec, label=path)
    kind = spec.get("kind")
    if kind == "hypr":
        key = spec.get("key") or []
        if not key or not all(LUA_KEY.match(k) for k in key):
            raise Refused(f"{path}: bad allowlist entry")
        lit = _lua_scalar(spec, value)
        lua = "hl.config({ " + "".join(f"{k} = {{ " for k in key[:-1]) + f"{key[-1]} = {lit}" + " }" * (len(key) - 1) + " })"
        return {"label": f"{'.'.join(key)} → {lit}", "kind": kind, "lua": lua}
    if kind == "theme":
        if not isinstance(value, str) or not THEME.match(value):
            raise Refused(f"{path}: not a theme name")
        if value not in (spec.get("values") or _themes()):
            raise Refused(f"{path}: no theme {value!r} is installed")
        return {"label": f"theme → {value}", "kind": kind, "arg": value}
    if kind == "font":
        if not isinstance(value, str) or not FONT.match(value):
            raise Refused(f"{path}: not a font family name")
        if value not in _fonts():
            raise Refused(f"{path}: the font {value!r} is not installed")
        return {"label": f"monospace font → {value}", "kind": kind, "arg": value}
    if kind == "background":
        if not isinstance(value, str) or "/" in value or value.startswith("."):
            raise Refused(f"{path}: give a file name from the current theme's backgrounds")
        r = subprocess.run(["omarchy-theme-dir"], capture_output=True, text=True)
        d = Path(r.stdout.strip() or "/nonexistent") / "backgrounds"
        f = d / value
        if not f.is_file():
            raise Refused(f"{path}: {value} isn't one of the current theme's backgrounds")
        return {"label": f"background → {value}", "kind": kind, "arg": str(f)}
    raise Refused(f"{path}: unknown preview kind")


def _record(kind: str, prev):
    p = _state_file()
    try:
        st = json.loads(p.read_text())
    except (OSError, json.JSONDecodeError):
        st = {}
    st.setdefault(kind, prev)      # the first preview remembers what to go back to
    p.write_text(json.dumps(st))


def _out(args) -> str:
    r = subprocess.run(args, capture_output=True, text=True)
    return r.stdout.strip()


def apply(allow: dict, path: str, value) -> dict:
    r = validate(allow, path, value)
    k = r["kind"]
    if k == "hypr":
        _record("hypr", True)
        cmd = ["hyprctl", "eval", r["lua"]]
    elif k == "theme":
        _record("theme", _out(["omarchy-theme-current"]).lower().replace(" ", "-"))
        cmd = ["omarchy-theme-set", r["arg"]]
    elif k == "font":
        _record("font", _out(["omarchy-font-current"]))
        cmd = ["omarchy-font-set", r["arg"]]
    else:
        _record("background", _out(["omarchy-theme-bg-current"]))
        cmd = ["omarchy-theme-bg-set", r["arg"]]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0 or "error" in p.stdout.lower():
        raise Refused(f"applying failed: {(p.stderr or p.stdout).strip()[:300]}")
    return r


def reset() -> list[str]:
    p = _state_file()
    try:
        st = json.loads(p.read_text())
    except (OSError, json.JSONDecodeError):
        return []
    done = []
    if st.get("theme"):
        subprocess.run(["omarchy-theme-set", st["theme"]], capture_output=True)
        done.append("theme")
    if st.get("font"):
        subprocess.run(["omarchy-font-set", st["font"]], capture_output=True)
        done.append("font")
    if st.get("background"):
        subprocess.run(["omarchy-theme-bg-set", st["background"]], capture_output=True)
        done.append("background")
    if st.get("hypr"):
        subprocess.run(["hyprctl", "reload"], capture_output=True)
        done.append("hypr")
    p.unlink(missing_ok=True)
    return done


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    catalog = os.environ.get("OMANIX_CATALOG", "/run/current-system/sw/share/omanix/catalog")
    allow = load_allowlist(catalog)
    try:
        if argv[:1] == ["reset"]:
            print(json.dumps({"ok": True, "reset": reset()}))
            return 0
        if len(argv) != 3 or argv[0] not in ("check", "apply"):
            print(__doc__, file=sys.stderr)
            return 2
        try:
            value = json.loads(argv[2])
        except json.JSONDecodeError:
            raise Refused("the value isn't JSON")
        r = validate(allow, argv[1], value) if argv[0] == "check" else apply(allow, argv[1], value)
        print(json.dumps({"ok": True, **r}))
        return 0
    except Refused as e:
        print(json.dumps({"ok": False, "refused": str(e)}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
