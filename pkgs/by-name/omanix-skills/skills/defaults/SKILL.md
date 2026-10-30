---
name: defaults
description: Default terminal, browser, editor and dictation backend. Replaces omarchy's default-* scripts.
---
# Defaults

- `omanix set omanix.defaults.terminal '"kitty"'` (alacritty, foot, ghostty, kitty).
- `omanix set omanix.defaults.browser '"firefox"'`, `.editor`, `.dictation` (see
  `omanix explain omanix.defaults.<slot>` for the allowed values).
- If the app isn't installed, add it in the same proposal (`apps` skill).
- The default browser for links (mimeapps.list) is set at activation from the option; no file edits.
