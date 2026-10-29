import json
import os
from pathlib import Path

import pytest

import omanix_overlay as ov


@pytest.fixture
def env(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    omarchy = tmp_path / "omarchy"
    (omarchy / "config/omarchy").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("XDG_STATE_HOME", raising=False)
    monkeypatch.setenv("OMARCHY_PATH", str(omarchy))
    monkeypatch.setenv("OMANIX_AGENT_NAME", "ada")
    monkeypatch.setenv("OMANIX_RUNTIME_JSON", str(tmp_path / "run/runtime.json"))
    return ov.Env()


def write_defaults(env, d):
    (env.omarchy / "config/omarchy/shell.json").write_text(json.dumps(d))


# ---------------------------------------------------------------- init


def test_init_creates_every_overlay_with_header(env):
    created = ov.cmd_init(env)
    assert set(created) == set(ov.OVERLAYS)
    for rel in ov.OVERLAYS:
        text = (env.overlay / rel).read_text()
        assert "Make it stick: ask ada" in text
        assert ov.is_empty(rel, env)
    # second run: idempotent, nothing recreated, content untouched
    (env.overlay / "kitty.conf").write_text("font_size 14\n")
    assert ov.cmd_init(env) == []
    assert (env.overlay / "kitty.conf").read_text() == "font_size 14\n"


def test_fontconfig_seed_is_a_valid_document(env):
    import xml.dom.minidom

    ov.cmd_init(env)
    xml.dom.minidom.parse(str(env.overlay / "fontconfig/fonts.conf"))


def test_init_reset_empties_and_backs_up(env):
    ov.cmd_init(env)
    ov.cmd_kv(env, "alacritty.toml", "font.size", "13")
    ov.cmd_init(env, reset=True)
    assert ov.is_empty("alacritty.toml", env)
    backups = list(env.reclaim.rglob("alacritty.toml"))
    assert backups and "size = 13" in backups[0].read_text()


# ---------------------------------------------------------------- kv


@pytest.mark.parametrize(
    "rel,key,value,line",
    [
        ("alacritty.toml", "font.size", "13", "size = 13"),
        ("kitty.conf", "font_size", "13.0", "font_size 13.0"),
        ("ghostty.conf", "font-size", "13", "font-size = 13"),
        ("foot.ini", "font", "JetBrainsMono:size=13", "font=JetBrainsMono:size=13"),
    ],
)
def test_kv_set_replace_unset(env, rel, key, value, line):
    ov.cmd_init(env)
    ov.cmd_kv(env, rel, key, value)
    text = (env.overlay / rel).read_text()
    assert line in text
    assert "Make it stick" in text  # header kept
    ov.cmd_kv(env, rel, key, value + "9")
    text = (env.overlay / rel).read_text()
    assert text.count(key.split(".")[-1]) == 1, text
    ov.cmd_kv(env, rel, key, None)
    assert ov.is_empty(rel, env)


def test_kv_toml_sections(env):
    t = ov.kv_set("", "toml", "font.size", "12")
    t = ov.kv_set(t, "toml", "font.normal.family", '"Iosevka"')
    t = ov.kv_set(t, "toml", "font.size", "14")
    assert ov.kv_get(t, "toml", "font.size") == "14"
    assert ov.kv_get(t, "toml", "font.normal.family") == '"Iosevka"'
    assert t.count("[font]") == 1


def test_kv_rejects_non_kv_overlay(env):
    with pytest.raises(SystemExit):
        ov.cmd_kv(env, "hypr/monitors.lua", "x", "1")


# ---------------------------------------------------------------- hypr-scale


def test_hypr_scale_block(env):
    ov.cmd_init(env)
    ov.cmd_hypr_scale(env, "", "1.5", "2")
    ov.cmd_hypr_scale(env, "DP-2", "auto", None)
    ov.cmd_hypr_scale(env, "", "1.75", None)
    text = (env.overlay / "hypr/monitors.lua").read_text()
    assert text.count(ov.SCALE_BEGIN) == 1
    assert 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.75 })' in text
    assert 'output = "DP-2"' in text and 'scale = "auto"' in text
    assert 'hl.env("GDK_SCALE", "2")' in text  # kept from the first call
    state = ov.cmd_state(env)
    assert {"output": "", "scale": "1.75"} in state["monitors"]


