"""One sysfs fixture per quirk probe in fork/hw-quirks.toml (checks.hw-quirks
fails when a quirk has none). Each fixture is a minimal machine; it must
match its own quirk, and a plain machine matches no v1 quirk."""

import json
import os
from pathlib import Path

import pytest

import omanix_hw_probe as hp

QUIRKS = hp.load()

AMD_CPU = "vendor_id\t: AuthenticAMD\nmodel\t\t: 1\nflags\t\t: fpu sse\n"


def intel_cpu(model):
    return f"vendor_id\t: GenuineIntel\nmodel\t\t: {model}\nflags\t\t: fpu sse\n"


def pci(slot, vendor, device, cls="0x020000", driver=None):
    d = {f"sys/bus/pci/devices/{slot}/vendor": f"0x{vendor}\n",
         f"sys/bus/pci/devices/{slot}/device": f"0x{device}\n",
         f"sys/bus/pci/devices/{slot}/class": f"{cls}\n"}
    if driver:
        d[f"sys/bus/pci/devices/{slot}/driver@"] = f"../../../bus/pci/drivers/{driver}"
    return d


def dmi(**fields):
    return {f"sys/class/dmi/id/{k}": v + "\n" for k, v in fields.items()}


BATTERY = {"sys/class/power_supply/BAT0/present": "1\n", "sys/class/power_supply/BAT0/type": "Battery\n",
           "sys/class/power_supply/BAT0/scope": "System\n"}
PTL_GPU = "00:02.0 VGA compatible controller [0300]: Intel Corporation Panther Lake [Intel Graphics] [8086:b080]\n"

# name -> (files, lspci text, arch)
FIXTURES = {
    "nouveau-cursor": (pci("0000:01:00.0", "10de", "1180", "0x030000", "nouveau"), "", None),
    "vm-no-animations": ({"proc/cpuinfo": "vendor_id\t: AuthenticAMD\nmodel\t\t: 1\nflags\t\t: fpu hypervisor\n"}, "", None),
    "intel-video": ({}, "00:02.0 VGA compatible controller [0300]: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics] [8086:46a6]\n", None),
    "intel-thermald": ({"proc/cpuinfo": intel_cpu(154), **BATTERY}, "", None),
    "intel-lpmd": ({"proc/cpuinfo": intel_cpu(170), **BATTERY}, "", None),
    "intel-sof": ({}, "00:1f.3 Multimedia audio controller [0401]: Intel Corporation Meteor Lake-P HD Audio Controller [8086:7e28]\n", None),
    "intel-ptl-fred": ({}, PTL_GPU, None),
    "intel-wifi7-eht": (pci("0000:00:14.3", "8086", "e440"), "", None),
    "intel-ipu7-camera": ({"sys/bus/acpi/devices/OVTI08F4:00/hid": "OVTI08F4\n"}, "", None),
    "asus-rog": (dmi(sys_vendor="ASUSTeK COMPUTER INC.", product_family="ROG Zephyrus G14", product_name="GA403UV"), "", None),
    "asus-z13-touchpad": (dmi(sys_vendor="ASUSTeK COMPUTER INC.", product_family="ROG Flow Z13", product_name="GZ302EA"), "", None),
    "asus-b9406-display": (dmi(sys_vendor="ASUSTeK COMPUTER INC.", product_name="ExpertBook B9406CAA"), PTL_GPU, None),
    "asus-b9406-touchpad": (dmi(sys_vendor="ASUSTeK COMPUTER INC.", product_name="ExpertBook B9406CAA"), PTL_GPU, None),
    "asus-ptl-backlight": (dmi(sys_vendor="ASUSTeK COMPUTER INC.", product_name="Zenbook UX5406AA"), PTL_GPU, None),
    "asus-proart-p14-speakers": (dmi(product_name="ProArt P14 H7407BA"), "", None),
    "framework16": (dmi(sys_vendor="Framework", product_name="Laptop 16 (AMD Ryzen 7040 Series)"), "", None),
    "framework13-amd-mic": (dmi(sys_vendor="Framework", product_name="Laptop 13 (AMD Ryzen 7040Series)"),
                            "c1:00.6 Audio device [0403]: Advanced Micro Devices, Inc. [AMD] Family 17h/19h HD Audio Controller [1022:15e3]\n", None),
    "lenovo-yoga-pro7-bass": (dmi(sys_vendor="LENOVO", product_name="83E2", product_family="Yoga Pro 7 14IAH10"), "", None),
    "surface": ({"proc/cpuinfo": intel_cpu(140), **dmi(sys_vendor="Microsoft Corporation", product_name="Surface Laptop 3")}, "", None),
    "apple-t2": (pci("0000:02:00.1", "106b", "1802"), "", None),
    "apple-brcmfmac": ({"proc/cpuinfo": intel_cpu(158), **pci("0000:02:00.1", "106b", "1801")}, "", None),
    "apple-spi-keyboard": (dmi(sys_vendor="Apple Inc.", product_name="MacBookPro14,1"), "", None),
    "apple-nvme-suspend": (dmi(sys_vendor="Apple Inc.", product_name="MacBook9,1"), "", None),
    "bcm43xx": (pci("0000:03:00.0", "14e4", "43a0"), "", None),
    "tuxedo-backlight": (dmi(sys_vendor="TUXEDO"), "", None),
    "synaptics-intertouch": ({"proc/bus/input/devices": "I: Bus=0011 Vendor=0002 Product=0007\nN: Name=\"SynPS/2 Synaptics TouchPad\"\n"}, "", None),
    "elgato-camlink-4k": ({"sys/bus/usb/devices/3-1/product": "Cam Link 4K\n"}, "", None),
    "speaker-tuning": (dmi(sys_vendor="Dell Inc.", product_sku="0DB9"), "", None),
    "nvidia": (pci("0000:01:00.0", "10de", "2684", "0x030000"), "", None),
    "hybrid-gpu": ({**pci("0000:00:02.0", "8086", "a7a0", "0x030000"), **pci("0000:01:00.0", "10de", "28e0", "0x030200")}, "", None),
    "dell-xps13-ptl": (dmi(sys_vendor="Dell Inc.", product_name="XPS 13 DX13260"), "", None),
    "dell-xps-haptics": (dmi(sys_vendor="Dell Inc.", product_name="XPS 14 DA14260"), "", None),
    "qualcomm": ({}, "", "aarch64"),
    "yoga-slim7x": (dmi(product_name="83ED", product_family="Yoga Slim 7x 14Q8X9"), "", "aarch64"),
    "thinkpad-t14s-camera": (dmi(product_name="21N1", product_family="ThinkPad T14s Gen 6"), "", "aarch64"),
    "n1x": (pci("0000:01:00.0", "10de", "2e06", "0x030000"), "", "aarch64"),
    "gb10": (dmi(product_name="NVIDIA_DGX_Spark"), "", "aarch64"),
}


