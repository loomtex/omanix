with subtest("chromium: a runtime feature goes to overlay/chromium-flags.conf and reaches the browser (W16)"):
    ov = f"{OVERLAY}/chromium-flags.conf"
    hm = f"{HOME}/.config/chromium-flags.conf"
    machine.succeed(as_user("omarchy-chromium-add-feature OmanixProbe"))
    machine.succeed(f"grep -qx -- '--enable-features=OmanixProbe' {ov}")
    machine.succeed(as_user("omarchy-chromium-add-feature OmanixProbe"))   # idempotent
    machine.succeed(as_user("omarchy-chromium-add-feature Second"))
    machine.succeed(f"grep -qx -- '--enable-features=OmanixProbe,Second' {ov}")
    machine.fail(f"grep -q OmanixProbe {hm}")
    flags = machine.succeed(as_user("omanix-chromium-flags")).splitlines()
    print(flags)
    want = "--enable-features=TouchpadOverscrollHistoryNavigation,OverlayScrollbar,OmanixProbe,Second"
    assert want in flags, flags
    assert sum(f.startswith("--enable-features=") for f in flags) == 1, flags
    assert "--ozone-platform=wayland" in flags, flags
    # the real browser, through the wrapper on PATH
    machine.succeed(as_user("setsid -f chromium --headless=new --user-data-dir=/tmp/omanix-cr about:blank >/tmp/omanix-cr.log 2>&1 </dev/null"))
    machine.wait_until_succeeds(f"pgrep -u {USER} -f -- 'OmanixProbe,Second'", timeout=T(90))
    pid = machine.succeed(f"pgrep -u {USER} -o -f -- 'OmanixProbe,Second'").strip()
    argv = machine.succeed(f"tr '\\0' '\\n' < /proc/{pid}/cmdline").splitlines()
    print(argv)
    assert want in argv, argv
    assert "--load-extension=/run/current-system/omarchy/default/chromium/extensions/copy-url,/run/current-system/omarchy/default/chromium/extensions/yt-dlp,/run/current-system/omarchy/default/chromium/extensions/whatsapp-slim" in argv, argv
    machine.succeed(f"pkill -u {USER} -f -- '--headless=new' || true")
    # reset clears it
    machine.succeed(as_user("omanix-overlay reset chromium-flags.conf"))
    machine.fail(f"grep -q OmanixProbe {ov}")
