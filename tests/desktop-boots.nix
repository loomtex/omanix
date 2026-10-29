# desktop-boots (W15; U24, U34): loom's host template through the omanix
# base boots to the Hyprland/uwsm session with the Quickshell shell running,
# home-manager's files in place (read-only) and the runtime overlays created.
#
# greeter = true: no autologin; SDDM's Wayland greeter (Hyprland with
# upstream's greeter Lua, upstream's theme) comes up, and logging in through
# it reaches the same session.
{ pkgs, loom, omanix, greeter ? false }:

let
  template = loom.outPath + "/templates/host";
  user = "alice";
  uid = "1000";
  asUser = cmd: "su - ${user} -c ${pkgs.lib.escapeShellArg "XDG_RUNTIME_DIR=/run/user/${uid} ${cmd}"}";
in
pkgs.testers.runNixOSTest {
  name = "omanix-desktop-boots${if greeter then "-greeter" else ""}";
  node.pkgsReadOnly = false;
  node.specialArgs = { inputs = { }; inherit loom omanix; };

  nodes.machine = { config, lib, ... }: {
    imports = [
      loom.nixosModules.default
      (loom.lib.mkHostModule { self = template; homeModules = [ (template + "/home.nix") ]; hostInputs = { }; system = "x86_64-linux"; })
      omanix.nixosModules.default
      (template + "/configuration.nix")
      (loom.outPath + "/tests/vm/disk-standin.nix")   # W4 stand-in (loom's W5 tests use it too)
    ];

    networking.hostName = lib.mkForce "machine";
    users.users.${user}.password = "test";
    omanix.session.autologin = !greeter;

    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;
    virtualisation.diskSize = lib.mkForce 4096;
    virtualisation.qemu.options = [ "-vga none" "-device virtio-gpu-pci" ];
  };

  testScript = ''
    import datetime
    T = lambda s: datetime.timedelta(seconds=s)

    def diag():
        print(machine.execute("journalctl -b --no-pager -n 300 -u display-manager; journalctl -b --no-pager -n 200 _UID=${uid}; ls -la /run/user/${uid} 2>&1")[1])

    machine.wait_for_unit("multi-user.target")

    try:
        machine.wait_for_unit("display-manager.service", timeout=120)
    except Exception:
        diag(); raise

    ${if greeter then ''
      with subtest("the SDDM greeter runs on Hyprland with the omarchy theme"):
          try:
              machine.wait_until_succeeds("pgrep -u sddm -f 'yprland.* --config .*default/sddm/hyprland.lua'", timeout=T(120))
              machine.wait_until_succeeds("pgrep -u sddm -f '[s]ddm-greeter'", timeout=T(120))
          except Exception:
              diag(); raise
          # the greeter was started with upstream's theme
          machine.succeed("pgrep -u sddm -af 'sddm-greeter' | grep -q 'themes/omarchy'")
          machine.sleep(5)
          machine.screenshot("greeter")

      with subtest("logging in through the greeter starts the session"):
          machine.send_chars("test\n")
    '' else ""}

    with subtest("the uwsm Hyprland session starts for the human"):
        try:
            # the NixOS binary is wrapped (.Hyprland-wrapped), so ask its IPC
            machine.wait_until_succeeds(${builtins.toJSON (asUser "hyprctl -i 0 -j monitors")}, timeout=T(180))
        except Exception:
            diag(); raise
        # uwsm runs the compositor as a user unit (wayland-wm@hyprland.desktop.service)
        machine.succeed(${builtins.toJSON (asUser "systemctl --user list-units --state=active --no-legend 'wayland-wm@*.service'")} + " | grep -q 'wayland-wm@'")

    with subtest("the Lua config loads without errors"):
        out = machine.succeed(${builtins.toJSON (asUser "hyprctl -i 0 configerrors")})
        print(out)
        assert out.strip() == "", out

    with subtest("the Quickshell shell runs from OMARCHY_PATH"):
        try:
            machine.wait_until_succeeds("pgrep -u ${user} -f 'quickshell .*-p /run/current-system/omarchy/shell'", timeout=T(120))
        except Exception:
            print(machine.execute("journalctl -b --no-pager -t omarchy-shell -n 200")[1]); raise
        machine.sleep(10)
        # still running after it had time to load the QML (a load error exits)
        machine.succeed("pgrep -u ${user} -f 'quickshell .*-p /run/current-system/omarchy/shell'")
        machine.screenshot("desktop")

    with subtest("session init created the overlays; HM files are read-only links"):
        machine.wait_until_succeeds(${builtins.toJSON (asUser "systemctl --user is-active omanix-session-init.service")}, timeout=T(60))
        for f in ["hypr/monitors.lua", "alacritty.toml", "foot.ini", "fontconfig/fonts.conf"]:
            machine.succeed(f"test -f /home/${user}/.local/state/omanix/overlay/{f}")
        machine.succeed("test -e /home/${user}/.local/state/omanix/done/first-login")
        machine.succeed("test -f /home/${user}/.gitconfig")
        for f in [".config/hypr/hyprland.lua", ".config/hypr/monitors.lua", ".bashrc", ".config/foot/foot.ini"]:
            machine.succeed(f"readlink -f /home/${user}/{f} | grep -q '^/nix/store/'")
            machine.fail(f"su - ${user} -c 'echo x >> /home/${user}/{f}'")
        machine.succeed("test \"$(readlink -f /run/current-system/omarchy)\" = \"$(readlink -f /run/current-system)/omarchy\" || readlink /run/current-system/omarchy | grep -q omanix-data")

    with subtest("an overlay change takes effect after a reload"):
        machine.succeed(${builtins.toJSON (asUser "omanix-overlay hypr-scale '' 1")})
        machine.succeed(${builtins.toJSON (asUser "hyprctl -i 0 reload")})
        machine.sleep(2)
        out = machine.succeed(${builtins.toJSON (asUser "hyprctl -i 0 -j monitors")})
        import json
        assert all(abs(m["scale"] - 1.0) < 0.01 for m in json.loads(out)), out
        assert machine.succeed(${builtins.toJSON (asUser "hyprctl -i 0 configerrors")}).strip() == ""

    with subtest("the runtime summary is written for the resident"):
        machine.wait_until_succeeds("test -s /run/omanix/session/${uid}/runtime.json", timeout=T(30))
        machine.succeed("stat -c %G /run/omanix/session/${uid}/runtime.json | grep -qx omanix-resident")
  '';
}
