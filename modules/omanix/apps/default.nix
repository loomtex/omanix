# omanix.apps: omarchy's applications, web apps and TUIs (§f.4.2).
#
# omanix.apps.<name> = { enable; packages; autostart; } for upstream's base
# applications (on by default) and any the host adds. Web apps and TUIs get
# desktop entries in the system profile (~/.local/share/applications stays
# the user's, §f.4.5). HM (read-only): ~/.config/hypr/autostart.lua
# (o.launch_on_start per app with `autostart`, then its overlay).
#
# Chromium is an entry of this list like the others (enable, packages,
# autostart), plus `package` (pkgs.omanix-chromium, the wrapper) and
# `features`; apps/chromium.nix owns ~/.config/chromium-flags.conf.
{ config, lib, pkgs, ... }:

let
  cfg = config.omanix;
  acfg = cfg.apps;
  user = config.loom.user.name;
  lua = import ../../../lib/lua.nix { inherit lib; };
  homeLib = import ../../../lib/home { inherit lib; };
  up = cfg.fork.package;

  appOptions = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install this application.";
    };
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Its packages (system-wide, like omarchy's).";
    };
    autostart = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "syncthing serve --no-browser";
      description = "A command started with the session (`o.launch_on_start` in the HM autostart.lua).";
    };
  };
  appType = lib.types.submodule { options = appOptions; };

  # Upstream's base applications (install/omarchy-base.packages), by name.
  base = with pkgs; {
    nautilus = [ nautilus nautilus-python sushi ];
    evince = [ evince ];
    imv = [ imv ];
    mpv = [ mpv ];
    libreoffice = [ libreoffice ];
    pinta = [ pinta ];
    gnome-disk-utility = [ gnome-disk-utility ];
    moonlight = [ moonlight-qt ];
    localsend = [ localsend ];
    docker = [ docker-buildx docker-compose ];
    herdr = [ herdr ];
    udiskie = [ udiskie ];
    cliamp = [ cliamp ];
    disktree = [ disktree ];
    lazygit = [ lazygit ];
    btop = [ btop ];
    # omarchy's own (pkgs/by-name)
    omacalc = [ omacalc ];
    omacut = [ omacut ];
    omawrite = [ omawrite ];
    omasnap = [ omasnap ];
    owe = [ owe owe-lockfeed ];
    gliff = [ gliff ];
    hype = [ hype ];
    monologue = [ monologue ];
    signed = [ signed ];
    aether = [ aether ];
    ttfx = [ ttfx ];
    try = [ try-tobi ];
    asdcontrol = [ asdcontrol ];
  };
  # Unfree upstream apps are off by default; enabling one allows its default
  # packages (loom.nixpkgs.allowUnfree).
  unfree = with pkgs; { obsidian = [ obsidian ]; };

  enabled = lib.filterAttrs (n: a: n != "webapps" && n != "tuis" && a.enable) acfg;
  appPackages = lib.concatLists (lib.mapAttrsToList (_: a: a.packages) enabled);
  autostarts = lib.filter (c: c != null) (lib.mapAttrsToList (_: a: a.autostart) enabled);

  autostartLua = homeLib.withOverlay
    (homeLib.banner "--" "omanix.apps (modules/omanix/apps/default.nix)"
      + "-- Upstream's own session start (default/hypr/autostart.lua) runs before this.\n"
      + lib.concatMapStrings (c: "o.launch_on_start(${lua.quote c})\n") autostarts
      + cfg.hyprland.fileLua.autostart)
    (homeLib.include.lua "autostart");

  # Desktop entries for web apps and TUIs, in the system profile.
  desktopEntry = name: fields: ''
    [Desktop Entry]
    Version=1.0
    Name=${name}
    Comment=${name}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}=${v}") fields)}
    Terminal=false
    Type=Application
    StartupNotify=true
  '';
  webappEntries = lib.mapAttrs (name: w: desktopEntry name ({
    Exec = if w.exec != null then w.exec else "omarchy-launch-webapp ${w.url}";
    Icon = w.icon;
  } // lib.optionalAttrs (w.mimeTypes != [ ]) { MimeType = lib.concatStringsSep ";" w.mimeTypes; }))
    (lib.filterAttrs (_: w: w.enable) acfg.webapps);
  tuiEntries = lib.mapAttrs (name: t: desktopEntry name {
    Exec = "xdg-terminal-exec --app-id=TUI.${t.style} -e ${t.command}";
    Icon = t.icon;
  }) acfg.tuis;
  entries = pkgs.runCommand "omanix-desktop-entries" { } ''
    mkdir -p $out/share/applications $out/share/icons/hicolor/256x256/apps
    ${lib.concatStrings (lib.mapAttrsToList (n: t: ''
      cp ${pkgs.writeText "entry.desktop" t} "$out/share/applications/${n}.desktop"
    '') (webappEntries // tuiEntries))}
    # upstream's icons (applications/icons), by their file names
    for f in ${up}/applications/icons/*.png; do
      b=$(basename "$f" .png)
      cp "$f" "$out/share/icons/hicolor/256x256/apps/$(echo "$b" | tr 'A-Z ' 'a-z-').png"
    done
    # upstream's own entries (browser hand-off, foot, imv, mpv) …
    for f in omarchy-browser foot imv mpv; do
      cp ${up}/applications/$f.desktop $out/share/applications/
    done
    # … and the chromium.desktop id omarchy's launchers look for (nixpkgs
    # names it chromium-browser.desktop).
    ${lib.optionalString acfg.chromium.enable ''
      cp ${acfg.chromium.package}/share/applications/chromium-browser.desktop $out/share/applications/chromium.desktop
    ''}
  '';

  webappType = lib.types.submodule {
    options = {
      enable = lib.mkOption { type = lib.types.bool; default = true; description = "Install this web app."; };
      url = lib.mkOption { type = lib.types.str; example = "https://app.hey.com"; description = "The URL it opens."; };
      icon = lib.mkOption { type = lib.types.str; default = "applications-internet"; example = "hey"; description = "Icon name."; };
      exec = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; example = "omarchy-webapp-handler-hey %u"; description = "A custom command instead of `omarchy-launch-webapp <url>`."; };
      mimeTypes = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; example = [ "x-scheme-handler/mailto" ]; description = "MIME types and URL schemes it handles."; };
      bind = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; example = "SUPER + SHIFT + E"; description = "A keybinding that opens it (omanix.keybinds)."; };
    };
  };
  tuiType = lib.types.submodule {
    options = {
      command = lib.mkOption { type = lib.types.str; example = "lazydocker"; description = "The command run in the terminal."; };
      style = lib.mkOption { type = lib.types.enum [ "float" "tile" ]; default = "float"; description = "Floating or tiled window (app id TUI.<style>)."; };
      icon = lib.mkOption { type = lib.types.str; default = "utilities-terminal"; example = "docker"; description = "Icon name."; };
      bind = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; example = "SUPER + SHIFT + D"; description = "A keybinding that opens it (omanix.keybinds)."; };
    };
  };

  # Upstream's applications/*.desktop web apps (the ones refresh-applications installed).
  upstreamWebapps = {
    Basecamp = { url = "https://launchpad.37signals.com"; icon = "basecamp"; };
    Discord = { url = "https://discord.com/channels/@me"; icon = "omarchy-discord"; };
    "Google Contacts" = { url = "https://contacts.google.com/"; icon = "google-contacts"; };
    "Google Maps" = { url = "https://maps.google.com"; icon = "google-maps"; };
    "Google Messages" = { url = "https://messages.google.com/web/conversations"; icon = "google-messages"; };
    "Google Photos" = { url = "https://photos.google.com/"; icon = "google-photos"; };
    HEY = { url = "https://app.hey.com"; icon = "hey"; exec = "omarchy-webapp-handler-hey %u"; mimeTypes = [ "x-scheme-handler/mailto" ]; };
    WhatsApp = { url = "https://web.whatsapp.com/"; icon = "whatsapp"; };
    X = { url = "https://x.com/"; icon = "x"; };
    YouTube = { url = "https://youtube.com/"; icon = "youtube"; };
    Zoom = { url = "https://app.zoom.us/wc/home"; icon = "zoom"; exec = "omarchy-webapp-handler-zoom %u"; mimeTypes = [ "x-scheme-handler/zoommtg" "x-scheme-handler/zoomus" ]; };
  };

  binds = lib.mapAttrs' (n: w: lib.nameValuePair "webapp-${n}" { keys = w.bind; description = n; action.webapp = w.url; })
      (lib.filterAttrs (_: w: w.enable && w.bind != null) acfg.webapps)
    // lib.mapAttrs' (n: t: lib.nameValuePair "tui-${n}" { keys = t.bind; description = n; action.tui = t.command; })
      (lib.filterAttrs (_: t: t.bind != null) acfg.tuis);
in
{
  imports = [ ./chromium.nix ];

  options.omanix.apps = lib.mkOption {
    type = lib.types.submodule {
      freeformType = lib.types.lazyAttrsOf appType;
      options = {
        # apps/chromium.nix writes the flags file these feed; the options sit
        # here because omanix.apps is one submodule (checks.layout).
        chromium = lib.mkOption {
          type = lib.types.submodule {
            options = appOptions // {
              package = lib.mkOption {
                type = lib.types.package;
                default = pkgs.omanix-chromium;
                defaultText = lib.literalExpression "pkgs.omanix-chromium (pkgs.chromium wrapped to read ~/.config/chromium-flags.conf and its overlay)";
                example = lib.literalExpression "pkgs.chromium.override { enableWideVine = true; }";
                apply = p: if p ? unwrapped then p else pkgs.omanix-chromium.override { chromium = p; };
                description = "The Chromium the app list installs (and omanix.defaults.browser uses); any package given here is wrapped to read the flags files.";
              };
              features = lib.mkOption {
                type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9]+");
                default = [ ];
                example = [ "WebUIDarkMode" ];
                description = "Chromium features to enable, added to upstream's `--enable-features` in ~/.config/chromium-flags.conf (what omarchy-chromium-add-feature does at runtime, in the overlay).";
              };
            };
          };
          default = { };
          description = "Chromium, omarchy's browser and web-app runtime.";
        };
        webapps = lib.mkOption {
          type = lib.types.attrsOf webappType;
          default = { };
          example = { Linear = { url = "https://linear.app"; icon = "linear"; bind = "SUPER + SHIFT + L"; }; };
          description = "Web apps (Chromium app windows) with desktop entries; upstream's set is on by default.";
        };
        tuis = lib.mkOption {
          type = lib.types.attrsOf tuiType;
          default = { };
          example = { Docker = { command = "lazydocker"; bind = "SUPER + SHIFT + D"; }; };
          description = "Terminal apps with desktop entries (app id TUI.float or TUI.tile).";
        };
      };
    };
    default = { };
    example = lib.literalExpression ''{ libreoffice.enable = false; syncthing = { packages = [ pkgs.syncthing ]; autostart = "syncthing serve --no-browser"; }; }'';
    description = ''
      Applications by name: `{ enable; packages; autostart; }`. Upstream's base
      set (nautilus, evince, imv, mpv, libreoffice, pinta, localsend, docker,
      herdr, udiskie, omarchy's own apps, …) is on by default; obsidian is
      unfree and off (enabling it adds it to loom.nixpkgs.allowUnfree). Add
      your own with `packages` (and `autostart`).
    '';
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      omanix.apps = lib.mapAttrs (_: ps: { packages = lib.mkDefault ps; }) base
        // lib.mapAttrs (_: ps: { enable = lib.mkDefault false; packages = lib.mkDefault ps; }) unfree
        // {
          chromium.packages = lib.mkDefault [ acfg.chromium.package ];
          webapps = lib.mapAttrs (_: w: lib.mapAttrs (_: lib.mkDefault) w) upstreamWebapps;
        };

      environment.systemPackages = appPackages ++ [ entries ];
      loom.nixpkgs.allowUnfree = lib.concatLists (lib.mapAttrsToList
        (n: ps: lib.optionals (acfg.${n}.enable or false) (map lib.getName ps)) unfree);
      omanix.keybinds.binds = binds;

      home-manager.users.${user} = lib.mkIf cfg.home.enable {
        xdg.configFile."hypr/autostart.lua".text = autostartLua;
      };
      omanix.home.files.".config/hypr/autostart.lua" = { module = "apps/default.nix"; overlay = "hypr/autostart.lua"; };
    }
    # Services behind the apps.
    (lib.mkIf (acfg.nautilus.enable or false) {
      services.gvfs.enable = lib.mkDefault true;
      services.gnome.sushi.enable = lib.mkDefault true;
    })
    (lib.mkIf (acfg.udiskie.enable or false) { services.udisks2.enable = lib.mkDefault true; })
    # LocalSend: upstream opens 53317 tcp/udp in ufw.
    (lib.mkIf (acfg.localsend.enable or false) { programs.localsend = { enable = lib.mkDefault true; openFirewall = lib.mkDefault true; }; })
    # Docker: the daemon (socket-activated) without the docker group (upstream:
    # group membership is root); the CLI goes through sudo.
    (lib.mkIf (acfg.docker.enable or false) {
      virtualisation.docker.enable = lib.mkDefault true;
      virtualisation.docker.enableOnBoot = lib.mkDefault false;
      loom.persist.system.directories = [ { directory = "/var/lib/docker"; mode = "0710"; } ];   # images, volumes
    })
  ]);
}
