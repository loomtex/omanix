# W19's checks: the omanix CLI, catalogs, skills and the host template
# (§h.8–§h.10, §i). `nix flake check` is the gate.
{ pkgs, self, inputs }:

let
  inherit (pkgs) lib;
  loom = inputs.loom;
  c = self.lib.checks;
  hr = import ../tests/lib/host-repo.nix { inherit lib; omanix = self; };
  py = pkgs.python3.withPackages (ps: [ ps.tree-sitter ps.tree-sitter-grammars.tree-sitter-nix ]);

  ref = self.nixosConfigurations.ref-default;
  refCatalog = "${ref.config.omanix.catalog.package}/share/omanix/catalog";

  # The reference host plus the plugin fixture (U20: the catalogs with a plugin).
  pluginFlake = (import ../tests/fixtures/plugin/flake.nix).outputs { self = { }; nixpkgs = self.inputs.nixpkgs; };
  template = loom.outPath + "/templates/host";
  withPlugin = self.lib.mkHost {
    self = template;
    modules = [ (template + "/configuration.nix") ../hosts/eval-stub.nix pluginFlake.nixosModules.default
      { loom.persist.system.directories = [ "/var/lib/private/omanix-fixture" ]; } ];
    homeModules = [ (template + "/home.nix") pluginFlake.homeModules.default ];
  };
  pluginCatalog = "${withPlugin.config.omanix.catalog.package}/share/omanix/catalog";

  # The rendered omanix host (loom-hostgen over templates/host + sample
  # answers), committed as tests/golden/host-omanix and evaluated as is.
  golden = ../tests/golden/host-omanix;
  goldenHost = self.lib.mkHost {
    self = golden;
    modules = [ (golden + "/configuration.nix") ../tests/fixtures/cli-host/vm.nix ];
  };
  answers = builtins.fromJSON (builtins.readFile ../tests/fixtures/hostgen/answers-omanix.json);
  gcfg = goldenHost.config;
  hostLock = hr.lock { };
  lockNodes = prefix: lib.filter (n: n == prefix || lib.hasPrefix "${prefix}_" n || lib.hasPrefix "${prefix}-" n) (builtins.attrNames hostLock.nodes);

  skills = "${pkgs.omanix-skills}/share/omanix/skills";
  known = (builtins.fromTOML (builtins.readFile ../fork/intents.toml)).skills.known;
  shipped = builtins.attrNames (builtins.readDir ../pkgs/by-name/omanix-skills/skills);

  vm = variant: import ../tests/cli.nix { inherit pkgs variant loom; omanix = self; };
