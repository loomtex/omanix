"""omanix: the keyboard layout picker, writing the runtime overlay (U28).

Upstream's picker (typing_setup.py) saves the layouts into
~/.config/omarchy/keyboard-layouts, which omanix makes a read-only
home-manager file (omanix.input.layouts). This module reuses upstream's
picker and its fcitx group step unchanged and swaps two pieces:

- the catalog comes from xkeyboard-config's evdev.lst (upstream's came from
  the installer form, which omanix doesn't ship);
- the selection goes into a keyboard block in
  ~/.local/state/omanix/overlay/hypr/input.lua (`omanix-overlay kb`), which
  Hyprland loads after the HM input.lua. After the reload the live
  input:kb_layout must match, or the overlay is put back as it was.

"Make it stick" turns the block into omanix.input.layouts.

Run with `python3 -I`; it imports typing_setup/configure from this directory.
"""

import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import configure as setup  # noqa: E402
import typing_setup as up  # noqa: E402

PYTHON = "/run/current-system/sw/bin/python3"
XKB_LISTS = [
  "/run/current-system/sw/share/X11/xkb/rules/evdev.lst",
  "/etc/X11/xkb/rules/evdev.lst",
]


def overlay_path():
  state = Path(os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state"))
  return state / "omanix/overlay/hypr/input.lua"


def keyboard_catalog():
  """{"us": "English (US)", "us:intl": "English (US, intl., with dead keys)", …}"""
  catalog = {}
  path = next((Path(p) for p in XKB_LISTS if Path(p).exists()), None)
  if path is None:
    return {"us": "English (US)"}
  section = None
  for line in path.read_text(errors="replace").splitlines():
    if line.startswith("! "):
      section = line[2:].strip()
      continue
    fields = line.split(None, 1)
    if len(fields) < 2:
      continue
    if section == "layout":
      catalog.setdefault(fields[0], fields[1].strip())
    elif section == "variant" and ":" in fields[1]:
      layout, label = fields[1].split(":", 1)
      catalog.setdefault(f"{layout.strip()}:{fields[0]}", label.strip())
  return catalog


def choose(title, catalog, selected, kind, overrides=None):
  # upstream's choose(), with the on-change command pointing at this module
  catalog = {**catalog, **{key: catalog.get(key, key) for key in selected}}
  rows = up.picker_rows(catalog, selected)
  args = ["omarchy-menu-select", title] + list(rows.values())
  on_change = [PYTHON, "-I", str(HERE / "omanix_keyboard.py"), "apply", kind,
               json.dumps({"catalog": catalog, "overrides": overrides or {}})]
  args += ["--", "--multiple", "--width", "620", "--maxheight", "650", "--on-change", json.dumps(on_change),
           "--change-key", "typing:" + kind]
  for key in selected:
    args += ["--selected", rows[key][1:]]
  result = subprocess.run(args, text=True, capture_output=True)
  if result.returncode == 1:
    return None
  if result.returncode:
    raise RuntimeError(result.stderr.strip() or "The selection menu could not open")


def fcitx_running():
  return subprocess.run(["fcitx5-remote", "-q"], capture_output=True).returncode == 0


def save_keyboard(selected):
  # upstream's save_keyboard(), writing the overlay instead of keyboard-layouts
  layouts, variants = up.keyboard_values(selected)
  path = overlay_path()
  original = setup.read(path) if path.exists() else None
  fcitx = fcitx_running()
  if fcitx:
    group, old_layout, before = setup.live_group()
  group_changed = False
  previous_errors = setup.run(["hyprctl", "configerrors"])
  try:
    setup.run(["omanix-overlay", "kb", layouts, variants])
    setup.run(["hyprctl", "reload"])
    errors = setup.run(["hyprctl", "configerrors"])
    if errors and errors != previous_errors:
      raise RuntimeError(errors)
    expected = [layout + (":" + variant if variant else "")
                for layout, variant in zip(layouts.split(","), variants.split(","))]
    if up.keyboard_selection() != expected:
      raise RuntimeError("Your personal keyboard layout override takes precedence over this selection")
    if not fcitx:
      return
    first_layout = layouts.split(",")[0]
    first_variant = variants.split(",")[0]
    group_layout = first_layout + ("-" + first_variant if first_variant else "")
    primary = next((item[0] for item in before if item[0].startswith("keyboard-")), None)
    if primary is None:
      raise RuntimeError("The current input group has no keyboard input")
    keyboard = "keyboard-" + group_layout
    after = [[keyboard, ""]] + [
      [name, setup.engine_layout(name, group_layout) if override == setup.engine_layout(name, old_layout) else override]
      for name, override in before if name not in (primary, keyboard)]
    group_changed = True
    setup.live_set(group, group_layout, after)
    if setup.live_group() != (group, group_layout, after):
      raise RuntimeError("Fcitx did not retain the keyboard selection")
  except BaseException:
    if original is None:
      setup.run(["omanix-overlay", "kb", "--unset"])
    else:
      setup.atomic_write(path, original)
    try:
      setup.run(["hyprctl", "reload"])
    finally:
      if group_changed:
        setup.live_set(group, old_layout, before)
    raise


up.keyboard_catalog = keyboard_catalog
up.choose = choose
up.save_keyboard = save_keyboard

if __name__ == "__main__":
  up.main()
