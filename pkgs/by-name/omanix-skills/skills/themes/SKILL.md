---
name: themes
description: Themes: install from a flake input, remove, update; the boot screen theme.
---
# Themes

- Built-in themes: `omanix set omanix.theme.default '"<name>"'` (list: `catalog/themes.json`).
- A theme from a repository: add it as a flake input with `omanix plugin add <flakeref> --name
  theme-<slug>` only if it is a flake; otherwise add the input by hand in `flake.nix` with
  `flake = false`, then `omanix.theme.extra.<slug> = { src = inputs.theme-<slug>; };`. A theme's
  `hyprland.lua` is code: leave `trusted = false` unless the human says otherwise, and say so.
- Boot screen (Plymouth, SDDM, Limine colors): `omanix.theme.boot.theme`.
- Update a theme input: `omanix update theme-<slug>`.
