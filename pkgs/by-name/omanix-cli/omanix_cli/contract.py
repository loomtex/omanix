"""The CLI contract (§h.8) as code: every command's --json output is an
envelope {ok, command, exit[, error]} and, when ok, matches the output
schema in commands.json. checks.cli-contract runs every command in a VM and
feeds each output through `python -m omanix_cli.contract`."""

from __future__ import annotations

import json
import sys

TYPES = {"object": dict, "array": list, "string": str, "integer": int, "boolean": bool, "number": (int, float)}


def validate(doc, schema: dict, where: str = "$") -> list[str]:
    errs = []
    t = schema.get("type")
    if t and not (isinstance(doc, TYPES[t]) and not (t in ("integer", "number") and isinstance(doc, bool))):
        return [f"{where}: expected {t}, got {type(doc).__name__}"]
    if "enum" in schema and doc not in schema["enum"]:
        errs.append(f"{where}: {doc!r} not in {schema['enum']}")
    if isinstance(doc, dict):
        for k in schema.get("required", []):
            if k not in doc:
                errs.append(f"{where}: missing {k!r}")
        for k, s in (schema.get("properties") or {}).items():
            if k in doc and doc[k] is not None:
                errs += validate(doc[k], s, f"{where}.{k}")
    if isinstance(doc, list) and "items" in schema:
        for i, x in enumerate(doc):
            errs += validate(x, schema["items"], f"{where}[{i}]")
    return errs


ENVELOPE = {"type": "object", "required": ["ok", "command", "exit"],
            "properties": {"ok": {"type": "boolean"}, "command": {"type": "string"}, "exit": {"type": "integer", "enum": [0, 1, 2, 3, 4, 5]}}}


def check_output(entry: dict, doc, exit_code: int | None = None) -> list[str]:
    errs = validate(doc, ENVELOPE)
    if errs:
        return errs
    if exit_code is not None and doc["exit"] != exit_code:
        errs.append(f"exit field {doc['exit']} != process exit {exit_code}")
    if doc["ok"] != (doc["exit"] == 0):
        errs.append("ok must be exit == 0")
    if doc["ok"]:
        errs += validate(doc, dict(entry.get("output", {}), type="object"))
    elif not isinstance(doc.get("error"), str) and doc["exit"] not in (3,):
        # a failed run says why (exit 3 is a card waiting, with its own fields)
        if not entry.get("output") or validate(doc, dict(entry["output"], type="object")):
            errs.append("a failed run carries an error string")
    return errs


def help_errors(entry_help: dict) -> list[str]:
    errs = []
    for k in ("command", "description", "args", "exitCodes", "output"):
        if k not in entry_help:
            errs.append(f"--help --json: missing {k}")
    if not entry_help.get("description"):
        errs.append("--help --json: empty description")
    return errs


def main(argv=None) -> int:
    """contract <commands.json> <group> <name> <exit code> < output"""
    argv = list(sys.argv[1:] if argv is None else argv)
    reg = json.load(open(argv[0]))
    entry = reg["commands"][argv[1]][argv[2]]
    text = sys.stdin.read()
    try:
        doc = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"not JSON ({e}): {text[:300]!r}")
        return 1
    if len(argv) > 4 and argv[4] == "help":
        errs = help_errors(doc)
    else:
        errs = check_output(entry, doc, int(argv[3]))
    for e in errs:
        print(e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
