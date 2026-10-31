"""omanix configure: the engine behind the configure skill (§e.2). The agent
converses; this acts. Every subcommand prints one JSON object with --json.

  configure ids         [--machine-id M]
  configure mint        --answers A --owner-key K --work W [--machine-id M] [--state-dir D]
  configure mint        --resume --id ID --owner-key K [--state-dir D]
                        loom-mint with the omanix template and hostgen catalog
  configure check       --repo W [--index stick-index.txt]… [--cache DIR]…
                        evaluate the host offline-capably; cacheMiss = what an
                        offline install couldn't build (see drvgraph.py)
  configure stage-cache --repo W --state S --owner-key K --out DIR [--index …]
                        build the misses here, copy them into a per-host
                        install cache signed by a fresh key, commit its public
                        key (.loom/install-cache.pub, owner-signed) and push;
                        the secret key is deleted
  configure sidecar     --state S --answers A --out DIR [--install-cache DIR] [--hint-unlock M]
  configure revoke-enroll --state S --owner-key K [--reuse-anyway]

Settings (template, catalog, the host flake.lock that pins omanix to this
release, the placeholder module for `check`, silo) are baked into the
package as $OMANIX_CONFIGURE_SETTINGS; flags override them (tests).

Never asks for or handles passwords, tokens or the system encryption key:
the answers schema has no field for them (loom-hostgen refuses unknown keys).
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

import drvgraph


class ConfigureError(Exception):
    pass


def settings():
    path = os.environ.get("OMANIX_CONFIGURE_SETTINGS")
    return json.load(open(path)) if path else {}


def run(cmd, capture=True, **kw):
    p = subprocess.run(cmd, text=True, capture_output=capture, **kw)
    if p.returncode != 0:
        err = (p.stderr or "").strip() if capture else ""
        raise ConfigureError(f"{cmd[0]} {cmd[1] if len(cmd) > 1 else ''} failed ({p.returncode}){': ' + err[-3000:] if err else ''}")
    return p.stdout if capture else ""


def common(a, s):
    out = ["--silo", a.silo or s.get("silo", "ssh://git@silo.loom.farm"), "--flavor", "omanix"]
    if a.known_hosts:
        out += ["--known-hosts", a.known_hosts]
    return out


# ── mint / sidecar / revoke (loom's tools, omanix's template) ────────────────

def cmd_ids(a, s):
    args = ["loom-mint", "ids", "--flavor", "omanix"] + (["--machine-id", a.machine_id] if a.machine_id else [])
    return json.loads(run(args))


def cmd_mint(a, s):
    if a.resume:
        # after a network error: push the existing mint commit again (§e.2 step 3.8)
        if not a.id:
            raise ConfigureError("--resume needs --id")
        args = ["loom-mint", "mint", "--resume", "--id", a.id, "--owner-key", a.owner_key, "--json", *common(a, s)]
        if a.state_dir:
            args += ["--state-dir", a.state_dir]
        return json.loads(run(args).strip().splitlines()[-1])
    if not a.answers or not a.work:
        raise ConfigureError("mint needs --answers and --work (or --resume --id)")
    answers = json.load(open(a.answers))
    if answers.get("flavor", "omanix") != "omanix":
        raise ConfigureError(f"these answers are for the {answers.get('flavor')} flavor, not omanix")
    args = ["loom-mint", "mint", "--answers", a.answers, "--template", a.template or s["template"],
            "--catalog", a.catalog or s["catalog"], "--work", a.work, "--owner-key", a.owner_key, "--json",
            *common(a, s)]
    if a.machine_id:
        args += ["--machine-id", a.machine_id]
    if a.state_dir:
        args += ["--state-dir", a.state_dir]
    out = run(args)
    return json.loads(out.strip().splitlines()[-1])


def cmd_sidecar(a, s):
    args = ["loom-mint", "sidecar", "--state", a.state, "--answers", a.answers, "--out", a.out]
    if a.hint_unlock:
        args += ["--hint-unlock", a.hint_unlock]
    if a.install_cache:
        args += ["--install-cache", a.install_cache]
    return json.loads(run(args).strip().splitlines()[-1])


def cmd_revoke(a, s):
    st = json.load(open(a.state))
    args = ["loom-enroll", "revoke-enroll", *common(a, s), "--id", st["id"], "--state", a.state,
            "--owner-key", a.owner_key, "--repo", st.get("work", ".")]
    if a.reuse_anyway:
        args.append("--reuse-anyway")
    out = run(args)
    return {"ok": True, "id": st["id"], "output": out.strip()[-2000:]}


# ── check: cacheMiss ─────────────────────────────────────────────────────────

def stage_tree(repo, s, lock=None):
    """A copy of the host repo with the release's flake.lock (pinned to this
    omanix) if it has none: what the installer evaluates (§e.8 step 7)."""
    tmp = tempfile.mkdtemp(prefix="omanix-check-")
    tree = os.path.join(tmp, "host")
    shutil.copytree(repo, tree, ignore=shutil.ignore_patterns(".git"))
    if not os.path.exists(os.path.join(tree, "flake.lock")):
        shutil.copyfile(lock or s["hostLock"], os.path.join(tree, "flake.lock"))
        os.chmod(os.path.join(tree, "flake.lock"), 0o644)
    return tmp, tree


def toplevel_drv(tree, s, module=None):
    """Evaluate the host with the install-only rows filled by placeholders
    (the mint commit has only the id); offline: every input is locked to a
    store path this release carries."""
    module = module or s["checkModule"]
    expr = (f'let h = (builtins.getFlake "path:{tree}").nixosConfigurations.host; in '
            f'(h.extendModules {{ modules = [ (import {module}) ]; }}).config.system.build.toplevel.drvPath')
    return run(["nix", "eval", "--raw", "--impure", "--offline", "--option", "substituters", "",
                "--extra-experimental-features", "nix-command flakes", "--expr", expr]).strip()


def cmd_check(a, s):
    indexes = a.index or ([s["stickIndex"]] if s.get("stickIndex") else [])
    if not indexes and not a.cache:
        raise ConfigureError("check needs the release's stick-index.txt (--index) or a cache directory (--cache)")
    available = drvgraph.Available()
    for i in indexes:
        available.add_index(i)
    for c in a.cache or []:
        available.add_cache(c)
    tmp, tree = stage_tree(a.repo, s, a.lock)
    try:
        drv = toplevel_drv(tree, s, a.check_module)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    res = drvgraph.plan(drv, available)
    return {"drv": drv, "cacheMiss": res["misses"], "toBuild": len(res["toBuild"]),
            "available": len(available)}


# ── stage-cache ──────────────────────────────────────────────────────────────

def cmd_stage_cache(a, s):
    chk = cmd_check(a, s)
    if not chk["cacheMiss"]:
        return {"staged": False, "cacheMiss": [], "reason": "nothing to stage: the stick has everything"}
    available = drvgraph.Available()
    for i in a.index or ([s["stickIndex"]] if s.get("stickIndex") else []):
        available.add_index(i)
    plan = drvgraph.plan(chk["drv"], available)
    outs = [o for d in plan["tainted"] for o in drvgraph.outputs(d).values()]
    run(["nix", "build", "--no-link", *[f"{d}^*" for d in plan["tainted"]]], capture=False)
    closure = run(["nix", "path-info", "--recursive", *outs]).split()
    missing = [p for p in closure if not available.has(p)]
    keydir = tempfile.mkdtemp(prefix="omanix-install-cache-key-")
    secret = os.path.join(keydir, "secret")
    st = json.load(open(a.state))
    try:
        with open(os.open(secret, os.O_WRONLY | os.O_CREAT, 0o600), "w") as f:
            f.write(run(["nix", "key", "generate-secret", "--key-name", f"install-{st['id'][:8]}-1"]))
        pub = run(["nix", "key", "convert-secret-to-public"], input=open(secret).read()).strip()
        dest = f"file://{os.path.abspath(a.out)}?compression=zstd"
        run(["nix", "copy", "--no-recursive", "--to", dest, *missing], capture=False)
        run(["nix", "store", "sign", "--store", f"file://{os.path.abspath(a.out)}", "--key-file", secret, *missing])
    finally:
        # the secret never outlives this command (§e.2 step 5)
        subprocess.run(["shred", "-u", secret], check=False)
        shutil.rmtree(keydir, ignore_errors=True)
    work = st["work"]
    os.makedirs(os.path.join(work, ".loom"), exist_ok=True)
    with open(os.path.join(work, ".loom", "install-cache.pub"), "w") as f:
        f.write(pub + "\n")
    commit_and_push(a, s, st, "configure: install cache key", [".loom/install-cache.pub"])
    return {"staged": True, "paths": len(missing), "publicKey": pub, "out": a.out, "cacheMiss": chk["cacheMiss"]}


def commit_and_push(a, s, st, message, files):
    """An owner-signed commit pushed with the owner key (F3); state.json's
    commit moves to it, so the sidecar names silo's master."""
    sys.path.insert(0, s.get("loomMintLib", ""))
    import siloops  # loom-mint's, shared with loom-enroll
    silo = siloops.Silo(a.silo or s.get("silo", "ssh://git@silo.loom.farm"), a.known_hosts)
    siloops.git(st["work"], "add", *files)
    user = json.load(open(a.answers))["user"] if a.answers else {"fullName": "omanix", "email": "omanix@localhost"}
    commit = siloops.signed_commit(st["work"], message, a.owner_key, user["fullName"], user["email"])
    ok, out = silo.push(st["work"], st["path"], "HEAD:refs/heads/master", a.owner_key)
    if not ok:
        raise ConfigureError(f"push failed: {out}")
    silo.head_check(st["path"], a.owner_key, commit)
    st["commit"] = commit
    with open(a.state + ".tmp", "w") as f:
        json.dump(st, f, indent=2)
    os.replace(a.state + ".tmp", a.state)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="configure", description="omanix configure engine (§e.2)")
    ap.add_argument("--json", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def p(name, *specs):
        sp = sub.add_parser(name)
        sp.add_argument("--json", action="store_true")
        sp.add_argument("--silo")
        sp.add_argument("--known-hosts")
        for spec in specs:
            sp.add_argument(*spec[0], **spec[1])
        return sp

    req = lambda *n: (n, {"required": True})
    opt = lambda *n, **kw: (n, kw)
    p("ids", opt("--machine-id"))
    p("mint", opt("--answers"), req("--owner-key"), opt("--work"), opt("--machine-id"), opt("--state-dir"),
      opt("--template"), opt("--catalog"), opt("--resume", action="store_true"), opt("--id"))
    chk = [req("--repo"), opt("--index", action="append"), opt("--cache", action="append"), opt("--lock"),
           opt("--check-module")]
    p("check", *chk)
    p("stage-cache", *chk, req("--state"), req("--owner-key"), req("--out"), opt("--answers"))
    p("sidecar", req("--state"), req("--answers"), req("--out"), opt("--install-cache"), opt("--hint-unlock"))
    p("revoke-enroll", req("--state"), req("--owner-key"), opt("--reuse-anyway", action="store_true"))
    a = ap.parse_args(argv)
    s = settings()
    fn = {"ids": cmd_ids, "mint": cmd_mint, "check": cmd_check, "stage-cache": cmd_stage_cache,
          "sidecar": cmd_sidecar, "revoke-enroll": cmd_revoke}[a.cmd]
    try:
        res = fn(a, s)
    except (ConfigureError, drvgraph.DrvError, OSError, KeyError, json.JSONDecodeError) as e:
        print(json.dumps({"error": str(e)}) if a.json else f"configure: {e}", file=sys.stderr)
        return 1
    if a.cmd == "check" and not a.json:
        miss = res["cacheMiss"]
        print(f"cacheMiss: {len(miss)}" + "".join(f"\n  {m['name']} ({m['drv']})" for m in miss)
              + f"\n{res['toBuild']} derivations differ from the release and build during the install")
    else:
        print(json.dumps(res, indent=None if a.json else 2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
