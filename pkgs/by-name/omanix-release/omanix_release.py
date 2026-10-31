"""omanix-release: build, sign and verify an omanix release (§e.1, §e.10, D11).

  omanix-release verify DIR [--signers F]
        SHA256SUMS.sig is by a pinned signer (namespace omanix-release), every
        file in DIR is listed in SHA256SUMS and matches it, and release.json
        names the version the files carry. `nix run .#verify-release` and
        scripts/verify-release.sh run this.
  omanix-release tree-sums ROOT
        writes ROOT/scripts/SHA256SUMS over the whole tree (what the
        scripts' preamble checks in a copy without git)
  omanix-release sign FILE --key K
        ssh-keygen -Y sign -n omanix-release: FILE.sig. K is an SSH key the
        agent or a token holds (Josh's YubiKey, D11), or a test key file.
  omanix-release sign-cache SRC OUT --key-file K
        a copy of the binary cache SRC with every narinfo signed by the nix
        key K (omanix-cache-1; the release skill decrypts it through an
        approval, D11), then `nix store verify` against its public key
  omanix-release build --repo R --tag T --out DIR
                       (--cache-key-file K | --signed-cache C) [--sign-key S]
        the release: verify tag T (SSH-signed by a signer in the tagged tree's
        release/allowed_signers), build the unsigned stick cache from the tag
        and sign it with K (or take C, signed by sign-cache beforehand), build
        the offline and net images from the tag with the signed cache, write
        stick-index.txt, cache-key.pub, release.json and SHA256SUMS, then sign
        SHA256SUMS with S and verify. Without S it stops before signing: the
        real signer is Josh's YubiKey, which only Josh's session can use.

Nothing here holds a key: keys are files or agent identities passed in, and
the dry run (docs in .claude/skills/release) passes throwaway ones.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

NAMESPACE = "omanix-release"
SYSTEM = "x86_64-linux"
SUMS, SIG = "SHA256SUMS", "SHA256SUMS.sig"


class ReleaseError(Exception):
    pass


def run(cmd, **kw):
    kw.setdefault("check", True)
    kw.setdefault("text", True)
    try:
        return subprocess.run(cmd, **kw)
    except subprocess.CalledProcessError as e:
        out = (e.stderr or e.stdout or "").strip()
        raise ReleaseError(f"{' '.join(map(str, cmd[:4]))}… failed ({e.returncode}){': ' + out[-2000:] if out else ''}")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def signers_principals(signers):
    keys = [line for line in open(signers) if line.strip() and not line.lstrip().startswith("#")]
    if not keys:
        raise ReleaseError(f"{signers} lists no signer (comments only): pin the release key first")
    return keys


# ── verification ───────────────────────────────────────────────────────────

def verify_sig(path, sig, signers):
    """The signature on `path` is by a principal in `signers` for the
    omanix-release namespace. Returns the principal."""
    signers_principals(signers)
    p = run(["ssh-keygen", "-Y", "find-principals", "-f", signers, "-s", sig], capture_output=True, check=False)
    principals = [x for x in p.stdout.split() if x]
    if p.returncode != 0 or not principals:
        raise ReleaseError(f"{os.path.basename(sig)} is not by a pinned release signer ({signers})")
    with open(path, "rb") as f:
        v = subprocess.run(["ssh-keygen", "-Y", "verify", "-f", signers, "-I", principals[0], "-n", NAMESPACE, "-s", sig],
                           stdin=f, capture_output=True)
    if v.returncode != 0:
        raise ReleaseError(f"{os.path.basename(sig)} doesn't verify: {v.stderr.decode().strip() or v.stdout.decode().strip()}")
    return principals[0]


def read_sums(path):
    sums = {}
    for n, line in enumerate(open(path), 1):
        parts = line.rstrip("\n").split(None, 1)
        if len(parts) != 2 or len(parts[0]) != 64:
            raise ReleaseError(f"{path}:{n}: not a sha256sum line")
        name = parts[1].lstrip("*")
        if name.startswith("/") or ".." in name.split("/"):
            raise ReleaseError(f"{path}:{n}: unsafe file name {name!r}")
        sums[name] = parts[0]
    return sums


def verify(d, signers):
    sums_path, sig = os.path.join(d, SUMS), os.path.join(d, SIG)
    for f in (sums_path, sig, signers):
        if not os.path.exists(f):
            raise ReleaseError(f"{f} is missing")
    principal = verify_sig(sums_path, sig, signers)
    sums = read_sums(sums_path)
    on_disk = sorted(f for f in os.listdir(d) if f not in (SUMS, SIG))
    unlisted = [f for f in on_disk if f not in sums]
    if unlisted:
        raise ReleaseError(f"not covered by SHA256SUMS: {', '.join(unlisted)}")
    for name, want in sorted(sums.items()):
        p = os.path.join(d, name)
        if not os.path.isfile(p):
            raise ReleaseError(f"{name} is listed in SHA256SUMS but missing")
        if sha256(p) != want:
            raise ReleaseError(f"{name} doesn't match SHA256SUMS")
    meta = {}
    if "release.json" in sums:
        meta = json.load(open(os.path.join(d, "release.json")))
        for img in meta.get("images", {}).values():
            if img["file"] not in sums:
                raise ReleaseError(f"release.json names {img['file']}, which SHA256SUMS doesn't list")
    return {"ok": True, "signer": principal, "files": sorted(sums), "version": meta.get("version"),
            "tag": meta.get("tag"), "commit": meta.get("commit")}


def write_sums(d):
    names = sorted(f for f in os.listdir(d) if f not in (SUMS, SIG) and os.path.isfile(os.path.join(d, f)))
    with open(os.path.join(d, SUMS), "w") as f:
        for n in names:
            f.write(f"{sha256(os.path.join(d, n))}  {n}\n")
    return names


def sign(path, key):
    sig = path + ".sig"
    if os.path.exists(sig):
        os.unlink(sig)
    run(["ssh-keygen", "-Y", "sign", "-q", "-f", key, "-n", NAMESPACE, path], capture_output=True)
    return sig


def tree_sums(root):
    """scripts/SHA256SUMS over every file of the tree (sorted, relative to
    root; .git, __pycache__ and the two sums files excluded): §e.10 step 2's
    fallback for a checkout without git. The whole tree, not only scripts/,
    pkgs/ and fork/: lib/ and flake.nix decide what `nix run` runs."""
    lines = []
    for dp, dns, fns in os.walk(root):
        dns[:] = sorted(x for x in dns if x not in ("__pycache__", ".git") and not (dp == root and x == "result"))
        for fn in sorted(fns):
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, root)
            if rel in ("scripts/SHA256SUMS", "scripts/SHA256SUMS.sig") or os.path.islink(full):
                continue
            lines.append(f"{sha256(full)}  {rel}\n")
    os.makedirs(os.path.join(root, "scripts"), exist_ok=True)
    with open(os.path.join(root, "scripts", SUMS), "w") as f:
        f.writelines(sorted(lines, key=lambda x: x.split("  ", 1)[1]))
    return len(lines)


# ── the cache ──────────────────────────────────────────────────────────────

def sign_cache(src, out, key_file):
    if os.path.exists(out):
        raise ReleaseError(f"{out} exists")
    shutil.copytree(src, out, symlinks=True)
    run(["chmod", "-R", "u+w", out])
    pub = run(["nix", "key", "convert-secret-to-public"], stdin=open(key_file), capture_output=True).stdout.strip()
    run(["nix", "store", "sign", "--store", f"file://{os.path.abspath(out)}", "--key-file", key_file, "--all"],
        capture_output=True)
    run(["nix", "store", "verify", "--store", f"file://{os.path.abspath(out)}", "--all", "--no-contents",
         "--sigs-needed", "1", "--option", "trusted-public-keys", pub], capture_output=True)
    with open(os.path.join(out, "cache-key.pub"), "w") as f:
        f.write(pub + "\n")
    return pub


# ── the release ────────────────────────────────────────────────────────────

def git(repo, *args, **kw):
    return run(["git", "-C", repo, *args], capture_output=True, **kw).stdout.strip()


def verify_tag(repo, tag):
    """The tag is SSH-signed by a signer pinned in the TAGGED tree's
    release/allowed_signers. Returns (commit, signers file)."""
    commit = git(repo, "rev-parse", f"{tag}^{{commit}}")
    tmp = tempfile.NamedTemporaryFile("w", delete=False, suffix=".allowed_signers")
    tmp.write(git(repo, "show", f"{commit}:release/allowed_signers") + "\n")
    tmp.close()
    signers_principals(tmp.name)
    if "-----BEGIN SSH SIGNATURE-----" not in git(repo, "cat-file", "tag", tag, check=False):
        raise ReleaseError(f"tag {tag} isn't signed by a key in release/allowed_signers at {commit[:12]}: no SSH signature")
    p = run(["git", "-C", repo, "-c", "gpg.format=ssh", "-c", f"gpg.ssh.allowedSignersFile={tmp.name}",
             "verify-tag", "--raw", tag], capture_output=True, check=False)
    if p.returncode != 0 or "Good \"git\" signature" not in (p.stderr + p.stdout):
        raise ReleaseError(f"tag {tag} isn't signed by a key in release/allowed_signers at {commit[:12]}:\n{p.stderr.strip()}")
    return commit, tmp.name


def nix_build(expr, out_link=None):
    cmd = ["nix", "build", "--no-link", "--print-out-paths", "--impure", "--expr", expr, "-L"]
    p = run(cmd, stdout=subprocess.PIPE)
    return p.stdout.strip().splitlines()[-1]


def build(a):
    repo = os.path.abspath(a.repo)
    commit, signers = verify_tag(repo, a.tag)
    version = git(repo, "show", f"{commit}:VERSION")
    if a.tag != f"v{version}":
        raise ReleaseError(f"tag {a.tag} doesn't match VERSION {version} at {commit[:12]}")
    flake = f'builtins.getFlake "git+file://{repo}?rev={commit}"'
    os.makedirs(a.out, exist_ok=False)
    work = a.work or tempfile.mkdtemp(prefix="omanix-release-")
    log = lambda m: print(f"omanix-release: {m}", file=sys.stderr, flush=True)

    log(f"{a.tag} = {commit} (tag verified)")
    if a.signed_cache:
        signed_src = os.path.abspath(a.signed_cache)
        pub = open(os.path.join(signed_src, "cache-key.pub")).read().strip() if os.path.exists(
            os.path.join(signed_src, "cache-key.pub")) else a.cache_public_key
        if not pub:
            raise ReleaseError("--signed-cache needs its cache-key.pub (sign-cache writes it) or --cache-public-key")
        run(["nix", "store", "verify", "--store", f"file://{signed_src}", "--all", "--no-contents",
             "--sigs-needed", "1", "--option", "trusted-public-keys", pub], capture_output=True)
        log(f"using the signed cache {signed_src} ({pub.split(':')[0]})")
    else:
        log("building the unsigned stick cache from the tag")
        unsigned = nix_build(f"({flake}).packages.{SYSTEM}.base-cache")
        signed_src = os.path.join(work, "cache")
        log(f"signing the cache with {a.cache_key_file}")
        pub = sign_cache(unsigned, signed_src, a.cache_key_file)
    signed = run(["nix", "store", "add", "--mode", "nar", "--name", f"omanix-{version}-cache", signed_src],
                 capture_output=True).stdout.strip()
    if not a.signed_cache:
        shutil.rmtree(signed_src)
    images = {}
    for variant in a.variants.split(","):
        log(f"building the {variant} image (cacheDir = {signed})")
        extra = (f'cacheDir = builtins.storePath "{signed}"; cachePublicKey = "{pub}";'
                 if variant == "offline" else "")
        img = nix_build(f'({flake}).lib.installer.image {{ variant = "{variant}"; {extra} }}')
        raw = [f for f in os.listdir(img) if f.endswith(".raw")]
        if len(raw) != 1:
            raise ReleaseError(f"{img}: expected one .raw image, found {raw}")
        name = f"omanix-installer-{version}.raw" if variant == "offline" else f"omanix-installer-{variant}-{version}.raw"
        shutil.copyfile(os.path.join(img, raw[0]), os.path.join(a.out, name))
        images[variant] = {"file": name, "size": os.path.getsize(os.path.join(a.out, name)), "store": img}
    index = nix_build(f"({flake}).packages.{SYSTEM}.stick-index")
    shutil.copyfile(os.path.join(index, "store-paths"), os.path.join(a.out, "stick-index.txt"))
    with open(os.path.join(a.out, "cache-key.pub"), "w") as f:
        f.write(pub + "\n")
    with open(os.path.join(a.out, "release.json"), "w") as f:
        json.dump({"schema": "omanix.release/v1", "version": version, "tag": a.tag, "commit": commit,
                   "cachePublicKey": pub, "cacheStore": signed, "images": images,
                   "dryRun": bool(a.dry_run)}, f, indent=2)
        f.write("\n")
    write_sums(a.out)
    if not a.sign_key:
        log("SHA256SUMS written, NOT signed. The release signer runs, with the YubiKey attached:")
        log(f"  ssh-keygen -Y sign -n {NAMESPACE} -f <signing key> {os.path.join(os.path.abspath(a.out), SUMS)}")
        log(f"then: omanix-release verify {a.out} --signers <tagged tree>/release/allowed_signers")
        return {"ok": True, "signed": False, "out": a.out, "version": version, "tag": a.tag, "commit": commit}
    log(f"signing SHA256SUMS with {a.sign_key}")
    sign(os.path.join(a.out, SUMS), a.sign_key)
    res = verify(a.out, signers)
    log(f"verified: signed by {res['signer']}")
    return res


def main(argv=None):
    ap = argparse.ArgumentParser(prog="omanix-release")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("verify")
    p.add_argument("dir")
    p.add_argument("--signers", default=os.path.expanduser("~/.config/omanix/allowed_signers"))
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("tree-sums")
    p.add_argument("root")
    p = sub.add_parser("sums")
    p.add_argument("dir")
    p = sub.add_parser("sign")
    p.add_argument("file")
    p.add_argument("--key", required=True)
    p = sub.add_parser("sign-cache")
    p.add_argument("src")
    p.add_argument("out")
    p.add_argument("--key-file", required=True)
    p = sub.add_parser("build")
    p.add_argument("--repo", required=True)
    p.add_argument("--tag", required=True)
    p.add_argument("--out", required=True)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--cache-key-file", help="the omanix-cache-1 nix secret key (a test key in a dry run)")
    g.add_argument("--signed-cache", help="a cache sign-cache already signed (the real run: signed through an approval)")
    p.add_argument("--cache-public-key", help="with --signed-cache, if it has no cache-key.pub")
    p.add_argument("--sign-key", help="SSH signing key for SHA256SUMS (a test key in a dry run); without it, "
                   "SHA256SUMS is left for the release signer's YubiKey")
    p.add_argument("--variants", default="offline,net")
    p.add_argument("--work")
    p.add_argument("--dry-run", action="store_true", help="recorded in release.json; nothing is published either way")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "verify":
            res = verify(a.dir, a.signers)
            print(json.dumps(res) if a.json else f"OK: {len(res['files'])} files, signed by {res['signer']}"
                  + (f", {res['tag']} ({res['commit']})" if res.get("tag") else ""))
        elif a.cmd == "tree-sums":
            print(f"scripts/SHA256SUMS: {tree_sums(a.root)} files")
        elif a.cmd == "sums":
            print("\n".join(write_sums(a.dir)))
        elif a.cmd == "sign":
            print(sign(a.file, a.key))
        elif a.cmd == "sign-cache":
            print(sign_cache(a.src, a.out, a.key_file))
        elif a.cmd == "build":
            print(json.dumps(build(a), indent=2))
        return 0
    except (ReleaseError, OSError, json.JSONDecodeError) as e:
        print(f"omanix-release: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
