# theme-switch (W16, §i.2): omarchy-theme-set at runtime on the read-only
# HM dotfiles.
#   - the first login applied omanix.theme.default (state, background,
#     browser policy color through the spool and the root path unit);
#   - two switches (tokyo-night -> catppuccin-latte -> kanagawa): running
#     alacritty, kitty and foot windows change color on screen;
#   - no HM target changed; configerrors stay empty;
#   - with omanix.theme.lock (a specialisation), omarchy-theme-set refuses
#     other themes, the menu hides the theme rows, and the next login puts
#     the declared theme back.
{ pkgs, loom, omanix }:

let
  d = import ./lib/desktop.nix { inherit pkgs loom omanix; };
  themesSrc = pkgs.omanixFork.src;
  palette = t: (import ../lib/theme.nix { inherit (pkgs) lib; }).palette "${themesSrc}/themes/${t}";
  bgs = builtins.toJSON (pkgs.lib.genAttrs [ "tokyo-night" "catppuccin-latte" "kanagawa" ] (t: (palette t).background));
in
pkgs.testers.runNixOSTest {
  name = "omanix-theme-switch";
  node.pkgsReadOnly = false;
  node.specialArgs = { inputs = { }; inherit loom omanix; };

  nodes.machine = { pkgs, lib, ... }: {
    imports = [ (d.node { }) ];
    environment.systemPackages = with pkgs; [ alacritty kitty foot imagemagick ];
    specialisation.locked.configuration = {
      omanix.theme.lock = true;
    };
  };

  testScript = ''
    ${d.helpers}
    import os, subprocess
    BG = json.loads(${builtins.toJSON bgs})
    MAGICK = "${pkgs.imagemagick}/bin/magick"
    STATE = f"{HOME}/.local/state/omarchy/current"

    def theme_name():
        return machine.succeed(f"cat {STATE}/theme.name").strip()

    def set_theme(t):
        machine.succeed(as_user(f"OMARCHY_THEME_WAIT=1 omarchy-theme-set {t} </dev/null"))
        assert theme_name() == t, theme_name()

    def chromium_hex():
        rgb = machine.succeed(f"cat {STATE}/theme/chromium.theme").strip().split(",")
        return "#" + "".join(f"{int(x):02x}" for x in rgb)

    def pixel(shot, x, y):
        out = subprocess.run([MAGICK, shot, "-format", f"%[hex:p{{{x},{y}}}]", "info:"], capture_output=True, text=True, check=True).stdout
        return "#" + out.strip()[:6].lower()

    def near(a, b, tol=40):
        return all(abs(int(a[i:i+2], 16) - int(b[i:i+2], 16)) <= tol for i in (1, 3, 5))

    def window_points():
        """One point per terminal, in screenshot pixels: low and right inside its window."""
        scale = json.loads(machine.succeed(as_user("hyprctl -i 0 -j monitors")))[0]["scale"]
        pts = {}
        for c in json.loads(machine.succeed(as_user("hyprctl -i 0 -j clients"))):
            cls = c["class"].lower()
            for term in ("alacritty", "kitty", "foot"):
                if term in cls:
                    (x, y), (w, h) = c["at"], c["size"]
                    pts[term] = (int((x + w * 0.8) * scale), int((y + h * 0.8) * scale))
        return pts

    def assert_terminals(t, name):
        machine.sleep(6)
        machine.screenshot(name)
        shot = os.path.join(os.environ["out"], name + ".png")
        pts = window_points()
        assert set(pts) == {"alacritty", "kitty", "foot"}, pts
        for term, (x, y) in pts.items():
            got = pixel(shot, x, y)
            print(f"{name}: {term} at {x},{y} is {got}, {t} background {BG[t]}")
            assert near(got, BG[t]), f"{term} shows {got}, not {t}'s {BG[t]}"

    wait_desktop()

    with subtest("the first login applied the declared theme"):
        assert theme_name() == "tokyo-night", theme_name()
        bg = machine.succeed(f"readlink -f {STATE}/background").strip()
        assert bg.endswith("/tokyo-night/backgrounds/0-omanix.png"), bg
        machine.succeed(f"test -e {HOME}/.local/state/omarchy/toggles/background-intros-off")
        machine.wait_until_succeeds(f"grep -qx '{chromium_hex()}' /run/omanix/browser-color.applied", timeout=T(30))
        machine.succeed(f"grep -q '\"BrowserThemeColor\": \"{chromium_hex()}\"' /etc/chromium/policies/managed/color.json")
        machine.succeed("stat -c '%U %a' /etc/chromium/policies/managed/color.json | grep -qx 'root 644'")
        machine.succeed("grep -q DefaultBrowserSettingEnabled /etc/chromium/policies/managed/extra.json")

    links = assert_hm_links(hm_links())

    with subtest("terminals open in the theme"):
        for t in ("alacritty", "kitty", "foot"):
            machine.succeed(as_user(f"setsid -f {t} >/dev/null 2>&1 </dev/null"))
        machine.wait_until_succeeds(as_user("hyprctl -i 0 -j clients") + " | grep -c '\"class\"' | grep -qx 3", timeout=T(60))
        assert_terminals("tokyo-night", "terminals-tokyo-night")

    with subtest("two switches retint the running terminals"):
        for t in ("catppuccin-latte", "kanagawa"):
            set_theme(t)
            assert_terminals(t, f"terminals-{t}")
            for f in ("kitty.conf", "alacritty.toml", "foot.ini"):
                machine.succeed(f"grep -qi '{BG[t]}' {STATE}/theme/{f}")
            machine.wait_until_succeeds(f"grep -qx '{chromium_hex()}' /run/omanix/browser-color.applied", timeout=T(30))
            machine.succeed(f"grep -q '{chromium_hex()}' /etc/chromium/policies/managed/color.json")
            configerrors_empty()

    with subtest("no HM target changed"):
        assert_hm_unchanged(links)

    with subtest("the spool only takes a color"):
        machine.succeed(as_user("printf 'x; rm -rf /\\n' > /var/lib/omanix/spool/browser-color"))
        machine.sleep(2)
        machine.succeed(f"grep -q '{chromium_hex()}' /etc/chromium/policies/managed/color.json")
        machine.fail(as_user("omarchy-theme-set-browser-policy 'zz0000'"))
        machine.fail("su -s /bin/sh nobody -c 'echo \"#000000\" > /var/lib/omanix/spool/browser-color'")

    with subtest("the lock: guard, hidden rows, and the declared theme at the next login"):
        machine.succeed("/run/current-system/specialisation/locked/bin/switch-to-configuration test")
        machine.fail(as_user("omarchy-theme-set catppuccin-latte"))
        machine.succeed(as_user("omarchy-theme-set catppuccin-latte 2>&1 | grep -q 'locked to tokyo-night'"))
        machine.succeed("grep '\"appearance.theme\"' /run/current-system/omarchy/default/omarchy/omarchy-menu.jsonc | grep -q '\"when\":\"false\"'")
        assert theme_name() == "kanagawa"
        machine.succeed("systemctl restart display-manager")
        machine.sleep(5)
        wait_desktop()
        machine.wait_until_succeeds(f"grep -qx tokyo-night {STATE}/theme.name", timeout=T(60))
        assert_hm_links(hm_links())
  '';
}