@pytest.mark.parametrize("args", [("", "1.5); os.execute('x')", None), ('"; x', "1", None), ("", "1", "2.5")])
def test_hypr_scale_rejects_code(env, args):
    ov.cmd_init(env)
    with pytest.raises(SystemExit):
        ov.cmd_hypr_scale(env, *args)


# ---------------------------------------------------------------- rebase


def test_merge3_rules():
    base = {"bar": {"position": "top", "layout": {"left": [1]}}, "idle": {"lock": 300}}
    ours = {"bar": {"position": "bottom", "layout": {"left": [1]}}, "idle": {"lock": 600}}
    theirs = {"bar": {"position": "top", "layout": {"left": [1, 2]}, "new": True}, "idle": {"lock": 120}}
    conflicts = []
    r = ov.merge3(base, ours, theirs, "", conflicts)
    assert r["bar"]["position"] == "bottom"  # only ours changed
    assert r["bar"]["layout"]["left"] == [1, 2]  # only theirs changed (array atomic)
    assert r["bar"]["new"] is True  # new default key arrives
    assert r["idle"]["lock"] == 600  # both changed: ours wins
    assert conflicts == ["/idle/lock"]


def test_merge3_deleted_default_key():
    base = {"a": 1, "b": 2}
    ours = {"a": 1, "b": 2}
    theirs = {"a": 1}
    assert ov.merge3(base, ours, theirs) == {"a": 1}


def test_rebase_end_to_end(env):
    d1 = {"version": 1, "bar": {"position": "top"}, "idle": {"lock": 300}}
    write_defaults(env, d1)
    ov.cmd_init(env)
    # the GUI writes a full snapshot of the defaults with one change
    snap = json.loads(json.dumps(d1))
    snap["bar"]["position"] = "bottom"
    (env.shell / "shell.json").write_text(json.dumps(snap))
    ov.cmd_snapshot_base(env)
    # a release changes the defaults
    d2 = {"version": 1, "bar": {"position": "top", "background": "glass"}, "idle": {"lock": 120}}
    write_defaults(env, d2)
    assert ov.cmd_rebase(env) == []
    got = json.loads((env.shell / "shell.json").read_text())
    assert got == {"version": 1, "bar": {"position": "bottom", "background": "glass"}, "idle": {"lock": 120}}
    assert json.loads((env.shell / "shell.json.base").read_text()) == d2
    # running again is a no-op
    assert ov.cmd_rebase(env) == []


def test_rebase_invalid_user_json_left_alone(env):
    write_defaults(env, {"a": 1})
    ov.cmd_init(env)
    (env.shell / "shell.json").write_text("{nope")
    (env.shell / "shell.json.base").write_text('{"a": 0}')
    assert ov.cmd_rebase(env)
    assert (env.shell / "shell.json").read_text() == "{nope"


# ---------------------------------------------------------------- settle


def test_settle_kv_and_whole_file(env):
    ov.cmd_init(env)
    ov.cmd_kv(env, "kitty.conf", "font_size", "13.0")
    ov.cmd_kv(env, "kitty.conf", "font_family", "Iosevka")
    (env.overlay / "hypr/looknfeel.lua").write_text(ov.header("hypr/looknfeel.lua", env) + "hl.config({ general = { gaps_in = 2 } })\n")
    sha = ov.snapshot_sha(env, "look")
    rep = ov.cmd_settle(env, {"kv": {"kitty.conf": {"font_size": "13.0", "font_family": "Other"}}, "absorbed": {"look": sha}})
    assert rep["removedKeys"] == {"kitty.conf": ["font_size"]}
    text = (env.overlay / "kitty.conf").read_text()
    assert "font_size" not in text and "font_family Iosevka" in text
    assert "hypr/looknfeel.lua" in rep["emptied"]
    assert ov.is_empty("hypr/looknfeel.lua", env)


