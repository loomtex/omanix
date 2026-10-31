with subtest("font set: overlays change, HM files don't; fc-match follows; the hook runs (W17)"):
    s("omarchy-font-set 'DejaVu Sans Mono'")
    machine.succeed(f"grep -qx 'font_family DejaVu Sans Mono' {OVERLAY}/kitty.conf")
    machine.succeed(f"grep -q 'family = \"DejaVu Sans Mono\"' {OVERLAY}/alacritty.toml")
    machine.succeed(f"grep -qx 'font-family = \"DejaVu Sans Mono\"' {OVERLAY}/ghostty.conf")
    machine.succeed(f"grep -qx 'font=DejaVu Sans Mono:size=9' {OVERLAY}/foot.ini")
    machine.succeed(f"grep -q '<string>DejaVu Sans Mono</string>' {OVERLAY}/fontconfig/fonts.conf")
    assert s("fc-match monospace -f '%{family[0]}'").strip() == "DejaVu Sans Mono"
    assert s("omarchy-font-current").strip() == "DejaVu Sans Mono"
    machine.succeed(f"grep -qx 'DejaVu Sans Mono' {HOME}/.cache/omanix-hook-font-set")
    doctor = json.loads(s("omanix doctor --json"))
    listed = {o["overlay"]: o for o in doctor["overlays"]}
    assert "kitty.conf" in listed and "fontconfig/fonts.conf" in listed, doctor
    assert "omanix.fonts.monospace" in listed["kitty.conf"]["shadows"], doctor
    state = json.loads(machine.succeed(f"cat /run/omanix/session/{UID}/runtime.json"))
    assert state["monospace"] == "DejaVu Sans Mono", state

with subtest("text size: terminal overlays and the shell's state file (W17)"):
    s("omarchy-display-text-size 16")
    machine.succeed(f"grep -qx 'font_size 12.0' {OVERLAY}/kitty.conf")
    machine.succeed(f"grep -qx 'size = 12' {OVERLAY}/alacritty.toml")
    machine.succeed(f"grep -qx 'font=DejaVu Sans Mono:size=12' {OVERLAY}/foot.ini")
    machine.succeed(f"grep -q 'base-size = 16' {HOME}/.local/state/omanix/shell/shell.toml")
    machine.fail(f"test -e {HOME}/.config/omarchy/shell.toml")
    s("omarchy-display-text-size reset")

with subtest("settle: declared values leave the overlays (make it stick, kv half; W17)"):
    declared = {"monospace": "DejaVu Sans Mono",
                "kv": {"kitty.conf": {"font_family": "DejaVu Sans Mono", "font_size": "9.0"},
                       "foot.ini": {"font": "DejaVu Sans Mono:size=9"}}}
    machine.succeed(f"echo {shlex.quote(json.dumps(declared))} > /tmp/declared.json && chmod 644 /tmp/declared.json")
    s("omanix-overlay settle /tmp/declared.json")
    machine.fail(f"grep -q font_family {OVERLAY}/kitty.conf")
    machine.fail(f"grep -q '^font=' {OVERLAY}/foot.ini")
    machine.fail(f"grep -q 'DejaVu' {OVERLAY}/fontconfig/fonts.conf")
    machine.succeed(f"grep -q 'family = \"DejaVu Sans Mono\"' {OVERLAY}/alacritty.toml")   # not declared: kept
