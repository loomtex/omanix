# omanix demo runbook

The community proof of concept (DESIGN §j): about 12 minutes, an omanix VM
on a laptop. Joshua Perry and Ada.

Two kinds of run:

- **Scripted** (scenes 2-7): the replay resident and the replay reviewer
  play `demo/scenes.nix`. The commits, cards, reviews, approvals, switches,
  watchdog and records are real; the model's words are not. Use it for
  rehearsals, for recording B-roll, and as the fallback when the network or a
  model login misbehaves on stage. `checks.vm-demo-<n>` runs the same thing
  headless in CI.
- **Live** (all scenes): the release-candidate image, a real install, ada and
  the reviewer signed in with claude-code. Scenes 1, 8 and 9 only exist live.

## What is where

| Path | What |
|---|---|
| `demo/scenes.nix` | per scene: the replay resident's script, the reviewer's answers, the systems the proposals switch to |
| `demo/fix-wifi.sh` | scene 5's 14-line root script (line 9 deletes the saved networks) |
| `demo/tools/demo-edit.py`, `demo-stick.py` | the replay resident's file edits and its make-it-stick mapping |
| `tests/demo.nix` | the VM checks: `vm-demo-2` … `vm-demo-7`, `make-it-stick`, `human-commit` |
| `tests/fixtures/demo/stick.json` | the snapshot values make-it-stick declares |
| `checks.<name>` output | `screenshots` of every beat (see below) |

## Before the talk

1. Laptop: x86_64, KVM, 16 GB RAM, Nix with flakes. A second screen
   mirrored to the projector.
2. Build everything once so nothing compiles on stage:

   ```
   nix build .#checks.x86_64-linux.vm-demo-{2,3,4,5,6,7} .#checks.x86_64-linux.{make-it-stick,human-commit} -L
   ```

   Each output has the screenshots of its run (`ls result*/`); they are the
   slides' stills and the B-roll for anything that fails live.
3. For the live run: the release-candidate USB image (W20), flashed with
   `loom-flash`, its SHA256SUMS verified against the signed tag; the
   reference laptop's disk is wiped by the install (no dual boot). A phone
   hotspot as the network (venue Wi-Fi tends to have captive portals).
   A real Claude account for ada and one for the reviewer, signed in on the
   phone so the provider's login page is one tap.
4. Write the SEK (system encryption key) of the rehearsal install on the
   paper you will show; never show a real one.

## Scripted run (scenes 2-7)

Each scene is its own VM. Open it interactively:

```
nix run .#checks.x86_64-linux.vm-demo-2.driverInteractive
>>> start_all()        # the VM window opens; the desktop comes up in ~1 min
>>> test_script()      # plays the scene; or run its lines one by one
```

`test_script()` drives the human's side too (menu, typing, clicks on the
card). To present by hand instead, run only the setup part of the script
(everything before the first `with subtest("scene …`) and then do the
scene's steps below yourself: the replay resident answers whatever you
send, in order, so say the lines in the order listed.

| Scene | VM | What you do | What happens |
|---|---|---|---|
| 2 Install and configure X (2 min) | `vm-demo-2` | `SUPER + SPACE` › Install › Gaming › Steam; Enter in the chat. Then type "and hide the dock unless I hover". | Activity rail: `omanix context`, reading `configuration.nix`, editing, `omanix check` (a real evaluation, ~1 min in the VM), commit, propose. A one-line card ("Install Steam." · Reviewer: matches); Approve; Steam is in the launcher. The dock line gets a second one-line card. |
| 3 Try it, then keep it (1.5 min) | `vm-demo-3` | Menu › Appearance › Theme; type "kanagawa"; Enter. Open chat (`SUPER + A`): the "Make theme stick" chip; Menu › Appearance › Make my look permanent (or the chip); Enter. | `omanix set omanix.theme.default "kanagawa"` rewrites the one line; one-line card; Approve; the chip is gone. In a terminal: `git -C /var/lib/loom/host log -1 -p` shows one changed line in `configuration.nix`. |
| 4 Read the card (1.5 min) | `vm-demo-4` | "Make my laptop last longer on battery." Read the full card; **Show git diff**, **nvd diff**; **Deny with reason…** "keep Bluetooth". Then Approve the one-line card. | The reviewer: "It also turns Bluetooth off at every boot, which you didn't ask for", recommendation LOOK CLOSER. The resident gets your reason, drops the line, recommits; one-line card; TLP on, 60 Hz. |
| 5 Explain this sudo (1.5 min) | `vm-demo-5` | "My wifi keeps dropping, fix it for now." **Show command and script**; Deny "don't touch my saved networks"; Approve the second card. Then "keep Wi-Fi power saving off". | The root-command card: the reviewer walks through the 14 lines and flags line 9; the script shown with line numbers is the snapshot that runs. Second attempt without line 9; the saved networks survive. The resident notices power saving is already off and turns off scan MAC randomization instead (a change card). |
| 6 Break it, get it back (1.5 min) | `vm-demo-6` | "I only use my external monitor: turn off the laptop screen." Approve. Then the "Why?" / "What went wrong" chip. Then "Yes, 60 Hz."; Approve; then **Undo** in the chat. | The VM has no external monitor: the screen goes black (Hyprland falls back to its headless output). Within 30 s the watchdog restores the old system: "Rolled back: Hyprland lost its display within 30 s". `why-failed` names the check. The 60 Hz change applies; Undo is one click and a one-line "Undo: Yes, 60 Hz." card. |
| 7 Two residents, one machine (1 min) | `vm-demo-7` | "What did the system do last?"; Approve. Then a terminal: `id ada`, `id reviewer`, `ls -ld /agents/*`, `sudo -u ada cat ~/.ssh/id_ed25519`, `sudo -l -U ada`, `ls /var/lib/nuketown-approval/`; as ada, `git push origin HEAD:master`. | uids 1100/1101, 0700 homes, Permission denied, one sudo rule (`nuketown-approve` as `nuketown-approval`), the audit copies; silo (the stand-in) refuses ada's push to `master` ("not in CODEOWNERS"), `gate/*` works. The reviewer's runs are in `journalctl -t sudo` as `USER=reviewer`. |

