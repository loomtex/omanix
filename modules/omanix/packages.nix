# omanix.packages: upstream's base package set (install/omarchy-base.packages,
# x86_64) as nixpkgs attributes, and the small services those tools need.
# Applications are omanix.apps (apps/), fonts omanix.fonts, the default
# terminal/browser/editor omanix.defaults; audio, network, power and
# printing have their own modules. Arch-only entries (pacman-contrib, yay,
# expac, base-devel, kernel-modules-hook, limine, snapper, …) are dropped:
# nix replaces them. The aarch64 lists are deferred (§f.2.3).
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;

  # gsettings (Arch's glib2), with the GNOME desktop schemas and the dconf
  # backend omarchy-theme-set-gnome and omarchy-display-text-size write
  # through (org.gnome.desktop.interface); nixpkgs keeps schemas out of
  # XDG_DATA_DIRS, and a user unit may lack the session's GIO_EXTRA_MODULES.
  gsettings = pkgs.writeShellScriptBin "gsettings" ''
    export XDG_DATA_DIRS=${pkgs.glib.getSchemaDataDirPath pkgs.gsettings-desktop-schemas}''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}
    export GIO_EXTRA_MODULES=${pkgs.dconf.lib}/lib/gio/modules''${GIO_EXTRA_MODULES:+:$GIO_EXTRA_MODULES}
    exec ${pkgs.glib.bin}/bin/gsettings "$@"
  '';
in
{
  options.omanix.packages.base = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = with pkgs; [
      # shell and CLI
      bat eza fd fzf ripgrep zoxide starship tmux less whois inetutils inotify-tools
      jq gum fastfetch tldr tree-sitter unzip usage socat curl git inxi mise
      lua5_1 luarocks ruby
      (python3.withPackages (p: [ p.pygobject3 ]))
      # Wayland desktop tools omarchy's scripts call
      wl-clipboard wtype grim slurp hyprpicker hyprsunset hyprland-guiutils
      hyprland-preview-share-picker xdg-user-dirs libnotify libsecret
      brightnessctl ddcutil bluez-tools
      # media and capture
      imagemagick ffmpeg ffmpegthumbnailer qrencode zbar yt-dlp
      (tesseract.override { enableLanguages = [ "eng" ]; })
      # look
      yaru-theme gnome-themes-extra adwaita-icon-theme
    ];
    defaultText = lib.literalExpression "[ bat eza fd fzf ripgrep zoxide starship tmux … ] (upstream's base list)";
    example = lib.literalExpression "with pkgs; [ bat ripgrep ]";
    description = ''
      The base command-line and desktop tools omarchy installs and its
      scripts call. Override to trim; add your own packages in
      environment.systemPackages or home.packages instead.
    '';
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = cfg.packages.base ++ [ gsettings ];
    programs.dconf.enable = lib.mkDefault true;                   # gsettings' backend

    # What those tools need from the system.
    services.gnome.gnome-keyring.enable = lib.mkDefault true;   # libsecret, chromium's password store
    security.pam.services.sddm.enableGnomeKeyring = lib.mkDefault true;
    services.locate = { enable = lib.mkDefault true; package = lib.mkDefault pkgs.plocate; };
    programs.gpu-screen-recorder.enable = lib.mkDefault true;    # capability wrapper for recording
    hardware.i2c.enable = lib.mkDefault true;                     # ddcutil (external monitor brightness)
    services.hardware.bolt.enable = lib.mkDefault true;           # thunderbolt authorisation
    documentation.man.enable = lib.mkDefault true;
    # /share/doc of every package (python's alone is 57 MiB) stays out of the
    # system; man pages stay. omarchy has no speech stack, and nixpkgs'
    # graphical-desktop turns speech-dispatcher on with mbrola's 645 MiB of
    # voices (mkDefault there, so one step above it here; a host's plain
    # `true` still wins). Both are closure-budget trims (§e.1).
    documentation.doc.enable = lib.mkDefault false;
    services.speechd.enable = lib.mkOverride 999 false;
    programs.bash.completion.enable = lib.mkDefault true;
  };
}
