# boot-visuals (W16): the Plymouth unlock screen and the SDDM greeter,
# rendered by the real programs in a VM for each golden theme, as the
# installed system draws them (omanix-plymouth and omanix-sddm-theme, built
# from the theme's colors.toml; the greeter on Hyprland with upstream's Lua).
#
# Each screenshot must show the theme's background at the corner and its
# accent in the logo, and match tests/golden/boot-visuals/<theme>-<what>.png
# (fuzz 10%, < 1% of the pixels differ). The screenshots are in $out; to
# regenerate the goldens after reviewing them, copy them over.
{ pkgs, loom, omanix, goldenThemes }:

let
  inherit (pkgs) lib;
  d = import ./lib/desktop.nix { inherit pkgs loom omanix; };
  themeLib = import ../lib/theme.nix { inherit lib; };
  palettes = lib.genAttrs goldenThemes (t: themeLib.palette "${pkgs.omanixFork.src}/themes/${t}");
  goldens = ./golden/boot-visuals;
in
pkgs.testers.runNixOSTest {
  name = "omanix-boot-visuals";
  node.pkgsReadOnly = false;
  node.specialArgs = { inputs = { }; inherit loom omanix; };

  nodes.machine = { config, pkgs, lib, ... }:
    let
      splash = t: pkgs.omanix-plymouth.override { omanixTheme = t; themeName = "omanix-${t}"; };
      greeter = t: pkgs.omanix-sddm-theme.override { omanixTheme = t; themeName = "omanix-${t}"; };
    in
    {
      imports = [ (d.node { greeter = true; }) ];
      boot.plymouth.themePackages = lib.mkForce ([ config.omanix.theme.boot.plymouth ] ++ map splash goldenThemes);
      environment.systemPackages = map greeter goldenThemes;
    };

  testScript = ''
    ${d.helpers}
    import os, subprocess
    THEMES = ${builtins.toJSON goldenThemes}
    PAL = json.loads(${builtins.toJSON (builtins.toJSON palettes)})
    GOLDEN = "${goldens}"
    MAGICK = "${pkgs.imagemagick}/bin/magick"
    OUT = os.environ["out"]

    def magick(*args):
        r = subprocess.run([MAGICK, *args], capture_output=True, text=True)
        return r.stdout.strip() or r.stderr.strip()

    def near(a, b, tol=12):
        return all(abs(int(a[i:i+2], 16) - int(b[i:i+2], 16)) <= tol for i in (1, 3, 5))

    def check(t, what):
        name = f"{t}-{what}"
        machine.screenshot(name)
        shot = os.path.join(OUT, name + ".png")
        corner = "#" + magick(shot, "-format", "%[hex:p{4,4}]", "info:")[:6].lower()
        assert near(corner, PAL[t]["background"]), f"{name}: corner {corner}, background {PAL[t]['background']}"
        acc = float(magick(shot, "-fuzz", "8%", "-fill", "white", "-opaque", PAL[t]["accent"], "-fill", "black", "+opaque", "white", "-format", "%[fx:mean]", "info:"))
        print(f"{name}: corner {corner}, accent coverage {acc:.4f}")
        assert acc > 0.005, f"{name}: the accent-colored logo is not on screen ({acc})"
        golden = os.path.join(GOLDEN, name + ".png")
        if os.path.exists(golden):
            r = subprocess.run([MAGICK, "compare", "-metric", "AE", "-fuzz", "10%", golden, shot, "null:"], capture_output=True, text=True)
            diff = float(r.stderr.split()[0])
            total = float(magick(shot, "-format", "%[fx:w*h]", "info:"))
            print(f"{name}: {diff:.0f} of {total:.0f} pixels differ from the golden")
            assert diff / total < 0.01, f"{name} differs from {golden}: {diff} pixels"
        else:
            print(f"{name}: no golden yet (tests/golden/boot-visuals/{name}.png)")

    machine.wait_for_unit("display-manager.service")
    machine.wait_until_succeeds("pgrep -u sddm -f '[s]ddm-greeter'", timeout=T(180))
    machine.succeed("pgrep -u sddm -af sddm-greeter | grep -q 'themes/omanix'")
    machine.succeed("systemctl stop display-manager")
    machine.sleep(3)

    for t in THEMES:
        with subtest(f"Plymouth: the {t} unlock screen"):
            machine.succeed("rm -f /etc/plymouth/plymouthd.conf && "
                            f"printf '[Daemon]\\nTheme=omanix-{t}\\nShowDelay=0\\nDeviceTimeout=8\\n' > /etc/plymouth/plymouthd.conf")
            machine.succeed("chvt 1")
            machine.succeed("plymouthd --mode=boot --tty=/dev/tty1 --pid-file=/run/omanix-plymouthd.pid")
            machine.succeed("plymouth show-splash")
            machine.execute("plymouth ask-for-password --prompt=Unlock >/dev/null 2>&1 &")
            machine.sleep(3)
            machine.send_chars("omanix")
            machine.sleep(2)
            check(t, "plymouth")
            machine.execute("plymouth quit; sleep 1; pkill plymouthd; pkill -f 'plymouth ask-for-password'")
            machine.sleep(2)

    for t in THEMES:
        with subtest(f"SDDM: the {t} greeter"):
            machine.succeed("sed 's/^Current=omanix$/Current=omanix-" + t + "/' \"$(readlink -f /etc/sddm.conf)\" > /etc/sddm.conf.new "
                            "&& grep -q 'Current=omanix-" + t + "' /etc/sddm.conf.new && mv -f /etc/sddm.conf.new /etc/sddm.conf")
            machine.succeed("systemctl start display-manager")
            machine.wait_until_succeeds(f"pgrep -u sddm -af sddm-greeter | grep -q 'themes/omanix-{t}'", timeout=T(120))
            machine.sleep(8)
            machine.send_chars("omanix")
            machine.sleep(2)
            check(t, "sddm")
            machine.succeed("systemctl stop display-manager")
            machine.sleep(3)
  '';
}
