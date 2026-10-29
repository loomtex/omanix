"""omanix-overlay: the runtime overlay layer (DESIGN §f.4.3-§f.4.8).

HM owns the dotfiles read-only; each one that has an overlay sources it
last. This tool creates the overlays, writes into them for the KEEP-AS-GUI
writers (kv, hypr-scale), rebases the Quickshell shell.json snapshot onto new
defaults, settles overlays after "make it stick", resets them, and writes the
typed runtime summary the resident reads.

Stdlib only; every write is atomic (temp file + rename).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

# overlay path (relative to the overlay dir) -> (comment prefix, kv format, area)
OVERLAYS: dict[str, tuple[str, str | None, str]] = {
    "hypr/hyprland.lua": ("--", None, "hypr"),
    "hypr/monitors.lua": ("--", None, "monitors"),
    "hypr/input.lua": ("--", None, "input"),
    "hypr/bindings.lua": ("--", None, "hypr"),
    "hypr/looknfeel.lua": ("--", None, "look"),
    "hypr/autostart.lua": ("--", None, "hypr"),
    "hypr/hyprsunset.conf": ("#", None, "look"),
    "alacritty.toml": ("#", "toml", "font"),
    "kitty.conf": ("#", "kitty", "font"),
    "ghostty.conf": ("#", "ghostty", "font"),
    "foot.ini": ("#", "foot", "font"),
    "xcompose": ("#", None, "input"),
    "bashrc": ("#", None, "hypr"),
    "gtk4.css": ("/*", None, "look"),
    "chromium-flags.conf": ("#", None, "look"),
    "fontconfig/fonts.conf": ("<!--", None, "font"),
}

AREAS = sorted({a for _, _, a in OVERLAYS.values()} | {"shell", "theme"})

EMPTY_FONTCONFIG = '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">\n<fontconfig/>\n'


class Env:
    """Where things live; tests point HOME/XDG_STATE_HOME at a temp dir."""

    def __init__(self) -> None:
        self.home = Path(os.environ.get("HOME", "~")).expanduser()
        self.state = Path(os.environ.get("XDG_STATE_HOME") or self.home / ".local/state")
        self.omanix = self.state / "omanix"
        self.overlay = self.omanix / "overlay"
        self.shell = self.omanix / "shell"
        self.manifest = self.omanix / "overlay.json"
        self.reclaim = Path(os.environ.get("OMANIX_RECLAIM_DIR") or self.state / "loom/clobbered")
        self.omarchy = Path(os.environ.get("OMARCHY_PATH", "/run/current-system/omarchy"))
        self.agent = os.environ.get("OMANIX_AGENT_NAME") or "your agent"
        self.runtime = Path(os.environ.get("OMANIX_RUNTIME_JSON") or f"/run/omanix/session/{os.getuid()}/runtime.json")


# ---------------------------------------------------------------- utilities


def sha256(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except FileNotFoundError:
        return None


def atomic_write(path: Path, text: str, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def header(rel: str, env: Env) -> str:
    c, _, area = OVERLAYS[rel]
    lines = [
        f"omanix runtime overlay for {rel}: loaded after your host configuration, so it wins.",
        f"Make it stick: ask {env.agent} (menu > Make my look permanent); `omanix reset {rel}` clears it.",
    ]
    if c == "/*":
        return "".join(f"/* {l} */\n" for l in lines)
    if c == "<!--":
        return "".join(f"<!-- {l} -->\n" for l in lines)
    return "".join(f"{c} {l}\n" for l in lines)


def empty_overlay(rel: str, env: Env) -> str:
    h = header(rel, env)
    if rel == "fontconfig/fonts.conf":
        # A later prepend_first wins; an empty document must still parse.
        return EMPTY_FONTCONFIG.replace("<fontconfig/>", h + "<fontconfig/>")
    return h


def body_lines(text: str, rel: str) -> list[str]:
    """Lines that are not the header or blank."""
    c = OVERLAYS[rel][0]
    out = []
    for l in text.splitlines():
        s = l.strip()
        if not s:
            continue
        if s.startswith(c) and "omanix runtime overlay" in s or "Make it stick:" in s:
            continue
        out.append(l)
    return out


def is_empty(rel: str, env: Env) -> bool:
    p = env.overlay / rel
    if not p.exists():
        return True
    text = p.read_text()
    if rel == "fontconfig/fonts.conf":
        return text.strip().endswith("<fontconfig/>")
    return not body_lines(text, rel)


def backup(path: Path, env: Env, stamp: str) -> None:
    if not path.exists():
        return
    rel = path.relative_to(env.home) if path.is_relative_to(env.home) else Path(str(path).lstrip("/"))
    dest = env.reclaim / stamp / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dest)


def load_manifest(env: Env) -> dict:
    try:
        return json.loads(env.manifest.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_manifest(env: Env, m: dict) -> None:
    atomic_write(env.manifest, json.dumps(m, indent=2, sort_keys=True) + "\n")


def stamp() -> str:
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


# ---------------------------------------------------------------- init / reset


def cmd_init(env: Env, reset: bool = False) -> list[str]:
    """Create the §f.4.3 layout and touch every missing overlay (idempotent)."""
    created = []
    for d in (env.overlay / "hypr", env.overlay / "fontconfig", env.shell, env.omanix / "done"):
        d.mkdir(parents=True, exist_ok=True)
    if reset:
        do_reset(env, list(OVERLAYS) + ["shell"])
    for rel in OVERLAYS:
        p = env.overlay / rel
        if not p.exists():
            atomic_write(p, empty_overlay(rel, env))
            created.append(rel)
    m = load_manifest(env)
    m.setdefault("overlays", {})
    for rel in OVERLAYS:
        m["overlays"].setdefault(rel, sha256(env.overlay / rel))
    save_manifest(env, m)
    return created


def resolve_targets(names: list[str]) -> list[str]:
    out: list[str] = []
    for n in names:
        n = n.removeprefix("overlay/")
        if n == "--all":
            out += list(OVERLAYS) + ["shell"]
        elif n in OVERLAYS or n == "shell":
            out.append(n)
        elif n in ("hypr", "tmux", "herdr"):
            # a directory: every overlay of that program's files
            out += [r for r in OVERLAYS if r.startswith(n + "/")]
        elif n in AREAS:
            out += [r for r, (_, _, a) in OVERLAYS.items() if a == n]
            if n == "shell":
                out.append("shell")
        else:
            # a path like ~/.config/alacritty/alacritty.toml or hypr/monitors.lua
            base = n.replace("~/.config/", "").replace(".config/", "")
            matches = [r for r in OVERLAYS if r == base or r.endswith("/" + base) or base.endswith(r)
                       or base.split("/")[-1].split(".")[0] == r.split("/")[-1].split(".")[0]]
            if not matches:
                raise SystemExit(f"omanix-overlay: no overlay for {n!r}")
            out += matches
    return list(dict.fromkeys(out))


def do_reset(env: Env, targets: list[str]) -> list[str]:
    st = stamp()
    done = []
    for rel in targets:
        if rel == "shell":
            for f in ("shell.json", "shell.json.base", "shell.toml"):
                p = env.shell / f
                if p.exists():
                    backup(p, env, st)
                    p.unlink()
                    done.append(f"shell/{f}")
            continue
        p = env.overlay / rel
        if p.exists() and not is_empty(rel, env):
            backup(p, env, st)
            done.append(rel)
        atomic_write(p, empty_overlay(rel, env))
    return done


# ---------------------------------------------------------------- kv formats


def _kv_regex(fmt: str, key: str) -> re.Pattern:
    k = re.escape(key)
    if fmt == "kitty":
        return re.compile(rf"^\s*{k}(\s+.*)?$")
    return re.compile(rf"^\s*{k}\s*=.*$")


def _render_kv(fmt: str, key: str, value: str) -> str:
    if fmt == "kitty":
        return f"{key} {value}"
    if fmt == "toml":
        return f"{key} = {value}"
    return f"{key} = {value}" if fmt == "ghostty" else f"{key}={value}"


def kv_get(text: str, fmt: str, key: str) -> str | None:
    section, leaf = _split_toml(key) if fmt == "toml" else (None, key)
    cur = None
    rx = _kv_regex(fmt, leaf)
    for l in text.splitlines():
        s = l.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1].strip()
            continue
        if (fmt != "toml" or cur == section) and rx.match(l):
            if fmt == "kitty":
                return s[len(leaf):].strip()
            return s.split("=", 1)[1].strip()
    return None


def _split_toml(key: str) -> tuple[str | None, str]:
    if "." in key:
        s, k = key.rsplit(".", 1)
        return s, k
    return None, key


def kv_set(text: str, fmt: str, key: str, value: str | None) -> str:
    """Set (or with value None, remove) key in a kv overlay; header kept."""
    lines = text.splitlines()
    if fmt == "toml":
        section, leaf = _split_toml(key)
    else:
        section, leaf = (None, key)
    rx = _kv_regex(fmt, leaf)
    cur = None
    found = False
    out: list[str] = []
    for l in lines:
        s = l.strip()
        if s.startswith("[") and s.endswith("]"):
            cur = s[1:-1].strip()
        elif (fmt != "toml" or cur == section) and rx.match(l):
            if value is not None and not found:
                out.append(_render_kv(fmt, leaf, value))
            found = True
            continue
        out.append(l)
    if not found and value is not None:
        if fmt == "toml" and section is not None:
            # append to the section, creating it at the end if absent
            hdr = f"[{section}]"
            if hdr in (x.strip() for x in out):
                i = max(j for j, x in enumerate(out) if x.strip() == hdr)
                j = i + 1
                while j < len(out) and not out[j].strip().startswith("["):
                    j += 1
                out.insert(j, _render_kv(fmt, leaf, value))
            else:
                out += ["", hdr, _render_kv(fmt, leaf, value)]
        else:
            # top-level keys go before the first section header
            idx = next((j for j, x in enumerate(out) if x.strip().startswith("[")), len(out))
            out.insert(idx, _render_kv(fmt, leaf, value))
    if fmt == "toml" and value is None:
        out = _drop_empty_sections(out)
    return "\n".join(out) + "\n"


def _drop_empty_sections(lines: list[str]) -> list[str]:
    """Remove TOML section headers left with no keys (after an unset)."""
    out: list[str] = []
    for i, l in enumerate(lines):
        s = l.strip()
        if s.startswith("[") and s.endswith("]"):
            rest = lines[i + 1:]
            nxt = next((x for x in rest if x.strip() and not x.strip().startswith("#")), None)
            if nxt is None or nxt.strip().startswith("["):
                continue
        out.append(l)
    while out and not out[-1].strip():
        out.pop()
    return out


def cmd_kv(env: Env, rel: str, key: str, value: str | None) -> None:
    fmt = OVERLAYS.get(rel, (None, None, None))[1]
    if fmt is None:
        raise SystemExit(f"omanix-overlay: {rel} is not a key/value overlay")
    p = env.overlay / rel
    text = p.read_text() if p.exists() else empty_overlay(rel, env)
    atomic_write(p, kv_set(text, fmt, key, value))


def cmd_get(env: Env, rel: str, key: str) -> str | None:
    """A key's value in a kv overlay (None when unset)."""
    fmt = OVERLAYS.get(rel, (None, None, None))[1]
    if fmt is None:
        raise SystemExit(f"omanix-overlay: {rel} is not a key/value overlay")
    p = env.overlay / rel
    return kv_get(p.read_text(), fmt, key) if p.exists() else None


