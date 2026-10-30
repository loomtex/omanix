with subtest("glass: theme state and overlay/gtk4.css, not the HM gtk.css (W16)"):
    gtk = f"{OVERLAY}/gtk4.css"
    empty = machine.succeed(f"cat {gtk}")
    machine.succeed(as_user("omarchy-hyprland-window-transparency glassy"))
    assert machine.succeed(as_user("omarchy-hyprland-window-transparency")).strip() == "glassy"
    machine.succeed(f"grep -q 'omarchy-glass begin' {gtk}")
    machine.succeed(f"grep -q '@import url(\"file:///run/current-system/omarchy/default/gtk/glass.css\")' {gtk}")
    machine.succeed("test -s /run/current-system/omarchy/default/gtk/glass.css")
    for f in ["alacritty.toml", "kitty.conf", "foot.ini", "btop.theme"]:
        machine.succeed(f"grep -q 'omarchy-glass begin' {STATE}/theme/{f}")
    # the HM gtk.css is untouched and imports the overlay as its last directive
    machine.succeed(f"tail -n1 {HOME}/.config/gtk-4.0/gtk.css | grep -q 'omanix/overlay/gtk4.css'")
    machine.fail(f"grep -q 'omarchy-glass' {HOME}/.config/gtk-4.0/gtk.css")
    # leaving glassy gives the overlay back exactly as it was
    machine.succeed(as_user("omarchy-hyprland-window-transparency transparent"))
    assert machine.succeed(f"cat {gtk}") == empty, machine.succeed(f"cat {gtk}")
    machine.fail(f"grep -q 'omarchy-glass begin' {STATE}/theme/alacritty.toml")
    # and glass survives a theme switch (the switch renders it into the new theme)
    machine.succeed(as_user("omarchy-hyprland-window-transparency glassy"))
    machine.succeed(as_user("OMARCHY_THEME_WAIT=1 omarchy-theme-set kanagawa </dev/null"))
    machine.succeed(f"grep -q 'omarchy-glass begin' {STATE}/theme/alacritty.toml")
    machine.succeed(f"grep -q 'omarchy-glass begin' {gtk}")
    machine.succeed(as_user("omarchy-hyprland-window-transparency transparent"))
