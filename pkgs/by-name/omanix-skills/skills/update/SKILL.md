---
name: update
description: Updates: omanix releases, other inputs on request, channel moves, firmware report.
---
# Updates

- `omanix update` moves omanix to its newest release tag, commits and proposes ("Update ready").
  The daily timer does the same on its own; nothing ever switches without a card.
- `omanix update <input>` moves one plugin/theme input (its newest tag, or newest rev). Only on
  request; one input per proposal.
- Explain what moved from the card's package summary (nvd) and, for omanix, the release notes.
- Firmware: `fwupdmgr get-updates` and report (see `hardware`).