FONT_RE = re.compile(r"[A-Za-z0-9 _.+-]+")


def font_document(family: str, env: Env) -> str:
    """overlay/fontconfig/fonts.conf for `omarchy-font-set` (§f.4.4): a full
    document whose prepend_first rule loads after the HM one, so it wins."""
    if not FONT_RE.fullmatch(family):
        raise SystemExit(f"omanix-overlay: bad font family {family!r}")
    h = header("fontconfig/fonts.conf", env)
    return (
        '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">\n'
        + h
        + "<fontconfig>\n"
        '  <match target="pattern">\n'
        '    <test name="family" qual="any"><string>monospace</string></test>\n'
        '    <edit name="family" mode="prepend_first" binding="strong">\n'
        f"      <string>{family}</string>\n"
        "    </edit>\n"
        "  </match>\n"
        "</fontconfig>\n"
    )


def cmd_font(env: Env, family: str | None) -> None:
    rel = "fontconfig/fonts.conf"
    atomic_write(env.overlay / rel, font_document(family, env) if family is not None else empty_overlay(rel, env))


def font_family(env: Env) -> str | None:
    """The family the fontconfig overlay prepends, if any."""
    p = env.overlay / "fontconfig/fonts.conf"
    if not p.exists():
        return None
    m = re.search(r'mode="prepend_first"[^>]*>\s*<string>([^<]+)</string>', p.read_text())
    return m.group(1) if m else None


