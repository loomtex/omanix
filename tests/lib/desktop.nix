# Shared by W16's VM tests (theme-switch, writers-respect-hm, boot-visuals):
# the same node as desktop-boots (loom's host template through the omanix
# base, autologin unless `greeter`), and Python helpers for the test script.
{ pkgs, loom, omanix }:

let
  template = loom.outPath + "/templates/host";
  user = "alice";
  uid = "1000";
in
{
  inherit user uid;

  node = { greeter ? false, extra ? { } }: { config, lib, ... }: {
    imports = [
      loom.nixosModules.default
      (loom.lib.mkHostModule { self = template; homeModules = [ (template + "/home.nix") ]; hostInputs = { }; system = "x86_64-linux"; })
      omanix.nixosModules.default
      (template + "/configuration.nix")
      (loom.outPath + "/tests/vm/disk-standin.nix")
      extra
    ];

    networking.hostName = lib.mkForce "machine";
    users.users.${user}.password = "test";
    omanix.session.autologin = !greeter;

    virtualisation.memorySize = 4096;
    virtualisation.cores = 2;
    virtualisation.diskSize = lib.mkForce 4096;
    virtualisation.qemu.options = [ "-vga none" "-device virtio-gpu-pci" ];
  };

  # Python: run as the human inside the session (the user manager's
  # environment: WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE, D-Bus).
  helpers = ''
    import datetime, json, shlex
    T = lambda s: datetime.timedelta(seconds=s)
    USER, UID = "${user}", "${uid}"
    HOME = f"/home/{USER}"

    def as_user(cmd):
        env = ("export XDG_RUNTIME_DIR=/run/user/" + UID + "; "
               "eval \"$(systemctl --user show-environment | sed -n -E "
               "'s/^(WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|DBUS_SESSION_BUS_ADDRESS|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE)=(.*)$/export \\1=\\2/p')\"; ")
        return "su - " + USER + " -c " + shlex.quote(env + cmd)

    def diag():
        print(machine.execute("journalctl -b --no-pager -n 200 _UID=" + UID + "; journalctl -b --no-pager -n 80 -u display-manager")[1])

    def wait_desktop():
        machine.wait_for_unit("multi-user.target")
        try:
            machine.wait_until_succeeds(as_user("hyprctl -i 0 -j monitors"), timeout=T(240))
            machine.wait_until_succeeds("pgrep -u " + USER + " -f 'quickshell .*-p /run/current-system/omarchy/shell'", timeout=T(120))
            machine.wait_until_succeeds(as_user("systemctl --user is-active omanix-session-init.service"), timeout=T(120))
        except Exception:
            diag(); raise

    def hm_links():
        """target -> link destination, for every HM-owned file (omanix.home.files)."""
        targets = json.loads(machine.succeed("cat /run/current-system/sw/share/omanix/catalog/home.json"))
        out = {}
        for t in sorted(targets):
            out[t] = machine.succeed(f"readlink {HOME}/{t} || echo NOT-A-LINK").strip()
        return out

    def assert_hm_links(links):
        for t, dest in links.items():
            assert dest.startswith("/nix/store/") and "home-manager-files" in dest, f"{t} -> {dest} is not an HM store link"
        return links

    def assert_hm_unchanged(before):
        after = assert_hm_links(hm_links())
        assert after == before, "HM targets changed: " + json.dumps({k: (before.get(k), after.get(k)) for k in after if before.get(k) != after.get(k)}, indent=1)

    def configerrors_empty():
        out = machine.succeed(as_user("hyprctl -i 0 configerrors"))
        assert out.strip() == "", out
  '';
}
