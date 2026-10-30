---
name: look
description: Make a runtime look change permanent (make it stick), clock format, branding, gaps, corners, animations.
---
# Look and make it stick

The human changes the look live (theme, font, scale, gaps, bar); those are runtime overlays in
their session. "Make it stick" sends you a `loom.snapshot/v1` attachment (kind runtime-snapshot)
for one area. Map it to options, never to files:

| snapshot | option |
|---|---|
| theme name | `omanix.theme.default` |
| background | `omanix.theme.background` |
| monospace font | `omanix.fonts.monospace` |
| monitors (output, mode, scale) + gdkScale | `omanix.hyprland.monitors`, `omanix.hyprland.gdkScale` |
| shell (bar, dock, widgets) | `omanix.shell.settings` |
| known Hyprland keys (gaps, rounding, opacity, animations) | `omanix.hyprland.settings.<section>.<key>` |
| keyboard | `omanix.input.layouts` |
| other Lua in `hypr/<f>.lua` | `omanix.hyprland.fileLua.<f>` (shown verbatim on the card) |
| the `hyprland` overlay | `omanix.hyprland.extraLua` |

For each whole-file overlay you absorb, also set `omanix.runtime.absorbed.<area> = "<snapshotSha>"`,
so the overlay is emptied after the switch. Use `omanix set` for single values; check
`shadowedBy` in its output.

Preview before committing: `omanix try <path> <value>` (only keys in `catalog/preview.json`);
the human allows it in the panel; `omanix try --reset` reverts.

Clock format, branding (`omanix.branding.about`, `.screensaver`), corners and animations are
`omanix.*` options; search with `omanix options <word>`.