KB_BEGIN = "-- omanix-overlay: keyboard (managed block)"
KB_END = "-- omanix-overlay: keyboard end"
KB_RE = re.compile(r"[A-Za-z0-9_-]*(,[A-Za-z0-9_-]*)*")


def cmd_kb(env: Env, layouts: str | None, variants: str | None) -> None:
    """Write (or with layouts None, remove) the keyboard layout block in
    overlay/hypr/input.lua: the keyboard picker's runtime choice (U28),
    loaded after the HM input.lua, so it wins over omanix.input.layouts."""
    rel = "hypr/input.lua"
    p = env.overlay / rel
    text = p.read_text() if p.exists() else empty_overlay(rel, env)
    if KB_BEGIN in text and KB_END in text:
        a, b = text.index(KB_BEGIN), text.index(KB_END) + len(KB_END)
        text = text[:a].rstrip("\n") + "\n" + text[b:].lstrip("\n")
    if layouts is not None:
        variants = variants or ""
        if not layouts or not KB_RE.fullmatch(layouts) or not KB_RE.fullmatch(variants):
            raise SystemExit(f"omanix-overlay: bad keyboard layouts {layouts!r} / variants {variants!r}")
        block = "\n".join([
            KB_BEGIN,
            f"-- layouts {layouts}",
            f"-- variants {variants}",
            f'hl.config({{ input = {{ kb_layout = "{layouts}", kb_variant = "{variants}" }} }})',
            KB_END,
        ])
        text = text.rstrip("\n") + "\n" + block + "\n"
    atomic_write(p, text)


