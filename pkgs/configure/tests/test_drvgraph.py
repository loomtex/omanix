"""drvgraph on synthetic .drv files: cacheMiss is exactly the fixed-output
derivations an offline install would have to build."""

import drvgraph


def aterm_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def drv(tmp, name, inputs=(), fixed=False):
    out = f"/nix/store/{name[0] * 32}-{name}"
    path = tmp / f"{name[0] * 32}-{name}.drv"
    outs = f'[("out",{aterm_str(out)},{aterm_str("sha256" if fixed else "")},{aterm_str("abc" if fixed else "")})]'
    ins = "[" + ",".join(f'({aterm_str(str(i))},["out"])' for i in inputs) + "]"
    weird = aterm_str('a "q" \\ b' + chr(10) + "c")
    env = f'[("name",{aterm_str(name)}),("weird",{weird})]'
    path.write_text(f'Derive({outs},{ins},["/nix/store/{"s" * 32}-src"],"x86_64-linux","/bin/sh",["-c","x"],{env})')
    return path, out


def test_plan(tmp_path):
    drvgraph._cache.clear()
    src_ok, src_ok_out = drv(tmp_path, "asrc", fixed=True)        # on the stick
    src_miss, _ = drv(tmp_path, "bsrc", fixed=True)               # not on the stick
    lib, lib_out = drv(tmp_path, "clib", [src_ok])                # on the stick
    app, _ = drv(tmp_path, "dapp", [src_miss, lib])               # needs the missing source
    etc, _ = drv(tmp_path, "eetc", [lib])                         # per host, buildable
    top, _ = drv(tmp_path, "ftop", [app, etc])
    av = drvgraph.Available()
    av.add(src_ok_out)
    av.add(lib_out)
    res = drvgraph.plan(str(top), av)
    assert [m["name"] for m in res["misses"]] == ["bsrc"]
    assert sorted(drvgraph.read(d)["name"] for d in res["toBuild"]) == ["bsrc", "dapp", "eetc", "ftop"]
    assert sorted(drvgraph.read(d)["name"] for d in res["tainted"]) == ["bsrc", "dapp", "ftop"]


def test_all_available(tmp_path):
    drvgraph._cache.clear()
    s, so = drv(tmp_path, "asrc", fixed=True)
    t, to = drv(tmp_path, "btop", [s])
    av = drvgraph.Available()
    av.add(to)
    assert drvgraph.plan(str(t), av)["toBuild"] == []
    assert drvgraph.read(str(t))["name"] == "btop"


def test_index(tmp_path):
    idx = tmp_path / "store-paths"
    idx.write_text("/nix/store/" + "a" * 32 + "-x\n\n")
    av = drvgraph.Available()
    av.add_index(str(idx))
    assert av.has("/nix/store/" + "a" * 32 + "-other-name") and len(av) == 1
