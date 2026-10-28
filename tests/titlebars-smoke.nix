# The titlebars plugin loads into the Hyprland it was built against (W3
# acceptance). Hyprland runs on the VM's virtio GPU with software rendering
# and a one-line Lua config; nothing from omarchy runs here.
{ pkgs }:

let
  hyprland = pkgs.hyprland-omarchy;
  titlebars = pkgs.omarchy-hyprland-titlebars.override { inherit hyprland; };
  config = pkgs.writeText "hl-smoke.lua" ''
    hl.plugin.load("${titlebars}/${titlebars.pluginPath}")
  '';
in
pkgs.testers.runNixOSTest {
  name = "omanix-titlebars-smoke";

  nodes.machine = { ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.qemu.options = [ "-vga none" "-device virtio-gpu-pci" ];
    hardware.graphics.enable = true;
    environment.systemPackages = [ hyprland ];
    users.users.alice = { isNormalUser = true; uid = 1000; };
    services.getty.autologinUser = "alice";
    environment.loginShellInit = ''
      if [ "$(tty)" = /dev/tty1 ] && [ "$USER" = alice ]; then
        exec Hyprland --config ${config} > /tmp/hyprland.log 2>&1
      fi
    '';
  };

  testScript = ''
    import datetime
    machine.wait_for_unit("multi-user.target")
    try:
        machine.wait_until_succeeds("pgrep -f '[H]yprland --config'", timeout=datetime.timedelta(seconds=60))
    except Exception:
        print(machine.execute("cat /tmp/hyprland.log; ls -la /dev/dri; loginctl")[1])
        raise
    out = machine.wait_until_succeeds(
        "su alice -c 'XDG_RUNTIME_DIR=/run/user/1000 hyprctl -i 0 plugin list'",
        timeout=datetime.timedelta(seconds=60))
    print(out)
    assert "hyprbars" in out or "titlebars" in out, out
  '';
}
