with subtest("apps: herdr, udiskie and a declared app's autostart run (W17)"):
    machine.wait_until_succeeds(f"pgrep -u {USER} -f 'herdr server'", timeout=T(60))
    machine.wait_until_succeeds(f"pgrep -u {USER} -f udiskie", timeout=T(60))
    machine.wait_until_succeeds(f"test -e /run/user/{UID}/omanix-autostart-ok", timeout=T(60))
    machine.fail(f"journalctl -b _UID={UID} | grep -E 'Command not found: .?(herdr|udiskie)'")
    machine.succeed(f"grep -q 'omanix-autostart-probe' {HOME}/.config/hypr/autostart.lua")
    machine.succeed("test -e /run/current-system/sw/share/applications/YouTube.desktop")
    machine.succeed("grep -q 'Exec=omarchy-launch-webapp https://linear.app' /run/current-system/sw/share/applications/Linear.desktop")
    machine.succeed("test -e /run/current-system/sw/share/applications/chromium.desktop")
    # The bind is declared in the HM bindings.lua; Hyprland holds a Lua
    # function for it, so `hyprctl binds` shows its chord and description.
    machine.succeed(f"grep -q 'https://linear.app' {HOME}/.config/hypr/bindings.lua")
    assert '"Linear"' in s("hyprctl -j binds"), "the web app's keybinding is not loaded"
    machine.succeed(f"grep -q -- '--enable-features=.*WebUIDarkMode' {HOME}/.config/chromium-flags.conf")
    machine.succeed(f"tail -n1 {HOME}/.config/chromium-flags.conf | grep -q 'omanix/overlay/chromium-flags.conf'")