def kb_block(text: str) -> dict | None:
    if KB_BEGIN not in text:
        return None
    l = re.search(r"^-- layouts (\S*)$", text, re.M)
    v = re.search(r"^-- variants (\S*)$", text, re.M)
    return {"layouts": l.group(1) if l else "", "variants": v.group(1) if v else ""}


# ---------------------------------------------------------------- hypr-scale

SCALE_BEGIN = "-- omanix-overlay: monitors (managed block)"
SCALE_END = "-- omanix-overlay: end"


MODE_RE = re.compile(r"preferred|highres|highrr|[0-9]+x[0-9]+(@[0-9]+(\.[0-9]+)?)?")
RULE_RE = re.compile(r"^-- rule (\S*) (\S+)(?: (\S+))?$", re.M)


def cmd_hypr_scale(env: Env, output: str, scale: str, gdk: str | None, mode: str | None = None) -> None:
    """Write a monitor scale into overlay/hypr/monitors.lua (P4 contract).

    One managed block holds a rule per output ("" = every output), with the
    mode the panel had (default "preferred"), and an optional GDK scale; the
    last rule wins in Hyprland, and the block comes after anything the human
    wrote by hand.
    """
    if not re.fullmatch(r"auto|[0-9]+(\.[0-9]+)?", scale):
        raise SystemExit(f"omanix-overlay: bad scale {scale!r}")
    if gdk is not None and not re.fullmatch(r"[0-9]+", gdk):
        raise SystemExit(f"omanix-overlay: bad gdk scale {gdk!r}")
    if not re.fullmatch(r"[A-Za-z0-9_.:-]*", output):
        raise SystemExit(f"omanix-overlay: bad output name {output!r}")
    if mode is not None and not MODE_RE.fullmatch(mode):
        raise SystemExit(f"omanix-overlay: bad mode {mode!r}")
    rel = "hypr/monitors.lua"
    p = env.overlay / rel
    text = p.read_text() if p.exists() else empty_overlay(rel, env)
    pre, block, post = _split_block(text)
    rules = {("" if o == '""' else o): (sc, md or "preferred") for o, sc, md in RULE_RE.findall(block)}
    gdk_old = re.search(r"^-- gdk (\S+)$", block, re.M)
    rules[output] = (scale, mode or rules.get(output, (None, "preferred"))[1])
    gdk = gdk or (gdk_old.group(1) if gdk_old else None)
    lines = [SCALE_BEGIN]
    for out, (sc, md) in rules.items():
        lines.append(f"-- rule {out or chr(34) * 2} {sc} {md}")
        val = f'"{sc}"' if sc == "auto" else sc
        lines.append(f'hl.monitor({{ output = "{out}", mode = "{md}", position = "auto", scale = {val} }})')
    if gdk:
        lines.append(f"-- gdk {gdk}")
        lines.append(f'hl.env("GDK_SCALE", "{gdk}")')
    lines.append(SCALE_END)
    atomic_write(p, pre.rstrip("\n") + "\n" + "\n".join(lines) + "\n" + post)


