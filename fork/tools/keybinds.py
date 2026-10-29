"""checks.keybind-conflicts: no chord is bound twice in the effective config.

Reads Lua as text (never runs it): the fork's default binding modules in the
order default/hypr/omarchy.lua requires them, then the host's HM
bindings.lua. o.bind / hl.bind / o.bind_toggle / o.bind_hold add a chord,
hl.unbind removes it, o.rebind replaces it. A chord added while it is
already bound is a conflict. Binds inside an `if` are counted as active
(the worst case); a conflict between two branches of one if/else is not
reported, nor a chord bound twice in one file (upstream stacks dispatchers
that way on purpose: Hyprland runs every bind of a chord).

usage: keybinds.py OMARCHY_PATH HM_BINDINGS_LUA
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

CALL = re.compile(r'\b(o\.bind_toggle|o\.bind_hold|o\.rebind|o\.bind|hl\.bind|hl\.unbind)\(\s*"([^"]+)"(?:\s*,\s*("([^"]*)"|nil))?')
MODS = ["SUPER", "CTRL", "ALT", "SHIFT"]
ALIASES = {"CONTROL": "CTRL", "MOD4": "SUPER", "WIN": "SUPER", "MOD1": "ALT"}


def norm(chord: str) -> str:
    parts = [ALIASES.get(p.strip().upper(), p.strip().upper()) for p in chord.split("+") if p.strip()]
    mods = sorted({p for p in parts if p in MODS}, key=MODS.index)
    keys = [p for p in parts if p not in MODS]
    return " + ".join(mods + keys)


def binding_modules(omarchy: Path) -> list[Path]:
    text = (omarchy / "default/hypr/omarchy.lua").read_text()
    mods = re.findall(r'(?:require|require_optional\.module)\("(default\.hypr\.bindings\.[a-z0-9_-]+)"\)', text)
    return [omarchy / (m.replace(".", "/") + ".lua") for m in mods]


def scan(files: list[Path]) -> list[str]:
    bound: dict[str, tuple[str, int, str, tuple]] = {}
    problems = []
    for f in files:
        if not f.exists():
            continue
        # track if/elseif/else branches so binds in exclusive branches don't clash
        stack: list[list] = []  # [if-id, branch-index]
        ifs = 0
        for n, line in enumerate(f.read_text().splitlines(), 1):
            s = line.split("--", 1)[0]
            if re.search(r"\bif\b.*\bthen\b", s) and not re.search(r"\bend\b", s):
                ifs += 1
                stack.append([ifs, 0])
            elif re.match(r"\s*(elseif\b|else\b)", s) and stack:
                stack[-1][1] += 1
            elif re.match(r"\s*end\b", s) and stack:
                stack.pop()
            branch = tuple(tuple(x) for x in stack)
            for m in CALL.finditer(s):
                fn, chord = m.group(1), norm(m.group(2))
                where = f"{f.name}:{n}"
                if fn == "hl.unbind":
                    bound.pop(chord, None)
                    continue
                if fn == "o.rebind":
                    bound[chord] = (where, n, m.group(4) or "", branch)
                    continue
                if chord in bound:
                    prev = bound[chord]
                    # Upstream stacks dispatchers on one chord within a file
                    # (ALT + TAB cycles, then brings to top): Hyprland runs both.
                    if prev[0].split(":")[0] == f.name or _exclusive(prev[3], branch):
                        continue
                    problems.append(f"{chord}: bound at {prev[0]} ({prev[2]!r}) and again at {where} ({m.group(4) or ''!r})")
                bound[chord] = (where, n, m.group(4) or "", branch)
    return problems


def _exclusive(a: tuple, b: tuple) -> bool:
    """Two branches of the same if (same if-id, different branch index)."""
    for x, y in zip(a, b):
        if x[0] == y[0] and x[1] != y[1]:
            return True
        if x != y:
            return False
    return False


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    omarchy, hm = Path(argv[0]), Path(argv[1])
    problems = scan(binding_modules(omarchy) + [hm])
    if problems:
        print("\n".join(problems))
        return 1
    print("keybind-conflicts: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
