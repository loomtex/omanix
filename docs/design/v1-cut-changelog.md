# DESIGN.md rev 3 → rev 4: v1 scope cut (2026-10-28)

Josh: keep nuketown unchanged except for critical compatibility; forgo most security hardening in v1 (the input is ~always the user typing; a rogue install is the `curl | bash` risk users already accept). Rev 3 is in git history and the session scratchpad (`DESIGN.rev3.md`). Line count 2786 → ~2490.

**nuketown.** N1–N15 all deferred. A source check of nuketown HEAD found no change *required*; eight compatibility needs (C1–C8, §a.3) are met by loom config: `/persist` root, `@agents` mounted by nuketown via `btrfsDevice` (installer writes the btrfs UUID), one `secrets/agents.yaml`, the HM broker imported into the human's HM plus loom-created group/tmpfiles, a uwsm restart hook for the dialog, a `pkgs.unstable` alias for option docs, `portal.enable` for sign-in, and `sudo.commands = [ sudo-with-approval ]` so D8 never installs the password-less `sudoex-run` rule. N1 is recorded as a nuketown bug that affects signi today (O11).

**Change pipeline (§g, rewritten).** Resident commits → `loom propose --request` → root switchd builds the commit → nvd + git diff + a file-based flags line → reviewer (ordinary second resident, `systemd-run --uid=reviewer`, `claude -p`) → card in `omanix.approval` + nuketown broker `SUDO` dialog sent by root → Approve → watchdog-armed `test` → health → promote → push `master` with the host key. Activates exactly the store path it built. Undo/rollback/updates kept, simplified.

**Dropped to Appendix H:** root request ledger (`loom-chatd`), `Request-Id`, provenance escalations; human-signed approval merges, nonces, expiry, verification, `approve --card`, `owner-key-local`; facts engine, highlight list (D5 superseded), presentation truth table, `suspiciousText`; preflight VM; reviewer sandbox, egress proxy, fenced bundle, strict schema; `loom audit --from-silo` and the reinstall chain check; eval/fetch DynamicUsers; `stripRev`; threat table (replaced by §g.9 trust stance); W7.

**Kept unchanged:** installer (USB only, closed answers, hostgen), FDE/unlock/Secure Boot, SEK and rotation (phase 4 now an ordinary card), sops, silo enrollment and human-owned repo (D6), flash guards, release signing (D11), the omarchy fork, HM read-only dotfiles, overlays and make-it-stick, the intent menu, chat UX, catalogs, CLI.

**Decisions.** Added V7. D5 superseded. D8 restated (C8; switching doesn't use it). D10 notes card approval is a click. Open: O1, O3, O4, O6, O7 kept; O5, O8, O9 retired with the hardening; new O10 (nuketown dialog vs a card-native Approve button) and O11 (fix N1 in nuketown for signi?).

**Tests.** Dropped facts/provenance/replay/isolation/preflight/nuketown tests (Appendix H.9). New: `card-render`, `review-parse`, `nuketown-glue`, `approval-dialog`, `agent-sudo-approval`, a loom-side approval stub. New UNVERIFIED U37–U40 (broker dialog under uwsm, root `SUDO` request with multi-line text, `sudo.commands` restriction, `pkgs.unstable` alias).

**Demo.** Scene 4 "The README that wanted root" replaced by "Read the card" (battery request that also disables Bluetooth; reviewer flags it; reject with reason; resident revises). Key touches became Approve clicks.

**Work packages.** W1 becomes loom-side nuketown glue; W7 withdrawn; W8–W10 shrink. Critical paths: pipeline W0 → W1 → W8 → W10 → W21; installer W0 → W6 → W4 → W14 → W20; desktop W3 + W5 → W15 → W18 → W19 → W20 (now the longest).

---

# Rev 5 (2026-10-28): reviewed sudo, no switch daemon (V8)

Josh: a privileged switch service is more complex than a couple of sudoers entries (as on mino) and covers only one escalation; every approval, not just switches, should get an adversarial plain-English review, because a scratchpad script doing several things in one sudo is hard to audit from the command alone; fix the `sudoex-run` bypass. Rev 4 is in `scratchpad/DESIGN.rev4.md`.

**Dropped.** `loom-switchd`, its socket and the `loom-switch` group, `loom approve`, `pkgs/loom-review` (the run moved into nuketown, K5), rev 4's one-line `SUDO:` card text to zenity, H9's "nuketown as-is", O10, O11.

**nuketown (§a.3, now K1–K10, W1).** `sudoex-run` becomes a root-side wrapper (K1, was N1); `SETENV` dropped (K2); requests are root-written directories with argv as JSON and `REQUEST:<id>` on the socket (K3); script snapshots that run in place of the original (K4); approval reviewer (K5); swappable prompter, zenity default with review + Details (K6); request kinds with a root collector (K7); per-agent `sudo.approvalAllow` (K8); shim `--why` (K9); `signi-compat` (K10). All new behaviour defaults off; signi gets K1–K3. N1 and N6 left Appendix H.1; C8 rewritten (default wrapper rules are safe after K1/K2).

**loom.** `loom-switch` (root script) + `loom-switch-collect` (kind collector: bundle into the mirror, refusals, git diff, flags, `nvd diff` against `<out>`, `card.json`) + `loom-switch-request` (pkexec entry for the human, polkit `farm.loom.propose`); undo through polkit `farm.loom.undo`; `loom-switch-review` (switch prompt). Options: `loom.agent.sudo = "listed" | "any"` (was `"none" | "approval"`), `loom.agent.sudoCommands`, `loom.reviewer.promptDelay`; nuketown wiring in §c.3. Reviewer skip is now by requester (the human), not commit authorship.

**omanix.** `omanix-approval-prompt` is the prompter; the card UI gains the root-command card (§h.4); `[Approve]` is on the card itself.

**Pipeline (§g.3).** Every request: approval list → request dir + snapshots → kind collector → background review → prompter → run `argvRun`. Switch: `loom propose` builds as the resident, bundles, `sudo --why "<request>" loom-switch --proposal <dir> <out>`; the collector computes the diffs as root; `loom-switch` activates exactly `<out>` with the unchanged watchdog. New accepted limit (§g.9): `<out>` is the resident's build and is not re-checked against the commit; snapshots don't cover what a script reads at run time.

**Tests.** New: `nuketown-sudoex-bypass`, `nuketown-setenv-bypass`, `nuketown-argv-newline`, `approval-review-snapshot`, `approval-review-unavailable`, `approval-kinds`, `approval-card`, nuketown pure checks `signi-compat`, `approval-request-json`, `snapshot-rules`. Rewritten: `pipeline-e2e`, `approval-dialog`, `agent-sudo-approval`, `undo-rollback`, `human-commit`, `nuketown-glue`. U38 moot; U39 rewritten; new U41–U43.

**Demo.** New scene 5 "Explain this sudo" (Wi-Fi script with an unrequested line flagged); later scenes renumbered 6–9; `vm-demo-2..7`.

**Work packages.** W1 = nuketown approval changes (day one); loom glue moved into W11; W8 = loom-switch + collector; W10 = reviewer wiring; W18 adds the prompter. Critical paths: pipeline W0 + W1 → W11 → W8 → W10 → W21; installer W0 → W6 → W4 → W14 → W20; desktop W3 + W5 → W15 → W18 → W19 → W20 (longest).
