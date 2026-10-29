# W15's checks: the desktop core (modules/omanix, lib, omanix-data,
# omanix-overlay). `nix flake check` is the gate (§i).
{ pkgs, self, inputs }:

let
  inherit (pkgs) lib python3;
  loom = inputs.loom;
  c = self.lib.checks;
  tools = ../fork/tools;

  host = self.nixosConfigurations.ref-default;
  cfg = host.config;
  user = cfg.loom.user.name;
  hm = cfg.home-manager.users.${user};
  data = cfg.omanix.fork.data;
  homeFiles = hm.home-files;
  template = loom.outPath + "/templates/host";

  # A reference host plus extra NixOS modules (for refusal fixtures).
  refWith = extra: self.lib.mkHost {
    self = template;
    modules = [ (template + "/configuration.nix") ../hosts/eval-stub.nix ] ++ extra;
  };
  failedAssertions = h: map (a: a.message) (lib.filter (a: !a.assertion) h.config.assertions);

  run = name: script: pkgs.runCommand "omanix-check-${name}" { nativeBuildInputs = [ python3 ]; } ''
    ${script}
    touch $out
  '';

  vm = greeter: import ../tests/desktop-boots.nix { inherit pkgs loom greeter; omanix = self; };

  # ---- home-owned (U31) -------------------------------------------------
  # For every omanix-owned target, a definition of its .text or .source
  # outside modules/omanix is a host taking the file over: allowed only as a
  # .source at lib.mkForce priority. HM itself wouldn't object (two .text
  # definitions concatenate; a lower-priority one silently loses).
  homeOwned = h:
    let
      hcfg = h.config;
      hopts = h.options.home-manager.users.valueMeta.attrs.${hcfg.loom.user.name}.configuration.options;
      fileOpts = target:
        if lib.hasPrefix ".config/" target
        then hopts.xdg.configFile.valueMeta.attrs.${lib.removePrefix ".config/" target}.configuration.options or null
        else hopts.home.file.valueMeta.attrs.${target}.configuration.options or null;
      # HM's own file-type module defines .source from .text; it isn't a taker.
      hmSrc = toString loom.inputs.home-manager.outPath;
      foreign = opt: lib.filter (d: let f = toString d.file; in !(lib.hasInfix "/modules/omanix/" f) && !(lib.hasPrefix hmSrc f)) opt.definitionsWithLocations;
      check = target: f:
        let o = fileOpts target; in
        if o == null then [ "${target}: owned by ${f.module} but not defined" ]
        else
          map (d: "${target}: .text set in ${toString d.file}; owned by omanix (${f.module}): set the option, or lib.mkForce the .source to take the file over") (foreign o.text)
          ++ lib.optionals (foreign o.source != [ ] && o.source.highestPrio > 50)
            (map (d: "${target}: .source set in ${toString d.file} without lib.mkForce; owned by omanix (${f.module})") (foreign o.source));
    in
    lib.concatLists (lib.mapAttrsToList check hcfg.omanix.home.files);

  takeoverText = refWith [{ home-manager.users.alice.xdg.configFile."hypr/monitors.lua".text = lib.mkAfter "-- mine"; }];
  takeoverForce = refWith [{ home-manager.users.alice.xdg.configFile."hypr/monitors.lua".source = lib.mkForce (pkgs.writeText "m.lua" "-- mine\n"); }];

  # ---- home-files-golden ------------------------------------------------
  # Every HM target with an overlay names it in its last directive; the
  # generated files equal the goldens in tests/golden/ref-default
  # (regenerate with tests/golden/update.sh, after reviewing the diff).
  withOverlay = lib.filterAttrs (_: f: f.overlay != null) cfg.omanix.home.files;
  lastDirectiveErrors = lib.concatLists (lib.mapAttrsToList (t: f:
    let
      text = builtins.readFile "${homeFiles}/${t}";
      all = lib.splitString "\n" text;
      # foot: the include is the last key of [main], not the file's last line
      main = if f.overlay == "foot.ini"
        then lib.take (lib.findFirst (i: i > 0 && lib.hasPrefix "[" (builtins.elemAt all i)) (builtins.length all) (lib.range 0 (builtins.length all - 1))) all
        else all;
      lines = lib.filter (l: builtins.match "[[:space:]]*" l == null) main;
      last = lib.last lines;
      ok = lib.hasInfix "omanix/overlay/${f.overlay}" last
        || lib.hasInfix ''omanix-overlay")("${lib.removeSuffix ".lua" (lib.removePrefix "hypr/" f.overlay)}")'' last;
    in
    lib.optional (!ok) "${t}: last directive is not its overlay (${f.overlay}): ${last}"
  ) withOverlay);
  goldenTargets = builtins.attrNames cfg.omanix.home.files;

  hmTargets = pkgs.writeText "hm-targets.json" (builtins.toJSON
    (lib.mapAttrsToList (_: f: f.target) hm.home.file));
