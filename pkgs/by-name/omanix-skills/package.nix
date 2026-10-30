# omanix-skills: the resident's skills and prompt fragment (DESIGN §h.10).
# Linked into /agents/<agent>/.claude/skills/ by modules/omanix/cli.nix; they
# update with the omanix release, so the host repo never carries copies.
# checks.skills-no-arch greps them; checks.menu-intents' skill names
# (fork/intents.toml [skills].known) must equal this directory's.
{ lib, runCommand }:

runCommand "omanix-skills-0.1.0"
  {
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [ ./skills ./prompt.md ];
    };
    meta.description = "The omanix resident's skills and prompt fragment";
  }
  ''
    mkdir -p $out/share/omanix
    cp -r $src/skills $out/share/omanix/skills
    cp $src/prompt.md $out/share/omanix/prompt.md
  ''