## Live run (release candidate; scenes 1, 8, 9 here only)

Run once on the reference laptop after W20 and record it (screen capture of
the VM window plus a phone video of the laptop for scene 1). Fill in the
record at the end.

### Scene 1: "An omarchy that started on nix" (90 s)

1. Boot the laptop from the USB image. The installer TUI: language, disk
   (the whole disk), unlock method (show the capability screen), "Use an AI
   agent? yes", agent sudo "listed".
2. The SEK paper check: the screen shows the system encryption key once;
   retype one group wrong to show the refusal, then right.
3. Time-lapse the install. Reboot, unlock (passphrase or TPM2+PIN).
4. First boot: the full desktop is there before anything else (theme, bar,
   dock, menu). Welcome: Network ✓; **Sign in ada**: the provider's normal
   login page opens in the browser on this machine (no credential copied
   anywhere); **Sign in the reviewer** the same way.
5. Check: `loom status` shows the host repo published on silo.

### Scenes 2-7 live

Same lines as the scripted table above, typed to the real ada. The model's
words will differ; what to look for is the same: one-line cards for plain
changes, the reviewer's notes on the battery and Wi-Fi requests, the
rollback. If the model takes another route (it may not add the Bluetooth
line in scene 4), say so and switch to the scripted VM for that scene.

### Scene 8: "Reinstall from the repo" (1.5 min)

1. Note the host repo id (`loom status`) and that Steam, the theme and the
   dock setting are in place.
2. Power off; wipe the VM disk (or reinstall the laptop).
3. Boot the USB with `loom.host=<id>` on the kernel command line (or type
   the id at the prompt); type the SEK when asked.
4. Same desktop, same Steam, same theme, same dock. ada has to sign in again
   and its old conversations are gone; the machine is identical.

### Scene 9: "No agent, same rules" (1 min, optional)

1. Network off (bar › Network › off). The chat shows ada offline.
2. Menu › Appearance › Menu Bar › Bar Indicators › Clock › "Sunday 2:30 PM"
   (the design's "24-hour" row; omarchy's rows name the format): no agent to
   ask, so the row's how-to opens (Do it yourself).
3. **Open host repo** (`~/omanix-host` in the editor); make the edit the
   how-to shows; save; commit; **Apply** (`loom propose`).
4. The card appears (your own commit, no review); Approve; the clock
   changes. (`checks.human-commit` covers this path headless, with the
   resident disabled, and the `sudo loom-switch` path over ssh.)

### Record

| | |
|---|---|
| Date, place | |
| omanix tag / image SHA256 | |
| Laptop | |
| Scene 1 install time | |
| Scene 8 reinstall time | |
| What differed from the script | |
| Recording files | |

## If something goes wrong on stage

- The card doesn't appear: `SUPER + A` › the card row › **Show card**; or
  `omarchy-shell omanix.approval open`. The broker's log:
  `journalctl --user -u nuketown-broker`.
- ada is offline: the chat's **Sign in ada**; or switch to the scripted VM.
- A switch rolls back unexpectedly: `omanix why-failed` (or the chip) says
  which check; `loom card show` shows the record.
- Never improvise disk operations on stage; reinstall only through the USB.
