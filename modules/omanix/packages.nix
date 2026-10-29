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
    environment.systemPackages = cfg.packages.base;

    # What those tools need from the system.
    services.gnome.gnome-keyring.enable = lib.mkDefault true;   # libsecret, chromium's password store
    security.pam.services.sddm.enableGnomeKeyring = lib.mkDefault true;
    services.locate = { enable = lib.mkDefault true; package = lib.mkDefault pkgs.plocate; };
    programs.gpu-screen-recorder.enable = lib.mkDefault true;    # capability wrapper for recording
    hardware.i2c.enable = lib.mkDefault true;                     # ddcutil (external monitor brightness)
    services.hardware.bolt.enable = lib.mkDefault true;           # thunderbolt authorisation
    documentation.man.enable = lib.mkDefault true;
    programs.bash.completion.enable = lib.mkDefault true;
  };
}
