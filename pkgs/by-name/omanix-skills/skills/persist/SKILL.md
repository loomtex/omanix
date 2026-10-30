---
name: persist
description: What survives a reboot: / is tmpfs; persist service state, audit what is lost.
---
# Persistence

- `/` is tmpfs; `/home`, `/nix` and `/persist` are kept. The human's home needs nothing.
- A service's state (`/var/lib/<svc>`) must be persisted in the module that enables it, or in
  `modules/persist.nix`: `omanix persist add /var/lib/<svc>` (`--file` for a file). DynamicUser
  services keep state in `/var/lib/private/<svc>`.
- `omanix check` fails when an enabled service's StateDirectory isn't covered; the message names
  the option. Deliberately throwaway state: `loom.persist.ephemeralOk` with a comment.
- `omanix persist audit` lists files written on `/` that no entry covers (they vanish at reboot).
- Your own home (`/agents/<you>`) is reset at boot except `projects` and `.claude`.
