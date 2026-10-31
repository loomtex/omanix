# The scripted demo (DESIGN §j), scenes 2-7 plus the make-it-stick and
# human-commit checks: what the replay resident does (`resident`, a
# loom.replay/v1 script), what the replay reviewer says (`reviews`,
# loom.review-replay/v1, first `when` that matches), and the systems the
# proposals switch to (`systems`: each becomes a specialisation of the demo
# VM, and the resident proposes its commit with `--out` that system).
#
# The commits, the bundles, the git and nvd diffs, the cards, the reviews,
# the approvals, the watchdog and the records are all real. What is
# prebuilt is the toplevel: the VM can't build the host repo's commit
# offline into a system the test driver keeps running, so each commit is
# paired with the specialisation that declares the same change (the nvd
# diff on the card is between the running system and that one).
#
# Used by tests/demo.nix (checks.vm-demo-<n>, make-it-stick, human-commit)
# and by the presenter's run (demo/RUNBOOK.md).
{ lib }:

let
  wait = { on = "user"; };
  say = text: { inherit text; };
  run = kind: label: cmd: { run = [ "sh" "-c" cmd ]; activity = { inherit kind label; }; };
  q = lib.escapeShellArg;
  edit = args: "demo-edit ${lib.escapeShellArgs args}";
  commit = msg: run "commit" "Committing: ${msg}" "git add -A && git commit -qm ${q msg}";
  # `omanix propose` waits for the card's decision; its JSON (result, log
  # with the human's reason) lands in ~/demo/<n>.json for the next steps and
  # for the test. A denial is an answer, not an error row.
  propose = n: request: system: run "propose" "Proposing: ${request}"
    "omanix propose --request ${q request} --out \"$(readlink -f /run/demo/out-${system})\" --json > ~/demo/${n}.json || true";
  start = run "read" "omanix context" "mkdir -p ~/demo && omanix context --json > ~/demo/context.json";

  review = when: summary: extra: { inherit when; review = { inherit summary; risk = "low"; recommendation = "approve"; notes = [ ]; not_shown = [ ]; } // extra; };

  steam = { programs.steam.enable = true; loom.nixpkgs.allowUnfree = [ "steam" "steam-unwrapped" ]; };
  battery = {
    services.power-profiles-daemon.enable = false;
    services.tlp.enable = true;
    loom.persist.system.directories = [ "/var/lib/tlp" ];
    omanix.hyprland.monitors = [ { output = ""; mode = "1280x800@60"; } ];
  };
in
{
  # 2. "Install and configure X": menu › Install › Gaming › Steam, Enter; then
  # "and hide the dock unless I hover". Two one-line cards.
  "2" = {
    resident = [
      wait
      (say "I'll add Steam. First a look at this machine and its configuration.")
      start
      (run "read" "Reading configuration.nix" "cat configuration.nix > /dev/null")
      (run "edit" "Editing configuration.nix" (edit [ "append" "configuration.nix" "  programs.steam.enable = true;" "  loom.nixpkgs.allowUnfree = [ \"steam\" \"steam-unwrapped\" ];" ]))
      (run "build" "Checking it evaluates (omanix check)" "omanix check --no-build --json > ~/demo/2-check.json")
      (commit "apps: Steam")
      (say "It evaluates. The card is up for you.")
      (propose "2a" "Install Steam." "steam")
      (say "Steam is installed; you'll find it in the launcher.")
      wait
      (say "I'll make the dock hide until you hover over the bottom edge.")
      (run "edit" "Editing configuration.nix" (edit [ "append" "configuration.nix" "  omanix.shell.settings.dock.autohide = true;" ]))
      (commit "look: the dock hides until hover")
      (propose "2b" "and hide the dock unless I hover" "steam-dock")
      (say "Done: the dock now hides until you hover.")
    ];
    reviews = [
      (review "dock" "Sets the dock to hide until the pointer reaches the bottom edge (omanix.shell.settings.dock.autohide). Nothing else changes." { })
      (review "steam" "Installs Steam (programs.steam.enable, with its 32-bit graphics libraries) and allows its two unfree packages by name. Nothing else changes." { })
    ];
    systems = {
      steam = steam;
      steam-dock = steam // { omanix.shell.settings.dock.autohide = true; };
    };
  };

  # 3. "Try it, then keep it": the theme picker previews Kanagawa; Make it
  # stick attaches the snapshot; the resident sets the one line.
  "3" = {
    resident = [
      wait
      (say "Making Kanagawa your theme for good: one line in configuration.nix.")
      (run "read" "Reading the snapshot you attached" "mkdir -p ~/demo && ls -t ~/inbox/*/*.json | head -n1 | xargs cat > ~/demo/3-snapshot.json")
      (run "edit" "omanix set omanix.theme.default" "t=$(jq -r '.theme | ascii_downcase | gsub(\" \"; \"-\")' ~/demo/3-snapshot.json); omanix set omanix.theme.default \"\\\"$t\\\"\" --json > ~/demo/3-set.json")
      (commit "look: theme kanagawa")
      (propose "3" "Make my current theme settings permanent." "kanagawa")
      (say "Done. Kanagawa is in your configuration now, so it survives a reinstall.")
    ];
    reviews = [
      (review "theme" "Changes the default theme from tokyo-night to kanagawa (omanix.theme.default). Nothing else changes." { })
    ];
    systems.kanagawa = { omanix.theme.default = "kanagawa"; };
  };

  # 4. "Read the card": the resident also turns Bluetooth off at boot; the
  # reviewer says so; the human denies with a reason; the resident drops it.
  "4" = {
    resident = [
      wait
      (say "I'll turn on TLP for power management and drop the refresh rate to 60 Hz.")
      start
      (run "search" "omanix options battery" "omanix options battery --json > /dev/null")
      (run "edit" "Writing modules/power.nix" (edit [ "write" "modules/power.nix"
        "# Battery life (asked: make my laptop last longer on battery)."
        "{ ... }:"
        ""
        "{"
        "  services.power-profiles-daemon.enable = false; # TLP replaces it"
        "  services.tlp.enable = true;"
        "  omanix.hyprland.monitors = [ { output = \"\"; mode = \"1280x800@60\"; } ];"
        "  loom.persist.system.directories = [ \"/var/lib/tlp\" ]; # TLP's state survives reboots"
        "  hardware.bluetooth.powerOnBoot = false;"
        "}" ]))
      (run "edit" "Importing it in modules/default.nix" (edit [ "replace" "modules/default.nix" "./vm.nix ]" "./vm.nix ./power.nix ]" ]))
      (commit "power: TLP, 60 Hz, Bluetooth off at boot")
      (propose "4a" "Make my laptop last longer on battery." "battery-bt")
      (run "read" "Reading your answer" "grep -q 'keep Bluetooth' ~/demo/4a.json")
      (say "You said: keep Bluetooth. I'll take that line out and ask again.")
      (run "edit" "Editing modules/power.nix" (edit [ "drop" "modules/power.nix" "bluetooth" ]))
      (commit "power: TLP and 60 Hz; Bluetooth untouched")
      (propose "4b" "Make my laptop last longer on battery. (You said: keep Bluetooth.)" "battery")
      (say "Applied: TLP manages power now and the screen runs at 60 Hz. Bluetooth is as it was.")
    ];
    reviews = [
      (review "keep bluetooth" "Enables TLP in place of power-profiles-daemon and sets the screen to 60 Hz. Bluetooth is left as it was." { })
      {
        when = "battery";
        review = {
          summary = "Enables TLP in place of power-profiles-daemon and sets the screen to 60 Hz. It also turns Bluetooth off at every boot, which you didn't ask for.";
          risk = "medium";
          recommendation = "ask";
          notes = [ "modules/power.nix sets hardware.bluetooth.powerOnBoot = false: Bluetooth devices stop working after a reboot until you switch it on; the request doesn't ask for that" ];
          not_shown = [ ];
        };
      }
    ];
    systems = {
      battery-bt = battery // { hardware.bluetooth.powerOnBoot = false; };
      inherit battery;
    };
  };

  # 5. "Explain this sudo": a 14-line root script; line 9 deletes every saved
  # network; the human denies with a reason; the resident drops it; then a
  # change card for the lasting part.
  "5" = {
    resident = [
      wait
      (say "I'll write a short script that turns Wi-Fi power saving off for this boot and restarts the Wi-Fi stack, and ask you to run it as root.")
      (run "edit" "Writing ~/scratch/fix-wifi.sh" "mkdir -p ~/scratch ~/demo && install -m 644 /etc/demo/fix-wifi.sh ~/scratch/fix-wifi.sh")
      (run "run" "sudo bash fix-wifi.sh" "cd ~/scratch && sudo --why 'Wi-Fi keeps dropping: turn power saving off for this boot and restart the Wi-Fi stack' bash fix-wifi.sh > ~/demo/5a.log 2>&1 || true")
      (run "read" "Reading your answer" "grep -q \"don't touch my saved networks\" ~/demo/5a.log")
      (say "Sorry: line 9 would have deleted every saved network. I've taken it out; asking again.")
      (run "edit" "Editing fix-wifi.sh" "cd ~/scratch && demo-edit drop fix-wifi.sh system-connections")
      (run "run" "sudo bash fix-wifi.sh" "cd ~/scratch && sudo --why 'Wi-Fi keeps dropping: turn power saving off for this boot and restart the Wi-Fi stack; saved networks untouched' bash fix-wifi.sh > ~/demo/5b.log 2>&1 || true")
      (say "Wi-Fi is back.")
      wait
      (say "Power saving is already off in omanix's defaults (networking.networkmanager.wifi.powersave). What drops the connection here is MAC address randomization while scanning, so I'll turn that off for good.")
      start
      (run "edit" "Editing configuration.nix" (edit [ "append" "configuration.nix" "  networking.networkmanager.wifi.scanRandMacAddress = false;" ]))
      (commit "network: no MAC randomization while scanning")
      (propose "5c" "keep Wi-Fi power saving off" "wifi")
      (say "Done; it stays that way after a reboot.")
    ];
    reviews = [
      (review "saved networks untouched" "Runs fix-wifi.sh as root: prints the Wi-Fi radio state, turns power saving off on each Wi-Fi interface until the next boot (iw), restarts NetworkManager and switches the radio on. Saved networks are not touched." { })
      {
        when = "power saving off for this boot";
        review = {
          summary = "Runs fix-wifi.sh as root. Lines 6-8 turn Wi-Fi power saving off until the next boot and lines 11-12 restart NetworkManager, as the reason says. Line 9 deletes every saved network, with its password, which the reason doesn't mention.";
          risk = "high";
          recommendation = "deny";
          notes = [
            "line 9: rm -f /etc/NetworkManager/system-connections/*.nmconnection deletes every saved Wi-Fi network and its password; nothing in the stated reason needs that, and it can't be undone"
            "line 11 restarts NetworkManager: every connection drops for a few seconds"
          ];
          not_shown = [ ];
        };
      }
      (review "power saving off" "Turns off MAC address randomization while NetworkManager scans (networking.networkmanager.wifi.scanRandMacAddress). Power saving stays off as before. Nothing else changes." { })
    ];
    systems.wifi = { networking.networkmanager.wifi.scanRandMacAddress = false; };
  };

  # 6. "Break it, get it back": the monitor rule turns off the only screen;
  # Hyprland falls back to its headless output; the watchdog rolls back.
  # Why? → why-failed. Then a working change, and Undo.
  "6" = {
    resident = [
      wait
      (say "I'll turn the built-in screen (Virtual-1) off.")
      start
      (run "edit" "Editing configuration.nix" (edit [ "append" "configuration.nix" "  omanix.hyprland.fileLua.monitors = ''hl.monitor({ output = \"Virtual-1\", disabled = true })'';" ]))
      (commit "display: built-in screen off")
      (propose "6a" "I only use my external monitor: turn off the laptop screen." "screen-off")
      (run "edit" "Dropping the rejected commit" "git reset -q --hard HEAD~1")
      wait
      (run "read" "omanix why-failed" "omanix why-failed --last --json > ~/demo/6-why.json")
      (say "The new rule turned off Virtual-1, and no other monitor is connected, so Hyprland was left drawing to its headless fallback: a black screen. The watchdog saw that and put the previous system back within 30 seconds; nothing reached the boot menu. Want something smaller instead, like 60 Hz on this screen?")
      wait
      (run "edit" "Editing configuration.nix" (edit [ "append" "configuration.nix" "  omanix.hyprland.monitors = [ { output = \"Virtual-1\"; mode = \"1280x800@60\"; } ];" ]))
      (commit "display: 60 Hz")
      (propose "6b" "Yes, 60 Hz." "refresh60")
      (say "Applied. If you don't like it, Undo is right there.")
    ];
    reviews = [
      (review "laptop screen" "Adds a Hyprland monitor rule that disables the output Virtual-1 (the built-in screen). If no other monitor is connected the session has no screen left; the watchdog would roll that back." { })
      (review "60 hz" "Sets Virtual-1 to 1280x800 at 60 Hz (omanix.hyprland.monitors). Nothing else changes." { })
    ];
    systems = {
      screen-off = { omanix.hyprland.fileLua.monitors = ''hl.monitor({ output = "Virtual-1", disabled = true })''; };
      refresh60 = { omanix.hyprland.monitors = [ { output = "Virtual-1"; mode = "1280x800@60"; } ]; };
    };
  };

  # 7. "Two residents, one machine": one reviewed root command, then the
  # human looks around in a terminal.
  "7" = {
    resident = [
      wait
      (say "I'll read the last lines of the system journal; that needs root, so you'll get a card.")
      (run "run" "sudo journalctl -n 5" "mkdir -p ~/demo && sudo --why 'Josh asked what the system did last; read the last 5 journal lines' journalctl -n 5 --no-pager > ~/demo/7.log 2>&1 || true")
      (say "Those are the last five lines. I'm a separate user (ada); the reviewer is another one; neither of us can read your home.")
    ];
    reviews = [
      (review "journal" "Prints the last five lines of the system journal. Read-only; nothing changes." { })
    ];
    systems = { };
  };

  # make-it-stick (§f.4.6): scale, text size and theme changed in the GUI, a
  # hand edit to the look overlay; the snapshots are attached and sent; the
  # resident maps them (demo-stick); the absorbed overlays settle after the
  # promoted switch, except the one the human changed after the snapshot.
  # The specialisation's values come from tests/fixtures/demo/stick.json,
  # the snapshot the GUI writes in the VM (the test checks they agree).
  make-it-stick = {
    resident = [
      wait
      (say "Making your current look permanent: scale, text size, theme and gaps.")
      (run "read" "Reading the snapshots you attached" "mkdir -p ~/demo && cat ~/inbox/*/*.json > ~/demo/stick-snapshots.json")
      (run "edit" "Mapping them to options (look skill)" "demo-stick > ~/demo/stick-lines.txt")
      (commit "look: make the current scale, text size, theme and gaps permanent")
      (propose "stick" "Make my current look settings permanent." "stick")
      (say "Done. The overlays that are now declared were emptied; the one you changed since is left alone.")
    ];
    reviews = [
      (review "permanent" "Declares the monitor scale, the terminal font size, the kanagawa theme and the outer gaps you set in the GUI, and records which runtime snapshots that absorbs. Nothing else changes." { })
    ];
    systems.stick =
      let s = builtins.fromJSON (builtins.readFile ../tests/fixtures/demo/stick.json); in {
        omanix.theme.default = "kanagawa";
        omanix.hyprland.monitors = map (m: { inherit (m) output mode; position = "auto"; scale = m.scale; }) s.monitors;
        omanix.hyprland.gdkScale = s.gdkScale;
        omanix.fonts.size = s.fontSize;
        omanix.hyprland.settings.general.gaps_out = s.gapsOut;
        omanix.runtime.absorbed = { monitors = s.monitorsSha; look = s.lookSha; };
      };
  };

  # human-commit: no resident; the human edits ~/omanix-host and proposes.
  human-commit = {
    resident = [ ];
    reviews = [ ];
    systems = {
      bar-bottom = { omanix.shell.settings.bar.position = "bottom"; };
      over-ssh = { omanix.shell.settings.bar.position = "bottom"; environment.etc."demo/over-ssh".text = "yes\n"; };
    };
  };
}
