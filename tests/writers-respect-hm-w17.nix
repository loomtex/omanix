# writers-respect-hm, W17's cases (§i.2; U28, U35): the KEEP-AS-GUI writers
# change runtime state and never an HM file, and the declared defaults and
# apps reach the session.
#
# - font set / text size: omarchy-font-set and omarchy-display-text-size
#   write the terminal and fontconfig overlays; fc-match and
#   omarchy-font-current return the new font; settle drops the keys once
#   they are declared; the declared font-set hook runs (omanix.hooks);
# - input (U28): upstream's keyboard picker, through the omanix override,
#   writes the keyboard block of overlay/hypr/input.lua, the live
#   input:kb_layout follows, and the HM input.lua/keyboard-layouts stay
#   read-only links;
# - defaults (U35): the readers print the declared defaults, xdg-settings
#   reports the declared browser (set by HM activation at boot, without a
#   session bus), xdg-terminal-exec picks the declared terminal; an
#   alacritty overlay key overrides omanix-base.toml;
# - apps: herdr and udiskie run (the session's autostart starts them), a
#   declared app's autostart ran, web-app entries and their keybinding
#   exist, chromium-flags.conf carries the declared feature.
# After all of it every HM target is still a link into the current
# generation and configerrors is empty.
{ pkgs, loom, omanix }:

let
  template = loom.outPath + "/templates/host";
  user = "alice";
  uid = "1000";
  home = "/home/${user}";
  ov = "${home}/.local/state/omanix/overlay";

  autostartProbe = pkgs.writeShellScriptBin "omanix-autostart-probe" ''
    touch "$XDG_RUNTIME_DIR/omanix-autostart-ok"
  '';
