"""checks.script-preamble-identical (§e.10): every scripts/*.sh is
`#!/usr/bin/env bash`, one comment line, then the preamble block, byte for
byte the same in each; after it, the only thing a script may do before
verification is call omanix_run or omanix_verify."""

import pathlib
import re
import sys

BEGIN = "# ---- omanix preamble:"
END = "# ---- end of omanix preamble ----"
EXPECTED = {"configure.sh", "flash-usb.sh", "verify-release.sh", "setup-remotes.sh"}

root = pathlib.Path(sys.argv[1])
scripts = sorted(p for p in root.glob("*.sh"))
errors, blocks = [], {}
names = {p.name for p in scripts}
if names != EXPECTED:
    errors.append(f"scripts/*.sh are {sorted(names)}, expected {sorted(EXPECTED)}")
for p in scripts:
    lines = p.read_text().split("\n")
    if lines[0] != "#!/usr/bin/env bash" or not lines[1].startswith(f"# scripts/{p.name}: "):
        errors.append(f"{p.name}: must start with the shebang and a '# scripts/{p.name}: …' line")
        continue
    if not lines[2].startswith(BEGIN):
        errors.append(f"{p.name}: line 3 must open the preamble")
        continue
    try:
        end = lines.index(END)
    except ValueError:
        errors.append(f"{p.name}: no end-of-preamble marker")
        continue
    blocks[p.name] = "\n".join(lines[2:end + 1])
    body = [l for l in lines[end + 1:] if l.strip() and not l.lstrip().startswith("#")]
    if not body or not re.match(r"^omanix_(run|verify)\b", body[0]):
        errors.append(f"{p.name}: the first command after the preamble must be omanix_run or omanix_verify")
distinct = set(blocks.values())
if len(distinct) > 1:
    ref = blocks[sorted(blocks)[0]]
    errors += [f"{n}: preamble differs from {sorted(blocks)[0]}" for n, b in sorted(blocks.items()) if b != ref]
for needle in ("allowed_signers", "trust <fingerprint>", "verify-tag", "OMANIX_DEV", "omanix-release", "exec nix"):
    if blocks and needle not in next(iter(blocks.values())):
        errors.append(f"the preamble lost {needle!r}")
if errors:
    print("FAIL: script-preamble-identical\n  " + "\n  ".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"PASS: script-preamble-identical ({len(blocks)} scripts, {len(next(iter(blocks.values())))} bytes)")
