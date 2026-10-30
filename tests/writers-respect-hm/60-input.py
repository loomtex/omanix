with subtest("input (U28): the keyboard picker writes the overlay; the live layout follows (W17)"):
    sel = json.dumps({"catalog": {"us": "English (US)", "de": "German"}, "overrides": {}})
    print(s(f"python3 -I \"$OMARCHY_PATH/default/input-methods/omanix_keyboard.py\" apply keyboard '{sel}' '[\"English (US)\", \"German\"]'"))
    machine.succeed(f"grep -q 'kb_layout = \"us,de\"' {OVERLAY}/hypr/input.lua")
    live = json.loads(s("hyprctl -j getoption input:kb_layout"))
    assert live["str"] == "us,de", live
    machine.succeed(f"grep -qx 'XKBLAYOUT=us' {HOME}/.config/omarchy/keyboard-layouts")
    configerrors_empty()
    s("omanix-overlay kb --unset")
    s("hyprctl reload")
    machine.sleep(2)
    assert json.loads(s("hyprctl -j getoption input:kb_layout"))["str"] == "us"
