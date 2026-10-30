"""omanix: the CLI the resident (and experts) drive (DESIGN §h.8).

Every command takes --json, never reads a TTY when --json is given, and
exits 0 ok, 1 failed, 2 usage/refused guard, 3 needs human approval (card
waiting), 4 rolled back, 5 offline/busy/retry later. Every verb only edits
files in the working copy and checks the result by evaluating it; none
switches the system, none is required (the same change can be made by
hand), and none refuses for policy reasons (V4).

The commands, their arguments and output schemas live in commands.json
(also the catalog's commands.json and checks.cli-contract's input).
`omanix <cmd> --help --json` prints one entry.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from . import common
from .common import Ctx, CliError, EXIT

_HANDLERS: dict[tuple[str, str], object] = {}


def handler(group: str, name: str):
    def deco(f):
        _HANDLERS[(group, name)] = f
        return f
    return deco


def _load_handlers():
    from . import cmd_info, cmd_edit, cmd_build, cmd_session  # noqa: F401  (register)


def _words(group: str, name: str) -> list[str]:
    return [name] if group == "core" else [group, name]


def _resolve(registry: dict, argv: list[str]):
    """(group, name, entry, rest) for argv, or None."""
    words = [a for a in argv if not a.startswith("-")]
    if not words:
        return None
    w = words[0]
    if w in registry.get("core", {}):
        i = argv.index(w)
        return "core", w, registry["core"][w], argv[:i] + argv[i + 1:]
    if w in registry and w != "core":
        i = argv.index(w)
        rest = argv[:i] + argv[i + 1:]
        sub = [a for a in rest if not a.startswith("-")]
        if sub and sub[0] in registry[w]:
            j = rest.index(sub[0])
            return w, sub[0], registry[w][sub[0]], rest[:j] + rest[j + 1:]
        return w, None, None, rest
    return None


def _parser(prog: str, entry: dict) -> argparse.ArgumentParser:
    p = common.Parser(prog=prog, description=entry.get("description"), add_help=False)
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.add_argument("--repo", help="the host repo working copy")
    for a in entry.get("args", []):
        kw = {k: v for k, v in a.items() if k in ("nargs", "default", "help", "action")}
        if a.get("type") == "int":
            kw["type"] = int
        if a["name"].startswith("-"):
            kw["dest"] = a["name"].lstrip("-").replace("-", "_")
        p.add_argument(a["name"], **kw)
    return p


def help_json(group: str, name: str, entry: dict, exit_codes: dict) -> dict:
    return {
        "command": "omanix " + " ".join(_words(group, name)),
        "group": group,
        "name": name,
        "description": entry.get("description", ""),
        "args": entry.get("args", []),
        "exitCodes": exit_codes,
        "output": entry.get("output", {}),
        "origin": entry.get("origin", "omanix"),
    }


def usage(registry: dict) -> str:
    lines = ["usage: omanix <command> [args] [--json]", "", "commands:"]
    for g, cmds in registry.items():
        for n, e in sorted(cmds.items()):
            lines.append(f"  {' '.join(_words(g, n)):<18} {e.get('description', '').split('.')[0]}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    as_json = "--json" in argv
    want_help = "--help" in argv or "-h" in argv
    reg = common.registry()
    commands = reg["commands"]
    r = _resolve(commands, argv)
    if r is None or r[1] is None:
        if want_help or not argv:
            if as_json:
                print(json.dumps({"command": "omanix", "commands": [help_json(g, n, e, reg["exitCodes"])
                                  for g, cs in commands.items() for n, e in cs.items()], "exitCodes": reg["exitCodes"]}, indent=2))
            else:
                print(usage(commands))
            return 0
        msg = f"unknown command: {' '.join(a for a in argv if not a.startswith('-'))}"
        common.emit_error(as_json, "omanix", EXIT.USAGE, msg + "\n" + usage(commands))
        return EXIT.USAGE
    group, name, entry, rest = r
    cmdname = " ".join(_words(group, name))
    if want_help:
        if as_json:
            print(json.dumps(help_json(group, name, entry, reg["exitCodes"]), indent=2))
        else:
            _parser("omanix " + cmdname, entry).print_help()
        return 0
    try:
        a = _parser("omanix " + cmdname, entry).parse_args([x for x in rest if x not in ("--help", "-h")])
    except CliError as e:
        common.emit_error(as_json, cmdname, e.code, e.message)
        return e.code
    if entry.get("command"):
        # extension commands (omanix.cli.commands.<g>.<n>.command)
        os.execvp(entry["command"], [entry["command"], *rest])
    _load_handlers()
    fn = _HANDLERS.get((group, name))
    if fn is None:
        common.emit_error(as_json, cmdname, EXIT.FAILED, f"{cmdname}: not implemented")
        return EXIT.FAILED
    ctx = Ctx(a, cmdname)
    try:
        out = fn(ctx, a) or {}
        code = out.pop("_exit", EXIT.OK) if isinstance(out, dict) else EXIT.OK
        common.emit(ctx, out, code)
        return code
    except CliError as e:
        common.emit_error(as_json, cmdname, e.code, e.message, e.data)
        return e.code
    except KeyboardInterrupt:
        return EXIT.FAILED


if __name__ == "__main__":
    sys.exit(main())
