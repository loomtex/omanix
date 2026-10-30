# W16's checks: themes, boot visuals, browser policy (§f.5, §i).
{ pkgs, self, inputs }:

let
  inherit (pkgs) lib;
  loom = inputs.loom;
  c = self.lib.checks;
  template = loom.outPath + "/templates/host";
  host = self.nixosConfigurations.ref-default;
  cfg = host.config;
  data = cfg.omanix.fork.data;
  registry = cfg.omanix.theme.package;
  themeLib = import ../lib/theme.nix { inherit lib; };

  refWith = extra: self.lib.mkHost {
    self = template;
    modules = [ (template + "/configuration.nix") ../hosts/eval-stub.nix ] ++ extra;
  };
  failedAssertions = h: map (a: a.message) (lib.filter (a: !a.assertion) h.config.assertions);

  # The three themes with golden boot visuals: the default, a second dark
  # one, and a light one.
  goldenThemes = [ "tokyo-night" "kanagawa" "catppuccin-latte" ];

  # Every key a theme must resolve to (omarchy-theme-color --all), and the
  # ones that must be #rrggbb.
  canonical = [
    "accent" "background" "foreground" "selection" "muted"
    "dark_background" "darker_background" "lighter_background"
    "dark_foreground" "light_foreground" "bright_foreground"
    "red" "yellow" "orange" "green" "cyan" "blue" "magenta" "brown"
    "bright_red" "bright_yellow" "bright_green" "bright_cyan" "bright_blue" "bright_magenta"
    "cursor" "selection_background" "selection_foreground" "mode"
  ] ++ map (i: "color${toString i}") (lib.range 0 15);

  vm = file: import file { inherit pkgs loom; omanix = self; };
