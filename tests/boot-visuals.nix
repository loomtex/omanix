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

  # The greeter node is the omanix desktop through SDDM; each Plymouth node
  # is a minimal system whose systemd initrd shows the theme's unlock
  # prompt (a password request, as for the disk) and waits there.
  nodes = {
    machine = { config, pkgs, lib, ... }:
      let greeter = t: pkgs.omanix-sddm-theme.override { omanixTheme = t; themeName = "omanix-${t}"; };
      in {
        imports = [ (d.node { greeter = true; }) ];
        environment.systemPackages = map greeter goldenThemes;
      };
  } // lib.listToAttrs (map (t: lib.nameValuePair "plymouth_${lib.replaceStrings [ "-" ] [ "_" ] t}" ({ config, pkgs, lib, ... }: {
    nixpkgs.overlays = [ omanix.overlays.default ];
    boot.plymouth = {
      enable = true;
      themePackages = [ (pkgs.omanix-plymouth.override { omanixTheme = t; }) ];
      theme = "omanix";
    };
    boot.initrd.systemd.services.omanix-unlock-prompt = {
      description = "Ask for a password (the unlock screen)";
      wantedBy = [ "initrd.target" ];
      after = [ "plymouth-start.service" ];
      before = [ "initrd-root-fs.target" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.boot.initrd.systemd.package}/bin/systemd-ask-password --timeout=0 Unlock";
        StandardOutput = "null";
      };
    };
    boot.initrd.systemd.storePaths = [ "${config.boot.initrd.systemd.package}/bin/systemd-ask-password" ];
    # Plymouth's DRM renderer never shows on virtio-gpu's QMP screendump
    # (no flip or dirty-FB); QEMU's standard VGA (bochs-drm) does.
    virtualisation.qemu.options = [ "-vga std" ];
  })) goldenThemes);

  testScript = ''
    ${d.helpers}
    import os, subprocess, time
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

    def shot_ok(t, name, node):
        node.screenshot(name)
        shot = os.path.join(OUT, name + ".png")
        corner = "#" + magick(shot, "-format", "%[hex:p{4,4}]", "info:")[:6].lower()
        acc = float(magick(shot, "-fuzz", "8%", "-fill", "white", "-opaque", PAL[t]["accent"], "-fill", "black", "+opaque", "white", "-format", "%[fx:mean]", "info:"))
        print(f"{name}: corner {corner} (background {PAL[t]['background']}), accent coverage {acc:.4f}")
        return shot, near(corner, PAL[t]["background"]) and acc > 0.005

    def check(t, what, diag=None, node=None):
        node = node or machine
        name = f"{t}-{what}"
        # retry: the VM's scanout can lag a mode set by a few seconds
        for attempt in range(6):
            shot, ok = shot_ok(t, name, node)
            if ok:
                break
            time.sleep(2)
        if not ok:
            if diag:
                print(node.execute(diag)[1])
            raise AssertionError(f"{name}: the theme's background and accent logo are not on screen")
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
            node = globals()["plymouth_" + t.replace("-", "_")]
            node.start()
            # no backdoor yet (the initrd is waiting): watch the screen
            for _ in range(60):
                time.sleep(2)
                node.screenshot("probe")
                c = "#" + magick(os.path.join(OUT, "probe.png"), "-format", "%[hex:p{4,4}]", "info:")[:6].lower()
                if near(c, PAL[t]["background"]):
                    break
            time.sleep(3)
            node.send_chars("omanix")
            time.sleep(2)
            check(t, "plymouth", node=node)
            node.crash()
    os.remove(os.path.join(OUT, "probe.png"))

    for t in THEMES:
        with subtest(f"SDDM: the {t} greeter"):
            machine.succeed("sed 's/^Current=omanix$/Current=omanix-" + t + "/' \"$(readlink -f /etc/sddm.conf)\" > /etc/sddm.conf.new "
                            "&& grep -q 'Current=omanix-" + t + "' /etc/sddm.conf.new && mv -f /etc/sddm.conf.new /etc/sddm.conf")
            machine.succeed("systemctl start display-manager")
            machine.wait_until_succeeds(f"pgrep -u sddm -af sddm-greeter | grep -q 'themes/omanix-{t}'", timeout=T(120))
            machine.sleep(8)
            machine.send_chars("omanix")
            machine.sleep(2)
            check(t, "sddm", diag="journalctl -b --no-pager -n 60 -u display-manager")
            machine.succeed("systemctl stop display-manager")
            machine.sleep(3)
  '';
}
