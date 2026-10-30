---
name: apps
description: Install or remove applications, web apps, TUIs, dev tools, games. Replaces omarchy's install/remove/pkg/webapp/tui scripts.
---
# Apps

Installing is a change to the host repo; never use an imperative package manager.

- An app omarchy ships (see `catalog/apps.json`): `omanix app add <name>` (sets
  `omanix.apps.<name>.enable = true`). Unfree apps (obsidian, …) are off by default.
- A web app: `omanix app add <Name> --url https://… [--icon <name>]` (`omanix.apps.webapps.<Name>`).
- A terminal app: `omanix app add <Name> --command <cmd>` (`omanix.apps.tuis.<Name>`).
- Anything else from nixpkgs: `omanix app add <attr>` adds it to `home.packages` in `home.nix`
  after checking the attribute exists (`meta.mainProgram` tells you the command).
- A service or something with settings (Steam, Docker, Tailscale, virtualisation): write a small
  module in `modules/` and list it in `modules/default.nix`, e.g. `programs.steam.enable = true;`
  plus `hardware.graphics.enable32Bit = true;` for gaming. Persist its state (`persist` skill).
- Dev environments and language toolchains: prefer per-project `nix develop`/direnv; add global
  tools to `home.packages` only when asked.
- Remove: `omanix app remove <name>`.

Then `omanix check`, commit, `omanix propose --request "…"`.
