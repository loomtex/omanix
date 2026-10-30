---
name: recover
description: After a rollback, a bad generation, or a machine that boots an older generation.
---
# Recover

- A switch that failed its health checks rolled back by itself: `omanix why-failed --last` gives
  the check and the journal. Fix and propose again.
- "Undo last change": the human clicks Undo, or you run `loom undo` (a card).
- Roll back further: `loom rollback --to <n>` (a card); `loom card show <n>` shows a past card.
- If the human booted an older generation from the boot menu, the next card offers making it the
  default; explain what that means.
