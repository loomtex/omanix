# DESIGN.md reconcile changelog (2026-10-27)

Target: /agents/ada/projects/omanix/docs/design/DESIGN.md (1224 → ~1693 lines). Pre-edit copy: scratchpad/reconcile/DESIGN.before.md. The edits were applied by scratchpad/reconcile/apply.py, which asserts every anchor matches exactly once, plus two manual stale-line fixes.

## Header
- Rev 2. Inputs now list Josh's resolved decisions D1–D12 as overriding the panel.

## §0 Overview
- H6, H7, H12 replaced (security.md): system-encryption-key slot, one recovery secret, human key creates the repo, no silo change in v1.
- H9 replaced (d9.md): HM read-only dotfiles, writers redirected to `~/.local/state/omanix/overlay/`. H2 reason text replaced (d9.md).
- H1 tagged D1. H8 now says omarchy is pinned by release tags only, from v4.5.0-rc2 (D2). H10 adds "no Seed-side builder in v1" (D3). H11 says lanzaboote is the supported, CI-tested alternative (D7).
- New H13 (D8): agent sudo is an install-time question, default off, typed and protected.
- §0.2 layering: the seed line is now "S3, S4 (v1); S1, S2 later". The loom layer adds HM wiring and the system encryption key.
- §0.3 errata: rows 7, 12, 15, 20, 31, 33 and 35 (security) and rows 10 and 14 (d9) were rewritten. A new row R records the reconcile pass.

