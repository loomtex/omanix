# omanix.theme: the theme registry, the declared theme, and the lock (§f.5).
#
# Runtime theme switching is upstream's, unchanged: omarchy-theme-set (KEEP-AS-
# GUI) renders into ~/.local/state/omarchy/current/** and the read-only HM
# files include that state. What nix adds:
#   - the registry ($OMARCHY_PATH/themes): upstream's themes, the host's
#     omanix.theme.extra, a plain background per theme (U23) and omanix's
#     unlock wordmark (pkgs/by-name/omanix-themes);
#   - the first login sets omanix.theme.default (runtime.nix's first-login
#     script);
#   - omanix.theme.lock re-applies it at every login, puts a guard on
#     omarchy-theme-set and hides the theme picker, background and install rows.
# "Make it stick" turns a runtime theme into omanix.theme.default (§f.4.6).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  user = config.loom.user.name;

  upstreamNames = builtins.attrNames (lib.filterAttrs (_: t: t == "directory")
    (builtins.readDir "${pkgs.omanixFork.src}/themes"));
  names = lib.unique (upstreamNames ++ builtins.attrNames cfg.theme.extra);

  extraType = lib.types.submodule {
    options = {
      src = lib.mkOption {
        type = lib.types.path;
        example = lib.literalExpression "inputs.theme-everblush";
        description = "The theme's directory (a flake input): colors.toml, backgrounds/, and so on.";
      };
      trusted = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Ship the theme as it is. A theme's hyprland.lua, neovim.lua and
          terminal configs are code that runs as the human; untrusted themes
          are staged like upstream stages a theme cloned from a repo (no Lua,
          no terminal configs, no vscode.json, no symlinks).
        '';
      };
    };
  };

  registry = pkgs.omanix-themes.override {
    omarchy-src = cfg.fork.package;
    omanixExtraThemes = cfg.theme.extra;
  };

  # The menu rows the lock hides (upstream ids at the pin).
  lockedMenuItems = [ "appearance.theme" "appearance.background" "install.style.theme" "install.style.background" ];

  bin = "${cfg.path}/bin";
  bg = if cfg.theme.background == null then null else "${cfg.theme.background}";

  # At every login with the lock: back to the declared theme (and background).
  relock = pkgs.writeShellScript "omanix-theme-relock" ''
    set -u
    # the session's PATH, not the unit's minimal one
    export PATH=${bin}:/run/wrappers/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH
    state="''${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current"
    if [ "$(cat "$state/theme.name" 2>/dev/null)" != ${lib.escapeShellArg cfg.theme.default} ]; then
      OMARCHY_THEME_WAIT=1 omarchy-theme-set ${lib.escapeShellArg cfg.theme.default} </dev/null \
        || echo "omanix: could not re-apply the locked theme" >&2
    fi
    ${lib.optionalString (bg != null) ''
      [ "$(readlink -f "$state/background")" = "$(readlink -f ${bg})" ] || omarchy-theme-bg-set ${bg} || true
    ''}
  '';
in
{
  imports = [ ./boot.nix ];

  options.omanix.theme = {
    default = lib.mkOption {
      type = lib.types.enum names;
      default = "tokyo-night";
      example = "kanagawa";
      description = ''
        The theme the first login applies (and every login, with
        `omanix.theme.lock`). Themes switched at runtime are runtime state;
        "make it stick" sets this option.
      '';
    };
    lock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Keep the declared theme: re-apply it at every login, refuse other
        themes in `omarchy-theme-set`, and hide the theme picker, background
        and theme install rows of the menu.
      '';
    };
    intros = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Play background intro videos on theme switches (the first login seeds upstream's `background-intros-off` toggle when false).";
    };
    available = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = names;
      defaultText = lib.literalMD "every theme in the registry";
      description = "The themes in the registry: upstream's and `omanix.theme.extra`.";
    };
    extra = lib.mkOption {
      type = lib.types.attrsOf extraType;
      default = { };
      example = lib.literalExpression ''{ everblush = { src = inputs.theme-everblush; }; }'';
      description = ''
        Third-party themes from flake inputs, added to the registry under
        their attribute name. Each needs a colors.toml (boot visuals are
        drawn from it).
      '';
    };
    background = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./wallpapers/fuji.jpg";
      description = "A background set at the first login (and every login, with the lock); null keeps the theme's.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = registry;
      defaultText = lib.literalExpression "pkgs.omanix-themes with omanix.theme.extra";
      description = "The theme registry, `$OMARCHY_PATH/themes`.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (n: e: {
      assertion = !(builtins.elem n upstreamNames) && builtins.pathExists (e.src + "/colors.toml");
      message = "omanix.theme.extra.${n}: "
        + (if builtins.elem n upstreamNames then "an upstream theme already has this name; pick another"
           else "${toString e.src} has no colors.toml");
    }) cfg.theme.extra;

    omanix.fork.dataArgs = {
      omanixThemes = registry;
    } // lib.optionalAttrs cfg.theme.lock {
      omanixThemeLock = cfg.theme.default;
      omanixHiddenMenuItems = lockedMenuItems;
    };

    systemd.user.services.omanix-session-init.serviceConfig.ExecStartPost =
      lib.mkIf cfg.theme.lock "${relock}";

    # catalog/themes.json (§h.9)
    environment.extraSetup = ''
      mkdir -p $out/share/omanix/catalog
      cat > $out/share/omanix/catalog/themes.json <<'EOF'
      ${builtins.toJSON {
        inherit (cfg.theme) default lock;
        available = names;
        extra = lib.mapAttrs (_: e: { inherit (e) trusted; }) cfg.theme.extra;
        boot = cfg.theme.boot.theme;
      }}
      EOF
    '';
  };
}