in
pkgs.testers.runNixOSTest {
  name = "omanix-writers-respect-hm-w17";
  node.pkgsReadOnly = false;
  node.specialArgs = { inputs = { }; inherit loom omanix; };

  nodes.machine = { config, lib, pkgs, ... }: {
    imports = [
      loom.nixosModules.default
      (loom.lib.mkHostModule { self = template; homeModules = [ (template + "/home.nix") ]; hostInputs = { }; system = "x86_64-linux"; })
      omanix.nixosModules.default
      (template + "/configuration.nix")
      (loom.outPath + "/tests/vm/disk-standin.nix")
    ];

    networking.hostName = lib.mkForce "machine";
    users.users.${user}.password = "test";
    omanix.session.autologin = true;

    # defaults case: not the upstream defaults, so the test sees them applied.
    omanix.defaults = { terminal = "alacritty"; browser = "chromium"; editor = "nvim"; };
    # apps case
    omanix.apps.autostart-probe = { packages = [ autostartProbe ]; autostart = "omanix-autostart-probe"; };
    omanix.apps.chromium.features = [ "WebUIDarkMode" ];
    omanix.apps.webapps.Linear = { url = "https://linear.app"; icon = "linear"; bind = "SUPER + CTRL + ALT + L"; };
    omanix.hooks.font-set = ''echo "$1" > "$HOME/.cache/omanix-hook-font-set"'';
    # The heavy apps add nothing to these cases.
    omanix.apps.libreoffice.enable = false;
    omanix.apps.docker.enable = false;

    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;
    virtualisation.diskSize = lib.mkForce 4096;
    virtualisation.qemu.options = [ "-vga none" "-device virtio-gpu-pci" ];
  };

  testScript = ''
    import datetime, json, shlex
    T = lambda s: datetime.timedelta(seconds=s)

    # A command in the human's graphical session (its env, bus and Hyprland).
    ENV = ("export XDG_RUNTIME_DIR=/run/user/${uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus; "
           "export WAYLAND_DISPLAY=$(cd /run/user/${uid} && ls wayland-* | grep -v lock | head -n1); "
           "export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/${uid}/hypr | head -n1); ")
    def s(cmd):
        return machine.succeed("su - ${user} -c " + shlex.quote(ENV + cmd))

    def diag():
        print(machine.execute("journalctl -b --no-pager -n 200 _UID=${uid}")[1])

    def hm_links_intact():
        # the generation home-manager-${user}.service activated at boot
        gen = machine.succeed("systemctl show -p ExecStart --value home-manager-${user}.service | grep -o '/nix/store/[^ ;]*-home-manager-generation' | head -n1").strip()
        files = machine.succeed(f"readlink -f {gen}/home-files").strip()
        targets = json.loads(machine.succeed("cat /run/current-system/sw/share/omanix/catalog/home.json"))
        for t in targets:
            p = "${home}/" + t
            link = machine.succeed(f"readlink {p}").strip()
            assert link.startswith(files + "/"), f"{t} is not a link into the current generation: {link}"
            if t != ".config/btop/themes/current.theme":   # an out-of-store link into theme state, by design
                machine.fail(f"su - ${user} -c 'echo >> {p}'")

    def no_configerrors():
        out = s("hyprctl configerrors").strip()
        assert out == "", out

    machine.wait_for_unit("multi-user.target")
    try:
        machine.wait_until_succeeds("su - ${user} -c " + shlex.quote(ENV + "hyprctl -j monitors"), timeout=T(240))
        machine.wait_until_succeeds("su - ${user} -c " + shlex.quote(ENV + "systemctl --user is-active omanix-session-init.service"), timeout=T(60))
    except Exception:
        diag(); raise
    machine.sleep(5)

    with subtest("apps: herdr, udiskie and a declared app's autostart run"):
        machine.wait_until_succeeds("pgrep -u ${user} -f 'herdr server'", timeout=T(60))
        machine.wait_until_succeeds("pgrep -u ${user} -f udiskie", timeout=T(60))
        machine.wait_until_succeeds("test -e /run/user/${uid}/omanix-autostart-ok", timeout=T(60))
        machine.fail("journalctl -b _UID=${uid} | grep -E 'Command not found: .?(herdr|udiskie)'")
        machine.succeed("grep -q 'omanix-autostart-probe' ${home}/.config/hypr/autostart.lua")
        machine.succeed("test -e /run/current-system/sw/share/applications/YouTube.desktop")
        machine.succeed("grep -q 'Exec=omarchy-launch-webapp https://linear.app' /run/current-system/sw/share/applications/Linear.desktop")
        machine.succeed("test -e /run/current-system/sw/share/applications/chromium.desktop")
        binds = s("hyprctl -j binds")
        assert "https://linear.app" in binds, "the web app's keybinding is missing"
        machine.succeed("grep -q -- '--enable-features=.*WebUIDarkMode' ${home}/.config/chromium-flags.conf")
        machine.succeed("tail -n1 ${home}/.config/chromium-flags.conf | grep -q 'omanix/overlay/chromium-flags.conf'")

    with subtest("defaults: readers, xdg-settings (set at activation, U35), xdg-terminal-exec"):
        assert s("omarchy-default-terminal").strip() == "alacritty"
        assert s("omarchy-default-browser").strip() == "chromium"
        assert s("omarchy-default-editor").strip() == "nvim"
        assert s("env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings get default-web-browser").strip() == "chromium.desktop"
        machine.succeed("test -f ${home}/.config/mimeapps.list && ! test -L ${home}/.config/mimeapps.list")
        assert s("xdg-terminal-exec --print-id").strip().startswith("Alacritty.desktop")
        machine.succeed("test -L ${home}/.config/xdg-terminals.list")

    with subtest("defaults (U35): an alacritty overlay key overrides omanix-base.toml"):
        s("omanix-overlay kv alacritty.toml env.TERM '\"omanix-u35\"'")
        s("setsid -f alacritty -e sh -c 'echo $TERM > /tmp/omanix-u35-term' >/dev/null 2>&1")
        machine.wait_until_succeeds("grep -qx omanix-u35 /tmp/omanix-u35-term", timeout=T(60))
        s("omanix-overlay kv alacritty.toml env.TERM --unset")

    with subtest("font set: overlays change, HM files don't; fc-match follows; the hook runs"):
        s("omarchy-font-set 'DejaVu Sans Mono'")
        machine.succeed("grep -qx 'font_family DejaVu Sans Mono' ${ov}/kitty.conf")
        machine.succeed("grep -q 'family = \"DejaVu Sans Mono\"' ${ov}/alacritty.toml")
        machine.succeed("grep -qx 'font-family = \"DejaVu Sans Mono\"' ${ov}/ghostty.conf")
        machine.succeed("grep -qx 'font=DejaVu Sans Mono:size=9' ${ov}/foot.ini")
        machine.succeed("grep -q '<string>DejaVu Sans Mono</string>' ${ov}/fontconfig/fonts.conf")
        assert s("fc-match monospace -f '%{family[0]}'").strip() == "DejaVu Sans Mono"
        assert s("omarchy-font-current").strip() == "DejaVu Sans Mono"
        machine.succeed("grep -qx 'DejaVu Sans Mono' ${home}/.cache/omanix-hook-font-set")
        doctor = s("omanix-overlay doctor")
        assert "overlay not empty: kitty.conf" in doctor and "overlay not empty: fontconfig/fonts.conf" in doctor, doctor
        state = json.loads(machine.succeed("cat /run/omanix/session/${uid}/runtime.json"))
        assert state["monospace"] == "DejaVu Sans Mono", state

    with subtest("text size: terminal overlays and the shell's state file"):
        s("omarchy-display-text-size 16")
        machine.succeed("grep -qx 'font_size 12.0' ${ov}/kitty.conf")
        machine.succeed("grep -qx 'size = 12' ${ov}/alacritty.toml")
        machine.succeed("grep -qx 'font=DejaVu Sans Mono:size=12' ${ov}/foot.ini")
        machine.succeed("grep -q 'base-size = 16' ${home}/.local/state/omanix/shell/shell.toml")
        machine.fail("test -e ${home}/.config/omarchy/shell.toml")
        s("omarchy-display-text-size reset")

    with subtest("settle: declared values leave the overlays (make it stick, kv half)"):
        declared = {"monospace": "DejaVu Sans Mono",
                    "kv": {"kitty.conf": {"font_family": "DejaVu Sans Mono", "font_size": "9.0"},
                           "foot.ini": {"font": "DejaVu Sans Mono:size=9"}}}
        machine.succeed(f"echo {shlex.quote(json.dumps(declared))} > /tmp/declared.json && chmod 644 /tmp/declared.json")
        s("omanix-overlay settle /tmp/declared.json")
        machine.fail("grep -q font_family ${ov}/kitty.conf")
        machine.fail("grep -q '^font=' ${ov}/foot.ini")
        machine.fail("grep -q 'DejaVu' ${ov}/fontconfig/fonts.conf")
        machine.succeed("grep -q 'family = \"DejaVu Sans Mono\"' ${ov}/alacritty.toml")   # not declared: kept

    with subtest("input (U28): the keyboard picker writes the overlay; the live layout follows"):
        sel = json.dumps({"catalog": {"us": "English (US)", "de": "German"}, "overrides": {}})
        out = s(f"python3 -I \"$OMARCHY_PATH/default/input-methods/omanix_keyboard.py\" apply keyboard '{sel}' '[\"English (US)\", \"German\"]'")
        print(out)
        machine.succeed("grep -q 'kb_layout = \"us,de\"' ${ov}/hypr/input.lua")
        live = json.loads(s("hyprctl -j getoption input:kb_layout"))
        assert live["str"] == "us,de", live
        machine.succeed("grep -qx 'XKBLAYOUT=us' ${home}/.config/omarchy/keyboard-layouts")
        no_configerrors()
        s("omanix-overlay kb --unset")
        s("hyprctl reload")
        machine.sleep(2)
        assert json.loads(s("hyprctl -j getoption input:kb_layout"))["str"] == "us"

    with subtest("every HM target is still a read-only link; no config errors"):
        hm_links_intact()
        no_configerrors()
  '';
}