def test_settle_keeps_changed_after_snapshot(env):
    ov.cmd_init(env)
    p = env.overlay / "hypr/looknfeel.lua"
    p.write_text(ov.header("hypr/looknfeel.lua", env) + "a()\n")
    sha = ov.snapshot_sha(env, "look")
    p.write_text(ov.header("hypr/looknfeel.lua", env) + "b()\n")
    rep = ov.cmd_settle(env, {"absorbed": {"look": sha}})
    assert rep["emptied"] == [] and "hypr/looknfeel.lua" in rep["kept"]
    assert "b()" in p.read_text()


# ---------------------------------------------------------------- reset / state / doctor


def test_reset_targets(env):
    ov.cmd_init(env)
    assert ov.resolve_targets(["hypr"]) == [r for r in ov.OVERLAYS if r.startswith("hypr/")]
    assert ov.resolve_targets(["hypr/hyprsunset.conf"]) == ["hypr/hyprsunset.conf"]
    assert ov.resolve_targets(["~/.config/alacritty/alacritty.toml"]) == ["alacritty.toml"]
    assert "shell" in ov.resolve_targets(["--all"])
    with pytest.raises(SystemExit):
        ov.resolve_targets(["nonsense.conf"])


def test_reset_shell(env):
    ov.cmd_init(env)
    (env.shell / "shell.json").write_text("{}")
    done = ov.do_reset(env, ["shell"])
    assert "shell/shell.json" in done
    assert not (env.shell / "shell.json").exists()


def test_state_has_no_free_text(env):
    ov.cmd_init(env)
    st = env.state / "omarchy/current"
    st.mkdir(parents=True)
    (st / "theme.name").write_text("tokyo-night\n")
    toggles = env.state / "omarchy/toggles"
    toggles.mkdir(parents=True)
    (toggles / "nightlight").touch()
    (toggles / "evil; rm -rf").touch()
    ov.write_state(env)
    doc = json.loads(Path(os.environ["OMANIX_RUNTIME_JSON"]).read_text())
    assert doc["theme"] == "tokyo-night"
    assert doc["toggles"] == ["nightlight"]
    assert all(set(v) == {"sha256", "empty"} for v in doc["overlays"].values())


def test_doctor_reports_shadow_files(env):
    ov.cmd_init(env)
    (env.state / "hypr").mkdir()
    (env.state / "hypr/monitors.lua").write_text("x")
    assert any("shadows" in p for p in ov.cmd_doctor(env))


def test_cli_smoke(env, capsys):
    assert ov.main(["init"]) == 0
    assert ov.main(["kv", "kitty.conf", "font_size", "12"]) == 0
    assert ov.main(["reset", "font"]) == 0
    assert ov.is_empty("kitty.conf", env)
    assert ov.main(["path"]) == 0
    assert str(env.overlay) in capsys.readouterr().out


# ---------------------------------------------------------------- runtime snapshot


def test_runtime_snapshot_font_and_monitors(env):
    ov.cmd_init(env)
    ov.cmd_kv(env, "alacritty.toml", "font.size", "13")
    ov.cmd_kv(env, "kitty.conf", "font_size", "13.0")
    snap = ov.runtime_snapshot(env, "font")
    assert snap["schema"] == "loom.snapshot/v1"
    keys = {f["path"]: f.get("keys") for f in snap["files"]}
    assert keys["overlay/alacritty.toml"] == {"font.size": "13"}
    assert keys["overlay/kitty.conf"] == {"font_size": "13.0"}
    assert snap["snapshotSha"] == ov.snapshot_sha(env, "font")

    ov.cmd_hypr_scale(env, "", "1.5", "2")
    m = ov.runtime_snapshot(env, "monitors")
    f = m["files"][0]
    assert f["monitors"] == [{"output": "", "scale": "1.5"}] and f["gdkScale"] == 2
    assert "text" not in f


def test_runtime_snapshot_unknown_area(env):
    with pytest.raises(SystemExit):
        ov.runtime_snapshot(env, "nope")
