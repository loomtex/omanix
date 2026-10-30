"""checks.set-roundtrip (U19): each case edits a module with omanix's
editor exactly as `omanix set`/`unset` would, then evaluates it with
lib.evalModules; the evaluated value must equal the JSON asked for, and the
bytes outside the edit must be unchanged (comments included).

usage: set_roundtrip.py <nixpkgs lib dir>
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

from omanix_cli import nixedit as ne

LIB = sys.argv[1]

DECLS = """
{ lib, ... }:
let o = t: lib.mkOption { type = t; default = null; }; in
{
  options.omanix = {
    defaults = { terminal = o (lib.types.nullOr lib.types.str); browser = o (lib.types.nullOr lib.types.str); editor = o (lib.types.nullOr lib.types.str); };
    hyprland.gdkScale = o (lib.types.nullOr lib.types.int);
    hyprland.settings = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
    apps = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule { options.enable = lib.mkOption { type = lib.types.bool; default = false; }; options.url = o (lib.types.nullOr lib.types.str); }); default = { }; };
    fonts.monospace = o (lib.types.nullOr lib.types.str);
    theme.default = o (lib.types.nullOr lib.types.str);
    input.layouts = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
    scale = o (lib.types.nullOr lib.types.float);
  };
  options.loom.user = { name = o lib.types.str; fullName = o lib.types.str; };
  options.home.packages = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
  options.loom.persist.system.directories = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
}
"""

CONF = """# Preferences for this machine.
{ lib, pkgs, ... }:

{
  imports = [ ];

  loom.user = { name = "josh"; fullName = "Joshua Perry"; }; # who
  omanix.defaults = {
    terminal = "alacritty"; # the terminal
    browser = "chromium";
  };
  omanix.input.layouts = [
    "us" # mine
    "de"
  ];
  omanix.apps.obsidian.enable = true;

  # Below this line: changes made by the agent or by you. Each one was approved on a card.
}
"""

HOME = """{ pkgs, ... }:
{
  home.packages = with pkgs; [ ];
}
"""

PERSIST = """# Host-level state.
{ ... }:

{ }
"""


def evaluate(files: dict, path: list[str]):
    with tempfile.TemporaryDirectory() as d:
        for name, text in files.items():
            Path(d, name).write_text(text)
        Path(d, "decls.nix").write_text(DECLS)
        mods = " ".join(f"./{n}" for n in files)
        Path(d, "eval.nix").write_text(
            f"let lib = import {LIB}; pkgs = {{ hello = \"hello\"; jq = \"jq\"; }}; in "
            f"(lib.evalModules {{ specialArgs = {{ inherit pkgs; }}; modules = [ ./decls.nix {mods} ]; }}).config"
            + "".join(f".{ne.attr_name(p)}" for p in path))
        r = subprocess.run(["nix-instantiate", "--eval", "--strict", "--json", str(Path(d, "eval.nix"))],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise AssertionError(f"eval failed:\n{r.stderr}\n--- files ---\n" + "\n".join(files.values()))
        return json.loads(r.stdout)


def value_match(tree, path):
    ms = [m for m in ne.find_in_module(tree, path) if m.kind == "value"]
    assert len(ms) == 1, (path, ms)
    return ms[0]


def set_(src: str, path, value) -> str:
    """omanix set: rewrite the one literal definition, else insert."""
    b = src.encode()
    t = ne.parse(b)
    ms = ne.find_in_module(t, path)
    vals = [m for m in ms if m.kind == "value"]
    if vals:
        assert len(ms) == 1 and ne.is_literal(vals[0].value), path
        return ne.replace_value(b, vals[0], value).decode()
    return ne.insert_path(t, b, path, value).decode()


def unset(src: str, path) -> str:
    b = src.encode()
    return ne.delete_binding(b, value_match(ne.parse(b), path)).decode()


def untouched(before: str, after: str, *removed: str):
    """Every line of before that isn't one of `removed` is still in after, in order."""
    it = iter(after.splitlines())
    for line in before.splitlines():
        if any(r in line for r in removed):
            continue
        for l2 in it:
            if l2 == line:
                break
        else:
            raise AssertionError(f"lost line: {line!r}\n--- after ---\n{after}")


CASES = []


def case(f):
    CASES.append(f)
    return f


@case
def rewrite_nested_string():
    out = set_(CONF, ["omanix", "defaults", "terminal"], "kitty")
    assert evaluate({"c.nix": out}, ["omanix", "defaults", "terminal"]) == "kitty"
    assert '    terminal = "kitty"; # the terminal' in out
    untouched(CONF, out, "terminal =")


@case
def rewrite_inline_attrset_member():
    out = set_(CONF, ["loom", "user", "name"], "alice")
    assert evaluate({"c.nix": out}, ["loom", "user"]) == {"name": "alice", "fullName": "Joshua Perry"}
    assert "# who" in out


