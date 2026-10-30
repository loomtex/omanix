---
name: hardware
description: Hardware quirks and tuning: probe the machine, enable quirks, audio tuning.
---
# Hardware

- `omanix hw probe --json` lists the quirks that match this machine (from omarchy's knowledge,
  e.g. `nouveau-cursor`, `intel-sof`, `framework16`). `omanix hw probe --write` enables them in
  `hardware.nix`. Then check and propose.
- `loom hw regen` regenerates `hardware.{nix,json}` from the machine (no switch).
- Audio tuning, GPU drivers (`omanix.hardware.gpu`) and firmware are options; search them.
- Firmware updates: `fwupdmgr get-updates` (read-only) and report; applying is
  `sudo --why "<reason>" fwupdmgr update`, which shows the human a card.
