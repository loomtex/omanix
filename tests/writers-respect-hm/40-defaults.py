with subtest("defaults: readers, xdg-settings (set at activation, U35), xdg-terminal-exec (W17)"):
    v = s("omarchy-default-terminal").strip(); assert v == "alacritty", v
    v = s("omarchy-default-browser").strip(); assert v == "chromium", v
    v = s("omarchy-default-editor").strip(); assert v == "nvim", v
    got = s("env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings get default-web-browser").strip()
    if got != "chromium.desktop":
        print(machine.execute(f"journalctl -b --no-pager -u home-manager-{USER}.service | tail -n 40; cat {HOME}/.config/mimeapps.list")[1])
    assert got == "chromium.desktop", f"default browser: {got!r}"
    machine.succeed(f"test -f {HOME}/.config/mimeapps.list && ! test -L {HOME}/.config/mimeapps.list")
    assert s("xdg-terminal-exec --print-id").strip().startswith("Alacritty.desktop")
    machine.succeed(f"test -L {HOME}/.config/xdg-terminals.list")

with subtest("defaults (U35): an alacritty overlay key overrides omanix-base.toml (W17)"):
    s("omanix-overlay kv alacritty.toml env.TERM '\"omanix-u35\"'")
    s("setsid -f alacritty -e sh -c 'echo $TERM > /tmp/omanix-u35-term' >/dev/null 2>&1")
    machine.wait_until_succeeds("grep -qx omanix-u35 /tmp/omanix-u35-term", timeout=T(60))
    s("omanix-overlay kv alacritty.toml env.TERM --unset")