in
{
  # The Hyprland/uwsm session with the Quickshell shell, autologin (U24) …
  desktop-boots = vm false;
  # … and through SDDM's Wayland greeter (U34).
  desktop-boots-greeter = vm true;

  # pytest runs in the build.
  omanix-overlay = pkgs.omanix-overlay;

  # The reference host evaluates with every assertion holding.
  eval-ref-default = c.mkCheck pkgs "eval-ref-default" (
    failedAssertions host
    ++ lib.optional (builtins.unsafeDiscardStringContext cfg.system.build.toplevel.drvPath == "") "no toplevel");

  # FILE PATH == OPTION PATH, mkDefault outside omanix.*, everything documented.
  layout = c.mkCheck pkgs "layout" (c.layout {
    inherit (host) options;
    prefix = "omanix";
    moduleDir = ../modules/omanix;
  });
  priorities = c.mkCheck pkgs "priorities" (c.priorities {
    inherit (host) options;
    modules = map
      (f: {
        file = "modules/omanix/${f}";
        module = if f == "default.nix" then import ../modules/omanix { omanix = self; } else import (../modules/omanix + "/${f}");
      })
      (c.nixFiles ../modules/omanix);
    args = { inherit (host) config options pkgs; inherit lib; inputs = { }; inherit loom; omanix = self; };
    ownPrefixes = [ "omanix" ];
    allowlist = self.lib.forceAllowlist;
  });
  documented = c.mkCheck pkgs "documented" (c.documented { inherit (host) options; prefix = "omanix"; });

  # Upstream's .jsonc files parse the same with lib.jsonc as with python.
  jsonc-equivalence = run "jsonc-equivalence" (lib.concatMapStrings
    (f: ''
      python3 -I ${tools}/jsonc.py ${data}/${f} ${pkgs.writeText "nix.json" (builtins.toJSON (self.lib.jsonc.readJSONC "${data}/${f}"))}
    '')
    [ "default/omarchy/omarchy-menu.jsonc" "config/omarchy/extensions/omarchy-menu.jsonc" "etc/fastfetch/config.jsonc" ]);

  # No chord is bound twice across the fork's defaults and the host's bindings.
  keybind-conflicts = run "keybind-conflicts" ''
    python3 -I ${tools}/keybinds.py ${data} ${homeFiles}/.config/hypr/bindings.lua
  '';

  # No shipped write site targets an HM-owned file (pending ones are listed
  # in fork/writers with the patch that fixes them).
  hm-owned-readonly = run "hm-owned-readonly" ''
    python3 -I ${tools}/writesites.py hm-owned ${data} ${hmTargets} ${../fork/writers}
  '';

  # Every KEEP-AS-GUI script that writes has a row in fork/writers.
  runtime-writers = run "runtime-writers" ''
    python3 -I ${tools}/writesites.py writers ${data} ${../fork/classify.toml} ${../fork/writers}
  '';

  home-owned = c.mkCheck pkgs "home-owned" (homeOwned host ++ homeOwned takeoverForce);
  home-owned-refuses-text = c.mkRefusal pkgs "home-owned-text" (homeOwned takeoverText);

  hm-unmanaged-paths = c.mkCheck pkgs "hm-unmanaged-paths" (
    map (t: "HM writes ~/${t}; ~/.ssh and ~/.gnupg are never HM-owned (§f.4.5)")
      (lib.filter (t: lib.hasPrefix ".ssh/" t || lib.hasPrefix ".gnupg/" t) (lib.mapAttrsToList (_: f: f.target) hm.home.file)));

  home-files-golden = pkgs.runCommand "omanix-check-home-files-golden"
    { passAsFile = [ "errors" ]; errors = lib.concatStringsSep "\n" lastDirectiveErrors; }
    ''
      if [ -s "$errorsPath" ]; then cat "$errorsPath" >&2; exit 1; fi
      mkdir got
      ${lib.concatMapStrings (t: ''
        f=${homeFiles}/${lib.escapeShellArg t}; g=got/${lib.escapeShellArg t}
        if [ -L "$f" ] && [ ! -e "$f" ]; then mkdir -p "$(dirname "$g")"; readlink "$f" > "$g.symlink"
        else install -Dm644 "$f" "$g"; fi
      '') goldenTargets}
      if ! diff -ru ${../tests/golden/ref-default} got; then
        echo "generated HM files differ from tests/golden/ref-default; review, then tests/golden/update.sh" >&2
        exit 1
      fi
      touch $out
    '';
}
