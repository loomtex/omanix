"""checks.closure-dupes and checks.closure-budget (§e.1).

  closure.py dupes NAME=store-paths…
  closure.py budget --budget B --image NAME=DIR… --cache omanix-cache.json
                    --docs store-paths --closure NAME=store-paths… --out OUT
"""

import argparse
import json
import os
import re
import subprocess
import sys

STORE = re.compile(r"^/nix/store/[0-9a-z]{32}-(.*)$")
# the drivers package (not mesa-libgbm, which nixpkgs builds from its own pin,
# nor mesa-demos) by version; llvm and libllvm by major; python by major.minor
FAMILIES = {
    "Mesa": re.compile(r"^mesa-(\d+\.\d+(?:\.\d+)?)(?:-[a-z]+)?$"),
    "LLVM": re.compile(r"^(?:lib)?llvm-(\d+)\.\d+\.\d+(?:-[a-z]+)?$"),
    "Python": re.compile(r"^python(\d\.\d+)-(?:\d|[a-z])"),
}


def names(path):
    out = []
    for line in open(path):
        m = STORE.match(line.strip())
        if m:
            out.append(m.group(1))
    return out


def dupes(args):
    errors = []
    for spec in args:
        label, path = spec.split("=", 1)
        found = {}
        for n in names(path):
            for fam, rx in FAMILIES.items():
                m = rx.match(n)
                if m:
                    found.setdefault(fam, {}).setdefault(m.group(1), []).append(n)
        python3 = {n for n in names(path) if re.match(r"^python3-\d", n)}
        summary = ", ".join(f"{f} {sorted(v)}" for f, v in sorted(found.items()))
        print(f"{label}: {summary}; {sorted(python3)}")
        for fam, versions in found.items():
            if len(versions) > 1:
                detail = "; ".join(f"{v}: {', '.join(sorted(set(ns))[:4])}" for v, ns in sorted(versions.items()))
                errors.append(f"{label}: more than one {fam} ({detail})")
    if errors:
        print("FAIL: closure-dupes\n  " + "\n  ".join(errors), file=sys.stderr)
        sys.exit(1)
    print("PASS: closure-dupes")


def registration_sizes(store_paths):
    """narSize per path from closureInfo's registration file next to store-paths."""
    reg = os.path.join(os.path.dirname(store_paths), "registration")
    lines = open(reg).read().split("\n")
    sizes, i = {}, 0
    while i + 4 < len(lines) and lines[i]:
        path, size, nrefs = lines[i], int(lines[i + 2]), int(lines[i + 4])
        sizes[path] = size
        i += 5 + nrefs
    return sizes


def zstd_bytes(path):
    """The image as a .raw.zst download would be (zstd -10 --long=27)."""
    p = subprocess.Popen(["zstd", "-q", "-10", "--long=27", "-T0", "-c", path], stdout=subprocess.PIPE)
    n = 0
    for chunk in iter(lambda: p.stdout.read(1 << 20), b""):
        n += len(chunk)
    if p.wait() != 0:
        sys.exit(f"zstd failed on {path}")
    return n


def budget(a):
    b = json.load(open(a.budget))
    rep = {"budget": b, "images": {}, "closures": {}}
    for spec in a.image:
        label, d = spec.split("=", 1)
        raws = [f for f in os.listdir(d) if f.endswith(".raw")]
        if len(raws) != 1:
            sys.exit(f"{d}: expected one .raw image, found {raws}")
        f = os.path.join(d, raws[0])
        st = os.stat(f)
        parts = json.load(open(os.path.join(d, "repart-output.json")))
        rep["images"][label] = {"file": raws[0], "bytes": st.st_size, "allocatedBytes": st.st_blocks * 512,
                                "zstdBytes": zstd_bytes(f),
                                "partitions": {p["label"]: p["raw_size"] for p in parts}}
    rep["cache"] = json.load(open(a.cache))
    for spec in a.closure:
        label, p = spec.split("=", 1)
        s = registration_sizes(p)
        rep["closures"][label] = {"paths": len(s), "narBytes": sum(s.values())}
    sizes = registration_sizes(a.docs)
    docs = {p: n for p, n in sizes.items() if p.endswith("-doc")}
    rep["docOutputs"] = {"bytes": sum(docs.values()), "paths": sorted(os.path.basename(p) for p in docs)}

    gib, mib = 1024 ** 3, 1024 ** 2
    for label, key in (("offline", "offlineImage"), ("net", "netImage")):
        im = rep["images"][label]
        print(f"{label:7} image  {im['bytes'] / gib:6.2f} GiB raw, what a release ships (budget {b[key] / gib:.2f} GiB); "
              f"{im['zstdBytes'] / gib:.2f} GiB as .raw.zst, {im['allocatedBytes'] / gib:.2f} GiB allocated (sparse)")
        print("               " + ", ".join(f"{n} {b / mib:.0f} MiB" for n, b in im["partitions"].items()))
    print(f"CACHE          {rep['cache']['fileSize'] / gib:6.2f} GiB compressed, {rep['cache']['narSize'] / gib:.2f} GiB NAR, "
          f"{rep['cache']['paths']} paths ({rep['cache']['skippedLive']} already in the live store)")
    for label, c in rep["closures"].items():
        print(f"closure {label:18} {c['narBytes'] / gib:6.2f} GiB NAR, {c['paths']} paths")
    print(f"doc outputs    {rep['docOutputs']['bytes'] / mib:6.1f} MiB  (budget {b['docOutputs'] / mib:.0f} MiB): "
          + ", ".join(rep["docOutputs"]["paths"]))
    errors = []
    if rep["images"]["offline"]["bytes"] > b["offlineImage"]:
        errors.append("the offline image is over budget")
    if rep["images"]["net"]["bytes"] > b["netImage"]:
        errors.append("the net image is over budget")
    if rep["docOutputs"]["bytes"] > b["docOutputs"]:
        errors.append("doc outputs are over budget")
    rep["errors"] = errors
    if errors:
        print("FAIL: closure-budget\n  " + "\n  ".join(errors), file=sys.stderr)
        sys.exit(1)
    os.makedirs(a.out)
    with open(os.path.join(a.out, "closure-budget.json"), "w") as f:
        json.dump(rep, f, indent=1)
    print("PASS: closure-budget")


def main():
    if sys.argv[1] == "dupes":
        return dupes(sys.argv[2:])
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("--budget", required=True)
    ap.add_argument("--image", action="append", required=True)
    ap.add_argument("--cache", required=True)
    ap.add_argument("--docs", required=True)
    ap.add_argument("--closure", action="append", default=[])
    ap.add_argument("--out", required=True)
    budget(ap.parse_args())


if __name__ == "__main__":
    main()
