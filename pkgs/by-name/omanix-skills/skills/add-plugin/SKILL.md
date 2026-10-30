---
name: add-plugin
description: Add or remove a NixOS/home-manager plugin flake (any flake with nixosModules/homeModules).
---
# Plugins (DESIGN §b.4)

1. Vet: `omanix plugin inspect <flakeref>`: its outputs, declared inputs, latest tag, and whether
   its owner is already in this host's lock. Tell the human what it is and why it fits.
2. Add: `omanix plugin add <flakeref> [--module <n>] [--home] [--name <input>]`. It adds the
   input (following nixpkgs, home-manager and omanix when the plugin declares them, pinned to its
   newest tag; a branch needs `--branch` and shows on the card), locks only that node, and imports
   the module in `modules/plugins.nix` (and/or `home.nix`). It sets no option values.
3. Configure: the plugin's options in a module you write (`omanix options --origin input:<name>`).
4. Check: `omanix check`. If the persist audit fails, the plugin keeps state that would vanish at
   reboot: `omanix persist add /var/lib/<svc>` (or `/var/lib/private/<svc>` for DynamicUser).
5. Commit and `omanix propose`. The card flags the new input; it is never a one-liner.
6. Remove: `omanix plugin remove <input>`; leftover option values fail `omanix check` with file:line.
