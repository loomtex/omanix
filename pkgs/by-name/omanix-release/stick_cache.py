"""Build the installer's CACHE partition contents (lib/installer.nix).

A file:// binary cache in nixpkgs' make-binary-cache layout of every path in
the `closure` graph that is not in the `live` graph: the live store already
has those, and nixos-install copies from it. Runs inside a derivation with
__structuredAttrs and exportReferencesGraph {closure, live}.

Also writes `omanix-cache.json` (counts and sizes) for checks.closure-budget.
"""

import argparse
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--level", type=int, default=19)
    a = ap.parse_args()
    out = Path(os.environ["out"])
    store = os.environ["NIX_STORE"]
    attrs = json.loads(Path(os.environ["NIX_ATTRS_JSON_FILE"]).read_text())
    live = {i["path"] for i in attrs["live"]}
    items = [i for i in attrs["closure"] if i["path"] not in live]
    (out / "nar").mkdir(parents=True)
    (out / "nix-cache-info").write_text(f"StoreDir: {store}\n")

    def one(item):
        h = item["path"][len(store) + 1:].split("-")[0]
        tmp = out / "nar" / f"{h}.tmp"
        with open(tmp, "wb") as f:
            dump = subprocess.Popen(["nix-store", "--dump", item["path"]], stdout=subprocess.PIPE)
            subprocess.run(["zstd", "-q", f"-{a.level}", "-T1", "-c"], stdin=dump.stdout, stdout=f, check=True)
            if dump.wait() != 0:
                raise RuntimeError(f"nix-store --dump {item['path']} failed")
        fh = subprocess.run(["nix-hash", "--base32", "--type", "sha256", "--flat", str(tmp)],
                            capture_output=True, check=True, text=True).stdout.strip()
        size = tmp.stat().st_size
        url = f"nar/{fh}.nar.zst"
        tmp.rename(out / url)
        refs = " ".join(r[len(store) + 1:] for r in item["references"])
        (out / f"{h}.narinfo").write_text(
            f"StorePath: {item['path']}\nURL: {url}\nCompression: zstd\nFileHash: sha256:{fh}\n"
            f"FileSize: {size}\nNarHash: {item['narHash']}\nNarSize: {item['narSize']}\nReferences: {refs}\n")
        return size, item["narSize"]

    workers = int(os.environ.get("NIX_BUILD_CORES", "4") or "4") or 4
    with ThreadPoolExecutor(max_workers=workers) as ex:
        sizes = list(ex.map(one, sorted(items, key=lambda i: -i["narSize"])))
    (out / "omanix-cache.json").write_text(json.dumps({
        "paths": len(items), "skippedLive": len(attrs["closure"]) - len(items),
        "fileSize": sum(s for s, _ in sizes), "narSize": sum(n for _, n in sizes), "zstdLevel": a.level,
    }, indent=1) + "\n")


if __name__ == "__main__":
    main()
