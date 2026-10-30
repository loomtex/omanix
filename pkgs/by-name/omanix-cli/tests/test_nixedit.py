"""The editor keeps everything it doesn't edit byte-identical (U19)."""

import json
from pathlib import Path

import pytest

from omanix_cli import nixedit as ne
from omanix_cli import contract

CONF = b'''# Preferences for this machine.
{ lib, pkgs, ... }:

{
  imports = [ ./machine.nix ./keys.nix ];

  loom.user = { name = "josh"; fullName = "Joshua Perry"; }; # who
  omanix.defaults = {
    terminal = "alacritty"; # the terminal
    browser = "chromium";
  };
  omanix.apps.obsidian.enable = true;
  omanix.hyprland.settings.general.gaps_out = lib.mkIf true 10;
  networking.firewall.allowedTCPPorts = [
    22 # ssh
    80
  ];
  x."a b".c = [ 1 2.5 "s${"x"}" ];

  # Below this line: changes made by the agent or by you. Each one was approved on a card.
}
'''


def edit(src, path, value):
    t = ne.parse(src)
    ms = [m for m in ne.find_in_module(t, path) if m.kind == "value"]
    assert len(ms) == 1, ms
    return ne.replace_value(src, ms[0], value)


def test_rewrite_nested_attr_keeps_comments():
    out = edit(CONF, ["omanix", "defaults", "terminal"], "kitty")
    assert b'terminal = "kitty"; # the terminal' in out
    assert out.replace(b'"kitty"', b'"alacritty"') == CONF


def test_rewrite_inline_attrset_member():
    out = edit(CONF, ["loom", "user", "name"], "alice")
    assert b'loom.user = { name = "alice"; fullName = "Joshua Perry"; }; # who' in out


def test_rewrite_list_literal_keeps_rest():
    out = edit(CONF, ["networking", "firewall", "allowedTCPPorts"], [22, 443])
    assert b"allowedTCPPorts = [\n    22\n    443\n  ];" in out
    assert out.count(b"# who") == 1 and b"# Below this line" in out


def test_literals_and_expressions():
    t = ne.parse(CONF)
    lit = lambda p: [ne.is_literal(m.value) for m in ne.find_in_module(t, p) if m.kind == "value"]
    assert lit(["omanix", "apps", "obsidian", "enable"]) == [True]
    assert lit(["networking", "firewall", "allowedTCPPorts"]) == [True]
    assert lit(["omanix", "hyprland", "settings", "general", "gaps_out"]) == [False]   # mkIf
    assert lit(["x", "a b", "c"]) == [False]                                        # interpolation
    assert lit(["loom", "user"]) == [True]


def test_partial_and_missing():
    t = ne.parse(CONF)
    kinds = [m.kind for m in ne.find_in_module(t, ["omanix", "defaults"])]
    assert kinds == ["value"]
    kinds = [m.kind for m in ne.find_in_module(t, ["omanix", "apps"])]
    assert kinds == ["partial"]
    assert ne.find_in_module(t, ["omanix", "theme", "default"]) == []


def test_append_lands_under_the_marker():
    t = ne.parse(CONF)
    out = ne.insert_path(t, CONF, ["omanix", "theme", "default"], "kanagawa")
    marker = out.index(b"# Below this line")
    added = out.index(b'  omanix.theme.default = "kanagawa";\n')
    assert added > marker and out.endswith(b'  omanix.theme.default = "kanagawa";\n}\n')
    assert out.replace(b'  omanix.theme.default = "kanagawa";\n', b"") == CONF


def test_insert_into_existing_nested_attrset():
    t = ne.parse(CONF)
    out = ne.insert_path(t, CONF, ["omanix", "defaults", "editor"], "helix")
    assert b'    browser = "chromium";\n    editor = "helix";\n  };' in out
    out2 = ne.insert_path(ne.parse(CONF), CONF, ["loom", "user", "email"], "j@x")
    assert b'loom.user = { name = "josh"; fullName = "Joshua Perry"; email = "j@x"; }; # who' in out2


def test_delete_binding_whole_line():
    t = ne.parse(CONF)
    m = [m for m in ne.find_in_module(t, ["omanix", "apps", "obsidian", "enable"]) if m.kind == "value"][0]
    out = ne.delete_binding(CONF, m)
    assert b"obsidian" not in out
    assert out == CONF.replace(b"  omanix.apps.obsidian.enable = true;\n", b"")


def test_render_escapes():
    assert ne.render('a"b${c}\\') == '"a\\"b\\${c}\\\\"'
    assert ne.render({"a b": 1, "ok": [True, None]}) == '{\n    "a b" = 1;\n    ok = [\n      true\n      null\n    ];\n  }'
    assert ne.render(2.0) == "2.0"
    assert ne.render([]) == "[ ]"


