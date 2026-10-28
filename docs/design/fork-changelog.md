# DESIGN.md rev 2 → rev 3 changelog (fork + agent-first, 2026-10-27)

Inputs: Josh's direction V1–V6, standing D1–D12, drafts `fork/{trust,host,fork,ux}.md`, DESIGN.md rev 2. spec.md rev 16 still overrides everything; no installer credential copying, no in-place/kexec/Windows vectors, no login transfer were reintroduced.

## Structure
- New top level: 0 Overview (0.1 Vision V1–V6, 0.2 Hard calls H1–H19, 0.3 Layering, 0.4 Errata pointer), a Repositories, b Flake interfaces & mkHost, c Options, d Host repo, e USB installer, f Runtime, g Change pipeline & trust, h Agent surfaces & UX, i Testing, j Demo, Decisions (resolved + still open), Work packages.
- Rev 2's 36-row errata table is no longer reproduced; §0.4 lists which rows still apply and which were superseded, and points to rev 2 / reconcile-changelog.md.
- Section numbering in carried-over text was remapped (old g.1→g.4, g.2→g.3, g.3→g.7, g.4→g.8, g.5→g.9, g.6→g.11, g.7→g.12, g.8→g.13, g.9→g.14, d.3→d.5, d.4→d.6, f.3.x→f.4.x, f.4→f.5, h.1→h.8, h.2→h.9, h.3→h.10). All § references resolve to existing headings (checked).

## Carried over (corrected where needed)
- §a.4 silo F1–F8 and guards: "classification refuses" → "switchd refuses"; `authorized-keys-in-sync` → `keys-sync`.
- §d.5 repo id: unchanged.
- §d.6 sidecar: schema `loom.sidecar/v2`; `settings` map → closed `answers` set (hostname, user, locale, theme, defaults, apps). Unlock, SB, SEK, keys, `loom.agent.enable`, `loom.agent.sudo`, disk never in the sidecar.
- §e.1–e.10 installer: carried over; configure mint renders the plain-module template with `loom-hostgen` + `loom keys sync` instead of writing settings.json; passphrase-less existing software keys refused (D10) instead of the `passphrase = false` + auth_self path; TUI step 4a now asks "Use an AI agent? yes/later/no" before the D8 sudo question; install commit written by hostgen into machine.nix/keys.nix/hardware.*/configuration.nix; first-boot secrets-prompt commits are proposed as cards (was Tier A); onboarding points to §h.7; e.10 verifies `fork/` instead of `upstream/`. New §e.5a: hostgen renderer, answer→line table, the three commits (mint, apply answers, install), install records accepted only as baseline.
- §e.6/e.7 unlock matrix and FDE: unchanged except Tang URLs come from an advanced TUI screen, not sidecar settings.
- §f.1 impermanence: unchanged plus module/plugin persistence rules and the guarded pattern.
- §f.4.2 HM table, §f.4.3 state layout, §f.4.7 shell.json rebase, §f.5 theme switching: carried over; `extraModules`/settable references, the `setup-git` XCompose writer and `defaults/agent` removed; overlay headers and theme persistence now say "make it stick".
- §g.11 enrollment (D6): unchanged flows; key table merged with the trust draft's key-powers table (CODEOWNERS never agents; only human keys count as approval; agent may force-push/delete gate/*, U15).
- §g.12 reinstall/fork/rotation: settings.json → machine.nix/keys.nix; rotation commands go through cards; passphrase-less key refusal.
- §g.13 script guards: unchanged.
- §g.14 SEK (D12): unchanged derivation/token/rotation, except phase 3 writes machine.nix + `loom keys sync`, and **phase 4 is now a human-signed commit + `loom propose` → escalated card → human-signed approval merge** (reviewer skipped because every commit is human-signed).
- §i.2 VM tests: fde-*, sek-rotate-crash, fde-tpm2-requires-sb, boot-lanzaboote, impermanence, hm-reclaim, sops, repo-id, silo-enrollment, installer-*, flash-guards, verity, nuketown tests kept (installer-e2e-fresh now approves its first card by passphrase).

