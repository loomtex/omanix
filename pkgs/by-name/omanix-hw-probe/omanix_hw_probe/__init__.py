"""omanix-hw-probe: which hardware quirks match this machine (DESIGN §f.2.6).

Evaluates the declarative probes of fork/hw-quirks.toml against /sys, /proc
and `lspci -nn`. Stdlib only; read-only; never runs omarchy code. Used by the
installer (loom.installer.probes, one entry per quirk) and by
`omanix hw probe`.

  omanix-hw-probe [--root DIR] [--lspci FILE] [--quirks TOML] [--all] [--json]
  omanix-hw-probe --check NAME     exit 0 if NAME matches, 1 if not
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import platform
import re
import subprocess
import sys
import tomllib
from pathlib import Path

DEFAULT_QUIRKS = Path(__file__).with_name("hw-quirks.toml")


class Machine:
    """What the probes read, rooted at `root` (a fixture tree in tests)."""

    def __init__(self, root: Path = Path("/"), lspci: str | None = None, arch: str | None = None):
        self.root = root
        self._lspci = lspci
        self.arch = arch

    def read(self, rel: str) -> str | None:
        try:
            return (self.root / rel.lstrip("/")).read_text(errors="replace").strip()
        except OSError:
            return None

    def glob(self, pattern: str) -> list[Path]:
        return sorted(self.root.glob(pattern.lstrip("/")))

    def lspci(self) -> str:
        if self._lspci is None:
            try:
                self._lspci = subprocess.run(["lspci", "-nn"], capture_output=True, text=True, timeout=10).stdout
            except (OSError, subprocess.TimeoutExpired):
                self._lspci = ""
        return self._lspci

    def is_x86(self) -> bool:
        if self.arch is not None:
            return self.arch == "x86_64"
        cpu = self.read("proc/cpuinfo") or ""
        if "vendor_id" in cpu:
            return True
        return platform.machine() == "x86_64" and self.root == Path("/")

    def cpuinfo(self, key: str) -> str | None:
        for line in (self.read("proc/cpuinfo") or "").splitlines():
            k, _, v = line.partition(":")
            if k.strip() == key:
                return v.strip()
        return None

    def pci_devices(self) -> list[dict]:
        out = []
        for d in self.glob("sys/bus/pci/devices/*"):
            def r(n):
                try:
                    return (d / n).read_text().strip()
                except OSError:
                    return ""
            drv = d / "driver"
            out.append({
                "vendor": r("vendor").lower().removeprefix("0x"),
                "device": r("device").lower().removeprefix("0x"),
                "class": r("class").lower(),
                "driver": os.path.basename(os.readlink(drv)) if drv.is_symlink() else r("driver_name"),
            })
        return out


def _glob_any(value: str | None, pattern: str) -> bool:
    if value is None:
        return False
    v = value.lower()
    return any(fnmatch.fnmatchcase(v, p.strip().lower()) for p in pattern.split("|"))


def matches(probe: dict, m: Machine) -> bool:
    for key, want in probe.items():
        if not _test(key, want, m):
            return False
    return True


def _test(key: str, want, m: Machine) -> bool:
    if key == "any":
        return any(matches(p, m) for p in want)
    if key.startswith("dmi."):
        return _glob_any(m.read(f"sys/class/dmi/id/{key[4:]}"), want)
    if key == "match":
        w = want.lower()
        return any(w in (m.read(f"sys/class/dmi/id/{f}") or "").lower() for f in ("product_name", "product_family"))
    if key == "pci":
        ids = {f"{d['vendor']}:{d['device']}" for d in m.pci_devices()}
        ids |= set(re.findall(r"\[([0-9a-f]{4}:[0-9a-f]{4})\]", m.lspci().lower()))
        return any(w.lower() in ids for w in want)
    if key == "pci_driver":
        return any(d["driver"] == want for d in m.pci_devices())
    if key == "lspci":
        rx = re.compile(want, re.I)
        return any(rx.search(l) for l in m.lspci().splitlines())
    if key == "acpi_hid":
        return any((p.read_text(errors="replace").strip() if p.is_file() else "") == want
                   for p in m.glob("sys/bus/acpi/devices/*/hid"))
    if key == "usb_product":
        return any(p.read_text(errors="replace").strip() == want for p in m.glob("sys/bus/usb/devices/*/product"))
    if key == "input_name":
        rx = re.compile(want, re.I)
        return any(l.startswith("N: Name=") and rx.search(l) for l in (m.read("proc/bus/input/devices") or "").splitlines())
    if key == "cpu_vendor":
        return m.cpuinfo("vendor_id") == want
    if key in ("cpu_model", "cpu_model_min"):
        try:
            model = int(m.cpuinfo("model") or "")
        except ValueError:
            return False
        return model in want if key == "cpu_model" else model >= want
    if key == "battery":
        return _battery(m) == want
    if key == "virt":
        flags = (m.cpuinfo("flags") or "").split()
        return ("hypervisor" in flags) == want
    if key == "gpu_count_min":
        return sum(1 for d in m.pci_devices() if d["class"].startswith("0x03")) >= want
    if key == "nvidia_gpu":
        for d in m.pci_devices():
            if d["vendor"] != "10de" or not d["class"].startswith("0x03"):
                continue
            dev = int(d["device"] or "0", 16)
            if want == "any" and dev >= 0x1340 or want == "open" and dev >= 0x1E00 \
                    or want == "legacy" and 0x1340 <= dev < 0x1E00:
                return True
        return False
    if key == "x86":
        return m.is_x86() == want
    raise ValueError(f"unknown probe key {key!r}")


def _battery(m: Machine) -> bool:
    for bat in m.glob("sys/class/power_supply/*"):
        def r(n):
            try:
                return (bat / n).read_text().strip()
            except OSError:
                return None
        if r("present") == "1" and r("type") == "Battery" and r("scope") != "Device":
            return True
    return False


def load(path: Path = DEFAULT_QUIRKS) -> dict:
    return tomllib.loads(path.read_text())["quirk"]


def probe_all(quirks: dict, m: Machine, include_deferred: bool = False) -> list[str]:
    return [n for n, q in quirks.items()
            if (include_deferred or q.get("status") == "v1") and matches(q.get("probe", {}), m)]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="omanix-hw-probe", description=__doc__.splitlines()[0])
    ap.add_argument("--root", type=Path, default=Path("/"))
    ap.add_argument("--lspci", type=Path, help="a saved `lspci -nn` output instead of running lspci")
    ap.add_argument("--quirks", type=Path, default=DEFAULT_QUIRKS)
    ap.add_argument("--all", action="store_true", help="include deferred quirks")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--check", metavar="NAME")
    a = ap.parse_args(argv)
    quirks = load(a.quirks)
    m = Machine(a.root, a.lspci.read_text() if a.lspci else None)
    if a.check:
        if a.check not in quirks:
            print(f"omanix-hw-probe: no quirk {a.check!r}", file=sys.stderr)
            return 2
        return 0 if matches(quirks[a.check].get("probe", {}), m) else 1
    found = probe_all(quirks, m, a.all)
    if a.json:
        print(json.dumps({"quirks": found}))
    else:
        print("\n".join(found))
    return 0


if __name__ == "__main__":
    sys.exit(main())
