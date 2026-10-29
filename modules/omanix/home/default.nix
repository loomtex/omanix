# omanix.home: the human's dotfiles (D9: home-manager, read-only store links;
# §f.4.2). Each owning module writes its targets with HM and registers them
# in omanix.home.files, which is exported to catalog/home.json and checked
# (checks.home-files-golden: the overlay is each file's last directive).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  user = config.loom.user.name;
  hmCfg = config.home-manager.users.${user} or null;

  fileType = lib.types.submodule ({ name, ... }: {
    options = {
      target = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Path relative to the home directory.";
      };
      module = lib.mkOption {
        type = lib.types.str;
        description = "The omanix module that owns the file (relative to modules/omanix).";
      };
      overlay = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Its runtime overlay, relative to ~/.local/state/omanix/overlay; null if none.";
      };
    };
  });

  # What the fork's scripts and the menu's install guards read (P6, W3).
  catalogConfig = {
    omanix = {
      defaults = {
        browser = cfg.defaults.browser or "chromium";
        terminal = cfg.defaults.terminal or "alacritty";
        editor = cfg.defaults.editor or "nvim";
        dictation = cfg.defaults.dictation or "voxtype";
        agent = if config.loom.agent.enable then config.loom.agent.name else null;
      };
      dns.provider = cfg.dns.provider or "dhcp";
      release.channel = "stable";
    };
  };
  homeCatalog = lib.mapAttrs (_: f: { inherit (f) module overlay; }) cfg.home.files;
in
{
  imports = [ ./desktop.nix ./terminals.nix ];

  options.omanix.home = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Manage the human's desktop dotfiles with home-manager (read-only links).";
    };
    overlays = lib.mkOption {
      type = lib.types.enum [ "keep" "reset" ];
      default = "keep";
      description = "Keep runtime overlays across logins, or empty them at every login (O1).";
    };
    files = lib.mkOption {
      type = lib.types.attrsOf fileType;
      default = { };
      example = { ".config/hypr/monitors.lua" = { module = "hyprland/monitors.nix"; overlay = "hypr/monitors.lua"; }; };
      description = "The HM-owned targets omanix writes, with their owning module and overlay (set by omanix modules).";
    };
    appOwned = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = [ ".config/btop/btop.conf" ".config/fcitx5" ".config/chromium" ".config/mimeapps.list" ".config/dconf" ];
      description = "Paths the applications own; HM never writes them (first login seeds a few).";
    };
  };

  config = lib.mkIf cfg.enable {
    # P6 / W3: the package manifests and the catalog the fork's readers use.
    # Written into system-path itself (extraSetup), so reading systemPackages
    # here is not a recursion.
    environment.extraSetup = ''
      mkdir -p $out/share/omanix/catalog
      cat > $out/share/omanix/packages.txt <<'EOF'
      ${lib.concatStringsSep "\n" (lib.unique (map lib.getName config.environment.systemPackages))}
      EOF
      cat > $out/share/omanix/catalog/config.json <<'EOF'
      ${builtins.toJSON catalogConfig}
      EOF
      cat > $out/share/omanix/catalog/home.json <<'EOF'
      ${builtins.toJSON homeCatalog}
      EOF
    '';

    home-manager.users.${user} = lib.mkIf cfg.home.enable ({ config, lib, ... }: {
      # The per-user manifest (P6): names of this profile's packages.
      home.extraProfileCommands = ''
        mkdir -p $out/share/omanix
        cat > $out/share/omanix/packages.txt <<'EOF'
        ${lib.concatStringsSep "\n" (lib.unique (map lib.getName config.home.packages))}
        EOF
      '';
      # Never HM-owned (§f.4.5): the generated software owner key lives in ~/.ssh.
      programs.ssh.enable = lib.mkForce false;
    });
  };
}