## New
- §0.1/0.2: V1–V6 and hard calls H3–H11, H14, H15, H19 restated for the fork, resident, reviewer, facts, provenance, presentation.
- §a: omanix `fork/` tree; loom packages loom-chatd, loom-agent-bridge, loom-facts, loom-review, loom-egress, loom-fetch, loom-card-tty, hostgen; `schemas/`; nuketown N8–N13.
- §b.3 mkHost returns a nixosSystem (host draft); §b.4 plugins are modules (conventions, add/remove flow).
- §c: `loom.keys.*`, `loom.chat.*`, `loom.reviewer.*`, `loom.highlight.{extra,portOptions}`, `loom.switch.{approvalTtl,keepClick,preflight.*}`, `loom.update.inputs`, `loom.agent.{enable,harness,loginCommand,chat.*}`; omanix `chat.*`, `approval.*`, `welcome.*`, `shell.plugins.*`, `runtime.absorbed.*`, `home.appOwned`, `dns.*`, `branding.*`, `hooks.*`, `hardware.quirks.*`; §c.3 the two nuketown residents.
- §d.1–d.4: plain-module host repo (configuration.nix, home.nix, machine.nix, keys.nix, hardware.*, modules/), who-writes table with the facts each file raises, generated trust files from keys.nix, host CLAUDE.md.
- §f.2 the fork: classes + decision rule, provisional counts, subsystem table, pinned input + patch queue mechanics, P1–P15 patch list, hardware quirks as modules, porting report (not a gate), fork mirror, MIT/branding.
- §f.3 GUI-vs-agent split table; §f.4.4 reduced runtime-writer table (only KEEP-AS-GUI writers); §f.4.5 rewritten session init/first login (runtime.json typed snapshot; no skill links into the human's harnesses); §f.4.6 make it stick + settle; §f.4.8 reset/edit/doctor; §f.4.9 checks.
- §g.1–g.10, g.15: principals, chatd provenance, the 16-step pipeline, facts (highlight list, schema, computation, escalation rule), reviewer isolation/bundle/output, card + presentation rule + fatigue controls, approval merge format/production/verification, activation/watchdog, Update ready cards, undo/rollback table, 15-row threat table.
- §h: rules, components, chat surface (shape, transport, events, storage, attachments, sign-in), card UI (routine/escalated), intent menu (intents.toml, build, runtime flow, keybindings), chips / options browser / agent preview, first boot + "Use an AI agent?" modes, CLI verbs (no policy refusals), catalogs, skills, no-agent mode and human-only tools.
- §i: new pure checks (keys-sync, hostgen-escape, facts-cases, presentation-rule, review-validate, fork checks, runtime-writers); new VM tests (pipeline-e2e, replay-refused, sign-from-nonroot-refused, ledger-forgery, reviewer-isolation, reviewer-cannot-deescalate, reviewer-down, undo-rollback, update-card, card-latency, chat-socket, approval-focus, make-it-stick, human-commit, plugin-fixture, vm-demo-2..6 incl. the injection scenario); reviewer corpus; one consolidated UNVERIFIED table U1–U36.
- §j demo script (8 scenes).
- Decisions: V1–V6 added; D2, D5, D6, D8, D9, D10, D12 rewritten for the new model; still-open O1, O3, O4 kept (O2 resolved by D12), O5–O7 added.
- Work packages W0–W21 re-planned (new: W7 facts, W9 chatd/bridge, W10 reviewer, W18 shell plugins + intent menu, W21 demo); three critical paths stated.

## Deleted (dropped model)
- H3 settings.json single edit surface, H4 three tiers, `host.nix` escape hatch.
- `settings.json`, `loom.lib.settings.module`, settable registry `loom.settings.settable.*` and all `settable:*` annotations, JSON Schema generation (`schema/settings.schema.json`), `checks.{schema,settable-review,settings-guard}`.
- Tier A/B/C, `loom policy classify/explain`, `policy-classify-cases`, `policy-view-golden`, `policy-enforcement`, the empty `approve <sha> view:<hash>` commit, Tier-A `data.yaml` rule.
- `loom.policy.{extraProtected,protectedRepoPaths,humanKeyKind}` (protected list → loom highlight list + `loom.highlight.extra`, not a gate).
- `loom.switch.confirmProtected` (→ `keepClick`), `autoUpdate = "stage"`, unattended Tier-B omanix bumps, "loom rollback always allowed".
- `loom.agent.mode` ("user" contradicts V3), `loom.host.{humanKeys,hostKey,agentKeys}`, `loom.secrets.recipients.human`, `humanKeys.*.{kind,passphrase}`, `loom.home.stateVersion`.
- `upstream/` pipeline (pin.toml, manifest, overrides, packages.toml, install-map.toml, writers.toml), `checks.{upstream-pin-tag,upstream-drift,script-map-complete,writer-map}` as gates, `bump-omarchy` skill, `omarchy-install-*`/`omarchy-pkg-*`/`omarchy-update*` shims, the D9-overridden upstream omarchy skill and its links into the human's harnesses.
- `omanix keep`, `omanix apply`, the class-c writer overrides (defaults, language, git identity, dictation-use) and their `omanix set` redirects, `omanix.home.extraModules`, `omanix.agents.harnesses.*`, `omanix.defaults.agent`.

## Reconciliation calls between drafts
1. Provenance: one root `loom-chatd` (recorder + relay, trust draft) instead of `loom-askd` + an untrusted bridge recording (UX draft); the UX draft's `loom-agent-bridge@` survives as the agent-side harness host behind chatd.
2. Trailer `Request-Id:` (trust), not `Ask:` (UX); ids `r-<ULID>`.
3. Reviewer user `reviewer` uid 1101 (trust), options under `loom.reviewer.*` (host/UX); no separate `loom-reviewd` daemon — switchd spawns the review unit.
4. Approval = human-signed merge with `Loom-*` trailers (trust), not `approve <sha> facts:<sha>` (UX).
5. Review output schema from trust (`oneLine/summary/matchesRequest/mismatches/concerns/recommendation`).
6. **Undo and rollback-to-generation require a signature** (trust; V4 "every switch"); UX draft's key-less human-uid rollback rejected. Reviewer skipped for rollbacks to approved trees, so undo is one touch.
7. Reviewer also skipped for all-human-signed terminal proposals (new; avoids every no-agent card escalating).
8. Eval/build failure → no card (UX); failed preflight check → reject-only card (trust).
9. `loom.switch.preflight.vm = auto|always|never` (UX's `vmCheck` semantics, trust's option path).
10. `loom propose` replaces `loom switch`; N12 sets `nuketown.switch.command = "loom propose"`.
11. Chat keybind `SUPER + A` (fork draft, pending U25) instead of `SUPER + SHIFT + A` (UX).
12. `loom.keys.*` single source with generated trust files (host draft) adopted in the trust sections.
13. Passphrase-less software human keys refused everywhere (task: "software keys need a passphrase"); rev 2's `passphrase = false` + auth_self gesture removed.
14. N7 (chat transport in the nuketown daemon) dropped: the bridge is a loom unit, nuketown stays generic.
15. Make it stick: snapshot generated as the human and attached (fork/UX); typed part validated by chatd and shown to the reviewer; settle per key for kv overlays (host draft) and by `omanix.runtime.absorbed.<area>` sha for whole-file overlays (fork draft).
16. Keyboard layout picker override writes `overlay/hypr/input.lua` (not the HM-owned keyboard-layouts file); added U28.
17. Human working copy `~/omanix-host` created on demand (fork U7 resolved).
18. `provenance.kind = "maintenance"` added for host-signed tool commits (first-boot secrets-prompt); `agent-choice` surface escalates.
19. Facts gained a `session` block (UX "session" category) alongside the trust draft's human exec surfaces.

## Verification fixes (2026-10-27)

51 reviewer findings were checked against DESIGN.md and the cited sources (nuketown module.nix/approval-daemon.nix, seed silo hooks.nix, omarchy bin/ and shell/ at the fork tree). All 51 were confirmed. Four are duplicates of other findings and were fixed together with them: evaluated-vs-activated (blocker + minor), timezone (2), Undo gestures (2), and base-list coverage (major + V5/D5 major). None was skipped.

### Trust pipeline (§b.3, §g)
- **Preflight VM:** the proposal's `system.build.vm` runner and its qemu package/options/shares are never executed. switchd builds only the vmVariant guest toplevel and boots it with the running generation's `$current/loom/preflight-vm` in a DynamicUser, PrivateNetwork unit with `/dev/kvm` only and a read-only `/nix/store`. loom's vmVariant clears LUKS, disko, impermanence, sops and SB. New: `checks.preflight-vmvariant`, VM test `preflight-runner-untrusted`.
- **Activate what was built:** `facts.proposal.toplevel.{drvPath,outPath}` is bound by `Loom-Facts`; step 15 activates that exact outPath, and the approval merge is never re-evaluated (§g.7.3 rule 9). mkHost sets `configurationRevision = self.narHash` and strips rev/revCount/lastModified from `inputs.self`. The old view comes from the deployed record's tip.
- **Facts compare derivations:** store paths are only displayed as `<pname>@<origin>`; change detection uses `.drv`. New `rebuilt` fact ("same name, different derivation") for root unit Exec, wrapper sources, PAM, polkit, kernel, initrd and base packages.
- **Effects diff:** new deny-by-default `effects` fact over the built `etc/` tree, `sw/share/polkit-1` and dbus system services, the parsed final nix.conf, the nftables ruleset and the initrd. The base list now covers whole `security.*`, `boot.*`, `services.openssh.*` and `nix.*` subtrees, plus udev, environment.etc, dbus packages, nftables, autologin, user password options, userActivationScripts, generators and shell-init options.
- **Units:** units are merged with their drop-ins; all unit types and generators are included; a "privileged" unit (root/human User, `+`/`!` exec prefixes, ambient caps, supplementary groups) escalates on any change.
- **Inputs:** new `transitiveOverride` (critical) for transitive nodes under trusted releases, the requirement that a tag's target equals `locked.rev`, `unreachableRev` (critical), and high-severity rev changes outside `trust.releases`. Daily updates default to the trusted-release inputs only.
- **Human exec surfaces** are now critical. Added: hypr Lua (any change, not only `hl.exec` lines), extraLua/fileLua/theme.extra and the inputs that feed them, hm-session-vars, activation bodies, package autostart/D-Bus/user units, PATH collisions, and shell-init options. New nuketown N14 restricts the `host-shell` polkit rule to agent targets.
- **Provenance:** pasted spans are recorded and fenced as untrusted (and escalate); the preceding agent turn is attached to every reply; `stale` (over `loom.chat.requestMaxAge`, cross-thread, or already used) now escalates.
- **Undo/rollback:** a GUI or terminal Undo records a ledger `undo` turn, and switchd makes a host-signed revert, so the approval is the one gesture. An agent-prepared rollback is "prepared by <agent>, not requested", the reviewer runs, and the card escalates. The Change password commit is also host-signed with a `tool` ledger turn.
- **Approval production:** no git runs as the human. SIGN carries tree, parents, author, committer and message; the broker returns only an `ssh-keygen -Y sign -n git` signature, and switchd assembles and writes the commit.
- **Update cards** are routine when every changed input is a verified release; the reviewer is skipped for them (step 10 case c). This matches g.9, h.4, `update-card`, W8 and W19.
- **Reinstall** runs `loom audit --from-silo` and installs the last valid approval merge (red screen otherwise). New open question O8: remove the host key from CODEOWNERS.
- **Watchdog ordering:** the per-session `hyprctl reload` moves to step 5a (after `test`, before the watchdog); rollback reloads again.
- Other changes: the `auth` event needs a portal token, https and an allow-listed host, and opens without xdg-open. `repo-exec` path class (.claude/settings, hooks, .envrc, .vscode, .mcp.json, .gitattributes, .githooks) escalates. The D8 residual is restated as disabling the pipeline's guarantees, with a deny-list caveat. Reviewer login env (CLAUDE_CONFIG_DIR, HTTPS_PROXY) and the wipe rule are specified. The bridge is a `.service`. `refs/dit/*` is stated in H6/d.3/D6, and switchd ignores it. New threat row 16.

### nuketown (§a.3, §c.3)
- The exact `sudo.enable` mapping, with an assertion that D8 "approval" requires N1. N2 is restated as a replacement with its own tests, and the broker socket and group are decoupled from `sudo.enable`. N12 is marked a convenience only. New N14 (host-shell target restriction) and N15 (NixOS `systemd.user` broker unit). The `omanix-resident` group is now added by omanix's residents.nix, not by loom.

### Fork and desktop (§f)
- KEEP-AS-GUI scripts that needed root (update-time, restart-trackpad, restart-audio, brightness-display-apple, toggle-hybrid-gpu) get polkit/unit/udev mappings. Tailscale operator → P18. New `privilege` column; fork-classify fails on an unmapped `sudo`/`pkexec`.
- Read modes: read-only `add/` readers for default-*/dns/channel-current. The call-graph post-check now scans QML/JS string literals. Clock middle-click → P19.
- Timezone is AGENT-INTENT only (picker-then-intent). The GUI rows were removed from f.3, f.4.4 and h.5.1.
- HM ownership: omanix sets `.source` at normal priority (force-allowlist); `checks.home-owned` is an explicit `definitionsWithLocations` check; U31 rewritten.
- `omanix try` is limited to a typed allowlist rendered from templates; new `try-injection` test.
- Weather geo lookup → P17 (`omanix.weather.geoUrl`, default null); `omarchy.org` hostnames are in the post-check.
- Patch files are numbered by P-id (branding = P16).
- The menu extensions sentence was removed (the file is HM-owned; use `omanix.menu.items`).
- The untrusted-tree statement was reworded (themes-render runs in the sandbox; shipped code runs as the human). f.5 class a/b labels were replaced.

### Install, tests, work packages
- First-boot step 2a `owner-key-local` (`ssh-keygen -K` for resident FIDO2, otherwise approve elsewhere); `loom-approve-sign` matches `~/.ssh` keys against keys.nix when `localPath` is null; new `installer-e2e` preconfigured variant.
- canokey via `qemu.override { canokeySupport = true; }`, unstable leg only. Nested-KVM tests declare `requiredSystemFeatures`, and others use a stubbed runner. `card-latency` became a non-gating benchmark, and the c.1 `auto` definition now matches U14.
- New tests: `provenance-facts`, `desktop-intents`, `nuketown-hostshell-target`, `nuketown-broker-peercred`, `try-injection`, `preflight-runner-untrusted`, plus about 25 new `facts-cases` fixtures.
- Work packages: ref-* fixtures move to W15; menu-intents and the intent/indicator asserts move to W18; make-it-stick, the theme-switch stick case and the crash prefill move to W21; W19 depends on W18; ledger-forgery is split (W9 / W10 `provenance-facts` / U18 in W18 `chat-socket`); the chatd watchdog case moves to W10; W2 (test) is added to W10 and W14; W21 gets a W20-gated manual part. Writer rows move to `fork/writers/{desktop,theme}.toml` so file ownership stays disjoint. Unowned modules (branding/hooks/fork/persist/weather) are assigned, and `loom user passwd` / `loom hw regen` are added to h.8, W6 and W14.
- The spec rev 16 line is scoped to install scope, with a list of the superseded Agent-security clauses. Demo scene 8 uses the clock-format change (store-resident); scene 2 states the nested-KVM prerequisite.