def _split_block(text: str) -> tuple[str, str, str]:
    if SCALE_BEGIN in text and SCALE_END in text:
        a = text.index(SCALE_BEGIN)
        b = text.index(SCALE_END) + len(SCALE_END)
        return text[:a], text[a:b], text[b:].lstrip("\n")
    return text, "", ""


# ---------------------------------------------------------------- shell.json rebase


def merge3(base, ours, theirs, path="", conflicts=None):
    """Three-way merge (base, overlay, new defaults). Objects recurse;
    arrays and scalars are atomic; on a conflict the overlay wins and the
    path is reported (§f.4.7)."""
    if conflicts is None:
        conflicts = []
    if isinstance(base, dict) and isinstance(ours, dict) and isinstance(theirs, dict):
        out = {}
        for k in list(ours.keys()) + [k for k in theirs if k not in ours]:
            b, o, t = base.get(k, _MISSING), ours.get(k, _MISSING), theirs.get(k, _MISSING)
            r = merge3(b, o, t, f"{path}/{k}", conflicts)
            if r is not _MISSING:
                out[k] = r
        return out
    if ours == theirs:
        return ours
    if ours == base:
        return theirs  # only the defaults changed
    if theirs == base:
        return ours  # only the human changed it
    conflicts.append(path or "/")
    return ours


class _Missing:
    def __repr__(self) -> str:
        return "<missing>"


_MISSING = _Missing()