## §a Repositories
- a.1: `upstream/writers.toml` replaces `mutable-paths.txt`. `pin.toml` is tag-only (D2). `lib/home/*`, `modules/omanix/home/*` and `language.nix` were added, `seed.nix` was removed, and `pkgs/omanix-overlay` was added.
- a.2: loom gains `modules/loom/home.nix` and its HM wiring paragraph, `loom-sek` (in loom-cli) and the `loom-askpass` package.
- a.4: fully replaced (security). v1 makes no silo behavior change, only S3/S4. S1 and S2 come later, and S1 needs the multi-owner pre-receive fix. loom-side guards were added: HEAD check, never delete `.authorized_keys`, push only to master and gate/*.

## §b Flake interfaces
- loom inputs: nixpkgs unstable→26.11 with 26.05 CI (D1), HM follows nixpkgs, **lanzaboote input added** (D7).
- The omarchy input is release tags only, ≥ v4.5.0-rc2, with `checks.upstream-pin-tag` (D2).
- New note: no Seed-side builder (D3).
- `loom-askpass` and `omanix-overlay` were added to the package outputs.

## §c Option tree
- The conventions bullet "no HM" was replaced by the d9 HM conventions.
- c.1 changes:
  - `humanKeys` submodule is now {key, kind, owner, localPath};
  - unlock-methods text: recovery is the SEK slot;
  - new `loom.secrets.recovery.fingerprint`;
  - settable `class` is now `data | session-code` and informational only;
  - `protectedRepoPaths` comment: `.silo/` is reserved for S1;
  - **`loom.policy.humanKeyKind` removed** (D10);
  - `loom.agent.sudo` is now `enum ["none" "approval"]`, install, protected, not settable from the sidecar (D8);
  - `loom.home.*` added;
  - `boot.loader` annotated D7, `extraProtected` annotated D5;
  - note added: uid 1000 fixed.
- c.2: `omanix.seed.refreshOnBump` was removed. Added: `omanix.home.{enable,overlays,extraModules,files}`, `hyprland.gdkScale`, `defaults.dictation` and `language`. `human-session-code` was renamed to `session-code` (informational). `hyprland.settings` now targets HM `looknfeel.lua`.

## §d Host repo
- d.1: the `.silo/owner` line was removed. `.authorized_keys` and CODEOWNERS now carry the enroll key in the initial commit only, and an owner note was added. The settings.json example now uses `kind`/`owner` and adds `secrets.recovery.fingerprint` and `agent.sudo`.
- d.4: fully replaced (security). Security options are not settable from the sidecar, `SEK1-` is a rejected pattern, and the enroll key's powers and `revoke-enroll` are described.

## §e Installer
- e.1: the ESP note mentions lanzaboote. Release signing follows D11: YubiKey, the cache key on signi in sops used by the release skill via approval, and no CI secrets.
- e.2: fully replaced (security). The owner key makes the first push, the D8 sudo question was added, software keys need a passphrase and the wording no longer claims they "lower the tier", and `revoke-enroll` was added. A D3 no-builder paragraph was added.
- e.3: the cache key row is tagged D11.
- e.5: step 0 replaced. Fresh mode takes the owner as FIDO2 on this machine or a generated software key, and a pasted pubkey can only be an additional key. New "Owner key generated on this machine" block, with `~/.ssh` not managed by HM. Steps 4, 4a (agent sudo) and 5 (system encryption key) replace the old recovery kit with its two secrets.
- e.6: the Recovery key row became the System encryption key row. Rules and generated config were replaced (`loom-askpass`). The TPM2-automatic and FIDO2 rows now say "system encryption key".
- e.7: fully replaced. A `loom-sek` slot and token replace systemd `--recovery-key`.
- e.8: steps 4, 5, 6, 9 and 10 were replaced. The install commit writes the final key files, there is a fresh-mode owner push, and the summary shows the owner key and agent sudo. Step 1 adds the lanzaboote `pkiBundle` variant (D7).
- e.9: step 2 is now "Enrollment catch-up" (enroll-retry + `repo-publish`). Onboarding confirms that the SEK is written down.
- e.10: release signers are Josh's YubiKey keys (D11).

## §f Runtime (D9)
- f.1: the "Human home" paragraph was inserted after "Nuketown handles agent persistence." The existing correctness list was kept.
- f.2, f.3 and f.4: fully replaced by the d9 versions. f.3.1–f.3.8 were demoted to `####`. The d9 UNVERIFIED list was added as f.3.9.

## §g Change pipeline
- g.1: the `loom.*` view line adds `secrets.recovery.*` and `agent.mode`, plus a note on agent sudo. A paragraph on normalizing HM activation was added.
- g.2: Tier step 3 was replaced. The software-key `session-code` exclusion was removed (D10). A "Refused" class was added for deleting `.authorized_keys`/CODEOWNERS and for commits that don't have exactly one owner. The protected-list paragraph is marked as resolved D5.
- g.3: step 3 adds approval by software-key passphrase.
- g.4: the watchdog adds the `hm-activation` check.
- g.6 and g.7: fully replaced. Mint, enrollment and fresh pushes now cite the silo facts F1–F7. The key table gains a SEK row and drops the enroll-as-owner row. Reinstall and fork use the SEK. Rotation now has `rotate encryption-key` and `add-human --generate`, and there is no key-kind downgrade.
- New **g.9 System encryption key (D12)**: encoding, HKDF derivation, `loom-askpass`, rotation phases, and the `sek-rotate-crash` test.

## §h Agent surfaces
- h.1: the context and options rows were replaced (d9), keep/reset/edit rows were added, and the loom row notes that the secret steps refuse `--json`.
- h.2: the `keybinds.json` row was replaced and a `home.json` row was added.
- h.3: two AGENTS.md rules were added. Host CLAUDE.md item 2 was replaced. The omanix, diagnose-unit and rotate-keys skills were extended. "Agent isolation" was replaced (D8 typed option and default; agent never sees the SEK or the human key).

## §i Testing
- i.1:
  - eval adds the `agent-sudo-approval` and `lanzaboote` fixtures, and the channel split from D1;
  - upstream: the d9 row plus `upstream-pin-tag`;
  - new `home` row;
  - policy row merged from both drafts: extraLua with a software key → A, not C (D10); `extraProtected` change → C (D5);
  - the security row was replaced, adding `sek-vectors` and `hm-unmanaged-paths`;
  - lint adds the omanix-overlay and writer-scanner pytest.
- i.2:
  - replaced rows: fde-*, silo-enrollment, installer-e2e, reinstall/fork, desktop-boots;
  - added: `sek-rotate-crash`, `installer-e2e-fresh`, `hm-reclaim`, `shell-json-rebase` and `boot-lanzaboote` (D7);
  - `theme-switch, seed-and-writers` was replaced by `theme-switch` + `writers-respect-hm`.

## Decisions
- "Decisions for Josh" (with recommendations, including the stale D6 "Needs S1", D9 "As designed", D10 "with the shrink" and D12 "Two secrets") was replaced by "Decisions (resolved 2026-10-27)". It has 12 rows, each giving the outcome and where the design implements it.
- New "Still open" table:
  - O1: the `omanix.home.overlays` default;
  - O2: the 160-bit SEK1 format vs the old 256-bit systemd recovery key;
  - O3: when S1 gets scheduled, since the v1 owner key can't be revoked;
  - O4: whether to require a second human key when the owner is a software key generated on the machine.

## Work packages
- W2, W4, W6, W9 and W10 were replaced (security). W5, W11, W12 and W14 were replaced (d9).
- W0 adds the D1 matrix and the D7 lanzaboote input. W3 adds the D2 tag pin and `upstream-pin-tag`. W4 adds lanzaboote and its tests (D7). W13 adds `eval-agent-sudo-approval`. W15 adds the D11 signing procedure and "no CI secret".
- Parallelism has new edges: W4 needs W6's `loom-sek`, and W11 needs W5's `loom.home`. The critical path is now W0 → W6 → W4 → W10 → W15.

## Stale-statement sweep
grep found no remaining hits for: skel seeding, seed.nix, refreshOnBump, mutable-paths (except "replaces mutable-paths.txt"), seed-and-writers, humanKeyKind (except its removal note), human-session-code, `hardware: bool`, tier shrink, "lowers the tier", recovery kit or recovery identity (except "replaces Recovery kit"), `.silo/owner` as a live file, `.owner_key = enroll`, S1 as required, the generated omanix.lua/omanix-pre.lua (except "no longer generated"), and "Decision D8" off framing.

Judgment calls:
- The d9 "Replaces §f.1 paragraph" block was inserted rather than used to replace anything, because nothing in §f.1 matched it.
- The d9 policy row's "extraLua with a software human key → C" contradicted D10. The security row's "→ A" was used instead.

## Verification fixes (2026-10-27)

Every issue was checked against its evidence first: the omarchy ref checkout at `bc220e7`, `seed/instances/silo/{shell,hooks}.nix`, the fontconfig 2.17.1 `fonts-conf(5)` man page, and DESIGN.md itself. All 28 were real. Two pairs were duplicates (silo F-table; rotation lock), and each pair was fixed by one edit. Fixed: 28. Skipped: 0.

1. Keyboard layout redirect (major), fixed. typing_setup.py:185-214 confirmed: it reloads, checks the live kb_layout, and its rollback deletes the file. The row is now a full override of `omarchy-setup-keyboard`: upstream picker, then `omanix set omanix.input.layouts` + apply, then the kb_layout check, then fcitx `live_set`. Removed `pending/keyboard-layouts` from §f.3.3 and the UNVERIFIED bullet from §f.3.9.
2. setup-git XCompose write (major), fixed. setup-git:7,62-87 confirmed. The Git identity row now covers the XCompose write: an override sends `set_compose_identity` to `overlay/xcompose`, and keep goes to loom.user.{fullName,email}. The smoke test is now `--name N --email E`, asserting both values, the overlay lines and the xcompose restart. setup-git was added to the §f.2 overrides list.
3. fontconfig directory include (major), fixed. The man page confirms that a directory include loads only `[0-9]*.conf`. The HM fonts.conf now includes the overlay **file** explicitly after `prepend_first`, and session init seeds it as valid XML. The input-method redirect is dropped, because `conf.d/` is not HM-owned (the row is now class a). Added an `fc-match`/`font-current` assertion to `writers-respect-hm`.
4. clamshell reader (major), fixed. clamshell:10,70-105,183-211 confirmed. Added a reader row and a second D9 patch (`monitor_rules` reads HM then overlay, and the last rule wins). Added `[[reader]]` rows to writers.toml, scanner reader detection and writer-map rule 7, plus a clamshell smoke assertion.
5. `keep` hypr order vs toggles (major), fixed. hyprland.lua require order and window-no-gaps.lua confirmed. Added the option `omanix.hyprland.fileLua.<f>`, emitted in the same slot as each per-file overlay (before toggles). keep maps known keys to options, otherwise to fileLua. extraLua is used only for the `hyprland` overlay. Added a keep-then-toggle assertion.
6. Upstream omarchy skill (major), fixed. SKILL.md:3-6,165-181 and provision-user:86-101 confirmed. Added an upstream `skill` stage that overrides `default/agents/skills/omarchy/{SKILL.md,hyprland.md}` with D9 guidance (sha-pinned, so drift is flagged). hm-owned-readonly now greps the shipped skills. Updated §f.3.5 step 3 and §h.3.
7. fix-nouveau-cursor (minor), fixed. all.sh:13 and fix-nouveau-cursor.sh:12-25 confirmed. Corrected the Provisioning row and added a quirk row: the script is dropped, and `hw-quirks.toml` `nouveau-cursor` emits the cursor setting into the HM looknfeel.lua. Added the script to the §f.2 drop list and a fixture to W13.
8. Scanner op vocabulary (minor), fixed. dictation-use:14,30-33 (`mv -f`) and xcompose.sh `tee` confirmed. Added the ops mv, install, tee, dd-of, redirect-gt/gtgt and tmp-mv, resolved by destination operand, with one pytest fixture per op. dictation-use was added to the defaults row (override to `omanix set omanix.defaults.dictation`) and to the §f.2 overrides.
9. alacritty import precedence (minor), fixed. alacritty.toml:1-20 confirmed, and alacritty documents that the importing file loads last. The HM alacritty.toml now holds only `general.import`, and the upstream settings moved to an imported `omanix-base.toml`. Added an overlay-beats-base assertion.
10. reinstall-configs drop vs override (minor), fixed. reinstall:11-12 and reinstall-configs:19 confirmed. Removed it from the drop list, so it is an override mapping to `omanix reset --all`. `omarchy-reinstall` is also overridden to drop `reinstall-pkgs`.
11. loom-sek token schema (major), fixed. Defined one schema `{type, keyslots, v, fp, salt, state}` in §g.9. §e.7 references it with `state: active`, and rotation phase 2 imports it with `--key-slot <newSlot>` and `state: pending`. sek-rotate-crash now asserts that the rescue path unlocks with the new SEK.
12. Rotation crash/resume (major), fixed. Phase 2 records `slotsBefore`/`oldSlots`, tests every slot with the new key before adding one, writes `newSlot` before the token import, and skips existing tokens. Added a pending cleanup (orphan pending tokens and slots) used by start-over, `--abort` and phase 1. Phase 5 wipes `oldSlots` plus every slot that opens with the old key when it is available, and verifies that every slot is accounted for. Table and prose now agree: resume means a full retype of R' from paper, and start-over is allowed only before phase 3. Phase-2 sub-step crashes were added to the test.
13. Owner squatting in offline fresh mode (major), fixed with option (a). Confirmed in shell.nix:64-73, and recorded as F1/F8. Minting a fresh id inside repo-publish (option b) was rejected because `loom.host.id` is already the SEK/LUKS salt at install time. Instead the agent units are gated on `repo-publish.done`, which the installer writes whenever the repo is already human-owned. repo-publish runs the not-found pre-check immediately before the push, detects a foreign owner, and offers `loom fork`. Added a squat variant to installer-e2e-fresh.
14. revoke-enroll (major), fixed. hooks.nix shows no fast-forward or content check on master (now F4). revoke-enroll lists non-human-signed commits since the sidecar commit, rewrites both files to the exact human-only set, and recommends re-mint if master moved (`--reuse-anyway` to override). Updated §d.4 and added silo-enrollment case (8).
15. SEK paper check (major), fixed. The installer (§e.5 step 5) and rotation phase 1 now require the complete key typed back from paper, checked by fp. Phases 3b and 5 are gated on `paperVerified`. The "Shown once" text was updated. installer-e2e asserts that a retype with one wrong group is rejected.
16/24. Rotation lock deadlock (minor; duplicate), fixed. The rotation tool no longer holds switch.lock. `sek-rotation.json` is the marker: from phase 1 until done/abort, switchd step 1 admits only the recorded `commit` and answers everything else with exit 5. Phase 4 records `commit` before calling `loom switch --commit`. Both §g.4 and §g.9 were updated.
17. ssh-agent approval bypass (minor), fixed. menu.jsonc:258 (gcr-ssh-agent) confirmed. Approval signing now runs with `env -u SSH_AUTH_SOCK` and the `gpg.ssh.program=loom-approve-sign` wrapper, which always uses the private key file at `localPath`.
18/20. F1–F7 undefined (minor/major; duplicate), fixed. Inserted a silo-facts table into §a.4 with shell.nix/hooks.nix line citations. It has F1–F7 and adds F8 (paths are pusher-chosen). F4 now also states that there is no fast-forward or content check. The §a.4 cross-reference was fixed.
19. add-human --generate passphrase on argv (minor), fixed. Generation everywhere feeds the passphrase through a pty to ssh-keygen's prompt and never through argv or env. On the installed system with a resident agent, a passphrase equal to the login password is refused, and add-human refuses `--json` and the agent uid.
21. agent.sudo owner / path==option (major), fixed. agent.sudo was removed from W9. The new W9b owns `modules/loom/agent.nix` (nuketown sudo wiring, the resident assertion, repo-publish gating), `firstboot.nix` (runner), `user/locale/nix/hardware.nix` and the loom eval fixtures. W0 implements default.nix and settings.nix fully.
22. W6 deps vs acceptance (major), fixed. Split into W6a (lib, secrets, keys CLI; deps W0, W5 test) and W6b (rotation + sek-rotate-crash; deps W6a, W4, W8, W1 test). W4 now depends on W6a, and the critical path was updated.
23. W10 deps (major), fixed. W10 deps are now W4, W5, W6a, W9, W9b, W8, W7, W1 (test). The critical path line now includes W7 → W8.
25. Finish message (minor), fixed. The §e.8 step 10 text now depends on state: enrollment verified, enrollment pending (the stick key still works, see revoke-enroll), or fresh (no sentence).
26. Passphrase-less existing key (minor), fixed. Added a `humanKeys.*.passphrase` field. configure detects passphrase-less keys and warns. §g.3 signs with the key at `localPath` and uses an explicit click + `auth_self` gesture for passphrase-less keys. Tiers are unchanged (D10).
27. lanzaboote parity (minor), fixed. Made loader-conditional the §e.8 finish install step, the §e.6 PCR 7 justification (the lanzaboote signed UKI covers kernel, initrd and cmdline) and the §g.4 boot-counting note (neither loader has boot counting enabled by loom).
28. Writer survey vs D2 pin (minor), fixed. The §f.3.4 heading and an intro paragraph mark the table PROVISIONAL until the scanner runs at v4.5.0-rc2. W3 now regenerates it there, and W11 acceptance requires writer-map, hm-owned-readonly and home-files-golden green at `v4.5.0-rc2` specifically.