def test_injection_is_data():
    out = edit(CONF, ["omanix", "defaults", "browser"], '"; system = "x"; #')
    t = ne.parse(out)
    m = [m for m in ne.find_in_module(t, ["omanix", "defaults", "browser"]) if m.kind == "value"][0]
    assert ne.literal_value(m.value) == '"; system = "x"; #'


HOME = b'''{ pkgs, ... }:
{
  home.stateVersion = "26.11";
  home.packages = with pkgs; [ ];
}
'''


def test_home_packages_list_ops():
    t = ne.parse(HOME)
    m = [m for m in ne.find_in_module(t, ["home", "packages"]) if m.kind == "value"][0]
    lst = ne.list_node(m.value)
    out = ne.list_append(HOME, lst, "hello")
    assert b"home.packages = with pkgs; [ hello ];" in out
    t = ne.parse(out)
    lst = ne.list_node([m for m in ne.find_in_module(t, ["home", "packages"]) if m.kind == "value"][0].value)
    out = ne.list_append(out, lst, "jq")
    assert b"[ hello jq ]" in out
    t = ne.parse(out)
    lst = ne.list_node([m for m in ne.find_in_module(t, ["home", "packages"]) if m.kind == "value"][0].value)
    assert ne.list_remove(out, lst, "hello").count(b"[ jq ]") == 1


def test_imports_and_formals():
    plugins = b"{ inputs, ... }:\n\n{ }\n"
    out = ne.import_add(ne.parse(plugins), plugins, "inputs.foo.nixosModules.default")
    assert b"imports = [ inputs.foo.nixosModules.default ];" in out
    out = ne.import_add(ne.parse(out), out, "inputs.bar.nixosModules.default")
    assert b"[ inputs.foo.nixosModules.default inputs.bar.nixosModules.default ]" in out
    out = ne.import_remove(ne.parse(out), out, "inputs.foo.nixosModules.default")
    assert b"[ inputs.bar.nixosModules.default ]" in out
    h = ne.ensure_formal(ne.parse(HOME), HOME, "inputs")
    assert h.startswith(b"{ pkgs, inputs, ... }:")
    assert ne.ensure_formal(ne.parse(h), h, "inputs") == h


def test_flake_inputs():
    flake = b'''{
  description = "x";
  inputs = {
    omanix.url = "git+https://example/omanix.git?ref=refs/tags/v0.1.0";
    nixpkgs.follows = "omanix/nixpkgs";
  };
  outputs = inputs@{ self, omanix, ... }: { };
}
'''
    out = ne.insert_path(ne.parse(flake), flake, ["inputs", "foo"], {"url": "github:a/foo/v1", "inputs": {"nixpkgs": {"follows": "nixpkgs"}}})
    t = ne.parse(out)
    m = [m for m in ne.find_in_module(t, ["inputs", "foo"]) if m.kind == "value"][0]
    assert ne.literal_value(m.value) == {"url": "github:a/foo/v1", "inputs": {"nixpkgs": {"follows": "nixpkgs"}}}
    assert out.index(b"foo = {") < out.index(b"outputs")
    m = [m for m in ne.find_in_module(t, ["inputs", "foo"]) if m.kind == "value"][0]
    assert ne.delete_binding(out, m) == flake


def test_not_a_module():
    with pytest.raises(ne.EditError):
        ne.module_body(ne.parse(b"let a = 1; in { }"))
    with pytest.raises(ne.EditError):
        ne.parse(b"{ a = ; }")


def test_commands_registry_is_complete():
    import omanix_cli
    from omanix_cli import common
    reg = common.registry()
    omanix_cli._load_handlers()
    for g, cs in reg["commands"].items():
        for n, e in cs.items():
            assert (g, n) in omanix_cli._HANDLERS, f"{g} {n} has no handler"
            assert e["description"] and "output" in e
            h = omanix_cli.help_json(g, n, e, reg["exitCodes"])
            assert not contract.help_errors(h)


def test_contract_validator():
    e = {"output": {"required": ["a"], "properties": {"a": {"type": "array"}}}}
    assert contract.check_output(e, {"ok": True, "command": "x", "exit": 0, "a": []}, 0) == []
    assert contract.check_output(e, {"ok": True, "command": "x", "exit": 0}, 0)
    assert contract.check_output(e, {"ok": False, "command": "x", "exit": 2, "error": "no"}, 2) == []
    assert contract.check_output(e, {"ok": False, "command": "x", "exit": 2}, 2)
    assert contract.check_output(e, {"ok": True, "command": "x", "exit": 0, "a": []}, 1)