def cmd_rebase(env: Env, defaults: Path | None = None) -> list[str]:
    defaults = defaults or env.omarchy / "config/omarchy/shell.json"
    user = env.shell / "shell.json"
    base_p = env.shell / "shell.json.base"
    if not user.exists():
        return []
    new = json.loads(defaults.read_text())
    try:
        ours = json.loads(user.read_text())
    except json.JSONDecodeError:
        return ["/ (shell.json is not valid JSON; left as is)"]
    if base_p.exists():
        base = json.loads(base_p.read_text())
    else:
        # First rebase: the snapshot was taken from some defaults we don't
        # know; treat the overlay itself as the base, so nothing is lost.
        base = ours
    if base == new:
        return []
    conflicts: list[str] = []
    merged = merge3(base, ours, new, "", conflicts)
    atomic_write(user, json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
    atomic_write(base_p, json.dumps(new, indent=2, ensure_ascii=False) + "\n")
    m = load_manifest(env)
    m["shellDefaultsSha"] = sha256(defaults)
    m["rebaseConflicts"] = conflicts
    save_manifest(env, m)
    return conflicts


def cmd_snapshot_base(env: Env, defaults: Path | None = None) -> None:
    """Record the defaults a fresh shell.json snapshot was derived from."""
    defaults = defaults or env.omarchy / "config/omarchy/shell.json"
    base_p = env.shell / "shell.json.base"
    if (env.shell / "shell.json").exists() and not base_p.exists():
        atomic_write(base_p, defaults.read_text())


# ---------------------------------------------------------------- settle


def cmd_settle(env: Env, declared: dict) -> dict:
    """After a promoted switch: drop overlay keys now declared with the
    same value; empty whole-file overlays whose current sha is the one a
    'make it stick' change absorbed (§f.4.6).

    declared = {"kv": {rel: {key: value}}, "monospace": family,
                "keyboard": {"layouts": l, "variants": v}, "absorbed": {area: sha}}
    """
    st = stamp()
    report = {"removedKeys": {}, "emptied": [], "kept": []}
    for rel, keys in (declared.get("kv") or {}).items():
        fmt = OVERLAYS.get(rel, (None, None, None))[1]
        p = env.overlay / rel
        if fmt is None or not p.exists():
            continue
        text = p.read_text()
        removed = []
        for k, v in keys.items():
            cur = kv_get(text, fmt, k)
            if cur is not None and _norm(cur) == _norm(str(v)):
                text = kv_set(text, fmt, k, None)
                removed.append(k)
        if removed:
            atomic_write(p, text)
            report["removedKeys"][rel] = removed
    # Typed values with their own overlay syntax (W17): the monospace family
    # (overlay/fontconfig/fonts.conf) and the keyboard block of input.lua.
    mono = declared.get("monospace")
    if mono and font_family(env) == mono:
        backup(env.overlay / "fontconfig/fonts.conf", env, st)
        cmd_font(env, None)
        report["removedKeys"]["fontconfig/fonts.conf"] = ["monospace"]
    kb = declared.get("keyboard")
    ip = env.overlay / "hypr/input.lua"
    if kb and ip.exists():
        cur = kb_block(ip.read_text())
        if cur is not None and cur["layouts"] == kb.get("layouts") and cur["variants"] == (kb.get("variants") or ""):
            cmd_kb(env, None, None)
            report["removedKeys"]["hypr/input.lua"] = ["keyboard"]
    absorbed = declared.get("absorbed") or {}
    for area, want in absorbed.items():
        if not want:
            continue
        for rel, (_, fmt, a) in OVERLAYS.items():
            if a != area or fmt is not None or is_empty(rel, env):
                continue
            p = env.overlay / rel
            if snapshot_sha(env, area) == want:
                backup(p, env, st)
                atomic_write(p, empty_overlay(rel, env))
                report["emptied"].append(rel)
            else:
                report["kept"].append(rel)
    return report


def _norm(v: str) -> str:
    return v.strip().strip('"').strip("'")


def snapshot_sha(env: Env, area: str) -> str:
    """sha256 over an area's overlays, as omanix-runtime-snapshot reports it."""
    h = hashlib.sha256()
    for rel, (_, _, a) in sorted(OVERLAYS.items()):
        if a == area:
            p = env.overlay / rel
            h.update(rel.encode() + b"\0" + (p.read_bytes() if p.exists() else b"") + b"\0")
    if area == "shell":
        p = env.shell / "shell.json"
        h.update(b"shell.json\0" + (p.read_bytes() if p.exists() else b"") + b"\0")
    return h.hexdigest()


# ---------------------------------------------------------------- state


def cmd_state(env: Env) -> dict:
    """The typed runtime summary (runtime.json): no file contents, no free text."""
    st = env.state / "omarchy"
    theme = None
    for f in (st / "current/theme.name", st / "current/theme/name"):
        if f.exists():
            theme = f.read_text().strip()[:64]
            break
    bg = st / "current/background"
    toggles = sorted(p.name for p in (st / "toggles").glob("*")) if (st / "toggles").is_dir() else []
    overlays = {}
    for rel in OVERLAYS:
        p = env.overlay / rel
        if p.exists():
            overlays[rel] = {"sha256": sha256(p), "empty": is_empty(rel, env)}
    monitors = []
    mp = env.overlay / "hypr/monitors.lua"
    if mp.exists():
        _, block, _ = _split_block(mp.read_text())
        for out, sc, md in RULE_RE.findall(block):
            monitors.append({"output": "" if out == '""' else out, "scale": sc, "mode": md or "preferred"})
    shell_keys: list[str] = []
    sj = env.shell / "shell.json"
    if sj.exists():
        try:
            shell_keys = sorted(json.loads(sj.read_text()).keys())
        except json.JSONDecodeError:
            shell_keys = ["<invalid>"]
    keyboard = None
    ip = env.overlay / "hypr/input.lua"
    if ip.exists():
        keyboard = kb_block(ip.read_text())
    doc = {
        "schema": "omanix.runtime/v1",
        "monospace": font_family(env),
        "keyboard": keyboard,
        "theme": theme if theme and re.fullmatch(r"[A-Za-z0-9_.-]+", theme) else None,
        "wallpaper": os.path.realpath(bg) if bg.exists() else None,
        "monitors": monitors,
        "toggles": [t for t in toggles if re.fullmatch(r"[A-Za-z0-9_.-]+", t)],
        "shellKeys": shell_keys,
        "overlays": overlays,
    }
    return doc


def write_state(env: Env) -> None:
    doc = cmd_state(env)
    try:
        atomic_write(env.runtime, json.dumps(doc, indent=2, sort_keys=True) + "\n", mode=0o640)
    except OSError as e:  # the directory is created by tmpfiles; absent outside omanix
        print(f"omanix-overlay: cannot write {env.runtime}: {e}", file=sys.stderr)


# ---------------------------------------------------------------- runtime snapshot


def runtime_snapshot(env: Env, area: str) -> dict:
    """loom.snapshot/v1 for one area (§f.4.6): typed keys where the format
    parses (kv overlays, the monitors block, shell.json), plus each overlay's
    path, sha256 and, for overlays that don't parse into keys, its text.
    The resident's look skill maps it to options; snapshotSha is what
    omanix.runtime.absorbed.<area> records."""
    if area not in AREAS:
        raise SystemExit(f"omanix-runtime-snapshot: unknown area {area!r} (one of {', '.join(AREAS)})")
    files = []
    for rel, (_, fmt, a) in sorted(OVERLAYS.items()):
        if a != area or is_empty(rel, env):
            continue
        p = env.overlay / rel
        text = p.read_text()
        entry = {"path": f"overlay/{rel}", "sha256": sha256(p)}
        if fmt:
            keys = {}
            for l in body_lines(text, rel):
                s = l.strip()
                if s.startswith("["):
                    continue
                k = s.split(None, 1)[0] if fmt == "kitty" else s.split("=", 1)[0].strip()
                v = kv_get(text, fmt, k) if fmt != "toml" else None
                if v is not None:
                    keys[k] = v
            if fmt == "toml":
                sec = None
                for l in body_lines(text, rel):
                    s = l.strip()
                    if s.startswith("[") and s.endswith("]"):
                        sec = s[1:-1].strip()
                    elif "=" in s:
                        k, v = (x.strip() for x in s.split("=", 1))
                        keys[f"{sec}.{k}" if sec else k] = v
            entry["keys"] = keys
        elif rel == "hypr/input.lua" and KB_BEGIN in text:
            entry["keyboard"] = kb_block(text)
            a, b = text.index(KB_BEGIN), text.index(KB_END) + len(KB_END)
            rest = body_lines(text[:a] + text[b:], rel)
            if rest:
                entry["text"] = "\n".join(rest) + "\n"
        elif rel == "hypr/monitors.lua" and SCALE_BEGIN in text:
            pre, block, post = _split_block(text)
            entry["monitors"] = [{"output": "" if o == '""' else o, "scale": sc, "mode": md or "preferred"}
                                 for o, sc, md in RULE_RE.findall(block)]
            g = re.search(r"^-- gdk (\S+)$", block, re.M)
            if g:
                entry["gdkScale"] = int(g.group(1))
            rest = body_lines(pre + post, rel)
            if rest:
                entry["text"] = "\n".join(rest) + "\n"
        else:
            entry["text"] = "\n".join(body_lines(text, rel)) + "\n"
        files.append(entry)
    doc = {"schema": "loom.snapshot/v1", "area": area, "files": files, "snapshotSha": snapshot_sha(env, area)}
    if area == "shell":
        sj = env.shell / "shell.json"
        if sj.exists():
            try:
                doc["shell"] = json.loads(sj.read_text())
            except json.JSONDecodeError:
                doc["shell"] = None
    if area == "theme":
        doc["theme"] = cmd_state(env)["theme"]
    return doc


def snapshot_main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="omanix-runtime-snapshot", description="print a loom.snapshot/v1 for an area")
    ap.add_argument("area", choices=AREAS)
    a = ap.parse_args(argv)
    print(json.dumps(runtime_snapshot(Env(), a.area), indent=2, ensure_ascii=False))
    return 0


