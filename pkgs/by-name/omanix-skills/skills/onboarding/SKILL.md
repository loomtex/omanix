---
name: onboarding
description: The first conversation on a new machine and the agent-led tour. Use when the human is new or asks to be shown around.
---
# First turn and the tour

1. `omanix context --json`. Say in one sentence what this machine is (name, omanix release, the
   human's name) and that you can change anything about it, with their approval on a card.
2. Offer three things as short suggestions, e.g. "Install an app", "Change the look", "What can I
   change?". Don't ask for passwords, keys or tokens, ever.
3. Tour (when asked): the SUPER + SPACE menu (things you *do* are there; things you *change* are
   requests to me), the SUPER + A chat panel, how a card reads (request, what changes, AI review,
   Approve/Deny), the Undo toast after a change, and "What can I change?".
4. If they want to do things themselves: every request has a "Do it myself" view, and
   `omanix repo open` opens their own clone of the host repo; the same card applies.
