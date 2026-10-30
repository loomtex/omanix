# omanix.catalog: /run/current-system/sw/share/omanix/catalog (§h.9), built
# from the same evaluation as the toplevel: option catalogs (shared per
# release, plus this host's plugin and host-module options), the effective
# config, host/home/keybind/menu/theme/app/persist/secret/service/unlock/
# command registries, the `omanix try` allowlist and host.md. index.json
# lists every file with its sha256. checks.catalogs and checks.catalog-size
# (U20) build and validate it.
{ config, options, lib, pkgs, ... }@args:

let
  cfg = config.omanix;
  user = config.loom.user.name;
  hm = config.home-manager.users.${user} or null;
  loomFlake = args.loom or null;
  hostInputs = args.inputs or { };
  noCtx = s: builtins.unsafeDiscardStringContext (toString s);

  # ---- origins ------------------------------------------------------------
  hostSrc = noCtx (config.loom.host.src or "");
  prefixes =
    [ { p = noCtx pkgs.path; o = "nixpkgs"; } ]
    ++ lib.optionals (loomFlake != null) (
      [ { p = noCtx loomFlake.outPath; o = "loom"; } ]
      ++ lib.mapAttrsToList (n: i: { p = noCtx i.outPath; o = n; })
        (lib.filterAttrs (n: i: i ? outPath && n != "self" && n != "nixpkgs") (loomFlake.inputs or { })))
    ++ lib.mapAttrsToList (n: i: { p = noCtx i.outPath; o = if n == "omanix" then "omanix" else "input:${n}"; })
      (lib.filterAttrs (n: i: i ? outPath && n != "self" && n != "nixpkgs" && n != "home-manager") hostInputs);
  originOf = file:
    let
      f = noCtx file;
      hit = lib.findFirst (x: x.p != "" && lib.hasPrefix (x.p + "/") f) null prefixes;
    in
    if hostSrc != "" && lib.hasPrefix (hostSrc + "/") f then { origin = "host:${lib.removePrefix (hostSrc + "/") f}"; rel = lib.removePrefix (hostSrc + "/") f; }
    else if lib.hasInfix "/modules/omanix/" f then { origin = "omanix"; rel = "modules/omanix/" + lib.last (lib.splitString "/modules/omanix/" f); }
    else if hit != null then { origin = hit.o; rel = lib.removePrefix (hit.p + "/") f; }
    else if lib.hasInfix "-source/nixos/modules/" f || lib.hasSuffix "-source/lib/modules.nix" f || f == "lib/modules.nix" then { origin = "nixpkgs"; rel = "nixos/modules/" + lib.last (lib.splitString "/nixos/modules/" f); }
    else { origin = "unknown"; rel = baseNameOf f; };
  shared = [ "nixpkgs" "loom" "omanix" "nuketown" "home-manager" "sops-nix" "impermanence" "disko" "lanzaboote" ];

  transform = opt:
    let decl = map originOf opt.declarations; in
    opt // {
      declarations = map (d: d.rel) decl;
      # options without a declaration (freeform and submodule children) take
      # their root's origin
      origin = if decl != [ ] then (builtins.head decl).origin
        else let r = builtins.head (lib.splitString "." opt.name); in
          if builtins.elem r [ "omanix" "loom" "nuketown" ] then r else "nixpkgs";
    };
  # nixosOptionsDoc's own list (lib.optionAttrSetToDocList), written as its
  # JSON, except that a default or example that fails to render (an unfree
  # package the host doesn't allow, say) becomes "<not rendered>" instead of
  # failing the host's build.
  safe = v: let r = builtins.tryEval (builtins.deepSeq v v); in if r.success then r.value else { _type = "literalExpression"; text = "<not rendered>"; };
  doc = opts:
    let
      entries = lib.filter (o: o.visible && !o.internal) (lib.optionAttrSetToDocList opts);
      entry = o: let t = transform o; in {
        name = t.name;
        value = removeAttrs t [ "name" "visible" "internal" "loc" "relatedPackages" ]
          // lib.optionalAttrs (t ? default) { default = safe t.default; }
          // lib.optionalAttrs (t ? example) { example = safe t.example; }
          // { description = let d = t.description or ""; in if builtins.isAttrs d then d.text or "" else if d == null then "" else d; };
      };
    in
    pkgs.writeText "options.json" (builtins.unsafeDiscardStringContext (builtins.toJSON (lib.listToAttrs (map entry entries))));

  nixosOptions = options // { home-manager = removeAttrs options.home-manager [ "users" ]; };
  # The human's own HM options (defaults render against a real home.stateVersion).
  homeOptions = removeAttrs
    (options.home-manager.users.valueMeta.attrs.${user}.configuration.options or (options.home-manager.users.type.getSubOptions [ ]))
    [ "_module" ];

  # ---- effective config ------------------------------------------------------
  san = depth: v:
    let r = builtins.tryEval (
      if lib.isDerivation v then "<derivation ${v.name or "?"}>"
      else if builtins.isFunction v then "<function>"
      else if builtins.isPath v then noCtx v
      else if builtins.isString v then builtins.unsafeDiscardStringContext v
      else if builtins.isList v then (if depth <= 0 then "<list>" else map (san (depth - 1)) v)
      else if builtins.isAttrs v then (if depth <= 0 then "<attrs>" else lib.mapAttrs (_: san (depth - 1)) (removeAttrs v [ "_module" ]))
      else v);
    in if r.success then r.value else "<error>";
  configJson = {
    loom = san 8 (removeAttrs config.loom [ "keys" "host" "secrets" ]) // {
      secrets = san 3 (removeAttrs config.loom.secrets [ "directory" ]) // { directory = "<host repo>/secrets"; };
      keys = san 3 (removeAttrs config.loom.keys [ "generated" ]);
      host = san 3 (removeAttrs config.loom.host [ "src" ]);   # the source's store path changes every commit
    };
    omanix = san 8 (removeAttrs cfg [ "home" "catalog" "cli" ]) // {
      # what the fork's readers expect (P6, W3/W17): the resident's name
      defaults = san 2 cfg.defaults // { agent = if config.loom.agent.enable or false then config.loom.agent.name else null; };
      home = { inherit (cfg.home) enable overlays appOwned; };
    };
    # derived, not options
    releaseChannel = "stable";
  };

  # ---- home.json: every HM-owned target --------------------------------------
  # the options that generate each owning module's files
  moduleOptions = {
    "hyprland/default.nix" = [ "omanix.hyprland.settings" "omanix.hyprland.windowRules" "omanix.hyprland.extraLua" "omanix.hyprland.fileLua" ];
    "hyprland/monitors.nix" = [ "omanix.hyprland.monitors" "omanix.hyprland.gdkScale" ];
    "input.nix" = [ "omanix.input" ];
    "keybinds.nix" = [ "omanix.keybinds" ];
    "apps/default.nix" = [ "omanix.apps" ];
    "home/terminals.nix" = [ "omanix.fonts.monospace" ];
    "fonts.nix" = [ "omanix.fonts.monospace" ];
    "home/desktop.nix" = [ "loom.user.fullName" "loom.user.email" ];
    "defaults.nix" = [ "omanix.defaults" ];
    "menu.nix" = [ "omanix.menu.items" ];
  };
  includeOf = t: overlay:
    if overlay == null then null
    else if lib.hasSuffix ".lua" t then "require(\"default.hypr.omanix-overlay\")"
    else if lib.hasPrefix ".config/alacritty" t then "general.import (last)"
    else if lib.hasPrefix ".config/kitty" t || lib.hasPrefix ".config/foot" t then "include"
    else if lib.hasPrefix ".config/ghostty" t then "config-file"
    else if lib.hasPrefix ".config/fontconfig" t then "<include>"
    else if lib.hasPrefix ".config/gtk-4.0" t then "@import"
    else if t == ".bashrc" then "source"
    else if t == ".XCompose" then "include"
    else if lib.hasSuffix ".conf" t then "source / read after"
    else "last directive";
  homeJson = lib.mapAttrs (t: f: {
    inherit (f) module overlay;
    options = moduleOptions.${f.module} or [ ];
    include = includeOf t f.overlay;
    source = if hm != null then "${noCtx hm.home-files}/${t}" else null;
  }) cfg.home.files;

  # files a host takes over with lib.mkForce on .source (§c)
  hopts = if hm != null then options.home-manager.users.valueMeta.attrs.${user}.configuration.options or null else null;
  fileOpt = t:
    if hopts == null then null
    else if lib.hasPrefix ".config/" t then hopts.xdg.configFile.valueMeta.attrs.${lib.removePrefix ".config/" t}.configuration.options or null
    else hopts.home.file.valueMeta.attrs.${t}.configuration.options or null;
  overridden = lib.concatLists (lib.mapAttrsToList (t: _:
    let o = fileOpt t; in
    if o == null then [ ]
    else map (d: { target = t; file = (originOf d.file).rel; })
      (lib.filter (d: lib.hasPrefix "host:" (originOf d.file).origin) (o.source.definitionsWithLocations or [ ])))
    cfg.home.files);

  # ---- host.json ---------------------------------------------------------------
  # Plugins and their locked revisions come from the flake's inputs (what
  # flake.lock resolved), not from the source path, so the catalog changes
  # only when they do.
  pluginInputs = lib.filterAttrs (n: i: !(builtins.elem n [ "self" "omanix" "nixpkgs" "home-manager" ]) && i ? outPath) hostInputs;
  plugins = lib.mapAttrsToList (n: i: { input = n; rev = i.rev or null; narHash = i.narHash or null; url = null; }) pluginInputs;
  hostFiles = dir: rel:
    if hostSrc == "" || !builtins.pathExists dir then [ ]
    else lib.concatLists (lib.mapAttrsToList (n: t:
      if t == "directory" && n != ".git" then hostFiles "${dir}/${n}" "${rel}${n}/"
      else lib.optional (t == "regular" && lib.hasSuffix ".nix" n) "${rel}${n}") (builtins.readDir dir));
  pathOf = e: if builtins.isString e then e else e.directory or e.file or "?";
  persistDefs = options.loom.persist.system.directories.definitionsWithLocations or [ ];
  hostJson = {
    name = config.networking.hostName;
    id = config.loom.host.id or null;
    inherit plugins;
    lockRevs = lib.mapAttrs (_: i: i.rev or i.narHash or null) (lib.filterAttrs (n: i: n != "self" && i ? outPath) hostInputs);
    moduleFiles = hostFiles hostSrc "";
    overriddenHomeFiles = overridden;
    persistAdditions = lib.concatMap (d: map pathOf (lib.toList d.value))
      (lib.filter (d: lib.hasPrefix "host:" (originOf d.file).origin) persistDefs);
  };

  # ---- small registries --------------------------------------------------------
  appNames = lib.filterAttrs (n: a: builtins.isAttrs a && a ? enable && !(builtins.elem n [ "webapps" "tuis" ])) cfg.apps;
  appsJson = {
    apps = lib.mapAttrs (_: a: { enable = a.enable; packages = map lib.getName (a.packages or [ ]); autostart = a.autostart or null; }) appNames;
    webapps = lib.mapAttrs (_: w: { inherit (w) url enable; }) cfg.apps.webapps;
    tuis = lib.mapAttrs (_: t: { inherit (t) command; }) cfg.apps.tuis;
  };
  persistJson = {
    root = config.loom.persist.root;
    system = {
      directories = map pathOf config.loom.persist.system.directories;
      files = map pathOf config.loom.persist.system.files;
    };
    ephemeralOk = config.loom.persist.ephemeralOk;
    home = "all of /home is a persisted subvolume (§f.1)";
  };
  secretsJson = {
    names = builtins.attrNames (config.sops.secrets or { });
    files = let d = hostSrc + "/secrets"; in
      if hostSrc != "" && builtins.pathExists d then builtins.attrNames (lib.filterAttrs (n: _: lib.hasSuffix ".yaml" n) (builtins.readDir d)) else [ ];
    set = "omanix secret set <host|user|data|agents> <name>   (the human's terminal; encrypt-only)";
  };
  servicesJson = {
    system = lib.mapAttrs (_: s: { description = s.description or ""; }) (lib.filterAttrs (_: s: s.enable or true) config.systemd.services);
  };
  unlockJson = {
    methods = config.loom.disk.unlock.methods or [ ];
    automatic = config.loom.disk.unlock.automatic or false;
    text = if loomFlake != null && loomFlake ? lib.unlockText then loomFlake.lib.unlockText else null;
  };
  enumValues = o: (builtins.tryEval (o.type.functor.payload.values or o.type.functor.payload or [ ])).value or [ ];
  hostgenJson = {
    defaults = lib.mapAttrs (_: o: enumValues o)
      (lib.filterAttrs (n: o: lib.isOption o && builtins.elem n [ "terminal" "browser" "editor" "dictation" ]) options.omanix.defaults);
    apps = builtins.attrNames appNames;
  };

  # `omanix try`: the typed allowlist (§h.6). Hyprland scalars with ranges;
  # theme, background and monospace font are checked against the registry
  # by the human-session helper.
  hypr = key: type: extra: { "omanix.hyprland.settings.${lib.concatStringsSep "." key}" = { kind = "hypr"; inherit key type; } // extra; };
  previewJson = {
    schema = "omanix.preview/v1";
    keys = hypr [ "general" "gaps_in" ] "int" { min = 0; max = 100; }
      // hypr [ "general" "gaps_out" ] "int" { min = 0; max = 200; }
      // hypr [ "general" "border_size" ] "int" { min = 0; max = 20; }
      // hypr [ "decoration" "rounding" ] "int" { min = 0; max = 50; }
      // hypr [ "decoration" "active_opacity" ] "float" { min = 0.1; max = 1.0; }
      // hypr [ "decoration" "inactive_opacity" ] "float" { min = 0.1; max = 1.0; }
      // hypr [ "decoration" "blur" "enabled" ] "bool" { }
      // hypr [ "decoration" "shadow" "enabled" ] "bool" { }
      // hypr [ "animations" "enabled" ] "bool" { }
      // hypr [ "dwindle" "preserve_split" ] "bool" { }
      // hypr [ "general" "layout" ] "enum" { values = [ "dwindle" "master" ]; }
      // {
        "omanix.theme.default" = { kind = "theme"; type = "registry"; };
        "omanix.theme.background" = { kind = "background"; type = "file"; };
        "omanix.fonts.monospace" = { kind = "font"; type = "registry"; };
      };
  };

  loomCommands = map (c: { command = "loom ${c.c}"; description = c.d; }) [
    { c = "propose"; d = "Build a commit of the host repo and ask to switch to it (a card)."; }
    { c = "card show"; d = "Show a switch record's card as text."; }
    { c = "undo"; d = "Undo the last switch (a revert, approved on a card)."; }
    { c = "rollback --to <n>"; d = "Roll back to an earlier switch (a card)."; }
    { c = "keys {list,sync,add-human,remove-human,rotate}"; d = "Keys of this host repo (human-only where a secret is shown)."; }
    { c = "unlock {status,add,remove,reseal}"; d = "Disk unlock methods (human-only)."; }
    { c = "user passwd"; d = "Change the login password (human-only)."; }
    { c = "hw regen"; d = "Regenerate hardware.{nix,json} in the working copy."; }
  ];

  spec = {
    optionsNixos = doc nixosOptions;
    optionsHome = doc homeOptions;
    sharedOrigins = shared;
    config = configJson;
    host = hostJson;
    home = homeJson;
    omarchy = cfg.fork.data;
    hmBindings = if hm != null && cfg.home.enable then "${hm.home-files}/.config/hypr/bindings.lua" else null;
    apps = appsJson;
    persist = persistJson;
    secrets = secretsJson;
    services = servicesJson;
    unlock = unlockJson;
    preview = previewJson;
    hostgen = hostgenJson;
    themeDefault = (cfg.theme or { }).default or null;
    themeLock = (cfg.theme or { }).lock or false;
    themeBoot = ((cfg.theme or { }).boot or { }).theme or null;
    extraThemes = builtins.attrNames ((cfg.theme or { }).extra or { });
    trustedThemes = builtins.attrNames (lib.filterAttrs (_: e: e.trusted or false) ((cfg.theme or { }).extra or { }));
    commands = "/etc/omanix/commands.json";
    inherit loomCommands;
  };

  catalog = pkgs.runCommand "omanix-catalog-${config.networking.hostName}"
    {
      nativeBuildInputs = [ pkgs.omanix-catalog ];
      passAsFile = [ "spec" "commands" ];
      spec = builtins.toJSON (spec // { commands = "@commands@"; });
      commands = builtins.toJSON cfg.cli.registry;
    }
    ''
      substitute "$specPath" spec.json --replace-fail '"@commands@"' "\"$commandsPath\""
      omanix-catalog assemble spec.json $out/share/omanix/catalog
      omanix-catalog validate $out/share/omanix/catalog
    '';
in
{
  options.omanix.catalog = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      defaultText = lib.literalExpression "config.omanix.enable";
      description = "Build the catalogs into the system (`/run/current-system/sw/share/omanix/catalog`).";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = catalog;
      defaultText = lib.literalExpression "the catalogs of this host";
      description = "The catalog directory's package (`share/omanix/catalog`).";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.catalog.enable) {
    # U40: the catalogs render every option's default, and nuketown's name
    # pkgs.unstable; loom adds this alias only on hosts with an agent.
    nixpkgs.overlays = [ (final: prev: { unstable = prev.unstable or final; }) ];

    # The catalog belongs to the generation: $out/catalog in the toplevel.
    # sw/share/omanix/catalog (next to home/default.nix's packages.txt) is a
    # fixed link to the running one, so a new catalog (every commit changes
    # config.json) rebuilds only the toplevel, not system-path and what
    # hangs off it (dbus, units, user environments).
    system.systemBuilderCommands = ''
      ln -s ${cfg.catalog.package}/share/omanix/catalog $out/catalog
    '';
    environment.extraSetup = ''
      mkdir -p $out/share/omanix
      ln -s /run/current-system/catalog $out/share/omanix/catalog
    '';
  };
}
