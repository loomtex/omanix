"""What an offline install has to build, and what it can't (configure check).

A derivation must be built when an output the install needs isn't on the
stick (the live store or the CACHE partition: the release's stick index).
Walking from the host's toplevel .drv, every such derivation is either

  - a fixed-output derivation (a source download): offline it can't be
    built at all. These are the cacheMiss entries;
  - an ordinary derivation: it builds offline once its own inputs exist,
    which by the same walk are on the stick or built first.

So an install is offline-capable exactly when cacheMiss is empty. The
derivations that differ per host (etc, units, the HM generation, the
catalog, the toplevel) are in toBuild; their inputs are on the stick
(installSupport), so they build in seconds to minutes.

The .drv files are read directly (ATerm), so this needs only the store the
evaluation wrote them into: no nix daemon queries, the same code on the
configuring computer and in a check.
"""

import os


class DrvError(Exception):
    pass


def _parse(text):
    """ATerm, the subset .drv files use: constructors, tuples, lists, strings."""
    i, n = 0, len(text)

    def value():
        nonlocal i
        c = text[i]
        if c == '"':
            i += 1
            out = []
            while True:
                c = text[i]
                if c == "\\":
                    nxt = text[i + 1]
                    out.append({"n": "\n", "t": "\t", "r": "\r"}.get(nxt, nxt))
                    i += 2
                elif c == '"':
                    i += 1
                    return "".join(out)
                else:
                    j = i
                    while text[j] not in '\\"':
                        j += 1
                    out.append(text[i:j])
                    i = j
        if c in "[(":
            close = "]" if c == "[" else ")"
            i += 1
            items = []
            while text[i] != close:
                items.append(value())
                if text[i] == ",":
                    i += 1
            i += 1
            return items
        j = i
        while text[j].isalnum():
            j += 1
        name, i = text[i:j], j
        if i < n and text[i] == "(":
            return (name, value())
        return name

    v = value()
    if not (isinstance(v, tuple) and v[0] == "Derive"):
        raise DrvError("not a Derive(...) term")
    return v[1]


_cache = {}


def read(drv):
    if drv not in _cache:
        try:
            text = open(drv).read()
        except OSError as e:
            raise DrvError(f"{drv}: {e}")
        f = _parse(text)
        outputs = {o[0]: o[1] for o in f[0]}
        fixed = any(o[2] for o in f[0])
        inputs = {d[0]: d[1] for d in f[1]}
        env = dict(tuple(kv) for kv in f[6])
        _cache[drv] = {"outputs": outputs, "fixed": fixed, "inputs": inputs,
                       "name": env.get("name", os.path.basename(drv)[33:-4])}
    return _cache[drv]


def outputs(drv):
    return read(drv)["outputs"]


def hash_part(path):
    return os.path.basename(path)[:32]


class Available:
    """Store paths the stick supplies, by hash part."""

    def __init__(self):
        self.hashes = set()

    def add_index(self, path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    self.hashes.add(hash_part(line))

    def add_cache(self, d):
        for name in os.listdir(d):
            if name.endswith(".narinfo"):
                self.hashes.add(name[:32])

    def add(self, path):
        self.hashes.add(hash_part(path))

    def has(self, path):
        return hash_part(path) in self.hashes

    def __len__(self):
        return len(self.hashes)


def plan(top, available, wanted=("out",)):
    """{"toBuild": [drv…], "misses": [{drv, name, outputs}…], "tainted": [drv…]}.
    tainted: the to-build derivations with a miss at or below them (what
    stage-cache builds and copies)."""
    to_build, need = {}, [(top, set(wanted))]
    while need:
        drv, outs = need.pop()
        d = read(drv)
        missing = {o for o in outs if not available.has(d["outputs"][o])}
        if not missing or drv in to_build:
            continue
        to_build[drv] = d
        # building it needs every input output it names
        need.extend((i, set(o)) for i, o in d["inputs"].items())
    misses = sorted((drv for drv, d in to_build.items() if d["fixed"]))
    # taint flows from a miss up to every to-build derivation that needs it
    users = {}
    for drv, d in to_build.items():
        for i in d["inputs"]:
            if i in to_build:
                users.setdefault(i, []).append(drv)
    tainted, stack = set(), list(misses)
    while stack:
        x = stack.pop()
        if x in tainted:
            continue
        tainted.add(x)
        stack.extend(users.get(x, []))
    return {"toBuild": sorted(to_build), "tainted": sorted(tainted),
            "misses": [{"drv": m, "name": to_build[m]["name"], "outputs": sorted(to_build[m]["outputs"].values())}
                       for m in misses]}
