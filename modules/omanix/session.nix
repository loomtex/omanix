# omanix.session: Hyprland under uwsm, upstream's session entry, autologin,
# and the user units upstream enables at first run (§f.2.9).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  user = config.loom.user.name;

  # Upstream's default/wayland-sessions/omarchy.desktop ("uwsm start … hyprland.desktop").
  session = pkgs.runCommand "omanix-session" { passthru.providedSessions = [ "omarchy" ]; } ''
    install -Dm644 ${cfg.fork.package}/default/wayland-sessions/omarchy.desktop \
      $out/share/wayland-sessions/omarchy.desktop
  '';

  # Upstream's user units, enabled the way its first run did (enable-user-units.sh),
  # through NixOS's /etc/systemd/user: ~/.config/systemd/user stays empty.
  units = pkgs.runCommand "omanix-user-units" { } ''
    mkdir -p $out/lib/systemd/user
    cp -r ${cfg.fork.package}/default/systemd/user/. $out/lib/systemd/user/
  '';
  firstRunUnits = {
    bt-agent = "graphical-session.target";
    omarchy-recover-internal-monitor = "graphical-session-pre.target";
    omarchy-sleep-lock = "graphical-session.target";
    omarchy-fcitx5 = "graphical-session.target";
    omarchy-crash-watch = "graphical-session.target";
  };
in
{
  options.omanix.session.autologin = lib.mkOption {
    type = lib.types.bool;
    default = !(config.loom.disk.unlock.automatic or false);
    defaultText = lib.literalExpression "!config.loom.disk.unlock.automatic";
    description = ''
      Log the human in without a greeter password. Only allowed when the disk
      unlock already asks for something (passphrase, PIN, FIDO2): with a
      hands-free TPM unlock, the greeter is the only password left.
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = !(cfg.session.autologin && (config.loom.disk.unlock.automatic or false));
      message = "omanix.session.autologin needs a disk unlock that asks for something; loom.disk.unlock.automatic is true.";
    }];

    programs.hyprland = {
      enable = lib.mkDefault true;
      package = lib.mkDefault cfg.hyprland.package;
      withUWSM = lib.mkDefault true;
    };

    services.displayManager.sessionPackages = [ session ];
    services.displayManager.defaultSession = lib.mkDefault "omarchy";
    services.displayManager.autoLogin = lib.mkIf cfg.session.autologin {
      enable = lib.mkDefault true;
      user = lib.mkDefault user;
    };

    systemd.packages = [ units ];
    # Only wantedBy: NixOS's default unit PATH (coreutils … systemd) would
    # shadow the session PATH uwsm imports, and upstream's scripts call the
    # system profile by name (omarchy-system-sleep-monitor: dbus-monitor).
    systemd.user.services = lib.mapAttrs (_: target: { wantedBy = [ target ]; enableDefaultPath = false; }) firstRunUnits;

    # What the session and the fork's scripts call by name.
    environment.systemPackages = with pkgs; [
      uwsm
      jq
      libnotify
      xdg-utils
      xdg-terminal-exec
      cfg.hyprland.package
      # The shell's own (whatever omanix.packages.base keeps): inotifywait
      # (plugin and input-device watches), dbus-monitor (the sleep lock), and
      # python3 with gi (the input-method indicator; the same env as
      # packages.base and input.nix, so one python3 on PATH).
      inotify-tools
      dbus
      (python3.withPackages (p: [ p.pygobject3 ]))
    ];

    xdg.portal = {
      enable = lib.mkDefault true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    security.polkit.enable = lib.mkDefault true;   # Quickshell is the polkit agent
    services.dbus.implementation = lib.mkDefault "broker";
    hardware.graphics.enable = lib.mkDefault true;
  };
}
