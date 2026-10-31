"""demo-stick: the replay resident's half of "make it stick" (DESIGN §f.4.6
step 4, the `look` skill's mapping), scripted for the demo. Reads the
loom.snapshot/v1 attachments of the human's last message from ~/inbox and
edits configuration.nix:

  theme     omanix.theme.default (the existing line, rewritten in place)
  monitors  omanix.hyprland.monitors + gdkScale, absorbed.monitors = <sha>
  font      omanix.fonts.size / monospace from the terminal kv keys
  look      known hypr keys (general.gaps_in/gaps_out) → omanix.hyprland.settings,
            absorbed.look = <sha>

  demo-stick [SNAPSHOT.json...]   (default: the newest attachments in ~/inbox)
"""

import glob
import json
import os
import re
import sys

NUM = re.compile(r"^-?[0-9]+(\.[0-9]+)?$")


def newest_snapshots():
    files = sorted(glob.glob(os.path.expanduser("~/inbox/*/*.json")), key=os.path.getmtime)
    docs = []
    for f in files:
        try:
            d = json.load(open(f))
        except (OSError, ValueError):
            continue
        if d.get("schema") == "loom.snapshot/v1":
            docs.append(d)
    by_area = {}
    for d in docs:                      # newest per area wins
        by_area[d["area"]] = d
    return list(by_area.values())


def nix(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return json.dumps(v)


def main(argv):
    docs = [json.load(open(f)) for f in argv] if argv else newest_snapshots()
    if not docs:
        print("demo-stick: no snapshot attached", file=sys.stderr)
        return 1
    conf = open("configuration.nix").read()
    add = []
    for d in sorted(docs, key=lambda d: d["area"]):
        area, sha = d["area"], d.get("snapshotSha")
        if area == "theme" and d.get("theme"):
            name = d["theme"].strip().lower().replace(" ", "-")
            conf, n = re.subn(r'omanix\.theme\.default = "[^"]*";', f'omanix.theme.default = "{name}";', conf)
            if n != 1:
                add.append(f'  omanix.theme.default = "{name}";')
        for f in d.get("files", []):
            if area == "monitors" and "monitors" in f:
                rules = " ".join("{ " + " ".join(f"{k} = {nix(v if k != 'scale' else (float(v) if NUM.match(str(v)) else v))};"
                                                 for k, v in (("output", m["output"]), ("mode", m["mode"]), ("position", "auto"), ("scale", m["scale"])))
                                 + " }" for m in f["monitors"])
                add.append(f"  omanix.hyprland.monitors = [ {rules} ];")
                if "gdkScale" in f:
                    add.append(f"  omanix.hyprland.gdkScale = {f['gdkScale']};")
                add.append(f'  omanix.runtime.absorbed.monitors = "{sha}";')
            if area == "font" and "keys" in f and f["path"].endswith("kitty.conf"):
                k = f["keys"]
                if "font_size" in k:
                    add.append(f"  omanix.fonts.size = {int(float(k['font_size']))};")
                if "font_family" in k:
                    add.append(f"  omanix.fonts.monospace = {json.dumps(k['font_family'])};")
            if area == "look" and f["path"].endswith("hypr/looknfeel.lua"):
                for key in ("gaps_in", "gaps_out"):
                    m = re.search(rf"\b{key}\s*=\s*([0-9]+)", f.get("text", ""))
                    if m:
                        add.append(f"  omanix.hyprland.settings.general.{key} = {m.group(1)};")
                add.append(f'  omanix.runtime.absorbed.look = "{sha}";')
    lines = conf.rstrip("\n").split("\n")
    end = max(i for i, l in enumerate(lines) if l.strip() == "}")
    lines[end:end] = add
    open("configuration.nix", "w").write("\n".join(lines) + "\n")
    print("\n".join(add))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
