# Runtime overlays and session init (§f.4.3-§f.4.6).
#
# omanix-session-init (user oneshot, before graphical-session-pre.target):
#   create the overlay layout and touch missing overlays, rebase shell.json,
#   reset overlays when omanix.home.overlays = "reset", and on the first
#   login only, copy the app-owned seeds and create ~/.gitconfig.
# omanix-session-state (path-triggered): /run/omanix/session/<uid>/runtime.json,
#   the typed summary the resident may read (group omanix-resident).
# /etc/omanix/settle.json: what `omanix-overlay settle` compares against
#   after a promoted switch ("make it stick").
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
    # §f.4.5 step 3, §f.5: the declared theme (theme/default.nix). Hyprland
    # and the shell start after this unit, so they come up themed. The
    # theme scripts need the session's PATH, not the unit's minimal one.
    themePath="${cfg.path}/bin:/run/wrappers/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
    ${lib.optionalString (!cfg.theme.intros) ''
      mkdir -p "$HOME/.local/state/omarchy/toggles"
      touch "$HOME/.local/state/omarchy/toggles/background-intros-off"
    ''}
    OMARCHY_THEME_WAIT=1 PATH="$themePath" omarchy-theme-set ${lib.escapeShellArg cfg.theme.default} </dev/null \
      || echo "omanix: the first-login theme did not apply" >&2
    ${lib.optionalString (cfg.theme.background != null) ''
      PATH="$themePath" omarchy-theme-bg-set ${lib.escapeShellArg "${cfg.theme.background}"} || true
    ''}
    mkdir -p "$(dirname "$done_flag")"
    touch "$done_flag"
  '';

  sessionEnv = {
    OMARCHY_PATH = cfg.path;
    OMANIX_AGENT_NAME = agentName;
    OMANIX_RECLAIM_DIR = "%h/.local/state/loom/clobbered";
  };

  settle = {
    kv = { };   # W17's font/input modules add their declared kv values here
    absorbed = lib.filterAttrs (_: v: v != null) cfg.runtime.absorbed;
  };
in
{
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
      # Stopped with the session, so the next login runs it again even when
      # the user manager outlives the session (UserStopDelaySec, lingering);
      # otherwise RemainAfterExit keeps it "active" and the lock and
      # overlays = "reset" are skipped (theme-switch caught it).
      partOf = [ "graphical-session-pre.target" ];
      unitConfig.ConditionUser = user;
      environment = sessionEnv;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [
          "${pkgs.omanix-overlay}/bin/omanix-overlay init${lib.optionalString (cfg.home.overlays == "reset") " --reset"}"
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