in
{
  # The upstream renderer (omarchy-theme-set-templates, the only upstream code
  # a check runs, in the sandbox with no network) over every theme in the
  # registry: every template renders with no {{ left, and every canonical
  # key resolves. U23: no upstream wallpaper is in the registry; every theme
  # has a background and the omanix unlock wordmark.
  themes-render = pkgs.runCommand "omanix-check-themes-render"
    { nativeBuildInputs = with pkgs; [ bash coreutils gawk gnused gnugrep findutils ]; }
    ''
      export OMARCHY_PATH=${data} PATH=${data}/bin:$PATH
      fail=0
      err() { echo "FAIL: $*"; fail=1; }
      n=0
      for t in $(ls ${data}/themes); do
        n=$((n + 1))
        export HOME=$TMPDIR/home-$t
        next=$HOME/.local/state/omarchy/current/next-theme
        mkdir -p "$next"
        cp -r --no-preserve=mode ${data}/themes/$t/* "$next/"
        omarchy-theme-set-templates 2> "$TMPDIR/$t.err" || err "$t: the renderer failed: $(cat $TMPDIR/$t.err)"
        if grep -q . "$TMPDIR/$t.err"; then err "$t: the renderer complained: $(cat $TMPDIR/$t.err)"; fi
        for tpl in ${data}/default/themed/*.tpl; do
          f=$next/$(basename "$tpl" .tpl)
          [ -f "$f" ] || { err "$t: $(basename "$f") was not rendered"; continue; }
          if grep -n '{{' "$f" > "$TMPDIR/left"; then err "$t: $(basename "$f") keeps a placeholder: $(head -3 $TMPDIR/left)"; fi
        done
        omarchy-theme-color --file "$next/colors.toml" --all > "$TMPDIR/$t.tsv"
        for k in ${lib.concatStringsSep " " canonical}; do
          v=$(awk -F'\t' -v k="$k" '$1 == k { print $2 }' "$TMPDIR/$t.tsv")
          [ -n "$v" ] || { err "$t: $k does not resolve"; continue; }
          case $k in
            mode) [ "$v" = dark ] || [ "$v" = light ] || err "$t: mode is $v" ;;
            *) echo "$v" | grep -Eq '^#[0-9A-Fa-f]{6}$' || err "$t: $k is $v, not #rrggbb" ;;
          esac
        done
        # U23 and branding: only nix-drawn or extra-theme media
        for b in ${data}/themes/$t/backgrounds/*; do
          case $(readlink -f "$b") in
            ${registry}/$t/backgrounds/0-omanix.png) ;;
            *) case $(readlink -f "$b") in */omarchy-src-*) err "$t: upstream background $(basename "$b") is in the registry (U23)";; esac ;;
          esac
        done
        [ -e ${data}/themes/$t/backgrounds ] || err "$t: no backgrounds/"
        [ -e ${data}/themes/$t/unlock.png ] || err "$t: no unlock.png"
      done
      [ "$n" -ge 23 ] || err "only $n themes in the registry"
      [ "$fail" = 0 ] || exit 1
      echo "themes-render: $n themes rendered"
      touch $out
    '';

  # An untrusted extra theme loses its code (Lua, terminal configs,
  # vscode.json, symlinks) but keeps its colors and gets a background and the
  # unlock wordmark; a name clash with an upstream theme is refused.
  theme-extra =
    let
      h = refWith [{ omanix.theme.extra.fixture.src = ../tests/fixtures/theme-untrusted; omanix.theme.default = "fixture"; }];
      errors = failedAssertions h
        ++ lib.optional (!(builtins.elem "fixture" h.config.omanix.theme.available)) "fixture not in omanix.theme.available";
      t = "${h.config.omanix.theme.package}/fixture";
    in
    pkgs.runCommand "omanix-check-theme-extra" { passAsFile = [ "errors" ]; errors = lib.concatStringsSep "\n" errors; } ''
      if [ -s "$errorsPath" ]; then cat "$errorsPath" >&2; exit 1; fi
      for f in hyprland.lua sub/gum_env.lua alacritty.toml vscode.json; do
        [ ! -e ${t}/$f ] || { echo "untrusted extra kept $f" >&2; exit 1; }
      done
      for f in colors.toml icons.theme backgrounds/0-omanix.png; do
        [ -e ${t}/$f ] || { echo "untrusted extra lost or lacks $f" >&2; exit 1; }
      done
      case $(readlink -f ${t}/unlock.png) in
        */share/omanix-plymouth/omanix/logo.png) ;;
        *) echo "unlock.png is $(readlink -f ${t}/unlock.png), not the omanix wordmark" >&2; exit 1 ;;
      esac
      touch $out
    '';
  theme-extra-refuses-clash = c.mkRefusal pkgs "theme-extra-clash"
    (failedAssertions (refWith [{ omanix.theme.extra.nord.src = "${inputs.omarchy}/themes/nord"; }]));

  # Limine's colors for the golden themes, against tests/golden/boot-visuals.
  boot-limine-golden = c.mkCheck pkgs "boot-limine-golden" (lib.concatMap (t:
    let
      got = builtins.toJSON (refWith [{ omanix.theme.boot.theme = t; }]).config.boot.loader.limine.style;
      want = lib.removeSuffix "\n" (builtins.readFile ../tests/golden/boot-visuals/${t}.limine.json);
    in
    lib.optional (got != want) "limine style for ${t} differs from tests/golden/boot-visuals/${t}.limine.json:\n${got}"
  ) goldenThemes);

  # The unlock screen (Plymouth's layout, drawn at build time by
  # omanix-plymouth) for the golden themes, against
  # tests/golden/boot-visuals/<theme>-unlock.png, byte for byte.
  boot-unlock-golden = pkgs.runCommand "omanix-check-boot-unlock-golden" { } (lib.concatMapStrings (t:
    let p = pkgs.omanix-plymouth.override { omanixTheme = t; }; in ''
      cmp ${p}/share/omanix-plymouth/omanix/preview-unlock.png ${../tests/golden/boot-visuals}/${t}-unlock.png \
        || { echo "${t}: the unlock screen differs from tests/golden/boot-visuals/${t}-unlock.png" >&2; exit 1; }
    '') goldenThemes + "touch $out\n");

  # TODO(W16, deferred): boot-visuals renders Plymouth (in a waiting systemd
  # initrd) and SDDM in VMs and compares screenshots. Plymouth starts and
  # takes the password request, but QEMU's screendump stays all black on
  # both virtio-gpu and std VGA, so it is not in the gate. Run it by hand:
  #   nix build --impure --expr '(import ./checks/theme.nix { … }).boot-visuals'
  # or re-enable it here once the screendump shows Plymouth.
  # boot-visuals = import ../tests/boot-visuals.nix { inherit pkgs loom goldenThemes; omanix = self; };

  # omarchy-theme-set at runtime: two switches, terminals retinted, the
  # browser policy color, no HM target changed; the lock at the next login.
  theme-switch = vm ../tests/theme-switch.nix;

  # KEEP-AS-GUI writers against the read-only HM files (cases in
  # tests/writers-respect-hm/*.py; W16: glass, chromium flags).
  writers-respect-hm = vm ../tests/writers-respect-hm.nix;
}
