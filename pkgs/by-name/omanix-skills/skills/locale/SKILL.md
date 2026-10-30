---
name: locale
description: Language, time zone, keyboard layouts, input methods and CJK fonts.
---
# Locale

- Time zone: `omanix set loom.locale.timeZone '"Europe/Berlin"'` (the clock can't change it at runtime).
- Language: `omanix set omanix.language '"de"'` and, for system messages, `loom.locale.language`.
- Keyboard layouts that persist: `omanix set omanix.input.layouts '["us","de"]'` (this also fixes
  the console and the disk-unlock keymap). The picker in the menu changes them for the session.
- Input methods (fcitx5) and CJK fonts: `omanix.fonts.cjk`, `omanix.input.*`; check
  `omanix options input` for the exact names.
- A runtime snapshot attached with "make it stick" may carry the keyboard area: map it as in `look`.
