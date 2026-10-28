"""One-off generator: fork.md appendices A and C -> fork/classify.toml.

fork.md (the reviewed design appendix) is the source; classify.toml is the
machine form. Run with python3 -I. Reads only markdown and a directory listing.
"""
import os
import re
import sys

CLASS = {"GUI": "KEEP-AS-GUI", "INTENT": "AGENT-INTENT", "ASSET": "ASSET",
         "NIX": "RE-EXPRESS-IN-NIX", "DROP": "DROP"}

PRIVILEGE = """
[privilege]
"omarchy-update-time" = "polkit"
"omarchy-restart-trackpad" = "unit"
"omarchy-restart-audio" = "unit"
"omarchy-brightness-display-apple" = "none"
"omarchy-toggle-hybrid-gpu" = "none"

# Kept shell QML/JS that uses sudo or pkexec, keyed to the patch that removes
# the use (W18). P20 is not in the design's patch table yet (contract issue).
[privilege-shell]
"shell/plugins/panels/tailscale/Service.qml" = "P18"
"shell/plugins/bar/indicators/PasswordlessSudo.qml" = "P7"
"shell/plugins/panels/elsewhen/Model.js" = "P20"
"""

md_path, src, out = sys.argv[1:4]
lines = open(md_path).read().splitlines()
a0 = lines.index("## Appendix A. bin/ mapping (558 scripts, `omarchy-` prefix omitted)")
b0 = next(i for i, l in enumerate(lines) if l.startswith("## Appendix B."))
c0 = next(i for i, l in enumerate(lines) if l.startswith("## Appendix C."))


def cells(line):
    # Split on unescaped pipes; "\\|" inside a cell is a regex alternation.
    return [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


bins, notes = {}, {}
for line in lines[a0:b0]:
    if not re.match(r"^\| \d+ \|", line):
        continue
    _, cls, scripts, mech = cells(line)[:4]
    for s in [x.strip() for x in scripts.split(",") if x.strip()]:
        name = s if s == "omarchy" else "omarchy-" + s
        if name in bins:
            continue  # first rule wins
        bins[name] = CLASS[cls]
        notes[name] = mech

paths = []
for line in lines[c0:]:
    if not line.startswith("| ") or line.startswith("| Class") or line.startswith("|---"):
        continue
    cls, rule = cells(line)[:2]
    rule = rule.strip("`").replace("\\|", "|")
    paths.append((CLASS[cls], rule))

present = sorted(os.listdir(os.path.join(src, "bin")))
missing = [b for b in present if b not in bins]
stale = sorted(b for b in bins if b not in present)


def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


with open(out, "w") as f:
    f.write("# Generated from docs fork.md appendices A and C (gen-classify.py), then\n")
    f.write("# reconciled by hand against the pinned tree (see [meta]). Every bin/omarchy-*\n")
    f.write("# script at the pin has exactly one class; checks.fork-classify enforces it.\n")
    f.write("# privilege = none|polkit|unit for KEEP-AS-GUI scripts that used root (§f.2.5).\n\n")
    f.write("[meta]\nrev = \"5978d93ae7da0a325b7493501911e3f1266cadd3\"\n")
    f.write("surveyed_on = \"bc220e7\"\n")
    f.write("stale_at_pin = [" + ", ".join(q(s) for s in stale) + "]\n\n")
    f.write("[bin]\n")
    for b in present:
        if b in bins:
            f.write(f"{q(b)} = {q(bins[b])}\n")
    for b in missing:
        f.write(f"{q(b)} = \"UNCLASSIFIED\"\n")
    f.write(PRIVILEGE)
    f.write("\n# Non-bin paths: first matching regex (full match) wins.\n")
    for cls, rule in paths:
        f.write(f"[[path]]\nclass = {q(cls)}\nregex = {q(rule)}\n")

print(f"classified {len(present) - len(missing)}/{len(present)}; missing {missing}; stale {stale}")
