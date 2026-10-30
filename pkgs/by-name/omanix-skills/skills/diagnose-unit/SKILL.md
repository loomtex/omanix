---
name: diagnose-unit
description: Read-only diagnosis of a failed systemd unit.
---
# A unit failed

1. `omanix status --json` (failed units) or `omanix why-failed [<unit>] --json` (journal excerpt).
2. `journalctl -u <unit> -b --no-pager` reads more (you are in systemd-journal).
3. Explain the cause in plain words. A fix is a module change and a proposal; restarting a unit
   now is `sudo --why "<reason>" systemctl restart <unit>`, which shows the human a card.
