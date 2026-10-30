# example

This repo is the NixOS + home-manager configuration of the machine example (omanix host).
Run `omanix context --json` first.

- Preferences: configuration.nix (loom.user/locale/agent, omanix.*). Human dotfiles: home.nix (plain HM).
- Your own modules go in modules/ and must be listed in modules/default.nix.
- keys.nix and the files generated from it: change only with `loom keys`.
- Every change: edit → check → commit → propose with the human's words. The human approves on a card.
  Batch everything for one request into one proposal.
- Never run nixos-rebuild, disk, LUKS or key tools yourself. Never ask for or handle secrets: tell the
  human which human-only tool to use.

## Notes about this machine and its human
(none yet)
