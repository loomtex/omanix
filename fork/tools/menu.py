"""The intent menu (DESIGN §h.5): build it, and check fork/intents.toml.

Runs in the nix sandbox with `python3 -I`; reads the pinned menu as data and
executes nothing from it.

  menu.py build <upstream.jsonc> <intents.toml> <menu-extra.jsonc> <host-items.json> <agent> <out-dir> [<hidden.json>]
      out-dir/omarchy-menu.jsonc   upstream order; gui rows unchanged (or with
                                   their override), intent rows lose `action`
                                   and gain `intent`/`skill`/`manual`, drop rows
                                   are omitted; then menu-extra, then host items.
                                   Ids in hidden.json (a list; omanix.menu.hidden,
                                   e.g. the theme lock's rows) get "when": "false";
                                   an id that is not in the menu fails the build.
      out-dir/intents.json         { id: {label, text, skill, manual, touches,
                                   provider?} } for `omarchy-shell omanix.chat
                                   intent <id>` and the Do-it-yourself view

  menu.py check <upstream.jsonc> <intents.toml> <menu-extra.jsonc> <shipped-bin-dir>
      checks.menu-intents (§h.5.2 step 4).
"""
import json
import os
import re
import sys
import tomllib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsonc  # noqa: E402

FIELDS = {"label", "value", "selection"}
TEMPLATE = re.compile(r"\{([^{}]*)\}")
KINDS = ("gui", "intent", "drop")
# Functions the menu's guard batch defines before evaluating when/checked/
# disabled (MenuModel.js guardHelpers, P6).
GUARD_FUNCS = {"omarchy-pkg-present", "omarchy-pkg-missing", "omarchy-cmd-present"}
CMD = re.compile(r"(?<![A-Za-z0-9_./-])(omarchy-[a-z0-9][a-z0-9-]*[a-z0-9])\b")


def load_jsonc(path):
    """Ordered dict of a .jsonc object (Python dicts keep insertion order)."""
    return json.loads(jsonc.drop_trailing_commas(jsonc.strip(open(path, encoding="utf-8").read())))


def actionable(e):
    return bool(e.get("action") or e.get("provider"))


def entry_line(eid, e):
    return "  " + json.dumps(eid, ensure_ascii=False) + ": " + json.dumps(e, ensure_ascii=False, separators=(",", ":")) + ","


def place(order, items, after):
    """Insert (id, entry) after `after` (or its last descendant), else at the end."""
    for eid, e in items:
        if after.get(eid) and after[eid] in order:
            anchor = after[eid]
            idx = max(i for i, k in enumerate(order) if k == anchor or k.startswith(anchor + "."))
            order.insert(idx + 1, eid)
        else:
            order.append(eid)


def build(upstream, intents_path, extra_path, host_path, agent, out_dir, hidden_path=None):
    menu = load_jsonc(upstream)
    rows = tomllib.load(open(intents_path, "rb"))["entry"]
    extra = load_jsonc(extra_path)
    host = json.load(open(host_path))
    out, order, table = {}, [], {}
    for eid, e in menu.items():
        r = rows.get(eid)
        if not actionable(e) or r is None:
            out[eid] = e
            order.append(eid)
            continue
        if r["kind"] == "drop":
            continue
        e = dict(e)
        if r["kind"] == "gui":
            for k in ("action", "label"):
                if k in r:
                    e[k] = r[k]
        else:
            e.pop("action", None)
            for k in ("when", "provider"):
                if k in r:
                    if r[k]:
                        e[k] = r[k]
                    else:
                        e.pop(k, None)
            e["intent"] = r["text"]
            e["skill"] = r["skill"]
            if r.get("manual"):
                e["manual"] = r["manual"]
            e["description"] = f"Asks {agent}"
            table[eid] = {"label": e.get("label", eid), "text": r["text"], "skill": r["skill"],
                          "manual": r.get("manual", ""), "touches": r.get("touches", []),
                          "provider": e.get("provider", "")}
        out[eid] = e
        order.append(eid)
    after = {}
    later = []
    for eid, e in list(extra.items()) + list(host.items()):
        e = {k: (v.replace("{agent}", agent) if isinstance(v, str) else v) for k, v in e.items()}
        if e.get("after"):
            after[eid] = e.pop("after")
        e = {k: v for k, v in e.items() if v is not None}
        # A host item's intent may name an intent row (its text and skill are
        # used) or be the text itself.
        if e.get("intent") in table:
            row = table[e["intent"]]
            e.setdefault("skill", row["skill"])
            e["intent"] = row["text"]
        if e.get("intent"):
            e.pop("action", None)
            e.setdefault("description", f"Asks {agent}")
            table[eid] = {"label": e.get("label", eid), "text": e["intent"], "skill": e.get("skill", ""),
                          "manual": e.get("manual", ""), "touches": [], "provider": ""}
        out[eid] = e
        later.append((eid, e))
    place(order, later, after)
    hidden = json.load(open(hidden_path)) if hidden_path else []
    missing = sorted(h for h in hidden if h not in out)
    if missing:
        sys.exit("menu.py build: rows to hide are not in the menu: " + ", ".join(missing))
    for eid in hidden:
        out[eid] = dict(out[eid], when="false")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "omarchy-menu.jsonc"), "w", encoding="utf-8") as f:
        f.write("{\n  // omanix: generated from the pinned omarchy-menu.jsonc, fork/intents.toml,\n"
                "  // fork/menu-extra.jsonc and omanix.menu.items (DESIGN §h.5.2). Read-only.\n")
        f.write("\n".join(entry_line(k, out[k]) for k in order) + "\n}\n")
    with open(os.path.join(out_dir, "intents.json"), "w", encoding="utf-8") as f:
        json.dump(table, f, indent=1, ensure_ascii=False)
        f.write("\n")


