# omanix.cli: the `omanix` CLI (§h.8) and what the resident gets with it
# (§h.10): the command registry (→ /etc/omanix/commands.json, the router and
# catalog/commands.json), /etc/omanix/cli.json (who is the agent, where the
# working copies, mirror, catalogs and runtime summary are), the resident's
# skills linked into ~/.claude/skills/ and its prompt fragment with a
# generated index of the option roots.
{ config, options, lib, pkgs, ... }:

let
  cfg = config.omanix;
  loomCfg = config.loom;
  agent = loomCfg.agent;
  human = loomCfg.user.name;
  builtin = builtins.fromJSON (builtins.readFile ../../pkgs/by-name/omanix-cli/commands.json);
  skillsDir = ../../pkgs/by-name/omanix-skills/skills;
  skillNames = builtins.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir skillsDir));
  json = (pkgs.formats.json { }).type;

  commandType = lib.types.submodule {
    options = {
      description = lib.mkOption { type = lib.types.str; description = "One or two sentences: what the command does."; };
      args = lib.mkOption { type = lib.types.listOf json; default = [ ]; description = "argparse-style arguments ({name, help, nargs, action, default})."; };
      output = lib.mkOption { type = json; default = { }; description = "The --json output schema (required keys, properties) when ok."; };
      command = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/run/current-system/sw/bin/my-omanix-verb";
        description = "For extension commands: the executable `omanix <group> <name>` runs (it gets the remaining arguments).";
      };
      origin = lib.mkOption { type = lib.types.str; default = "omanix"; description = "Who provides it (omanix, a plugin's input name)."; };
    };
  };

  # The resident's option index: one line per loom.*/omanix.* option root.
  firstLine = d: let t = d.text or d; in builtins.head (lib.splitString "\n" (if builtins.isString t then t else ""));
  rootLine = prefix: name: o:
    if lib.isOption o then "- `${prefix}.${name}`: ${firstLine (o.description or "")}"
    else "- `${prefix}.${name}.*`: " + lib.concatStringsSep ", " (lib.take 12 (builtins.attrNames (removeAttrs o [ "_module" ])));
  index = prefix: opts: lib.mapAttrsToList (rootLine prefix) (removeAttrs opts [ "_module" ]);
  optionIndex = lib.concatStringsSep "\n" ([
    "## Option roots (generated)"
    "Search with `omanix options <words>`; plugin and host-module options are in catalog/host.md."
  ] ++ index "omanix" options.omanix ++ index "loom" options.loom);
in
{
  options.omanix.cli = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      defaultText = lib.literalExpression "config.omanix.enable";
      description = "Install the `omanix` CLI and give the resident its skills and prompt.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.omanix-cli;
      defaultText = lib.literalExpression "pkgs.omanix-cli";
      description = "The `omanix` CLI package.";
    };
    commands = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf commandType);
      default = { };
      example = lib.literalExpression ''{ myplugin.sync = { description = "Sync my plugin's state."; command = "''${pkgs.myplugin}/bin/sync"; origin = "myplugin"; }; }'';
      description = ''
        The command registry, `<group>.<name>` (group `core` for single
        verbs): the router, `--help --json` and catalog/commands.json read it.
        omanix's own verbs are defined here; plugins may add commands with a
        `command` to run.
      '';
    };
    registry = lib.mkOption {
      type = json;
      readOnly = true;
      default = { schema = "omanix.commands/v1"; inherit (builtin) exitCodes; commands = lib.mapAttrs (_: lib.mapAttrs (_: c: lib.filterAttrs (_: v: v != null) c)) cfg.cli.commands; };
      defaultText = lib.literalExpression "commands.json from omanix.cli.commands";
      description = "What /etc/omanix/commands.json holds.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.cli.enable) (lib.mkMerge [
    {
      omanix.cli.commands = lib.mapAttrs (_: lib.mapAttrs (_: c: lib.mapAttrs (_: lib.mkDefault) c)) builtin.commands;

      environment.systemPackages = [ cfg.cli.package pkgs.omanix-catalog ];
      environment.etc."omanix/commands.json".text = builtins.toJSON cfg.cli.registry;
      environment.etc."omanix/cli.json".text = builtins.toJSON {
        agent = if agent.enable then agent.name else null;
        agentUids = lib.optional agent.enable agent.uid ++ lib.optional loomCfg.reviewer.enable loomCfg.reviewer.uid;
        inherit human;
        humanUid = config.users.users.${human}.uid or 1000;
        humanRepo = "omanix-host";
        agentRepo = "projects/host";
        catalog = "/run/current-system/sw/share/omanix/catalog";
        skills = "${pkgs.omanix-skills}/share/omanix/skills";
        runtimeJson = "/run/omanix/session/${toString (config.users.users.${human}.uid or 1000)}/runtime.json";
        hostAttr = "nixosConfigurations.host";
        firstbootDir = "${loomCfg.persist.root}/var/lib/loom/firstboot";
        fetchUrl = loomCfg.host.repo.fetchUrl or null;
        pushUrl = loomCfg.host.repo.pushUrl or null;
        commands = "/etc/omanix/commands.json";
      };
    }

    (lib.mkIf agent.enable {
      # §h.10: the resident's global prompt carries the omanix guidance.
      loom.agent.promptFragments = [ (builtins.readFile ../../pkgs/by-name/omanix-skills/prompt.md) optionIndex ];
      # Skills update with the release; the resident may add its own next to them.
      home-manager.users.${agent.name}.home.file = lib.listToAttrs (map (n: {
        name = ".claude/skills/${n}";
        value.source = lib.mkDefault "${pkgs.omanix-skills}/share/omanix/skills/${n}";
      }) skillNames);
    })
  ]);
}
