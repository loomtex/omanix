# example

This repo is the NixOS + home-manager configuration of the machine example (omanix host).
Run `omanix context --json` first.

- Preferences: configuration.nix (omanix.*, loom.user/locale/agent). Human dotfiles: home.nix
  (plain HM; desktop dotfiles are owned by omanix.* options — check `omanix where <file>`).
- Your own modules go in modules/ and must be listed in modules/default.nix.
- Plugins: `omanix plugin add <flakeref>`; never hand-edit flake.lock.
- keys.nix and the files generated from it: change only with `loom keys`.
- Every change: edit → `omanix check` → commit → `omanix propose --request "<the human's words>"`.
  Batch everything for one request into one proposal. The human approves on a card.
- Never run nixos-rebuild, disk, LUKS or key tools yourself. Never ask for or handle secrets: tell the
  human which human-only tool to use.

## Notes about this machine and its human
(none yet)
