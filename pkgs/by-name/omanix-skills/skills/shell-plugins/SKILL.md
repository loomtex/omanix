---
name: shell-plugins
description: Quickshell shell plugins: add, clone, remove, update as flake inputs (omanix.shell.plugins).
---
# Shell plugins

The bar's plugins come from flake inputs, never from a clone in the human's config.
1. Add the repository as an input in `flake.nix` (`flake = false` unless it is a flake).
2. `omanix.shell.plugins.<name> = { src = inputs.<input>; enable = true; };` in a module.
3. Enabling/disabling an installed plugin is a runtime toggle for the human; make it stick with
   `omanix.shell.settings`.
4. Update: `omanix update <input>`; remove: delete both and `omanix plugin remove <input>` if
   it was added that way.