@case
def rewrite_list_literal_keeps_comments_elsewhere():
    out = set_(CONF, ["omanix", "input", "layouts"], ["us", "fr", "de"])
    assert evaluate({"c.nix": out}, ["omanix", "input", "layouts"]) == ["us", "fr", "de"]
    untouched(CONF, out, '"us"', '"de"', "omanix.input.layouts", "  ];")


@case
def append_under_marker():
    out = set_(CONF, ["omanix", "hyprland", "gdkScale"], 1)
    assert out.index("omanix.hyprland.gdkScale = 1;") > out.index("# Below this line")
    assert evaluate({"c.nix": out}, ["omanix", "hyprland", "gdkScale"]) == 1
    untouched(CONF, out)


@case
def insert_into_existing_nested_set():
    out = set_(CONF, ["omanix", "defaults", "editor"], "helix")
    assert evaluate({"c.nix": out}, ["omanix", "defaults"]) == {"terminal": "alacritty", "browser": "chromium", "editor": "helix"}
    untouched(CONF, out)


@case
def nested_attrs_and_quoted_names():
    out = set_(CONF, ["omanix", "hyprland", "settings", "general", "gaps_out"], 4)
    out = set_(out, ["omanix", "apps", "My App", "url"], "https://example.org")
    assert evaluate({"c.nix": out}, ["omanix", "hyprland", "settings"]) == {"general": {"gaps_out": 4}}
    assert evaluate({"c.nix": out}, ["omanix", "apps", "My App", "url"]) == "https://example.org"
    out2 = set_(out, ["omanix", "hyprland", "settings", "general", "gaps_out"], 10)
    assert evaluate({"c.nix": out2}, ["omanix", "hyprland", "settings", "general", "gaps_out"]) == 10
    assert out2.count("gaps_out") == 1


@case
def attrset_float_bool_null_values():
    out = set_(CONF, ["omanix", "scale"], 1.25)
    assert evaluate({"c.nix": out}, ["omanix", "scale"]) == 1.25
    out = set_(out, ["omanix", "apps", "obsidian", "enable"], False)
    assert evaluate({"c.nix": out}, ["omanix", "apps", "obsidian", "enable"]) is False
    out = set_(out, ["omanix", "theme", "default"], None)
    assert evaluate({"c.nix": out}, ["omanix", "theme", "default"]) is None


@case
def strings_are_data():
    nasty = 'x"; system = "y"; ${builtins.abort "z"} \\ \n\t\'\''
    out = set_(CONF, ["omanix", "fonts", "monospace"], nasty)
    assert evaluate({"c.nix": out}, ["omanix", "fonts", "monospace"]) == nasty


@case
def unset_restores_default():
    out = unset(CONF, ["omanix", "apps", "obsidian", "enable"])
    assert "obsidian" not in out
    assert evaluate({"c.nix": out}, ["omanix", "apps"]) == {}
    untouched(CONF, out, "obsidian")


@case
def list_append_with_pkgs():
    b = HOME.encode()
    t = ne.parse(b)
    lst = ne.list_node(value_match(t, ["home", "packages"]).value)
    out = ne.list_append(b, lst, "hello")
    t = ne.parse(out)
    out = ne.list_append(out, ne.list_node(value_match(t, ["home", "packages"]).value), "jq").decode()
    assert evaluate({"h.nix": out}, ["home", "packages"]) == ["hello", "jq"]


@case
def persist_add_into_empty_module():
    b = PERSIST.encode()
    out = ne.insert_path(ne.parse(b), b, ["loom", "persist", "system", "directories"], ["/var/lib/foo"]).decode()
    assert evaluate({"p.nix": out}, ["loom", "persist", "system", "directories"]) == ["/var/lib/foo"]
    assert out.startswith("# Host-level state.")


@case
def nixfmt_is_stable():
    out = set_(CONF, ["omanix", "hyprland", "gdkScale"], 1)
    with tempfile.NamedTemporaryFile("w", suffix=".nix", delete=False) as f:
        f.write(out)
    r = subprocess.run(["nixfmt", f.name], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    once = Path(f.name).read_text()
    subprocess.run(["nixfmt", f.name], check=True)
    assert Path(f.name).read_text() == once
    assert evaluate({"c.nix": once}, ["omanix", "hyprland", "gdkScale"]) == 1
    assert "# the terminal" in once and "# Below this line" in once


failed = 0
for c in CASES:
    try:
        c()
        print(f"ok   {c.__name__}")
    except Exception as e:  # noqa: BLE001
        failed += 1
        print(f"FAIL {c.__name__}: {e}")
sys.exit(1 if failed else 0)