# ---- check ---------------------------------------------------------------

errors = []


def fail(msg):
    errors.append(msg)


def commands(script):
    """omarchy-* command words of a bash string (bashlex), incl. $(…) and pipes."""
    try:
        import bashlex
    except ImportError:
        return set(CMD.findall(script))
    found = set()

    class V(bashlex.ast.nodevisitor):
        def visitcommand(self, node, parts):
            words = [p for p in parts if p.kind == "word"]
            if words:
                w = words[0].word
                if w in ("exec", "setsid", "uwsm-app", "--", "sudo", "pkexec", "timeout", "env"):
                    rest = [x.word for x in words[1:] if not x.word.startswith("-")]
                    w = rest[0] if rest else w
                found.add(w)
            # arguments of the launchers are themselves commands
            if words and words[0].word.startswith("omarchy-launch-floating-terminal") and len(words) > 1:
                found.update(commands(words[1].word))

    try:
        for tree in bashlex.parse(script):
            V().visit(tree)
    except Exception:  # bashlex can't parse some $'…' forms; fall back to the token scan
        return set(CMD.findall(script))
    return {w for w in found if w.startswith("omarchy-")}


def template_fields(text):
    return set(TEMPLATE.findall(text or ""))


def check(upstream, intents_path, extra_path, bindir):
    menu = load_jsonc(upstream)
    doc = tomllib.load(open(intents_path, "rb"))
    rows = doc.get("entry", {})
    known = set(doc.get("skills", {}).get("known", []))
    shipped = set(os.listdir(bindir)) | GUARD_FUNCS
    extra = load_jsonc(extra_path)

    for eid, e in menu.items():
        if actionable(e) and eid not in rows:
            fail(f"{eid}: upstream entry has no row in intents.toml")
    for eid, r in rows.items():
        e = menu.get(eid)
        if e is None:
            fail(f"{eid}: stale row (no such entry at the pin)")
            continue
        if not actionable(e):
            fail(f"{eid}: row for a submenu without a provider")
        k = r.get("kind")
        if k not in KINDS:
            fail(f"{eid}: kind must be one of {', '.join(KINDS)}, not {k!r}")
            continue
        if k == "drop":
            if not r.get("why"):
                fail(f"{eid}: drop row without why")
            continue
        if k == "intent":
            if not str(r.get("text", "")).strip():
                fail(f"{eid}: intent row with empty text")
            if r.get("skill") not in known:
                fail(f"{eid}: unknown skill {r.get('skill')!r}")
            for f in ("text", "manual"):
                bad = template_fields(r.get(f, "")) - FIELDS
                if bad:
                    fail(f"{eid}: {f} uses template field(s) {sorted(bad)}; only {{label}} {{value}} {{selection}}")
            guards = {g: (r[g] if g in r else e.get(g, "")) for g in ("when", "checked", "disabled")}
        else:
            action = r.get("action", e.get("action", ""))
            for c in sorted(commands(action) - shipped):
                fail(f"{eid}: gui action calls {c}, which omanix does not ship")
            guards = {g: e.get(g, "") for g in ("when", "checked", "disabled")}
        for g, expr in guards.items():
            for c in sorted(commands(expr or "") - shipped):
                fail(f"{eid}: {g} guard calls {c}, which omanix does not ship (override it in intents.toml)")

    for eid, e in extra.items():
        if eid in menu:
            fail(f"menu-extra {eid}: collides with an upstream id")
        if "action" in e:
            for c in sorted(commands(e["action"]) - shipped):
                fail(f"menu-extra {eid}: action calls {c}, which omanix does not ship")
        elif not any(k in e for k in ("target", "intent")) and not any(k.startswith(eid + ".") for k in extra):
            fail(f"menu-extra {eid}: no action, target or intent")

    n = {k: sum(1 for r in rows.values() if r.get("kind") == k) for k in KINDS}
    print(f"menu-intents: {len(rows)} rows ({n['gui']} gui, {n['intent']} intent, {n['drop']} drop), "
          f"{len(extra)} omanix entries, {len(known)} skills")
    for m in errors:
        print("FAIL:", m)
    return 1 if errors else 0


if __name__ == "__main__":
    cmd, *args = sys.argv[1:]
    if cmd == "build":
        build(*args)
    elif cmd == "check":
        sys.exit(check(*args))
    else:
        sys.exit(f"unknown command {cmd}")