in
{
  # The CLI's pytest (editor, registry, contract validator) runs in the build.
  omanix-cli = pkgs.omanix-cli;

  # U19: `omanix set`'s editor round-trips through the module system. Each
  # case edits a fixture with the editor and evaluates the result with
  # lib.evalModules (nix-instantiate inside the build): the value equals the
  # JSON asked for, and every byte outside the edit is unchanged.
  set-roundtrip = pkgs.runCommand "omanix-check-set-roundtrip"
    { nativeBuildInputs = [ py pkgs.nix pkgs.nixfmt ]; }
    ''
      export TEST_ROOT=$PWD/nix; mkdir -p $TEST_ROOT
      export NIX_STORE_DIR=$TEST_ROOT/store NIX_STATE_DIR=$TEST_ROOT/var NIX_LOG_DIR=$TEST_ROOT/log NIX_CONF_DIR=$TEST_ROOT/etc
      export NIX_REMOTE= HOME=$TEST_ROOT
      nix-store --init
      PYTHONPATH=${../pkgs/by-name/omanix-cli} python3 ${../tests/set_roundtrip.py} ${pkgs.path}/lib
      touch $out
    '';

  # Every catalog file builds and validates; index.json is complete (U40:
  # nuketown's options render with loom's pkgs.unstable alias). Also with a
  # plugin: its service shows in services.json.
  catalogs = pkgs.runCommand "omanix-check-catalogs" { nativeBuildInputs = [ pkgs.omanix-catalog pkgs.jq ]; } ''
    omanix-catalog validate ${refCatalog}
    omanix-catalog validate ${pluginCatalog}
    jq -e '."omanix.defaults.terminal".origin == "omanix"' ${refCatalog}/options/nixos.json
    jq -e '[.[] | .origin] | index("loom") and index("nuketown") and index("nixpkgs")' ${refCatalog}/options/nixos.json
    jq -e '."home.packages".origin == "home-manager"' ${refCatalog}/options/home.json
    jq -e '.[".config/hypr/monitors.lua"].options | index("omanix.hyprland.monitors")' ${refCatalog}/home.json
    jq -e '.omanix.defaults.agent == "ada" and .releaseChannel == "stable"' ${refCatalog}/config.json
    jq -e '.system["omanix-fixture"]' ${pluginCatalog}/services.json
    jq -e '.commands | map(.command) | index("omanix set") and index("loom propose")' ${refCatalog}/commands.json
    jq -e '.keys["omanix.hyprland.settings.general.gaps_out"].type == "int"' ${refCatalog}/preview.json
    jq -e '.defaults.terminal | index("kitty")' ${refCatalog}/hostgen.json
    jq -e 'length > 100' ${refCatalog}/keybinds.json
    grep -q '^## Plugins' ${refCatalog}/host.md
    touch $out
  '';

  # U20: per-host files < 2 MB, shared option files < 15 MB.
  catalog-size = pkgs.runCommand "omanix-check-catalog-size" { nativeBuildInputs = [ pkgs.omanix-catalog ]; } ''
    omanix-catalog size ${refCatalog}
    omanix-catalog size ${pluginCatalog}
    touch $out
  '';

  # §h.10: no shipped skill or prompt tells the resident to use Arch tools or
  # to sed a dotfile; the skill set is exactly intents.toml's [skills].known
  # (what menu-intents accepts). A planted skill must fail the grep.
  skills-no-arch = pkgs.runCommand "omanix-check-skills-no-arch" { } ''
    pat='pacman|yay|omarchy-pkg|omarchy-refresh|sed -i ~/.config'
    if grep -rnE "$pat" ${skills} ${pkgs.omanix-skills}/share/omanix/prompt.md; then
      echo "a shipped skill names an Arch tool or seds a dotfile" >&2; exit 1
    fi
    mkdir planted && echo 'Run `sudo pacman -S steam`.' > planted/SKILL.md
    grep -rqE "$pat" planted || { echo "refusal fixture not caught" >&2; exit 1; }
    for f in ${skills}/*/SKILL.md; do
      head -n1 "$f" | grep -qx -- '---' || { echo "$f: no frontmatter" >&2; exit 1; }
      grep -q '^description: ..' "$f" || { echo "$f: no description" >&2; exit 1; }
    done
    ${lib.optionalString (lib.sort lib.lessThan known != lib.sort lib.lessThan shipped) ''
      echo "skills differ from intents.toml [skills].known: shipped ${toString shipped}; known ${toString known}" >&2; exit 1
    ''}
    touch $out
  '';

  # The omanix host template: loom-hostgen renders it from sample answers
  # byte for byte as tests/golden/host-omanix; that tree evaluates through
  # omanix.lib.mkHost with every answer in place and builds (IFD stays off:
  # nothing in omanix reads a build output at evaluation); its lock has
  # exactly one nixpkgs and one home-manager node (U29).
  host-template = pkgs.runCommand "omanix-check-host-template"
    {
      nativeBuildInputs = [ pkgs.python3 ];
      toplevel = gcfg.system.build.toplevel;
      passAsFile = [ "errors" ];
      errors = lib.concatStringsSep "\n" (
        lib.optional (gcfg.loom.user.name != answers.user.name) "loom.user.name"
        ++ lib.optional (gcfg.omanix.defaults.terminal != answers.defaults.terminal) "omanix.defaults.terminal"
        ++ lib.optional (gcfg.omanix.apps.localsend.enable != true) "omanix.apps.localsend.enable"
        ++ lib.optional (gcfg.loom.host.id != answers.host.id) "loom.host.id"
        ++ lib.optional (gcfg.loom.keys.generated.".authorized_keys" != builtins.readFile (golden + "/.authorized_keys")) ".authorized_keys"
        ++ lib.optional (gcfg.loom.keys.generated.CODEOWNERS != builtins.readFile (golden + "/CODEOWNERS")) "CODEOWNERS"
        ++ lib.optional (lockNodes "nixpkgs" != [ "nixpkgs" ]) "U29: nixpkgs lock nodes ${toString (lockNodes "nixpkgs")}"
        ++ lib.optional (lockNodes "home-manager" != [ "home-manager" ]) "U29: home-manager lock nodes ${toString (lockNodes "home-manager")}");
    }
    ''
      if [ -s "$errorsPath" ]; then echo "the rendered host disagrees:" >&2; cat "$errorsPath" >&2; exit 1; fi
      PYTHONPATH=${loom}/pkgs/loom-cli python3 -I -c 'import sys; sys.path.insert(0, "${loom}/pkgs/loom-cli"); sys.path.insert(0, "${loom}/pkgs/loom-installer"); import hostgen; sys.exit(hostgen.main(sys.argv[1:]))' \
        install --answers ${../tests/fixtures/hostgen/answers-omanix.json} --template ${../templates/host} \
        --catalog ${refCatalog}/hostgen.json --out rendered
      diff -r rendered ${golden}
      test -e $toplevel/sw/share/omanix/catalog/index.json
      touch $out
    '';

  # VM tests (§i.2).
  cli-contract = vm "cli-contract";
  cli-e2e = vm "cli-e2e";
  try-preview = vm "try-preview";
  plugin-fixture = vm "plugin-fixture";
}
