"""checks.hw-quirks, the file half (§f.2.6). Reads the pinned tree as data.

  hwquirks.py <pinned-src> <hw-quirks.toml> <quirk-module-dir>

Fails when a file under install/hardware/** or install/user/hardware/** is
not a row's source, a [generic] entry or a [drop] entry; when a listed path
no longer exists at the pin; when a v1 row has no module or a module has no
v1 row.
"""
import os
import sys
import tomllib


def main(src, toml_path, module_dir):
    d = tomllib.load(open(toml_path, "rb"))
    quirks, generic, drop = d.get("quirk", {}), d.get("generic", {}), d.get("drop", {})
    errors = []
    mapped = {}
    for name, q in quirks.items():
        if q.get("status") not in ("v1", "deferred"):
            errors.append(f"quirk {name}: status must be v1 or deferred")
        if q.get("status") == "deferred" and not q.get("reason"):
            errors.append(f"quirk {name}: deferred without a reason")
        if "probe" not in q:
            errors.append(f"quirk {name}: no probe")
        for s in q.get("source", []):
            mapped.setdefault(s, []).append(f"quirk {name}")
    for s in generic:
        mapped.setdefault(s, []).append("generic")
    for s in drop:
        mapped.setdefault(s, []).append("drop")
    for s, owners in sorted(mapped.items()):
        if not os.path.exists(os.path.join(src, s)):
            errors.append(f"{s}: listed ({', '.join(owners)}) but not in the pinned tree")
        if len(owners) > 1 and not all(o.startswith("quirk") for o in owners):
            errors.append(f"{s}: listed more than once ({', '.join(owners)})")
    for base in ("install/hardware", "install/user/hardware"):
        for root, _, files in os.walk(os.path.join(src, base)):
            for f in files:
                rel = os.path.relpath(os.path.join(root, f), src)
                if rel not in mapped:
                    errors.append(f"{rel}: not mapped to a quirk row, [generic] or [drop] in fork/hw-quirks.toml")
    modules = {f[:-4] for f in os.listdir(module_dir) if f.endswith(".nix")}
    v1 = {n for n, q in quirks.items() if q.get("status") == "v1"}
    for n in sorted(v1 - modules):
        errors.append(f"quirk {n}: v1 but modules/omanix/hardware/quirks/{n}.nix is missing")
    for n in sorted(modules - v1):
        errors.append(f"modules/omanix/hardware/quirks/{n}.nix: no v1 row in fork/hw-quirks.toml")
    if errors:
        print("\n".join(errors))
        return 1
    print(f"hw-quirks: {len(v1)} v1 quirks, {len(quirks) - len(v1)} deferred, {len(mapped)} upstream files mapped")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
