---
name: omanix-host
description: The edit loop for this machine's host repo: where settings live, omanix set vs a hand edit, check, commit, propose. Use for any change to what the machine is.
---
# Changing this machine

The machine is the host repo in `~/projects/host` (plain NixOS + home-manager modules). Nothing
changes until the human approves a card; you never switch the system yourself.

## Start of a session
1. `omanix context --json`: host, generation, deployed commit, whether your working copy is behind,
   plugins, the last switch and its card result, the human's runtime state, catalogs.
2. If `workingCopy.behind > 0`: `git pull --rebase` from the mirror (`git fetch` then rebase onto
   the deployed commit); a proposal that doesn't descend from it is refused.

## Where things live
- `configuration.nix`: preferences (`omanix.*`, `loom.user`, `loom.locale`, `loom.agent`). New
  settings go under the marker line at the end.
- `home.nix`: the human's own home-manager settings (`home.packages`, `programs.*`).
- `modules/*.nix`: your own modules; list each in `modules/default.nix`. `modules/plugins.nix`
  imports plugin modules; `modules/persist.nix` keeps state across reboots.
- `machine.nix`, `keys.nix`, `hardware.nix`, `secrets/`: installer- and tool-written; see the
  `secrets`, `hardware`, `rotate-keys` skills.
- The desktop dotfiles (`~/.config/hypr/*.lua`, terminals, fontconfig, …) are generated read-only
  from `omanix.*` options. `omanix where <file>` names the option; never write those files.
- Catalogs: `/run/current-system/sw/share/omanix/catalog/` (`options/*.json`, `home.json`,
  `keybinds.json`, `menu.json`, `apps.json`, `host.md`). Read `host.md` before touching a plugin.

## Find, then change
- `omanix options <words>` searches every option (path, type, default, origin, description).
- `omanix where <option>` evaluates the working copy: each definition with file:line, priority,
  and whether it's editable. `omanix explain <option>` adds the description and current value.
- `omanix set <path> <json>`: when one literal host definition exists it is rewritten in place;
  when none, the setting is added under the marker of `configuration.nix` (`home.nix` for `home.*`).
  It evaluates the result and reverts if something else wins. Exit 2 means several places or an
  expression define it: edit those files by hand. The output's `shadowedBy` lists runtime overlays
  that will keep overriding it in the human's session until they make it stick or reset it.
- Use a hand edit for anything that isn't a single value: new modules, `lib.mkIf`, services with
  several options, lists built from expressions.

## Land it
1. `omanix check` (evaluates, checks the generated key files, builds). Fix every error.
2. `git add` new files, `git commit` with a plain subject.
3. `omanix propose --request "<the human's words, verbatim>"`. Batch everything for one request
   into one proposal. Run it in the background; it returns when the human decides:
   exit 0 applied, 1 denied (the reason is in the output: act on it), 4 rolled back
   (`omanix why-failed --last`), 5 refused (rebase, retry).
4. Tell the human what changed in one or two sentences.

Exit codes for every `omanix`/`loom` command: 0 ok, 1 failed, 2 usage or refused (edit by hand),
3 a card is waiting, 4 rolled back, 5 offline/busy (try later).
