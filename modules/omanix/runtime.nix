# Runtime overlays and session init (§f.4.3-§f.4.6).
#
# omanix-session-init (user oneshot, before graphical-session-pre.target):
#   create the overlay layout and touch missing overlays, rebase shell.json,
#   reset overlays when omanix.home.overlays = "reset", and on the first
#   login only, copy the app-owned seeds and create ~/.gitconfig.
# omanix-session-state (path-triggered): /run/omanix/session/<uid>/runtime.json,
#   the typed summary the resident may read (group omanix-resident).
# /etc/omanix/settle.json: what `omanix-overlay settle` compares against
#   ("make it stick"): the declared kv/typed values (omanix.runtime.settle,
#   from fonts.nix and input.nix) and the absorbed whole-file snapshots. It
#   runs at every login (session init) and after a promoted switch: loom's
#   afterTest hook reloads Hyprland right after `switch-to-configuration
#   test` and leaves a user unit that settles once the system profile points
#   at the new generation (loom has no after-promote hook; a rollback never
#   gets there, so nothing is settled against a rejected generation).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  user = config.loom.user.name;
  uid = toString config.users.users.${user}.uid;
  agentName = if config.loom.agent.enable or false then config.loom.agent.name else "your agent";
  data = cfg.fork.data;

  textOrFile = v: if builtins.isPath v || lib.isStorePath v then v else pkgs.writeText "omanix-branding" v;

  # First login only (gated on done/first-login); never overwrites a file.
  firstLogin = pkgs.writeShellScript "omanix-first-login" ''
    set -u
    done_flag="''${XDG_STATE_HOME:-$HOME/.local/state}/omanix/done/first-login"
    [ -e "$done_flag" ] && exit 0
    seed() {   # seed <src> <dest>: copy only if dest is absent
      [ -e "$2" ] && return 0
      [ -e "$1" ] || return 0
      mkdir -p "$(dirname "$2")"
      cp -rL --no-preserve=mode "$1" "$2"
    }
    seed ${data}/config/btop/btop.conf "$HOME/.config/btop/btop.conf"
    seed ${data}/config/fcitx5 "$HOME/.config/fcitx5"
    seed ${data}/config/opencode/opencode.json "$HOME/.config/opencode/opencode.json"
    ${lib.optionalString (cfg.defaults.editor == "nvim")
      ''seed ${pkgs.omarchy-nvim}/share/omarchy-nvim/config "$HOME/.config/nvim"''}   # app-owned (lazy.nvim writes it)
    ${lib.optionalString (cfg.branding.about != null)
      ''seed ${textOrFile cfg.branding.about} "$HOME/.config/omarchy/branding/about.txt"''}
    ${lib.optionalString (cfg.branding.screensaver != null)
      ''seed ${textOrFile cfg.branding.screensaver} "$HOME/.config/omarchy/branding/screensaver.txt"''}
    if [ ! -e "$HOME/.gitconfig" ]; then
      printf '%s\n' \
        "# Your own git settings. git reads this after ~/.config/git/config (managed by" \
        "# omanix), and \`git config --global\` writes here." > "$HOME/.gitconfig"
    fi
    ${pkgs.xdg-user-dirs}/bin/xdg-user-dirs-update || true
    mkdir -p "$(dirname "$done_flag")"
    touch "$done_flag"
  '';

  sessionEnv = {
    OMARCHY_PATH = cfg.path;
    OMANIX_AGENT_NAME = agentName;
    OMANIX_RECLAIM_DIR = "%h/.local/state/loom/clobbered";
  };

  settle = cfg.runtime.settle // {
    absorbed = lib.filterAttrs (_: v: v != null) cfg.runtime.absorbed;
  };

  hyprctl = "${cfg.hyprland.package}/bin/hyprctl";
  # Find the session's Hyprland when the unit environment doesn't name it.
  hyprEnv = ''
    if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" ]; then
      HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" | head -n1)
      export HYPRLAND_INSTANCE_SIGNATURE
    fi
  '';

  # loom.switch.afterTest (as = session), with @toplevel@ = the generation
  # just activated (new, or the old one on rollback).
  afterTest = pkgs.writeShellScript "omanix-after-switch-test" ''
    set -u
    top=$1
    ${hyprEnv}
    # The watchdog's configerrors check must see the new Lua (§f.2.9).
    ${hyprctl} reload >/dev/null 2>&1 || true
    case "$top" in /nix/store/*) ;; *) exit 0 ;; esac
    ${pkgs.systemd}/bin/systemd-run --user --no-block --collect --quiet \
      --unit="omanix-settle-$(basename "$top" | cut -c1-12)" \
      ${settleWhenPromoted} "$top" >/dev/null 2>&1 || true
  '';
  settleWhenPromoted = pkgs.writeShellScript "omanix-settle-when-promoted" ''
    set -u
    top=$1
    for _ in $(seq 1 360); do
      if [ "$(readlink -f /nix/var/nix/profiles/system)" = "$top" ]; then
        [ "$(readlink -f /run/current-system)" = "$top" ] || exit 0
        ${pkgs.omanix-overlay}/bin/omanix-overlay settle "$top/etc/omanix/settle.json"
        ${hyprEnv}
        exec ${hyprctl} reload
      fi
      [ "$(readlink -f /run/current-system)" = "$top" ] || exit 0   # rolled back
      sleep 5
    done
  '';
in
{
  options.omanix.runtime.settle = lib.mkOption {
    type = lib.types.attrsOf (pkgs.formats.json { }).type;
    default = { };
    internal = true;
    description = ''
      Declared values `omanix-overlay settle` drops from the overlays when
      they match: `kv.<overlay>.<key>` (the overlay's own syntax),
      `monospace`, `keyboard.{layouts,variants}`. Set by fonts.nix and
      input.nix.
    '';
  };

  options.omanix.runtime.absorbed = lib.mkOption {
    type = lib.types.attrsOf (lib.types.nullOr lib.types.str);
    default = { };
    example = { look = "3b1f…"; };
    description = ''
      Per area, the sha256 of the runtime snapshot a "make it stick" change
      absorbed (§f.4.6). After the switch, `omanix-overlay settle` empties
      that area's whole-file overlays only if they still have this sha.
    '';
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.omanix-overlay pkgs.omanix-runtime-snapshot ];
    environment.etc."omanix/settle.json".text = builtins.toJSON settle;
    loom.switch.afterTest = [ { command = "${afterTest} @toplevel@"; as = "session"; } ];

    users.groups.omanix-resident = { };
    systemd.tmpfiles.rules = [
      "d /run/omanix 0755 root root -"
      "d /run/omanix/session 0755 root root -"
      "d /run/omanix/session/${uid} 2750 ${user} omanix-resident -"
    ];

    systemd.user.services.omanix-session-init = {
      description = "omanix: runtime overlays and first login";
      wantedBy = [ "graphical-session-pre.target" ];
      before = [ "graphical-session-pre.target" ];
      unitConfig.ConditionUser = user;
      environment = sessionEnv;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [
          "${pkgs.omanix-overlay}/bin/omanix-overlay init${lib.optionalString (cfg.home.overlays == "reset") " --reset"}"
          "${pkgs.omanix-overlay}/bin/omanix-overlay settle /etc/omanix/settle.json"
          "${firstLogin}"
        ];
      };
    };

    systemd.user.services.omanix-session-state = {
      description = "omanix: write the typed runtime summary for the resident";
      unitConfig.ConditionUser = user;
      environment = sessionEnv;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.omanix-overlay}/bin/omanix-overlay state";
      };
    };
    systemd.user.paths.omanix-session-state = {
      description = "omanix: watch overlays, theme and toggles";
      wantedBy = [ "graphical-session.target" ];
      unitConfig.ConditionUser = user;
      pathConfig = {
        PathChanged = [
          "%h/.local/state/omanix/overlay"
          "%h/.local/state/omanix/overlay/hypr"
          "%h/.local/state/omanix/shell"
          "%h/.local/state/omarchy/current"
          "%h/.local/state/omarchy/toggles"
        ];
        Unit = "omanix-session-state.service";
      };
    };
  };
}