def build(tmp_path, files):
    for rel, content in files.items():
        if rel.endswith("@"):
            p = tmp_path / rel[:-1]
            p.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(content, p)
        else:
            p = tmp_path / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
    return tmp_path


def machine(tmp_path, name):
    files, lspci, arch = FIXTURES[name]
    if "proc/cpuinfo" not in files and arch is None:
        files = {"proc/cpuinfo": AMD_CPU, **files}
    return hp.Machine(build(tmp_path, files), lspci, arch or "x86_64")


def test_every_quirk_has_a_fixture():
    assert sorted(QUIRKS) == sorted(FIXTURES)


@pytest.mark.parametrize("name", sorted(QUIRKS))
def test_fixture_matches_its_quirk(tmp_path, name):
    assert hp.matches(QUIRKS[name]["probe"], machine(tmp_path, name)), name


def test_plain_machine_matches_nothing(tmp_path):
    m = hp.Machine(build(tmp_path, {"proc/cpuinfo": AMD_CPU, **dmi(sys_vendor="Generic", product_name="Desktop")}), "", "x86_64")
    assert hp.probe_all(QUIRKS, m, include_deferred=True) == []


def test_nvidia_open_and_legacy(tmp_path):
    new = hp.Machine(build(tmp_path / "a", pci("0000:01:00.0", "10de", "2684", "0x030000")), "", "x86_64")
    old = hp.Machine(build(tmp_path / "b", pci("0000:01:00.0", "10de", "1b80", "0x030000")), "", "x86_64")
    assert hp.matches({"nvidia_gpu": "open"}, new) and not hp.matches({"nvidia_gpu": "legacy"}, new)
    assert hp.matches({"nvidia_gpu": "legacy"}, old) and not hp.matches({"nvidia_gpu": "open"}, old)


def test_device_scoped_battery_is_not_a_laptop(tmp_path):
    m = hp.Machine(build(tmp_path, {"sys/class/power_supply/hidpp_battery_0/present": "1\n",
                                    "sys/class/power_supply/hidpp_battery_0/type": "Battery\n",
                                    "sys/class/power_supply/hidpp_battery_0/scope": "Device\n"}), "", "x86_64")
    assert not hp.matches({"battery": True}, m)


def test_cli_check_and_json(tmp_path, capsys):
    files, lspci, _ = FIXTURES["intel-video"]
    root = build(tmp_path, {"proc/cpuinfo": AMD_CPU, **files})
    (tmp_path / "lspci.txt").write_text(lspci)
    assert hp.main(["--root", str(root), "--lspci", str(tmp_path / "lspci.txt"), "--check", "intel-video"]) == 0
    assert hp.main(["--root", str(root), "--lspci", str(tmp_path / "lspci.txt"), "--check", "nvidia"]) == 1
    assert hp.main(["--root", str(root), "--lspci", str(tmp_path / "lspci.txt"), "--check", "nope"]) == 2
    capsys.readouterr()
    hp.main(["--root", str(root), "--lspci", str(tmp_path / "lspci.txt"), "--json"])
    assert json.loads(capsys.readouterr().out) == {"quirks": ["intel-video"]}


def test_unknown_probe_key_is_an_error(tmp_path):
    with pytest.raises(ValueError):
        hp.matches({"bogus": 1}, hp.Machine(tmp_path, "", "x86_64"))