# ---------------------------------------------------------------- doctor


def cmd_doctor(env: Env) -> list[str]:
    out = []
    for rel in OVERLAYS:
        if not is_empty(rel, env):
            out.append(f"overlay not empty: {rel}")
    shadow = env.state / "hypr"
    if shadow.is_dir():
        for f in shadow.glob("*.lua"):
            out.append(f"shadows an HM file (bootstrap loads ~/.local/state first): {f}")
    m = load_manifest(env)
    for c in m.get("rebaseConflicts") or []:
        out.append(f"shell.json rebase conflict (your value kept): {c}")
    return out


# ---------------------------------------------------------------- CLI


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="omanix-overlay", description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("init", help="create the overlay layout (session init)")
    p.add_argument("--reset", action="store_true", help="empty every overlay first (omanix.home.overlays = reset)")
    p = sub.add_parser("reset", help="empty overlays (backup in the reclaim dir)")
    p.add_argument("targets", nargs="+")
    p = sub.add_parser("kv", help="set or remove a key in a terminal overlay")
    p.add_argument("overlay")
    p.add_argument("key")
    p.add_argument("value", nargs="?")
    p.add_argument("--unset", action="store_true")
    p = sub.add_parser("get", help="print a key's value in a terminal overlay (exit 1 if unset)")
    p.add_argument("overlay")
    p.add_argument("key")
    p = sub.add_parser("font", help="set the monospace family in overlay/fontconfig/fonts.conf")
    p.add_argument("family", nargs="?")
    p.add_argument("--unset", action="store_true")
    p = sub.add_parser("kb", help="set the keyboard layouts in overlay/hypr/input.lua")
    p.add_argument("layouts", nargs="?")
    p.add_argument("variants", nargs="?", default="")
    p.add_argument("--unset", action="store_true")
    p = sub.add_parser("hypr-scale", help="set a monitor scale in overlay/hypr/monitors.lua")
    p.add_argument("output", help='output name, or "" for every output')
    p.add_argument("scale")
    p.add_argument("--gdk")
    p.add_argument("--mode", help='the mode to keep, e.g. 2880x1800@120 (default "preferred")')
    p = sub.add_parser("rebase", help="rebase shell.json onto the current defaults")
    p.add_argument("--defaults", type=Path)
    p = sub.add_parser("settle", help="drop overlay content now declared (after make it stick)")
    p.add_argument("declared", type=Path, help="JSON: {kv: {overlay: {key: value}}, absorbed: {area: sha}}")
    sub.add_parser("state", help="write runtime.json")
    sub.add_parser("doctor", help="list overlays, conflicts and shadow files")
    sub.add_parser("path", help="print the overlay directory")
    a = ap.parse_args(argv)
    env = Env()

    if a.cmd == "init":
        cmd_init(env, a.reset)
        cmd_snapshot_base(env)
        for c in cmd_rebase(env):
            print(f"shell.json: kept your value at {c}", file=sys.stderr)
        write_state(env)
    elif a.cmd == "reset":
        for d in do_reset(env, resolve_targets(a.targets)):
            print(f"reset {d}")
        write_state(env)
    elif a.cmd == "kv":
        cmd_kv(env, a.overlay, a.key, None if a.unset else a.value)
        write_state(env)
    elif a.cmd == "get":
        v = cmd_get(env, a.overlay, a.key)
        if v is None:
            return 1
        print(v)
    elif a.cmd == "font":
        if not a.unset and not a.family:
            raise SystemExit("omanix-overlay font: give a family or --unset")
        cmd_font(env, None if a.unset else a.family)
        write_state(env)
    elif a.cmd == "kb":
        if not a.unset and not a.layouts:
            raise SystemExit("omanix-overlay kb: give layouts or --unset")
        cmd_kb(env, None if a.unset else a.layouts, a.variants)
        write_state(env)
    elif a.cmd == "hypr-scale":
        cmd_hypr_scale(env, a.output, a.scale, a.gdk, a.mode)
        write_state(env)
    elif a.cmd == "rebase":
        for c in cmd_rebase(env, a.defaults):
            print(f"conflict (kept yours): {c}")
    elif a.cmd == "settle":
        print(json.dumps(cmd_settle(env, json.loads(a.declared.read_text())), indent=2))
        write_state(env)
    elif a.cmd == "state":
        write_state(env)
    elif a.cmd == "doctor":
        problems = cmd_doctor(env)
        print("\n".join(problems) if problems else "nothing to report")
    elif a.cmd == "path":
        print(env.overlay)
    return 0


if __name__ == "__main__":
    sys.exit(main())
