# omanix: design

Rev 5.1, 2026-10-28 (v1 scope cut; reviewed sudo; approval service user built). Authors: Ada, with Joshua Perry.

**Rev 4 in one paragraph.** Josh (2026-10-28): keep nuketown unchanged except for critical compatibility, and forgo most security hardening in v1, because the input is almost always the user typing into a textbox and a rogue plugin is the same risk as `curl | bash`. So v1 keeps the user-visible promise of V4/V5 (every switch is a card the human approves; a reviewer agent writes the summary; watchdog and rollback) and drops the machinery that defended it against a compromised resident: the request ledger, human-signed approval merges, nonces, the deterministic facts engine, the preflight VM, the reviewer sandbox and every nuketown change. Nothing is deleted: each dropped mechanism has a short entry in **Appendix H** pointing at its rev 3 section. Rev 3 is in git history and in `scratchpad/DESIGN.rev3.md`; the cut is listed in `v1-cut-changelog.md`.

**Rev 5 in one paragraph.** Josh (2026-10-28, later): the root switch daemon was rev 3 machinery doing a sudoers rule's job, and it covered only switching. Rev 5 drops `loom-switchd`. The resident switches with `sudo loom-switch <result>` through nuketown's approval sudo, mino-style: a short list of commands it may ask for, each approved by the human. **Every approval, not just switches, gets a reviewer analysis**: the root-side wrapper snapshots any script the command runs, the reviewer resident explains in plain English what will happen and what it can't see, and the card (Quickshell on omanix, zenity elsewhere) shows that above the raw command. A switch is the same request with a richer card (nvd and git diff computed by root). So nuketown changes in v1 (§a.3 K1–K10): the `sudoex-run`, `SETENV` and request-line bypasses are fixed, and a swappable prompter, request kinds, an approval list and the approval reviewer are new options that default off, so signi keeps today's dialog plus the fixes. Rev 4 is in `scratchpad/DESIGN.rev4.md`; the changes are in `v1-cut-changelog.md` (rev 5 section).

**Rev 5.1 in one paragraph.** Josh (2026-10-28, later still): instead of a root wrapper, an unprivileged **`nuketown-approval` service user** does the request work and reaches root only through `sudo`, so every privileged step it takes is logged by sudo and root itself only runs the approved command. This is **built** (W1, nuketown `6b4960c`, `eafb45f`, `6b9e5c1` on top of `7a2b84e`): agents' only sudo rule starts `nuketown-approve` as that user; it snapshots scripts by reading them *as the requester*, runs the reviewer with a timeout before asking, talks to the broker (whose socket group now holds only the service user), runs the command, and writes a journal record and an audit copy. §a.3, §c.3, §g.1, §g.3, §g.4, §i and W1 describe what was built; request kinds (K7), human/timer requesters (`--requester`) and `NUKETOWN_APPROVAL_DIR` are still to build (W1b, needed by W8). Rev 5 is in `scratchpad/DESIGN.rev5.md`; changes are in `v1-cut-changelog.md` (rev 5.1).

**Inputs.****Inputs.**
- `spec.md` rev 16. It is authoritative for **install scope and the excluded vectors** (below) and overrides this document on those points. Its "Agent security" clauses are **superseded by V4/V7**: every switch needs the human's approval on a card (no agent-only path, no protected-set gate); the "one approval gesture: the existing GUI sudo dialog" is kept literally, as nuketown's approval dialog (§g.3).
- `design/facts.md` (toolchain facts, verified 2026-10-27).
- Josh's direction V1–V8 and the standing decisions D1–D12.
- DESIGN.md rev 3 and the four fork drafts behind it (`draft-{trust,host,fork,ux}.md`, `fork-changelog.md`).

**Scope (spec rev 16).**
- Install is only from a standard bootable USB installer image, onto a whole disk.
- The installer never copies or embeds credentials.
- Secrets are sops-encrypted to keys generated on the host, or prompted for. No unencrypted secret is ever committed.
- **Not designed, on purpose:** in-place conversion of a running OS, kexec/infect vectors, Windows boot-chain vectors, and moving an existing AI-assistant login or token to the new machine. On the installed machine, each agent (the resident and the reviewer) signs in through its own normal login flow, or not at all.

---

## 0. Overview

### 0.1 Vision (V1–V8)

| # | Direction | What it means in this design |
|---|---|---|
| V1 | omanix is a proof of concept and a conversation piece: **what omarchy would look like if it had started on nix**. It **forks** omarchy at `v4.5.0-rc2`. | omarchy is the product spec and the asset source: Quickshell shell QML, themes and templates, default Hyprland Lua, menu data, keybinding defaults, branding, hardware-quirk knowledge. Its bash state-mutation layer (package install/remove, migrations, settings writers, refresh/reinstall, provisioning, update) is replaced by nix. Upstream drift is an optional **porting report**, never a `nix flake check` gate (§f.2.7). |
| V2 | **Agent-first.** The agent is the primary UI for change. | Mutating human tools are dropped in favour of asking the agent, except where asking would be onerous: continuous controls, instant toggles, visual browsing with live preview, and everything needed to reach or repair the agent (§f.3). GUI changes are runtime state; "make it stick" is a request to the agent. The menu is an intent launcher. The system stays fully usable without the agent (§h.11). |
| V3 | **Resident agent.** The UI agent is a nuketown resident (its own unix user), not a process in the human's session. | `ada` (uid 1100) runs under nuketown. A chat surface in the Quickshell shell talks to it over a unix socket served by the resident's bridge. Showing off nuketown's user partitioning is an explicit goal (demo scene 7). |
| V4 | **No settings registry, no tiers.** | The resident may edit any NixOS/home-manager module and any flake input in the host repo. **Every switch is approved by the human on a card.** The watchdog and automatic rollback stay. Updates are "Update ready" cards. |
| V5 | **Card summary from a reviewer agent.** | A second resident, `reviewer` (uid 1101), reads the request (as the resident relays it), the git diff, the nvd diff and the build result, and writes a plain-language summary with a recommendation. The card always shows the nvd diff and the git diff next to it; routine cards are one line (§g.4). Since rev 5 it reviews every approval, not only switches (V8). |
| V6 | **omanix ≈ a function.** | `omanix.lib.mkHost` returns a `nixosSystem` with loom + nuketown + the omanix base, then loads the host's own plain NixOS and home-manager modules. Plugins are ordinary modules from any flake (§b.4). Typed verbs (`omanix set`, `app add`, …) remain as agent tools, not gates. |
| V7 | **v1 security scope cut** (2026-10-28). | nuketown was to be used unchanged; V8 amends that with K1–K10 (§a.3). v1 does not defend against a compromised or prompt-injected resident beyond what unix users already give; the stance and its limits are in §g.9. The hardening track is Appendix H. |
| V8 | **Reviewed sudo, no switch daemon** (2026-10-28). | The resident switches with `sudo loom-switch` through nuketown approval, from a short per-agent list of commands it may ask for (mino-style). Every approval gets a plain-English adversarial review of what will run, including the contents of any script, snapshotted so what runs is what was reviewed (§g.3, §g.4). nuketown gains the bypass fixes, a swappable prompter, request kinds, an approval list and the approval reviewer (§a.3). |

### 0.2 Hard calls

| # | Call | Reason |
|---|---|---|
| H1 | The whole omanix stack runs on **one nixpkgs: `nixos-unstable`**, moving to `nixos-26.11` at branch-off. Hyprland v0.56.2, quickshell and hyprland-guiutils come from their flakes with `inputs.nixpkgs.follows`. loom keeps CI green on **26.05 and unstable**, so signi is unaffected (D1). | Quattro needs Hyprland ≥ 0.56 and quickshell ≥ 0.3.2. One nixpkgs gives one Mesa and one Qt (facts §3). |
| H2 | `/` is **tmpfs**. `/nix`, `/persist` and **all of `/home`** are btrfs subvolumes. `/agents` is reset every boot by nuketown. | omarchy writes state all over `$HOME`; a persisted `/home` covers it with no per-path entries (§f.1). |
| H3 | **omanix forks omarchy at `v4.5.0-rc2`** as a pinned, unmodified, hash-locked input plus a patch queue under `fork/` (§f.2). Every bin script, menu entry and tree path has exactly one class: KEEP-AS-GUI, AGENT-INTENT, ASSET, RE-EXPRESS-IN-NIX or DROP. `checks.fork-classify` fails on an unclassified path. The bash state-mutation layer is **removed, not wrapped**. | V1. The divergence reads as a short list of drops and patches, and nothing in `nix flake check` compares against newer upstream. |
| H4 | **`omanix.lib.mkHost` returns a `nixosSystem`.** It adds loom (bundling nuketown, home-manager, sops-nix, impermanence, disko, lanzaboote), the omanix base, `specialArgs.inputs` and the human's HM entry point. Everything else is the host's plain modules, reached through ordinary `imports` (§b.3). | V6. A host flake can be read and debugged with plain NixOS knowledge. |
| H5 | **Every switch, and every root command the resident asks for, goes through a card the human approves** (nuketown approval, drawn by omanix's card; §g.3). There are no tiers and no agent-only path. The watchdog's automatic rollback is the only activation without an approval, and it only restores the generation that was already running. | V4. One rule is easy to explain and test. |
| H6 | The resident can edit **anything** in the host repo. Its key can push only `gate/*` and `refs/dit/*` on silo, never `master` or tags, because it is never in `CODEOWNERS` (§g.7). | V4, D6. silo's existing CODEOWNERS behaviour gives this for free. |
| H7 | **No switch daemon. `loom-switch <out>` is a root script the resident runs through approval sudo.** The resident builds as itself. Before the card, loom's request-kind collector (root) fetches the proposal bundle into the root mirror and computes the git diff, the flags and `nvd diff /run/current-system <out>`; after approval `loom-switch` activates exactly `<out>`. | V8. A privileged service was more complex than a sudoers entry and covered only one escalation. The diffs on the card are computed by root, not taken from the agent. |
| H8 | **The reviewer is an ordinary second nuketown resident** (`reviewer`, uid 1101) that the `nuketown-approval` service user runs once per approval request (`sudo -H -u reviewer`, `claude -p`, no session memory). It explains what will run; if it is signed out, slow or fails, the card shows the raw request with "No AI review". | V5, V8, without a sandbox (Appendix H.5). |
| H9 | **Approval is nuketown's broker with a swappable prompter.** A request is a root-written directory (argv as JSON, script snapshots, collector files, review); the broker hands it to the prompter. omanix's prompter is the `omanix.approval` card; zenity is nuketown's default (§a.3 K6). | One approval surface; signi keeps zenity. |
| H10 | **Watchdog and rollback by default.** `loom-switch` arms a dead-man rollback from the old generation before `switch-to-configuration test`, runs health checks, and only then makes the new generation the boot default (§g.5). | The spec's switch watchdog. A broken generation can't disable its own rollback. |
| H11 | (retired: rev 3's switchd pipeline steps; Appendix H.4) | — |
| H12 | **Every disk gets a system-encryption-key slot.** TPM2 without a PIN is offered **only with Secure Boot on our own keys** (PCR 7); all TPM2 enrollment happens at first boot. **Autologin is on only when no enrolled unlock method is automatic** (D4). | A stolen laptop never boots into a desktop without a human factor. |
| H13 | The **host sops key is a file under `/persist`**, protected by LUKS. The user has one recovery secret, the **system encryption key** (SEK), from which the LUKS recovery passphrase and the sops recovery age identity are derived by HKDF with separate labels (D12, §g.10). | AMD fTPM clears must not destroy the secrets key, and users get one thing to write down. |
| H14 | **Human dotfiles are read-only home-manager files** generated from `omanix.*` options and the host's `home.nix` (D9). The GUI tools omanix keeps write only runtime state: `~/.local/state/omarchy/**` and writable overlays under `~/.local/state/omanix/`, which the HM files include last (§f.4). | Reproducible dotfiles; the kept GUI tools keep working; the resident cannot write the human's home anyway (V3). |
| H15 | The **installer is deterministic**: no agent, no sshd, no answers file. It writes the host repo from a **closed, typed answer set** through one escaping renderer (`loom-hostgen`), never free-form Nix. No Seed-side builder in v1 (D3). | The medium that does destructive work holds no network credential and no remote shell, and untrusted input enters Nix only as data. |
| H16 | Boot loader: **Limine** by default; lanzaboote is the supported, CI-tested alternative (D7). | Under Secure Boot the config and the kernel/initrd checksums are signed, so PCR 7 is meaningful. |
| H17 | **The human key creates the host repo** (first push ⇒ silo `.owner_key`). The enrollment key is temporary and removes itself in the installer's push. No silo change in v1 (D6). | The host and the enrollment key can never seize the repo. |
| H18 | **The resident's sudo is a short approval list** (`loom.agent.sudoCommands`: `loom-switch`, `journalctl`, `systemctl`, `fwupdmgr`, `nix-collect-garbage`); each request shows the reviewed card. **Whether it may ask for any other command is an install-time question, default no** (`loom.agent.sudo = "listed" \| "any"`, D8). | Mino-style: a couple of entries instead of a service. nuketown's `sudo.approvalAllow` refuses unlisted commands before bothering the human (§a.3 K8). |
| H19 | **The system is whole without any agent.** A terminal user edits the host repo, commits and runs `loom propose`; the same card, approval, watchdog and rollback apply. | V2: it is just NixOS. |

### 0.3 Layering

```
host repo  silo:omanix/<id>.git   flake.nix · configuration.nix · home.nix · machine.nix · keys.nix ·
   │                              hardware.{nix,json} · modules/ · secrets/   (plain NixOS + HM, §d)
   │ inputs.omanix (+ any plugin inputs; nixpkgs/home-manager follow omanix)
omanix   "omarchy as if it started on nix": fork/ of omarchy v4.5.0-rc2 (omarchy-src, omanix-data),
         Hyprland-Lua, Quickshell shell + omanix.chat/approval/status/welcome plugins, themes, intent menu,
         keybinds, apps, hw quirks, omanix CLI + verbs, catalogs, resident skills, mkHost
   │ inputs.loom
loom     DE-agnostic platform + agent base: mkHost core, installer image + hostgen, disko/LUKS/unlock,
         Secure Boot, impermanence, home-manager wiring, sops lifecycle + SEK, loom.keys, silo mint/enroll,
         agent bridge (chat socket), loom-switch + switch-kind collector (card, watchdog), updates,
         firstboot, catalogs lib, nuketown compatibility glue (§a.3)
   │ inputs.nuketown   (v1 changes K1–K10, §a.3)
nuketown agents as unix users (resident ada, reviewer); approval: root wrapper, script snapshots,
         request kinds, reviewer run, broker + swappable prompter (built-in GTK card)
seed/silo: S3, S4 (v1, test infra only); S1, S2 later
```

**Rules.**
- loom never mentions Hyprland or omarchy. A flavor hooks in through registries such as `loom.installer.probes` and `loom.switch.watchdog.checks`.
- loom and omanix set nixpkgs/HM options and `loom.*` only with `mkDefault`, so a host module wins at normal priority (`checks.priorities`). The exceptions are listed in `lib/force-allowlist.nix`; they include the `.source` of every omanix-owned HM file target, which is set at normal priority (§c).
- **nuketown changes only as listed in §a.3 (K1–K10).** New behaviour is behind options that default off; `checks.signi-compat` keeps signi's evaluation unchanged apart from the bypass fixes. Everything else omanix needs from nuketown is configuration or loom-side glue (C1–C8).

### 0.4 Errata pointer

Rev 2's §0.3 mapped 36 judge findings to fixes; that table is in git history and `reconcile-changelog.md`. Rev 3's 51 findings are in `fork-changelog.md`. Under rev 4:
- **Still in force:** rev 2 items 1–4 (autologin and TPM/SB rules, §e.6), 6 (watchdog armed before `test`, §g.5), 7 (reinstall re-encrypts sops, §g.8), 8 (every cache signed, no `trusted=1`, §e.3), 9 (exact repo-id algorithm, §d.5), 12 (password hash never encrypted to the enroll key, §d.6), 15 (fork needs a new human key, §g.8), 17–34 except where they cite dropped machinery; rev 3's installer, hostgen, enrollment, SEK, impermanence, HM and fork fixes.
- **Moved to Appendix H:** rev 2 item 11 (eval in a DynamicUser) and every rev 3 finding against the ledger, facts, approval merges, nonces, preflight VM, reviewer isolation and nuketown deltas, including the four rev 3 blockers.

---

## a) Repositories

### a.1 omanix (`~/projects/omanix`)

```
omanix/
  flake.nix  flake.lock         # inputs.omarchy pinned to v4.5.0-rc2 = 5978d93 (flake = false)
  CLAUDE.md                     # "@AGENTS.md"
  AGENTS.md                     # router ≤150 lines: layers, rules, where things live, test etiquette
  LICENSE                       # MIT, Copyright (c) 2026 Joshua Perry and Ada
  LICENSES/omarchy-MIT.txt      # copy of upstream's notice (§f.2.8)
  .claude/skills/
    configure/ build-installer/ release/      # spec skills (§e.2) and the release procedure (D11)
    port-omarchy/                              # runs the porting report, prepares a fork-point move on gate/*
    add-patch/ add-intent/ add-quirk/ add-option/ add-theme/ vm-test/ diagnose-build/
  scripts/                      # spec: deterministic, reviewed, signed; thin wrappers -> nix run
    flash-usb.sh  configure.sh  verify-release.sh  setup-remotes.sh
    SHA256SUMS  SHA256SUMS.sig  # ssh-keygen -Y sign -n omanix-release
  release/allowed_signers       # published copy; user pins out of band (§e.10)
  fork/                         # THE divergence from omarchy (§f.2)
    UPSTREAM.toml  NOTICE  classify.toml  writers/{desktop,theme}.toml  drop.txt  rewrite.toml  intents.toml  menu-extra.jsonc
    hw-quirks.toml  hl-symbols.txt  patches/*.patch  add/**
  lib/
    default.nix                 # omanix.lib = loom.lib // { mkHost; lua; jsonc; menu; fork; home; }
    mk-host.nix  lua.nix  jsonc.nix  menu.nix  fork.nix
    home/{files,kv}.nix         # HM file generators, overlay kv formats
  modules/omanix/               # FILE PATH == OPTION PATH (omanix.<a>.<b> in <a>/<b>.nix or <a>/default.nix)
    default.nix  path.nix  session.nix  login.nix  language.nix  runtime.nix
    home/{default,terminals,desktop}.nix   hyprland/{default,monitors,window-rules}.nix
    keybinds.nix  menu.nix  shell.nix  chat.nix  approval.nix  welcome.nix
    theme/{default,boot}.nix  defaults.nix  apps/{default,webapps,tuis}.nix  packages.nix
    input.nix fonts.nix audio.nix network.nix power.nix printing.nix region.nix dns.nix
    hardware/{default,intel,nvidia,amd,vulkan,bluetooth,wireless}.nix  hardware/quirks/<name>.nix
    browser-policy.nix  cli.nix  catalog.nix  health.nix  probes.nix  residents.nix
    branding.nix  hooks.nix  fork.nix  persist.nix  weather.nix
  pkgs/by-name/
    omarchy-src/  omanix-data/  hyprland-omarchy/  omarchy-hyprland-titlebars/  quickshell-omarchy/
    hyprland-guiutils/  owe/ ttfx/ omacalc/ aether/ omasnap/ omacut/ omawrite/ hype/ signed/
    monologue/ gliff/ asdcontrol/ try-tobi/  omanix-plymouth/ omanix-sddm-theme/ omanix-glyphs/
    omanix-cli/ omanix-catalog/ omanix-skills/ omanix-overlay/ omanix-runtime-snapshot/
  templates/host/               # host repo template (§d)
  demo/                         # replay transcripts, battery-card scene, bad monitor rule (§j)
  checks/  tests/               # §i
  docs/                         # architecture.md, porting.md; options.md GENERATED, not committed
```

The omanix shell plugins (`omanix.chat`, `omanix.approval`, `omanix.status`, `omanix.welcome`) live in `fork/add/shell/plugins/` so that upstream's plugin registry discovers them like any first-party plugin.

Remotes: `scripts/setup-remotes.sh` sets `origin` fetch to `ssh://git@silo.loom.farm/omanix.git` and the pushurls to silo and github. loom and nuketown carry the same script.

**Removed from rev 2:** `upstream/` (pin.toml, manifest, overrides, packages.toml, install-map.toml, writers.toml), `lib/upstream.nix`, `lib/home/writer-scan.nix` as a gate, the `bump-omarchy`/`override-upstream` skills, generated `omarchy-install-*` shims.

### a.2 loom (`~/projects/loom`, refactor approved; the existing MVP is replaced)

```
loom/
  flake.nix flake.lock CLAUDE.md(@AGENTS.md) AGENTS.md .claude/skills/{add-option,vm-test}/
  lib/
    default.nix  mk-host.nix  mk-installer.nix  catalog.nix  checks.nix  repo-id.nix  persist-audit.nix
    keys.nix                    # loom.keys → .authorized_keys / CODEOWNERS / allowed_signers / .sops.yaml
  modules/loom/                 # FILE PATH == OPTION PATH under loom.*
    default.nix host.nix keys.nix user.nix locale.nix silo.nix home.nix hardware.nix nix.nix
    disk/{default,unlock}.nix  boot/{default,secure-boot}.nix  persist/{default,snapshots}.nix
    secrets/{default,host-key,prompted}.nix  trust.nix
    switch/{default,watchdog}.nix  update.nix  chat.nix  reviewer.nix
    agent/{default,bridge,login,nuketown}.nix  firstboot.nix  installer/{default,probes}.nix   # agent/nuketown.nix = §a.3 glue
  pkgs/                         # python3 stdlib only; pytest in checks
    loom-cli/ (incl. sek.py = loom-sek, keys.py)  loom-switch/ (switch, collect, request)  loom-watchdog/
    loom-switch-review/ (switch-kind prompt)  loom-agent-bridge/ (adapters: claude-code stream-json, replay)
    loom-installer/ (incl. hostgen.py)
    loom-mint/  loom-enroll/  loom-flash/  loom-detect/  loom-askpass/ (initrd SEK agent, §g.10)
  schemas/                      # loom.chat/v1 loom.snapshot/v1 loom.sidecar/v2 (checks.schemas)
  templates/host/               # generic (DE-agnostic) host template
  tests/  tests/lib/{silo-standin,fixtures,approval-stub}.nix
  scripts/setup-remotes.sh
```

`modules/loom/home.nix` (`loom.home.*`) holds the DE-agnostic HM wiring: the HM NixOS module (`useGlobalPkgs`, `useUserPackages`, `backupFileExtension = null`, `home.enableNixpkgsReleaseCheck`), the `loomReclaim` activation entry, the `hm-activation` watchdog check and the ordering drop-in on `home-manager-<user>.service`. loom's `home-manager` input follows nixpkgs (HM master on unstable; `release-26.05` in the 26.05 CI eval through an input override).

**Removed:** `installer.nix` (dead code); the inline Python auth server and QR credential handoff; the `MOCK_APPROVED` runtime file; the `wheelNeedsPassword=false` default; the hardcoded Hyprland prompt snippets (loom `prompt.nix`'s live-tuning idea survives as `omanix try`, §h.6). From rev 2: `lib/settings.nix`, `lib/json-schema.nix`, `lib/policy-view.nix`, `modules/loom/{settings,policy}.nix`, `loom policy classify`. From rev 3 (V7): `lib/highlight/`, `loom-facts`, `loom-chatd`, `loom-eval`, `loom-fetch`, `loom-egress`, `loom-card-tty` and their schemas (Appendix H). From rev 4 (V8): `loom-switchd`, its socket, the `loom-switch` group and `loom approve`; `loom-review` (the run moved into nuketown's approval reviewer, K5).

### a.3 nuketown: approval changes (K1–K12) and compatibility (C1–C8)

V7 kept nuketown unchanged; V8 changes its approval path, because every approval now carries a review and the resident's sudo is the switch path. Everything new defaults off except the bypass fixes and the service user, so signi keeps the zenity dialog (now with the request rendered from `request.json`, a **Show files** button, and "No reviewer configured") (`checks.signi-compat`, K10). **Built** on nuketown `master` (`7a2b84e`, `6b4960c`, `eafb45f`, `6b9e5c1`; not pushed beyond `7a2b84e`), except K7 and the items marked W1b.

**nuketown changes in v1.**

| # | Change | Why | State |
|---|---|---|---|
| K1 | **No agent sudo rule reaches root.** The `sudo` shim, `sudoex` and `sops-unlock` run `sudo -u nuketown-approval /run/current-system/sw/bin/nuketown-approve [--decrypt src:dest]… [--why …] [--user u] [--group g] [--login] [--shell] [--set-home] --cwd "$PWD" -- argv…`; that is each sudo agent's only rule (NOPASSWD). `sudo-with-approval` and `sudoex-run` are gone. | `sudoex-run` was NOPASSWD `exec "$@"`: any agent with default rules got root with no dialog, on signi too. Fixed first in `7a2b84e` (root-side wrapper), then replaced by the service user. | built |
| K2 | **No `SETENV`** on any agent or service-user rule. | With `SETENV`, `sudo BASH_ENV=/tmp/x sudo-with-approval true` ran agent code as root before approval (confirmed in a VM on the old code). | built |
| K3 | **A request is a directory written by the service user, not a text line.** `nuketown-approve` writes `/run/nuketown-approval/<id>/request.json` (argv as a JSON array, `display` = argv `%q`-quoted on one line, requester from sudo's `SUDO_USER`, run-as, cwd, why, decrypt) and sends the broker only `REQUEST:<id>` (plus `DECRYPT:` lines). `SUDO:`/legacy lines are gone; the broker rejects unknown operations and ids that don't name a request directory. | A newline in an argument could add a second request line, so the dialog showed something other than what ran (confirmed in a VM). The id is chosen by the service user; argv never crosses the socket. | built |
| K4 | **Script snapshots, read as the requester.** The program (`argv[0]` outside `/nix/store` and `/run/wrappers`), or the first non-option argument after an interpreter (`bash sh dash zsh ksh fish python python3* perl node ruby lua*`; `-c`/`-e`/`-m`/`-` mean inline code, no file), is read with `sudo -u <requester> nuketown-approval-read <path>` (regular file, ≤ `snapshotMaxBytes`, default 1 MiB), stored as `snapshots/<n>/<basename>` with its sha256, and **runs in place of the original**. If it can't be read *by the requester*, the request is refused before asking. Up to 8 other path-like arguments are snapshotted for review only. | Josh: a scratchpad script that does several things in one sudo is hard to audit. What runs is what was reviewed, and the service user never reads a file the agent couldn't. | built |
| K5 | **Approval reviewer** (`nuketown.approval.reviewer.{enable,agent,command,timeout}`, default off). Before asking, the service user runs `timeout <timeout> sudo -H -u <agent> <command> <request dir>` (default command: `claude -p` with a fixed adversarial prompt and the request inlined; default timeout 45 s), validates the JSON it prints and writes `review.json` (`status`: `ok` \| `unavailable` with a reason \| `disabled`). The service user parses the output, unprivileged; root never sees it. | The review is adversarial and in plain English (§g.4). | built (synchronous; the "card fills in later" mode of rev 5 is W1b) |
| K6 | **Swappable prompter** (`nuketown.approvalDaemon.prompter`, HM, default null = the built-in GTK card). The broker runs `<prompter> <request dir>`; exit 0 approves, anything else denies. With a custom prompter a `--decrypt` runs after approval (one YubiKey touch). The built-in zenity prompter renders `request.json`/`review.json` (Pango-escaped) with a **Show files** button (`--extra-button`) for the snapshots; DECRYPT + REQUEST keeps the combined YubiKey dialog. | omanix draws the card in Quickshell; signi keeps zenity. | built (a deny reason on the requester's stderr is W1b) |
| K7 | **Request kinds** (`nuketown.approval.kinds.<name> = { command; collect; reviewPrompt; timeout; }`): a collector runs before the review when the resolved `argv[0]` matches; non-zero refuses with its message. | A switch is a richer request (nvd, git diff) on the same path, with no daemon. | **W1b** |
| K8 | **Per-agent approval list** (`nuketown.agents.<n>.sudo.approvalAllow`, `nullOr (listOf str)`, default null = any command; entries are absolute paths or names resolved in the system PATH, compared as resolved paths, not realpaths, because coreutils is one binary). Refused before asking. `sudo.commands` is a deprecated alias. | Mino-style: a short list instead of "anything with approval". | built |
| K9 | The shim accepts `--why <text>`; the card shows it as the agent's stated reason and the reviewer checks the command against it. | The reason is context, not trust. | built |
| K10 | `checks.signi-compat`: a fixture with signi's nuketown options forces the system to evaluate; mynix signi also evaluates against this nuketown with `--override-input` (not committed or switched). | signi deploys the same nuketown. | built |
| K11 | **The `nuketown-approval` service user** (system user, no home, nologin; groups `nuketown-approval`, `nuketown-broker`). Its one sudo rule is `ALL=(ALL:ALL) NOPASSWD: ALL`: it is root-equivalent by design, and the value is that each step (snapshot reads as the requester, the review as the reviewer, the approved command) is a logged sudo call and it parses everything unprivileged. Agents are no longer in `nuketown-broker`. | Josh: log invocations; root does no parsing. | built |
| K12 | **Audit.** One journal record per request (`journalctl -t nuketown-approval`, JSON: id, requester, argv, exec_argv, snapshot hashes, review status/risk/recommendation, decision, prompter, exit code), and the finished request directory copied to `nuketown.approval.audit.dir` (default `/var/lib/nuketown-approval`, persisted, pruned daily after `audit.keepDays`, default 30). | An after-the-fact record of what ran and why. | built |

W1b (still to build, needed by W8): K7; `--requester <name>` accepted only when the caller is root (for `loom-switch-request` and timers); `NUKETOWN_APPROVAL_DIR` for the approved command; a deny reason from the prompter to the requester's stderr; showing the prompter before the review finishes.

The request directory (`/run/nuketown-approval/<id>/`, `nuketown-approval:nuketown-approval-read`, setgid `2751`; the group holds `humanUser` and the reviewer agent; removed when the request ends, after the audit copy):

```
request.json    { id, requester, time, cwd, why, run_as: {user, group, login, shell, set_home},
                  argv: [...], exec_argv: [...], display, decrypt: [...],
                  snapshots: [{ path, snapshot, sha256, executed }] }
snapshots/<n>/<basename>   0755 if it runs, 0644 if review only
review.json     { status: ok, summary, risk, recommendation, notes, not_shown } | { status: unavailable, reason } | { status: disabled }
review.stderr
decision.json   the audit record (also in the journal)
```

The approved command runs as `sudo [-u/-g/-H/-i/-s] -- nuketown-run-in <cwd> <exec_argv…>` (cwd of the request, `/` if the run-as user can't enter it; system PATH), with stdio and the exit code passed through to the agent.

**loom-side compatibility.** Each row is something a fresh loom host needs from nuketown and how loom gets it with configuration:

| # | Need | Without it | loom-side answer |
|---|---|---|---|
| C1 | Agent persistence under `/persist` | nuketown writes `environment.persistence."/persist".users.<agent>` unconditionally (hard-coded root) | loom's persist root is `/persist` and loom always imports impermanence. `loom.persist.root` is asserted equal to `"/persist"` while nuketown is enabled (rev 3's N5 `persistRoot` deferred). |
| C2 | `/agents` mount and per-boot reset | nuketown mounts `@agents` itself from `nuketown.btrfsDevice` (a btrfs **filesystem UUID**) and rolls it back in initrd after `cryptsetup.target` | loom's disko layout creates `@agents` and `@agents-blank` but **declares no mount for `/agents`** (nuketown's `fileSystems./agents` would conflict). The installer reads the btrfs UUID inside LUKS and writes `nuketown.btrfsDevice` into `machine.nix`. A nested subvolume inside `@agents` would make nuketown's plain `btrfs subvolume delete` fail; nothing omanix runs creates one (N5's nested delete deferred). |
| C3 | Agent ssh key from sops | nuketown reads every agent secret from one `nuketown.sopsFile` | loom sets `nuketown.sopsFile = <host>/secrets/agents.yaml` (one file, not rev 3's per-agent files) and `agents.ada.secrets.sshKey = "ada/ssh"`. sops-nix's key is loom's host age key (`sops.age.keyFile`), independent of nuketown. |
| C4 | The approval dialog | nuketown's broker is a **home-manager** user unit (`nuketown.homeManagerModules.approvalDaemon`); the socket directory `/run/nuketown-broker`, group `nuketown-broker` and the `nuketown-approval` service user exist only when some agent has `sudo.enable` | loom imports the HM module into the human's HM config and enables it (the one HM `systemd.user` unit omanix allows, §f.4.5) and sets `nuketown.humanUser`. The resident always has `sudo.enable` (C8), so nuketown creates the socket directory, group and service user; omanix sets the prompter (K6). |
| C5 | The dialog appears under Hyprland/uwsm | the broker unit sets only `DISPLAY=:0` and may start before the session imports `WAYLAND_DISPLAY` | Works on signi (Hyprland) today. omanix's autostart runs `systemctl --user restart nuketown-broker` after uwsm imports the session environment. UNVERIFIED under uwsm (U37). |
| C6 | Option docs for the catalog | nuketown's `portal.command` default references `pkgs.unstable.claude-code`; `nixosOptionsDoc` evaluates defaults | loom adds an overlay alias `unstable = final` on the unstable channel (and a real unstable on the 26.05 CI leg), so catalogs build (U40). |
| C7 | Agent sign-in terminal | the human reaches an agent with `machinectl shell <agent>@`, which nuketown's polkit rule allows only when some agent has `portal.enable` | loom sets `portal.enable = true` for the resident and the reviewer, with `portal.command` = the harness. The sign-in terminal runs `machinectl shell <agent>@ <loginCommand>` (§h.3.6). |
| C8 | The resident's sudo | `sudo.enable` gives the agent one rule: start `nuketown-approve` as the service user (K1) | loom sets `sudo.enable = true` and `sudo.approvalAllow` from `loom.agent.sudoCommands`, or null when `loom.agent.sudo = "any"` (D8, K8). |

**Still deferred** (Appendix H.1): N2 Python broker with `SO_PEERCRED`, N3 build-time mock approval, N4 key cleanup trap, N5 option additions other than K6's prompter, N8 egress, N9 `interactive = false`, N10 claude-code lockdown, N11 `SIGN`, N12 `switch.command`, N13 `homeMode`, N14 host-shell target restriction, N15 NixOS broker unit.

### a.4 seed/silo deltas

**v1 needs no change to silo's behavior.** The only v1 seed work is test infrastructure.

**Silo behaviors relied on (F1–F8).** Checked against `seed/instances/silo/{shell,hooks}.nix` at HEAD. Every D6 argument in this document (§d.6, §e.2, §e.9, §g.3, §g.5) cites these rows.

| # | Behavior | Source |
|---|---|---|
| F1 | The first `git-receive-pack` to a missing path runs `git init --bare` and writes `"$SILO_KEY_TYPE $SILO_KEY_BLOB silo-user"` to `.owner_key`. This happens **before** the pack is received and with no authorization beyond "any key that reached silo-shell", so the pusher is owner even if the push then fails. `.owner_key` is never rewritten. | `shell.nix:64-73` |
| F2 | A push to an existing repo is allowed at the transport level if the pusher's blob is in `.owner_key` or in the bare repo's `.authorized_keys` (`grep -qF`). | `shell.nix:74-80` |
| F3 | pre-receive: the owner bypasses everything. It compares `cut -d' ' -f2 < .owner_key` with `=`, so it works only for a **single-line** `.owner_key` (S1 needs a `grep -qxF` fix). | `hooks.nix:21-28` |
| F4 | pre-receive: `refs/heads/gate/*` always passes. For other non-`dit` refs, the pusher's blob must appear in a non-comment line of `CODEOWNERS` **at the bare repo's current `HEAD`**, meaning before this push. If `HEAD:CODEOWNERS` is missing, every transport-authorized key may push. There is **no fast-forward or content check** on these refs: a CODEOWNERS key may force-push `master` and may change `CODEOWNERS`/`.authorized_keys` arbitrarily. | `hooks.nix:31-70` (gate at :35, CODEOWNERS at :52-63) |
| F5 | post-receive: on an update of the default branch (`symbolic-ref HEAD`), it copies `<new>:.authorized_keys` over the bare repo's `.authorized_keys`. If the new tree has no `.authorized_keys`, the old copy **stays**. A push to any other ref does not sync. | `hooks.nix:77-101` |
| F6 | `init.defaultBranch` is unset on silo, so `HEAD` → `refs/heads/master` (the hook's fallback is also master). A newer git default (`main`) would break F4 and F5 silently: F4 because `HEAD:CODEOWNERS` resolves to nothing. | `hooks.nix:80`; no `defaultBranch` anywhere in `instances/silo/` |
| F7 | `git-upload-pack` is always allowed (public read). Push is over SSH only. A `git-upload-pack` to a missing path fails with `repository not found` (used by the mint pre-check). | `shell.nix:64-69`, `:89-91` |
| F8 | Repo paths are chosen by the pusher; anyone who knows or can compute a missing path can claim it through F1. | `shell.nix:40-73` |

| id | change | when |
|---|---|---|
| S3 | `seed.nixosModules.silo-standalone`: silo-shell, siloauth, hooks and git-http read, with no controller webhook. This is the local silo stand-in for VM tests. It sets nothing that changes `init.defaultBranch`. | **v1** |
| S4 | Test that `sk-ssh-ed25519@openssh.com` keys pass `AuthorizedKeysCommand`, the `.owner_key` match (F1, F3), the `.authorized_keys` grep and the CODEOWNERS grep. This is required because a FIDO2 key is the usual repo owner. UNVERIFIED today. | **v1** |
| S1 | Owner handoff and rotation: an in-tree owner file that only the current owner may change, copied to `.owner_key` by post-receive. **Prerequisite fix:** pre-receive compares one owner blob with `=` (F3), so a multi-line `.owner_key` would silently lose its bypass (it fails closed). Change it to `cut -d' ' -f2 "$OWNER_KEY_FILE" \| grep -qxF -- "$KEY_BLOB"` before allowing more than one owner. | later |
| S2 | Path hardening: no `.`-prefixed components, no repo inside a repo, depth ≤ 3. The v1 flow doesn't need it, because ids are unguessable and there is no `..`. | later |

These existing silo behaviors are relied on unchanged: F1–F8 in the table above, plus public read over HTTPS for nested paths.

Guards loom adds on its own side, since silo is not changed:
- **HEAD check (F6).** After the first push, `loom-mint` runs `git ls-remote --symref <fetchUrl> HEAD`. It requires `ref: refs/heads/master` and that `master` equals the pushed commit. Otherwise it stops with `silo default branch is not master; enrollment would be ungated`. The S3 stand-in test asserts the same thing.
- **Never delete `.authorized_keys` (F5).** `loom-switch`'s collector refuses a proposal that removes `.authorized_keys` or `CODEOWNERS`: removing the file would freeze the stale bare copy. `checks.keys-sync` also requires both files in every host repo commit.
- **Push only to `master` and `gate/*`.** loom never pushes another non-gate ref, so F4 always gates it.

---

## b) Flake interfaces and mkHost

### b.1 Inputs

| repo | inputs |
|---|---|
| loom | nixpkgs (`nixos-unstable`, then `nixos-26.11`; CI also evaluates 26.05 for signi, D1), home-manager (follows nixpkgs), disko v1.13.0, impermanence, sops-nix, lanzaboote (D7), nuketown, seed (only for `checks`: silo-standalone) |
| omanix | loom (and `follows` for all of loom's inputs), `omarchy` (`github:omacom/omarchy/5978d93ae7da0a325b7493501911e3f1266cadd3` = tag `v4.5.0-rc2`, `flake = false`, D2; moved only by a recorded decision, §f.2.7), `omarchy-pkgs` (`flake = false`; Hyprland patches and PKGBUILD versions), hyprland `v0.56.2`, quickshell at rev `2b4501a…`, hyprland-guiutils v0.2.2. All follow omanix's nixpkgs. |
| host flake | `omanix` (pinned to a release tag rev), `nixpkgs.follows = "omanix/nixpkgs"`, `home-manager.follows = "omanix/home-manager"`, plus **any plugin inputs** (each new one is flagged on the card that adds it). |

There is no Seed-side builder input or output in v1 (D3).

### b.2 Outputs

```nix
# loom
lib = { mkHost; mkInstallerImage; keys; persistAudit; repoId; catalog; checks; };
nixosModules = { default; };                      # bundle; sub-modules importable by path
packages.<sys> = { loom-cli loom-switch loom-watchdog loom-switch-review loom-agent-bridge loom-installer loom-mint
                   loom-enroll loom-flash loom-detect loom-askpass installer-image installer-image-test; };
templates.host; checks.<sys>; apps.<sys> = { flash-usb; mint; };

# omanix
lib = loom.lib // { mkHost; lua; jsonc; menu; fork; };
nixosModules.default; homeModules.default; overlays.default;
packages.<sys> = { omarchy-src omanix-data omanix-cli omanix-catalog omanix-skills omanix-overlay hyprland-omarchy …
                   installer-offline installer-net installer-test base-cache; };
apps.<sys> = { configure; flash-usb; verify-release; porting-report; fork-mirror; };
nixosConfigurations = { ref-default; ref-nvidia; ref-laptop; vm-test; };   # cache seeds + fixtures
templates.host; checks.<sys>; devShells.default;   # nixfmt statix deadnix shellcheck nvd sops age nix-tree
```

### b.3 `mkHost`

```nix
# omanix/lib/mk-host.nix   (omanix.lib.mkHost; loom.lib.mkHost is the same function without the omanix base)
mkHost =
  { self                                   # the host flake (configurationRevision, loom.host.src)
  , inputs                                 # the host flake's inputs (plugins); passed as specialArgs.inputs
  , system ? "x86_64-linux"
  , modules ? [ (self + "/configuration.nix") ]   # NixOS entry points; configuration.nix imports the rest
  , homeModules ? [ (self + "/home.nix") ]        # HM entry points for loom.user.name
  , specialArgs ? { }                      # merged over { inputs; omanix; }
  }:
  inputs.omanix.inputs.nixpkgs.lib.nixosSystem {   # omanix's nixpkgs (D1: nixos-unstable)
    inherit system;
    specialArgs = { inherit inputs; omanix = omanixSelf; } // specialArgs;
    modules = [
      loom.nixosModules.default            # loom + nuketown + home-manager + sops-nix + impermanence + disko + lanzaboote
      omanixSelf.nixosModules.default      # omanix base (desktop fork, residents, catalogs, CLI)
      ({ config, ... }: {
        system.configurationRevision = self.rev or self.dirtyRev or null;
        loom.host.src = self;
        home-manager.extraSpecialArgs = { inherit inputs; omanix = omanixSelf; };
        home-manager.users.${config.loom.user.name}.imports = homeModules;
      })
    ] ++ modules;
  };
```

| Part | Provides | Host-visible options |
|---|---|---|
| loom | disk/LUKS/unlock, boot, Secure Boot, impermanence, sops lifecycle + SEK, `loom.keys`, silo working copy, agent bridge, loom-switch (collector, card, activation) + watchdog, updates, firstboot, catalogs lib, nuketown glue (§a.3) | `loom.*` |
| nuketown (via loom; K1–K10, §a.3) | agents as unix users, approval broker, portal | `nuketown.*`; loom sets the two residents from `loom.agent.*` and `loom.reviewer.*` (§c.3) |
| home-manager (via loom) | HM NixOS module, `home-manager-<u>.service` ordered before the display manager | the human's tree is `home.nix` |
| omanix base | the omarchy fork: Quickshell shell + omanix plugins, themes, Hyprland Lua, intent menu, keybinds, apps, quirks, HM read-only dotfiles (§f.4.2), runtime overlays, `omanix` CLI, catalogs, resident skills | `omanix.*` |
| host modules | everything reached from `configuration.nix` and `home.nix` | anything |

**Rules.**
- The output attribute is always `nixosConfigurations.host`. `loom propose` builds `<commit>#nixosConfigurations.host`. Renaming the machine is a one-line edit.
- **What is activated is what the card showed.** Root computes the card's nvd diff against `<out>`, and `loom-switch` activates that `<out>` (§g.3). That `<out>` is the build of the proposal commit is the resident's claim, not checked in v1 (§g.9).
- Evaluation is pure, with `allow-import-from-derivation = false` in `loom propose`'s build and in CI. A plugin that needs IFD fails with an error naming the input.
- mkHost does not read `hardware.nix`, `machine.nix`, `keys.nix` or `modules/` itself; `configuration.nix` imports them, so a reader can trace every file.
- The template also exports `checks.<system>.host = toplevel`, so `nix flake check` in a host clone builds the machine. omanix provides no other per-host outputs; catalogs and docs are part of the toplevel (§h.9).

### b.4 Plugins are modules

| Plugin flake output | Meaning | How a host uses it |
|---|---|---|
| `nixosModules.<n>` (and `.default`) | NixOS module | `imports` in `modules/plugins.nix` |
| `homeModules.<n>` (and `.default`) | HM module for the human | `imports` in `home.nix` |
| `homeManagerModules.<n>` | legacy alias; accepted, `omanix plugin add` prefers `homeModules` | same |
| `overlays.<n>` | optional; added via `nixpkgs.overlays` in `modules/plugins.nix` | same file |
| `packages.<sys>.<n>` | optional; `inputs.<p>.packages.${pkgs.system}.<n>` | any module |

```nix
# modules/plugins.nix
{ inputs, ... }:
{
  imports = [ inputs.hypr-dynamic-cursors.nixosModules.default ];
  programs.hypr-dynamic-cursors.enable = true;
}
```

`inputs` comes from `specialArgs`, so it can be used in `imports`. HM plugins go in `home.nix` `imports`, with `inputs` from `home-manager.extraSpecialArgs`. Nothing in omanix wraps, registers or lists plugins; `omanix context` derives "installed plugins" from `flake.lock` and from `imports` that resolve to input store paths.

**Conventions for plugin authors** (none enforced except where a check is named): declare a `nixpkgs` input so hosts can `follows` it; use your own option namespace and never set `omanix.*`/`loom.*` above `mkDefault`; describe every option (the catalog flags undocumented plugin options); persist state with the guarded pattern (§f.1); no IFD.

```nix
# guarded persistence: works on hosts without loom
{ lib, options, ... }:
{ config = lib.optionalAttrs (options ? loom.persist) { loom.persist.system.directories = [ "/var/lib/foo" ]; }; }
```

**Adding a plugin (resident flow, skill `add-plugin`).**
1. **Vet.** `omanix plugin inspect <flakeref>` runs `nix flake metadata --json` and `nix flake show --json` (pure fetches, no module evaluation) and reports outputs, declared inputs, the latest tag, and whether the owner already appears in this host's lock. The resident tells the human what it is and why it fits the request.
2. **Edit.** `omanix plugin add <flakeref> [--module <n>] [--home] [--name <input>]` adds the input with `follows` for `nixpkgs`/`home-manager`/`omanix` when declared, prefers a tag ref (a bare branch needs `--branch` and shows on the card), runs `nix flake update <input>` touching only that node, and appends the import. It sets no option values.
3. **Check.** `omanix check` evaluates and builds. The persist audit fails if the plugin's services keep unpersisted state; the resident adds lines to `modules/persist.nix`.
4. **Propose.** Commit, `omanix propose`. The card flags the new input, so it is never a routine one-liner.
5. **Remove.** `omanix plugin remove <input>` deletes the import lines, the input and its lock node; leftover option values become eval errors with file:line.

---

## c) Options

**Conventions.**
- Every value that loom or omanix sets on a nixpkgs/HM option or on `loom.*` from omanix is `mkDefault`. Exceptions live in `lib/force-allowlist.nix` with a reason (`checks.priorities`).
- Every option has a `description`; non-trivial types also have an `example` (`checks.documented`). Enums are preferred over strings. Assertion messages name an option path (`checks.assertion-messages`).
- **No option carries a settable level, class or tier.** Types and descriptions are the only metadata (V4).
- The omanix desktop is configured through `omanix.*` NixOS options; omanix modules write `home-manager.users.${loom.user.name}.*` from them. The human may also write plain HM in `home.nix`. omanix sets each HM file target it owns as `.source` **at normal priority** (these targets are on the force-allowlist), so a plain `home.nix` `.source` for the same target is a conflicting-definition error, and `lib.mkForce` on `.source` takes the file over. Other overlaps do not raise errors: a `home.nix` `.text` silently loses (HM turns `.text` into a `mkDefault` `.source`), and two `.text` definitions are concatenated. So `checks.home-owned` does not rely on module-system errors. For every omanix-owned target it compares `definitionsWithLocations` of `home.file.<t>.{text,source}`, and fails with "owned by `omanix.<x>`; set the option, or `lib.mkForce` the `.source` to take the file over" when a host file defines either one without `mkForce`.
- omanix defines **no HM `systemd.user` units and no HM `dconf.settings`** for the human. Session units come from NixOS `systemd.user.*`. dconf keys omarchy writes at runtime stay app-owned.

### c.1 `loom.*` (key options)

```
loom.enable                                bool false
loom.host.id                               strMatching "^[0-9a-f]{32}$"                       (machine.nix)
loom.host.name                             hostname (→ networking.hostName)                   (machine.nix)
loom.host.src                              path (set by mkHost)
loom.host.forkedFrom                       nullOr str null
loom.host.repo.{namespace,path,fetchUrl,pushUrl}   namespace "loom" (omanix: "omanix"); path "${ns}/${id}.git"

loom.keys.humans.<name>                    submodule {
                                             key       = str;              # sk-ssh-ed25519@… or ssh-ed25519 pub
                                             owner     = bool false;       # made the first push = silo .owner_key (F1)
                                             localPath = nullOr str null;  # e.g. "~/.ssh/id_ed25519.pub" when on this host
                                             age       = nullOr str null;  # optional sops recipient (age-plugin-yubikey)
                                           }  ≥1 asserted; exactly one owner asserted        (keys.nix)
loom.keys.host                             str (ssh-ed25519 pub)                              (keys.nix)
loom.keys.agents.<name>                    str (ssh-ed25519 pub)                              (keys.nix)
loom.keys.enroll                           nullOr str null (mint commit only)                 (keys.nix)
                                           A software human key must be passphrase-protected (checked when added, D10).

loom.user.{name,fullName,email}            str
loom.user.password                         enum ["sops" "firstboot"] "sops"
loom.locale.{timeZone,language,keyMap}     str/enum   (keyMap: initrd falls back to us for non-Latin)

loom.disk.device                           strMatching "^/dev/disk/by-id/.+"
loom.disk.swap                             enum ["zram" "zram+file"] "zram"; swap.fileSize nullOr str; swap.hibernate bool
loom.disk.rootTmpfsSize                    str "25%"
loom.disk.btrfsUuid                        str (installer-written; → nuketown.btrfsDevice, §a.3 C2)
loom.disk.unlock.methods                   listOf (enum ["recovery" "passphrase" "fido2" "tpm2-pin" "tpm2" "tang"])
                                           "recovery" ∈ methods (asserted); it is the system-encryption-key slot (§g.10)
loom.disk.unlock.automatic                 bool (readOnly) = methods ∩ {tpm2,tang} ≠ ∅
loom.disk.unlock.tpm2.pcrs                 listOf int [7]
loom.disk.unlock.fido2.{clientPin,userPresence} bool true true
loom.disk.unlock.tang.urls                 listOf str []   (servers only)

loom.boot.loader                           enum ["limine" "lanzaboote"] "limine"   (D7)
loom.boot.secureBoot.enable                bool false; tpm2 ∈ methods ⇒ true (asserted)
loom.boot.secureBoot.includeMicrosoftKeys  bool true
loom.boot.maxGenerations                   int 10

loom.persist.root                          str "/persist"
loom.persist.system.{directories,files}    listOf (str | submodule)   feature modules append
loom.persist.installBinds                  listOf str (derived: /var/lib/sbctl, /etc/ssh, /var/lib/loom)
loom.persist.ephemeralOk                   listOf str   StateDirectories deliberately not persisted
loom.persist.snapshots.enable              bool true    (btrbk on @home, @persist: 24h 7d 4w)

loom.home.enable                           bool false   (omanix: true)
loom.home.reclaimDir                       str "~/.local/state/loom/clobbered"

loom.secrets.hostKey.backend               enum ["file" "tpm"] "file"   (tpm asserted off until checks.sops-tpm-age1tag is green)
loom.secrets.recipients.{host,recovery}    str (age)   (recovery = derived from the SEK)          (machine.nix)
loom.secrets.recovery.fingerprint          strMatching "^[0-9a-f]{16}$"                       (machine.nix)
loom.secrets.prompted.<name>               { description; file = enum ["data" "user"]; validate = enum ["nonempty" "psk" "hash"]; }

loom.silo.{enable,host,hostKey}            true, "silo.loom.farm", pinned ed25519
loom.silo.workingCopy                      "/persist/var/lib/loom/host"   (root-owned mirror)

loom.trust.releases.<input>                { signers = listOf str; refPattern = "refs/tags/v*"; }
loom.trust.installCacheKey                 nullOr str   (install-time only; never added to nix.settings)

loom.chat.enable                           bool = loom.agent.enable   (agent bridge socket)

loom.switch.watchdog.timeout               int 120
loom.switch.watchdog.checks.<name>         { command; as = enum ["root" "session"]; critical = bool; baselineRelative = true; }
loom.switch.autoUpdate                     enum ["off" "notify"] "notify"   (never auto-switch)
loom.update.inputs                         listOf str (default: [ "omanix" ]; others only on request, §g.4)

loom.agent.enable                          bool true      install question "Use an AI agent?" yes / later / no (§h.7)
loom.agent.{name,uid}                      "ada", 1100
loom.agent.harness                         enum ["claude-code" "replay"] "claude-code"
loom.agent.{harnessPackage,loginCommand}   package; str (claude-code: "claude" then /login)
loom.agent.sudo                            enum ["listed" "any"] "listed"   (D8; asked at install, never in the sidecar; "any" = approvalAllow null, K8)
loom.agent.sudoCommands                    listOf str [ loom-switch journalctl systemctl fwupdmgr nix-collect-garbage ]   (full paths; each request gets a reviewed card)
loom.agent.promptFragments                 listOf lines
loom.agent.chat.attachments.maxBytes       int 8388608

loom.reviewer.enable                       bool = loom.agent.enable
loom.reviewer.{name,uid}                   "reviewer", 1101
loom.reviewer.harness                      enum ["claude-code" "replay"] "claude-code"
loom.reviewer.loginCommand                 str (claude-code: "claude" then /login)
loom.reviewer.model                        nullOr str null   (null = harness default; a separate login from the resident)
loom.reviewer.timeout                      int 180      (→ nuketown.approval.reviewer.timeout)
loom.reviewer.promptDelay                  int 20       (W1b: show the card before the review lands; v1 as built waits up to loom.reviewer.timeout)

loom.firstboot.steps.<name>                { order; description; command; interactive; doneWhen; }
loom.hardware.facts                        typed submodule from hardware.json
loom.hardware.firmware                     enum ["filtered" "full"] "filtered"
loom.installer.probes.<name>               { command (store path); emits = "quirk" | "fact"; }   (flavor-contributed)
loom.installer.tty                         str "tty1"   (test image: "ttyS0")
```

Nothing is "protected": every `loom.*` option is changed through the same card as any other option.

**Fixed by loom:** `users.users.${loom.user.name}.uid = 1000` (mkDefault), so the installer can write `~/.ssh` before first boot.

**Removed from rev 2:** `loom.settings.settable.*`, `loom.policy.{extraProtected,protectedRepoPaths,humanKeyKind}`, `loom.switch.confirmProtected`, `autoUpdate = "stage"`, `loom.agent.mode` (`"user"` contradicts V3; `"none"` is `loom.agent.enable = false`), `loom.host.{humanKeys,hostKey,agentKeys}` and `loom.secrets.recipients.human` (→ `loom.keys.*`), `loom.home.stateVersion` (plain `home.stateVersion` in `home.nix`). **Removed in rev 4 (V7):** `loom.highlight.*`, `loom.chat.{retention,requestMaxAge}`, `loom.switch.{approvalTtl,keepClick,preflight.*}`, `loom.reviewer.{egress.allow,maxDiffBytes}`, the `"api"` reviewer harness. **Changed in rev 5 (V8):** `loom.agent.sudo` values `"none" | "approval"` → `"listed" | "any"`; new `loom.agent.sudoCommands` and `loom.reviewer.promptDelay`.

### c.2 `omanix.*` (key options; path == file)

```
omanix.enable                              bool
omanix.release                             str (readOnly; tag of this build)
omanix.fork.{src,package}                  inputs.omarchy / pkgs.omarchy-src (readOnly)
omanix.path                                str (readOnly) "/run/current-system/omarchy"
omanix.session.autologin                   bool  default = !config.loom.disk.unlock.automatic
                                           assertion: autologin ⇒ !loom.disk.unlock.automatic
omanix.login.greeter                       enum ["sddm"] "sddm"
omanix.hyprland.package                    package  hyprland-omarchy (0.56.2 + omarchy-pkgs patches)
omanix.hyprland.settings                   attrsOf (JSON-able) {}   → hl.config in HM ~/.config/hypr/looknfeel.lua
omanix.hyprland.monitors                   listOf {output; mode; position; scale; vrr}
omanix.hyprland.windowRules.<name>         {match; float; size; workspace; …}
omanix.hyprland.extraLua                   lines ""   emitted in the HM tail of hyprland.lua (after toggles)
omanix.hyprland.fileLua.<f>                lines ""   f ∈ {monitors,input,bindings,looknfeel,autostart}; end of HM hypr/<f>.lua, before its overlay
omanix.hyprland.gdkScale                   int 2
omanix.hyprland.titlebars.enable           bool true
omanix.keybinds.{defaults,preinstalled}    bool true true
omanix.keybinds.binds.<name>               {keys; description; action = {launch|webapp|tui|menu|ipc|intent}; replaces ? null}
omanix.keybinds.unbind                     listOf str
omanix.menu.items.<id>                     {label; icon; action | intent = str; after ? null; when ? null}
omanix.shell.settings                      JSON attrs {}   merged over upstream shell.json defaults (default layer)
omanix.shell.plugins.<n>                   { src = path (flake input); enable = bool; }
omanix.shell.package                       quickshell-omarchy
omanix.chat.{keybind,menuFallthrough}      "SUPER + A" (U25), true
omanix.welcome.{enable,tour}               bool true true
omanix.theme.default                       enum <registry> "tokyo-night"
omanix.theme.{lock,intros}                 bool false false
omanix.theme.available                     listOf name (all)
omanix.theme.extra.<slug>                  {src (flake input path); trusted = false}   (a theme's hyprland.lua is code)
omanix.theme.background                    nullOr path null
omanix.theme.boot.theme                    str = theme.default   (plymouth/sddm/limine colors; rebuild-time)
omanix.defaults.{terminal,browser,editor,dictation}   enum
omanix.apps.<name>.enable                  bool (omarchy base list)
omanix.apps.webapps.<Name>                 {url; icon; bind ? null; mimeTypes}
omanix.apps.tuis.<Name>                    {command; style; bind ? null}
omanix.apps.chromium.features              listOf str []
omanix.input.{layouts,options,compose,touchpad.*}
omanix.fonts.{monospace,cjk}
omanix.language                            enum <upstream default/i18n registry> "en"
omanix.dns.provider                        enum ["dhcp" "cloudflare" "google" "custom"] "dhcp"; dns.servers listOf str
omanix.region                              enum ["global" "cn"]   (mirrors only, never new trust)
omanix.branding.{about,screensaver}        nullOr (lines | path) null
omanix.hooks.<name>                        lines
omanix.hardware.{gpu,isVM,laptop}          from hardware.json facts
omanix.hardware.quirks.<name>.enable       bool (mkEnableOption; set by loom-detect in hardware.nix, §f.2.6)
omanix.home.enable                         bool true
omanix.home.overlays                       enum ["keep" "reset"] "keep"   (O1) reset ⇒ session init empties overlays at login
omanix.home.files                          attrsOf {target; source; overlay ? null; module}   (readOnly; → catalog/home.json)
omanix.home.appOwned                       listOf str (readOnly) btop.conf, fcitx5/**, chromium profile, mimeapps.list, dconf
omanix.runtime.absorbed.<area>             nullOr str null   sha256 of the runtime snapshot a "make it stick" change absorbed (§f.4.6)
omanix.cli.commands.<group>.<name>         registry → router + commands.json
```

**Removed from rev 2:** `omanix.upstream.*` (→ `omanix.fork.*`), `omanix.home.extraModules` (→ `home.nix` imports), `omanix.defaults.agent` and `omanix.agents.harnesses.*` (the human's own coding harnesses are ASSET launchers from upstream; the resident's harness is `loom.agent.harness`), and every `settable:*` annotation.

### c.3 nuketown configuration

loom sets two agents and the approval options of §a.3:

```nix
nuketown = {
  enable = true;
  humanUser = config.loom.user.name;                                   # C4
  btrfsDevice = config.loom.disk.btrfsUuid;                            # C2 (machine.nix, written by the installer)
  sopsFile = config.loom.host.src + "/secrets/agents.yaml";            # C3
  approval.reviewer = {                                                # K5
    enable = cfg.reviewer.enable;
    agent = cfg.reviewer.name;
    inherit (cfg.reviewer) timeout;                                    # command = null: nuketown's claude -p reviewer
  };
  approval.kinds.loom-switch = {                                       # K7 (W1b), §g.3
    command = "/run/current-system/sw/bin/loom-switch";
    collect = "${pkgs.loom-switch}/libexec/loom-switch-collect";
    reviewPrompt = "${pkgs.loom-switch-review}/prompt.md";
    timeout = 0;                                                       # until answered or the requester exits
  };
};
home-manager.users.${config.loom.user.name} = {             # C4: the broker is an HM module in nuketown
  imports = [ nuketown.homeManagerModules.approvalDaemon ];
  nuketown.approvalDaemon.enable = true;                    # omanix adds .prompter = omanix-approval-prompt (K6)
};
nuketown.agents.${cfg.agent.name} = {          # resident, default "ada", uid 1100
  enable = cfg.agent.enable; uid = cfg.agent.uid; role = "software";
  sudo.enable = true;                                                  # C8: only "start nuketown-approve as nuketown-approval"
  sudo.approvalAllow = if cfg.agent.sudo == "any" then null else cfg.agent.sudoCommands;   # K8, D8
  persist.directories = [ "projects" ".claude" ];
  secrets.sshKey = "${cfg.agent.name}/ssh";
  portal = { enable = true; command = cfg.agent.loginCommand; };      # C7
  claudeCode = { enable = cfg.agent.harness == "claude-code"; extraPrompt = lib.concatLines cfg.agent.promptFragments; };
};
nuketown.agents.${cfg.reviewer.name} = {       # reviewer, default "reviewer", uid 1101
  enable = cfg.reviewer.enable; uid = cfg.reviewer.uid; role = "review";
  persist.directories = [ ".claude" ];         # its own login
  portal = { enable = true; command = cfg.reviewer.loginCommand; };   # sign-in only
  claudeCode.enable = cfg.reviewer.harness == "claude-code";
};
users.users.${cfg.agent.name}.extraGroups = [ "systemd-journal" ];   # omanix's residents.nix adds "omanix-resident"
```

The reviewer has no ssh key and no sudo, and is not in `.authorized_keys`. It reads request directories through the `nuketown-approval` group, which also holds the human. It is otherwise an ordinary nuketown agent: v1 does not sandbox it (Appendix H.5).

---

## d) Host repo

### d.1 File tree (`silo:omanix/<id>.git`, branch `master`)

```
flake.nix              # inputs: omanix + follows + plugin inputs; outputs: nixosConfigurations.host
flake.lock
configuration.nix      # preferences; imports the rest (installer-written, then agent/human-edited)
home.nix               # the human's home-manager module (plain HM)
machine.nix            # this machine: id, name, disk, unlock, boot, recipients, stateVersion (installer-written)
keys.nix               # loom.keys: humans / host / agents / enroll (single source)
hardware.nix           # nixos-generate-config --no-filesystems + quirk enables (regenerable)
hardware.json          # loom-detect facts (cpu/gpu/tpm2/fido2/sb/pci+usb ids/quirks/firmware globs)
modules/
  default.nix          # explicit imports = [ ./plugins.nix ./persist.nix … ] (no readDir)
  plugins.nix          # imports of NixOS modules from plugin inputs
  persist.nix          # host-level loom.persist.system additions
  home/                # HM modules split out of home.nix when it grows
secrets/
  host.yaml  user.yaml (password hash, neededForUsers)  data.yaml (Wi-Fi PSKs, app tokens)  agents.yaml (C3)
.sops.yaml             # GENERATED from keys.nix + machine.nix
.authorized_keys       # GENERATED: humans + host + agents            (silo transport, F2/F5; never deleted)
CODEOWNERS             # GENERATED: humans + host; NEVER agents      (silo master gate, F4; never deleted)
allowed_signers        # GENERATED: <name>@human|host|agent principals (git verification in any clone)
.loom/install-cache.pub   # optional per-host install cache key (§e.3)
.gitignore             # result, result-*
CLAUDE.md              # host notes for the resident (§d.4)
.claude/skills/        # optional host-local skills (ordinary reviewed files)
```

**Who writes which file.** No file is restricted. Every change reaches the machine only through an approved card. The last column is what the card's flags line says (§g.3, switch step 2).

| File | Written by | Card flag |
|---|---|---|
| `configuration.nix`, `home.nix`, `modules/**` | resident, terminal user | — (packages via nvd; the diff) |
| `flake.nix`, `flake.lock` | `omanix plugin add`, `omanix update`, update timer, human | `flake.lock`: inputs added, removed or moved |
| `machine.nix` | installer, `loom unlock`, `loom keys rotate` | `machine.nix` changed |
| `keys.nix` + generated files | installer, `loom keys add-human/remove-human/sync` | `keys.nix` / `.authorized_keys` / `CODEOWNERS` changed |
| `hardware.nix`, `hardware.json` | installer, `loom hw regen`, `omanix hw probe --write` | — |
| `secrets/**` | `omanix secret set` (encrypt-only), `loom keys` (re-encrypt) | `secrets/**` changed |
| `CLAUDE.md`, `.claude/skills/**` | anyone | — (no system effect) |
| `.claude/settings*.json`, `.claude/hooks/**`, `.mcp.json`, `.envrc`, `.vscode/**`, `.gitattributes`, `.githooks/**` | anyone | — (these run code as the human when the human opens a harness, a direnv shell or an editor in `~/omanix-host`; a flag for them is Appendix H.8) |

### d.2 Installer-written files

```nix
# flake.nix
{
  description = "kestrel — an omanix host";
  inputs = {
    omanix.url = "git+https://silo.loom.farm/omanix.git?ref=refs/tags/v0.1.0";
    nixpkgs.follows = "omanix/nixpkgs";           # one nixpkgs / one HM for plugins (one Mesa, one Qt)
    home-manager.follows = "omanix/home-manager";
    # plugins are added here by `omanix plugin add`; each one appears on an approval card
  };
  outputs = inputs@{ self, omanix, ... }: {
    nixosConfigurations.host = omanix.lib.mkHost { inherit self inputs; };
    checks.x86_64-linux.host = self.nixosConfigurations.host.config.system.build.toplevel;
  };
}
```

```nix
# configuration.nix
{ lib, pkgs, ... }:
{
  imports = [ ./machine.nix ./keys.nix ./hardware.nix ./modules ];

  loom.user = { name = "josh"; fullName = "Joshua Perry"; email = "josh@6bit.com"; };
  loom.locale = { timeZone = "America/Denver"; keyMap = "us"; language = "en_US.UTF-8"; };
  loom.agent = { name = "ada"; harness = "claude-code"; sudo = "listed"; };   # D8: written explicitly

  omanix.theme.default = "tokyo-night";
  omanix.defaults = { terminal = "alacritty"; browser = "chromium"; editor = "nvim"; };
  omanix.apps.obsidian.enable = true;

  # Below this line: changes made by the agent or by you. Each one was approved on a card.
}
```

```nix
# home.nix
{ pkgs, ... }:
{
  # The human's home-manager module. Files HM writes are read-only store links (D9).
  # omanix already owns the desktop dotfiles (hypr/*.lua, terminals, fontconfig, …): change those
  # through omanix.* options in configuration.nix (`omanix where <file>` tells you which).
  home.stateVersion = "26.11";
  home.packages = with pkgs; [ ];
}
```

```nix
# machine.nix
{
  loom.host = { id = "3f9c0a…"; name = "kestrel"; };
  loom.hardware.facts = builtins.fromJSON (builtins.readFile ./hardware.json);
  loom.disk = { device = "/dev/disk/by-id/nvme-Samsung_…"; unlock.methods = [ "recovery" "fido2" "passphrase" ]; };
  loom.boot.secureBoot.enable = false;
  loom.secrets.recipients = { host = "age1…"; recovery = "age1…"; };
  loom.secrets.recovery.fingerprint = "5be1c0…";
  system.stateVersion = "26.11";
}
```

```nix
# keys.nix
{
  loom.keys = {
    humans.josh-yk = { key = "sk-ssh-ed25519@openssh.com AAAA… josh@yk"; owner = true; age = "age1yubikey1…"; };
    host = "ssh-ed25519 AAAA… root@kestrel";
    agents.ada = "ssh-ed25519 AAAA… ada@kestrel";
    enroll = null;                        # set only in the mint commit; the installer's enrollment push sets null
  };
}
```

### d.3 Generated files and `loom keys sync`

`keys.nix` is the single source. `loom keys sync` renders four files with a deterministic order (humans sorted by name, then host, then agents) and trailing `# loom:<role>:<name>` comments. The reviewer has no key: it writes nothing.

| File | Lines | Consumer | Effect |
|---|---|---|---|
| `.authorized_keys` | humans + host + agents (+ enroll in the mint commit) | silo transport (F2), synced on master update (F5) | everyone listed can push **something** |
| `CODEOWNERS` | humans + host (+ enroll in the mint commit); **never agents** | silo pre-receive on non-gate refs (F4) | the agent key can push **only `gate/*` and `refs/dit/*`** (new or fast-forward; silo checks no CODEOWNERS there, and `loom-switch` ignores them); master moves only by humans or by `loom-switch` (host key) after a promoted switch |
| `allowed_signers` | `<name>@human namespaces="git" <key>`, `<host>@host …`, `<n>@agent …` | `git log --show-signature` in any clone; `/etc/loom/allowed_signers` is built from the **running** generation | informational in v1 (signed approvals are Appendix H.3) |
| `.sops.yaml` | creation rules: host + humans' `age` + recovery, per file in `secrets/` | sops | the agent can encrypt to recipients but never decrypt (it holds no identity) |

`checks.keys-sync` re-renders and compares byte for byte; `omanix check` runs the same check before every proposal, and `loom-switch`'s collector refuses a tree without `.authorized_keys` or `CODEOWNERS`. **Refused:** a commit that deletes `.authorized_keys` or `CODEOWNERS` (F5), or that leaves `loom.keys.humans` with no owner or more than one.

### d.4 `CLAUDE.md` (repo) and where the resident's guidance comes from

The resident's **global** prompt carries the omanix guidance (nuketown `promptFragments` from `loom.agent.promptFragments` and omanix), and its skills come from the `omanix-skills` package linked into `/agents/<n>/.claude/skills/`. Both update with the omanix release, so the host repo never carries stale copies. The repo `CLAUDE.md` holds only host-specific notes; the installer writes:

```markdown
# kestrel

This repo is the NixOS + home-manager configuration of the machine kestrel (omanix host).
Run `omanix context --json` first.

- Preferences: configuration.nix (omanix.*, loom.user/locale/agent). Human dotfiles: home.nix
  (plain HM; desktop dotfiles are owned by omanix.* options — check `omanix where <file>`).
- Your own modules go in modules/ and must be listed in modules/default.nix.
- Plugins: `omanix plugin add <flakeref>`; never hand-edit flake.lock.
- keys.nix and the files generated from it: change only with `loom keys`.
- Every change: edit → `omanix check` → commit → `omanix propose --request "<the human's words>"`.
  Batch everything for one request into one proposal. The human approves on a card.
- Never run nixos-rebuild, disk, LUKS or key tools yourself. Never ask for or handle secrets: tell the
  human which human-only tool to use.

## Notes about this machine and its human
(none yet)
```

### d.5 Host repo id (exact)

The id is `appSpecific(machineId, OMANIX_APP_ID)`, using systemd's algorithm:
1. Compute `HMAC-SHA256(key = machine-id as 16 raw bytes, msg = app-id as 16 raw bytes)`.
2. Take the first 16 bytes.
3. Apply the v4 fixups `b[6] = (b[6] & 0x0f) | 0x40` and `b[8] = (b[8] & 0x3f) | 0x80`.
4. Encode as 32 lowercase hex characters.

Implementation details:
- It lives in `loom-mint` (python stdlib), so it runs on Linux, macOS and WSL2.
- `loom/lib/repo-id.nix` holds the app ids (omanix's is a fixed UUID constant) and test vectors.
- **`checks.repo-id-vector`** boots a VM with a fixed `/etc/machine-id` and asserts that `systemd-id128 machine-id --app-specific=<OMANIX_APP_ID>` equals the Python result.

Where the machine-id comes from:
- `loom-mint` mints the machine-id (`systemd-id128 new` semantics, 128-bit random v4) together with the repo id.
- The machine-id travels **only in the sidecar** (§d.6), never in the repo. The installer writes it to `/persist/etc/machine-id`.
- In fresh mode, the installer verifies `id == appSpecific(machineId)` and refuses on a mismatch.

On reinstall the machine gets a new machine-id but keeps the repo id. `loom.host.id` is therefore a literal, and the id/machine-id relation is guaranteed only at mint time. It is never a raw machine-id.

### d.6 Sidecar (`OMANIX-CFG`, vfat, schema `loom.sidecar/v2`)

```
OMANIX-CFG/
  sidecar.json
  host.bundle          # git bundle of the host repo at `commit` (owner-signed mint commit)
  enroll.key           # per-repo single-use enrollment private key (ed25519); preconfigured mode only
  install-cache/       # optional: nix-cache-info, *.narinfo, nar/*.nar.zst signed by the host's install cache key
  SHA256SUMS           # integrity only
```
```json
{
  "schema": "loom.sidecar/v2",
  "host": { "id": "3f9c0a…", "commit": "a1b2…", "machineId": "9e1f…" },
  "enrollment": { "publicKey": "ssh-ed25519 AAAA… enroll-3f9c" },
  "answers": { "hostname": "kestrel", "user": { "name": "josh", "fullName": "Joshua Perry", "email": "josh@6bit.com" },
               "locale": { "timeZone": "America/Denver", "keyMap": "us", "language": "en_US.UTF-8" },
               "theme": "tokyo-night", "defaults": { "terminal": "alacritty" }, "apps": [ "obsidian" ] },
  "hints": { "unlock": ["fido2", "passphrase"] }
}
```

- `answers` is a **closed, typed set** restricted to rows that touch no security: hostname, user name/full name/email, locale, theme, defaults, apps. Unknown keys are refused. The installer renders them through `loom-hostgen` (§e.5a) and commits `install: apply answers`. **Unlock, Secure Boot, the SEK, keys, `loom.agent.enable`, `loom.agent.sudo` and the disk are never in the sidecar.** They are asked in the TUI or come from the owner-signed mint commit in the bundle. `hints` only preselect TUI answers.
- **The sidecar never contains** passwords or hashes, Wi-Fi PSKs, API keys, AI-assistant logins or tokens, personal SSH/GPG private keys, the system encryption key, substituter URLs or cache public keys. The validator rejects unknown keys and known secret patterns: `-----BEGIN` outside `enroll.key`, `sk-ant-`, `ghp_`, `AKIA`, `AGE-SECRET-KEY`, and `SEK1-`.
- **What the enrollment key can do.** From mint until the installer's enrollment push, `enroll.key` can push `master`, because it is in `.authorized_keys` and `HEAD:CODEOWNERS` (F2, F4). It cannot remove the owner (F1), it is never in `allowed_signers`, and it is never a sops recipient. **It can, however, rewrite or force-push `master`, including adding its own attacker keys to both files (F4 has no fast-forward or content check).** A lost or stolen stick before install is handled by `configure revoke-enroll <id>` (§e.2 step 7). The installer refuses to enroll if silo's `master` ≠ `sidecar.host.commit` (§g.7).
- The login password is **prompted in the installer TUI** and hashed with yescrypt. The hash is sops-encrypted to host + human + recovery into `secrets/user.yaml`. The alternative is `loom.user.password = "firstboot"`.
- Reinstall or VM test without a sidecar: the repo id comes from the kernel cmdline `loom.host=<id>` or a TUI prompt. No other config file is read.

---

## e) USB installer, end to end

### e.1 Image (`loom.lib.mkInstallerImage`, nixpkgs `image.repart`, no nixos-generators)

| # | Partition | Format | Contents |
|---|---|---|---|
| 1 | ESP | vfat 512 MiB | systemd-boot + installer UKI (installer only; the installed system uses Limine by default, or lanzaboote, D7) |
| 2 | STORE | erofs zstd + dm-verity | Installer closure: `minimal` + `perlless` where possible, `all-hardware`, full `linux-firmware`, nix, disko, cryptsetup, sbctl, tpm2-tools, age, age-plugin-tpm/-tag, age-plugin-yubikey, sops, git, gum, loom-installer, flavor probes. Includes the release cache public key. |
| 3 | CACHE | erofs, uncompressed (the content is already `.nar.zst`), + dm-verity | Release `file://` cache: closures of `ref-default`, `ref-nvidia` and `ref-laptop`, plus `nix flake archive` of omanix and all inputs, signed `omanix-cache-1`. **Absent in the `net` variant.** |
| 4 | OMANIX-CFG | vfat 256 MiB (flash-usb grows it) | sidecar |

- **Verity is corruption detection, not authenticity.** The root hashes sit on the unsigned ESP cmdline. Authenticity comes from `SHA256SUMS.sig` over the image file, which `flash-usb` verifies, plus the readback hash after writing. On a verity error the installer says "This USB stick is damaged. Re-flash it."
- The installer is not Secure Boot-signed. To boot it, the user disables Secure Boot or puts the firmware in **Setup Mode**. Setup Mode is also what enables the TPM2-automatic option (§e.6).
- Size checks:
  - `checks.closure-budget`: offline image ≤ 3.5 GiB (the bar is omarchy's ~6 GB), net image ≤ 200 MB;
  - `system.forbiddenDependenciesRegexes` (`-doc$`, `texlive`, `ghc-`);
  - `checks.closure-dupes`: no second Mesa, LLVM or Python major.
- The installed store is the `@nix` subvolume (`compress=zstd,noatime`) with `auto-optimise-store`.
- Release (D11): images are built from signed tags. `SHA256SUMS` is signed with `ssh-keygen -Y sign -n omanix-release` on **Josh's YubiKey**, and the tag is SSH-signed on the same key. The `omanix-cache-1` cache signing key lives on signi in sops and is used only by the `release` skill, through an approval. **No CI secrets in v1**: CI builds and tests, and never signs.

### e.2 Configure skill (on the user's existing computer; the agent converses, scripts act)

1. `scripts/configure.sh` checks its own signature (§e.10), then runs `nix run .#configure -- … --json`.
2. The conversation collects:
   - hostname, user and full name, timezone, keymap, theme, default apps, extra apps, a GPU guess;
   - an optional human age recipient (YubiKey);
   - **agent sudo** (D8). The question is: "Should <agent> be able to ask you for any administrator (sudo) command, beyond its short list (applying changes, logs, services, firmware, cleaning the nix store)? Each request shows a card with an AI explanation and runs only if you approve." Answers are `listed` (default) or `any`, written to `loom.agent.sudo`. The installer asks again with this answer preselected.
   - the **owner human SSH key**. **It must be usable on this computer, because it makes the first push and becomes silo's owner (F1).** Three choices:
     - recommended: a FIDO2 key, `ssh-keygen -t ed25519-sk -O resident -O verify-required -O application=ssh:omanix`;
     - an existing key that ssh can use here (agent or file); the skill checks this with a dry-run sign (`ssh-keygen -Y sign -n loom-probe`). If it is a software key file with **no passphrase** (`ssh-keygen -y -P "" -f` succeeds), the skill refuses it and offers to add a passphrase (`ssh-keygen -p`) or to generate a new key (D10);
     - a new software key, `ssh-keygen -t ed25519 -a 100`, **with a mandatory passphrase** (refused if empty). The skill says FIDO2 is recommended. It does **not** say the software key lowers anything, because it doesn't (D10).
   - optional **additional human public keys**. Each must parse as `sk-ssh-ed25519@openssh.com` or `ssh-ed25519`. These are not owners. They go into `keys.nix`, and from there into `.authorized_keys` and `CODEOWNERS`.

   **The skill never asks for passwords or tokens, and the answers schema has no field for them.** It never handles the system encryption key, which only the installer generates (§e.5).
3. `configure mint` (`loom-mint`):
   1. Mints the machine-id and the repo id (§d.5).
   2. **Pre-check:** `git ls-remote ssh://git@<silo>/omanix/<id>.git` must fail with `repository not found`. Otherwise it aborts. With a 128-bit id this only catches bugs.
   3. Generates `enroll.key` (ed25519, no passphrase, 0600).
   4. Renders the host template with `loom-hostgen` (§e.5a): `configuration.nix` (including `loom.agent.sudo`), `home.nix`, a stub `machine.nix` (only `loom.host.id`), and `keys.nix` with the humans (owner flagged) and `enroll`.
   5. Runs `loom keys sync`, which renders `.authorized_keys = owner + additional humans + enroll` and `CODEOWNERS = owner + additional humans + enroll`. Each line is `<type> <blob> <label>`, with label `enroll-<id8>` on the enroll line.
   6. Commits `mint: <host>`, **signed by the owner key** (`gpg.format=ssh`).
   7. **Pushes `master` with the owner key** (`GIT_SSH_COMMAND="ssh -o IdentitiesOnly=yes -i <owner key>"`). Silo auto-creates the repo with `.owner_key = owner` (F1). post-receive copies `.authorized_keys`, so the enroll key is now transport-authorized (F5).
   8. **Verify:** `ls-remote --symref` shows `HEAD → refs/heads/master` and `master = <commit>` (§a.4 HEAD check). If the push failed after the auto-create, re-running `mint --resume` pushes again: the owner is already set to this key.

   Optionally, the user adds data secrets encrypted **only to human age recipients**. The installer can re-encrypt them with the YubiKey.
4. `configure check` evaluates the host offline-capably and reports `cacheMiss: [...]` against the release cache's narinfo list.
5. `configure stage-cache` (only if there are misses and local Nix exists):
   - generates a per-host signing key (`nix key generate-secret`);
   - commits `.loom/install-cache.pub` and sets `loom.trust.installCacheKey` (owner-signed, pushed with the owner key);
   - builds the misses and runs `nix copy --to file://…/install-cache`;
   - signs with `nix store sign -k`;
   - **deletes the secret key**.
6. `configure sidecar` writes `sidecar.json` with `commit` = silo's current `master`, then `host.bundle` (`git bundle create`), `enroll.key`, `install-cache/` and `SHA256SUMS`. It then hands off to build-installer.
7. `configure revoke-enroll <id>` is for a lost stick or an abandoned install. It is idempotent and works as follows:
   1. `git ls-remote` silo's `master` and compare it with `sidecar.host.commit` (kept in `~/.local/state/omanix/hosts/<id>.json` on the configuring computer).
   2. Fetch and list **every commit since the sidecar commit that is not signed by an owner or additional human key** (`allowed_signers` of the sidecar commit), with author, files touched and a `.authorized_keys`/`CODEOWNERS` diff.
   3. Rewrite **both files to the exact expected set** taken from the last owner-signed commit: owner + additional humans, with no enroll line and no other key. It never "removes one line" from whatever is on silo.
   4. Push that owner-signed commit with the owner key (F3). post-receive re-syncs the bare `.authorized_keys` (F5), so every key the stick may have added loses transport access.
   5. **If `master` had moved** (step 2 listed anything), the tool stops before step 3 and recommends a **re-mint** (`configure mint` with a new machine-id and id) instead of reusing the repo: configuration files, `.sops.yaml` and other files may have been changed by the stick's holder. `--reuse-anyway` performs steps 3–4 and then shows the full diff since the sidecar commit for the owner to review.

**No Seed-side builder in v1** (D3): misses are built with local Nix on Linux, or in WSL2 on Windows. The `configure check` / `stage-cache` contract ("commit X of repo Y") lets a builder be added later without changing the installer.

Windows users run the engine in WSL2 and copy the sidecar to the vfat partition from any OS. A FIDO2 key needs USB passthrough into WSL2 (`usbipd`); otherwise they use a passphrase software key.

### e.3 Cache trust model

| Cache | Signed by | Key comes from |
|---|---|---|
| release CACHE partition, `cache.omanix…` | `omanix-cache-1` (key on signi in sops; release skill only, D11) | the verity store, the signed release, and `nix.settings` on installed hosts |
| install-cache on CFG | the per-host install cache key | the host repo **at `sidecar.host.commit`**, which is in the bundle and cross-checked against silo with `git ls-remote` when online |
| cache.nixos.org | upstream | the image |

- `require-sigs = true` everywhere. `?trusted=1` is never used.
- The install cache key is **passed only to the `nixos-install` invocation** (`--option extra-trusted-public-keys`). It never enters the installed system's `nix.settings`.
- **Honest limit:** someone who can write the stick can replace the whole image. The integrity root of an install is the stick the user flashed from a verified image.

### e.4 flash-usb (`scripts/flash-usb.sh` → `loom-flash`; two-phase; guards in code)

```
loom-flash plan  --image <img> [--sidecar <dir>] --json
  candidates: TRAN=usb OR removable=1; TYPE=disk; AND none of: a mounted partition, holders
  (dm/LVM/md/LUKS), swap, backing / /boot /nix or the running system; size ≥ image+CFG; size ≤ 512 GiB
  (--allow-large still requires removable)
  prints vendor, model, serial, size, partitions/labels and
  CONFIRM TOKEN = first 10 hex of sha256(by-id path | serial | size | major:minor | image sha256)
loom-flash write --device /dev/disk/by-id/usb-… --confirm <token> [--sidecar <dir>]
  re-resolves the device and recomputes the token (a different stick or image ⇒ exit 2)
  TTY present: also require typing the last 4 characters of the serial
  verifies SHA256SUMS.sig (pinned signers) + image hash → dd oflag=direct conv=fsync → re-read GPT →
  read back and hash the written range → grow OMANIX-CFG → copy the sidecar → verify SHA256SUMS → sync → eject
loom-flash sidecar --device … --confirm <token> --sidecar <dir>     # rewrite the sidecar only
```

- An agent may run `plan` freely. `write` needs a token from a `plan` run against the same physical device and image.
- Distinct exit codes per refusal reason, and JSON progress output.

### e.5 Installer runtime (`loom-installer`, deterministic TUI)

`loom-installer` is a single Python state machine.
- On a color TTY it renders with gum. On a dumb terminal (`TERM=dumb`, the test serial console) it uses line mode, with the same states and the same code.
- Everything is logged as JSON lines to `/run/loom/install.jsonl`, viewable on Alt+F2. It is copied to `/mnt/persist/var/log/loom-install.jsonl`.

**0. Mode.** Mount OMANIX-CFG read-only.
- If `sidecar.json` exists: **preconfigured** mode.
  - Verify `SHA256SUMS`.
  - Verify that `host.bundle` contains `commit`, and that `commit` is signed by the `loom.keys.humans` entry with `owner = true` in its own tree.
  - Verify `id == appSpecific(machineId)`.
  - Validate `answers` (§d.6).
- Else, if the cmdline has `loom.host=<id>` or the user picks "Reinstall an existing host": **reinstall** mode.
  - Clone `fetchUrl` over HTTPS, pinned to the silo host key baked into the image.
  - Show the last five commits on `master` (subject, author, date) and install its tip. v1 does not audit the chain (Appendix H.6).
  - Test images bake `loom.silo.host = "silo.test"`; release images bake `silo.loom.farm`. There is no cmdline override of the silo host.
- Else: **fresh** mode. The installer asks the configure questions in gum forms and runs the same `loom-mint` engine. **There is no other computer, so the owner key must be one of these:**
  - **FIDO2 on this machine** (recommended): `ssh-keygen -t ed25519-sk -O resident -O verify-required -O application=ssh:omanix-<host>` on a plugged-in token. The token's PIN and touch are required.
  - **A software key generated here**: see "Owner key generated on this machine" below.

  A pasted public key alone is accepted only as an **additional** human key: it can't make the first push.
  - **Online:** there is no enroll key. After install, the owner key signs and pushes the **final** tree directly (§g.7, fresh variant). That is one push, and the repo is created with `.owner_key = owner`.
  - **Offline:** the first push waits for the first-boot step `repo-publish` (§e.9). Until then the repo id is unclaimed on silo, and the id is computable locally (machine-id, the rendered files), so anyone who pushes first would become owner (F1, F8). Therefore, **until `repo-publish` succeeds, the resident agent does not run**: every nuketown agent unit (and the agent's `user@<uid>` linger) carries `ConditionPathExists=/persist/var/lib/loom/firstboot/repo-publish.done` (set by `loom.agent` config in every mode). The installer writes that marker itself whenever the repo is already human-owned on silo (preconfigured, reinstall, fork, or a successful fresh-online push), so only offline fresh installs wait. No other local user exists besides the human. `repo-publish` also detects a repo that someone else claimed (§e.9).

**Owner key generated on this machine** (D6/D10). This is offered in every mode: in fresh mode as the owner, and in preconfigured or reinstall mode as an additional human key.
- Screen text: "Generate an SSH key on this computer to control its configuration. It is protected by a passphrase you type when you approve changes. A FIDO2 security key is safer: it can't be copied off this disk. Use this option for VMs and for trying omanix without a token."
- Passphrase:
  - entered twice;
  - pwquality score ≥ 3, otherwise refused;
  - must differ from the disk passphrase;
  - may equal the login password only when its score is ≥ 3, the same rule as the disk passphrase. **On the installed system** (`loom keys add-human --generate`, §g.8) with a resident agent enabled, a passphrase equal to the login password is refused.
- Generation: `ssh-keygen -t ed25519 -a 100 -C "<user>@<host> omanix" -f /run/loom/keys/id_ed25519`, on tmpfs, with the passphrase fed through a pty to ssh-keygen's own prompt. **The passphrase is never on argv or in the environment**, in the installer or on the installed system (where the agent could read `/proc/<pid>/cmdline`).
- Written to the installed home after step 6 mounts it:
  - `/mnt/home/<user>/.ssh/` with mode 0700, owner uid 1000, gid `users`;
  - `id_ed25519` (0600) and `id_ed25519.pub` (0644).

  For FIDO2, the key handle files `id_ed25519_sk{,.pub}` go to the same place. `/home` is a persistent subvolume (H2), so the files survive reboots with no impermanence entry.
- `keys.nix`: `loom.keys.humans.<user>-<host> = { key; owner = <fresh mode>; localPath = "~/.ssh/id_ed25519.pub"; }`.
- **`~/.ssh` is not managed by home-manager** (D9). The human HM profile may not declare any `home.file` target under `.ssh/`, and `programs.ssh` in HM is forced off. SSH client settings go to `/etc/ssh/ssh_config` via `programs.ssh.extraConfig`. `checks.hm-unmanaged-paths` enforces this for `.ssh/` and `.gnupg/`. The read-only HM git config may **reference** the key (`user.signingKey = ~/.ssh/id_ed25519.pub`, `gpg.format = ssh`), generated from `loom.keys.humans.*.localPath`.
- Final screen: "This key exists only on this disk. If the disk dies and you have no other human key, you keep your data through your system encryption key, but you must fork the configuration repo (§g.8). Add a FIDO2 key or another computer's key any time with `loom keys add-human`."

**1. Detect** (`loom-detect` → `hardware.json`):
- disks (non-removable, excluding the boot medium, identified as the parent of the STORE partition)
- TPM2 (`systemd-analyze has-tpm2`, `/sys/class/tpm/tpm0/tpm_version_major`, fTPM vendor heuristics)
- FIDO2 (`systemd-cryptenroll --fido2-device=list`, `hmac-secret`)
- Secure Boot state (`off` | `on (vendor keys)` | `setup mode`)
- CPU, GPU, DMI, PCI/USB ids, RAM
- firmware globs (`modinfo -F firmware` of bound modules)
- **flavor probes** from `loom.installer.probes`. omanix contributes omarchy's read-only `omarchy-hw-*` predicates as store paths, which yields `quirks[]`.

**2. Disk.** Whole disk only.
- Show model, serial, size, partitions and OS signatures (`wipefs -n`, "Contains: Windows 11").
- Confirm by typing the hostname, plus `ERASE` if an OS signature was found.
- The choice is written as a by-id path, and major:minor plus serial are re-checked right before writing (TOCTOU).

**3. Unlock.** Show the capability matrix (§e.6) with only the available rows. Secure Boot enrollment is offered when the firmware is in setup mode.

**4. Local secrets.**
- Login password, entered twice. The pwquality score is shown.
- Disk passphrase. "Same as login" is allowed only when the score is ≥ 3. The installer refuses a disk passphrase that parses as a system encryption key (§g.10).
- TPM PIN, if chosen.
- Software owner key passphrase, if that option was chosen (above).

**4a. Agent (V3, D8).** First: **Use an AI agent?** *Yes* (the resident `ada` and the reviewer are set up; each signs in through its own normal login after first boot), *Later* (set up, signed out), or *No* (`loom.agent.enable = false`: no residents; everything works through the menu how-tos and your own commits). Then, unless the answer is *No*, the sudo question below. In preconfigured and reinstall mode, the repo's values are preselected.

> **Can <agent> ask for any administrator command?**
> No (recommended): <agent> may ask only for its short list: applying changes, reading logs, restarting services, firmware updates, cleaning the nix store. Each request shows a card you approve.
> Yes: <agent> may ask for any command as root. Each one still shows a card with an AI explanation of what it will do, and runs only if you approve. Treat each approval as handing over root for that command.
> You can change this later through a card.

The answers are written to `loom.agent.enable` and `loom.agent.sudo` (`"listed"` | `"any"`) by `loom-hostgen` in the install commit.

**5. System encryption key** (replaces "Recovery kit"; §g.10).
- Generated in installer memory from `getrandom`. The live image has no swap.
- Shown once as text in the canonical format (`SEK1-XXXX-…`, 9 groups) and as a QR code.
- Screen text: "This is your **system encryption key**. It unlocks this disk and your encrypted settings when everything else is lost: a dead TPM, a lost security key, a forgotten passphrase, or a reinstall. Write it on paper and keep it somewhere safe. Omanix does not store it anywhere and cannot show it again. Anyone who has it can read this computer's disk."
- **Paper check:** after the user confirms it is written down, the screen clears and the user types the **complete key back from paper**. It is accepted only if it parses and its `fp` equals the generated one; otherwise the key is shown again and the check repeats. (The check group only detects a misread character; it cannot correct one, so every group must be verified from the paper copy.) This happens before §e.7 wipes the bootstrap slot, so a disk is never left with an unverified SEK as its only recovery path.
- The key is never written to the stick, the disk or the log. The installer keeps only the derived values (`K_luks` for step 6, the age recipient, and the fingerprint).
- **Reinstall mode:** the screen first asks "Do you have this computer's system encryption key?" If the user types it and its fingerprint matches `loom.secrets.recovery.fingerprint`, it is **kept**: the same key unlocks the new disk, and secrets stay readable (§g.8). Otherwise a new one is generated and shown.

**6. Partition and FDE** (§e.7). **7. Secure Boot** (optional). **8. Keys, secrets, install** (§e.8). **9. Enrollment** (§g.7). **10. Finish** (§e.8).

### e.5a Writing the host repo (`loom-hostgen`)

`loom-hostgen` is part of `loom-installer` and of the configure engine (python stdlib).
- **Input:** an answers object with a fixed key set, typed and validated per row (table below). Unknown keys are refused.
- **Output:** the template files with values substituted in place. Every string goes through one serializer, `to_nix_str` (escapes `\`, `"` and `${`, rejects control characters), so no answer can produce Nix syntax. The installer never emits free-form Nix (H15).
- **After rendering:** `nix eval --json .#nixosConfigurations.host.config.<path>` for every answer path, compared with the answer. A mismatch stops the installer before anything is written to disk.
- `nixfmt` on the output, so later diffs stay small.

| Answer (TUI / configure / sidecar) | Validation | File | Line written |
|---|---|---|---|
| host repo id | `^[0-9a-f]{32}$`; `appSpecific` check in fresh mode | machine.nix | `loom.host.id` |
| hostname | RFC 1123 label | machine.nix | `loom.host.name` |
| user name / full name / email | `^[a-z_][a-z0-9_-]{0,31}$` / printable / simple RFC 5322 | configuration.nix | `loom.user = { … };` |
| login password | typed twice | secrets/user.yaml | yescrypt hash; `loom.user.password` stays `"sops"` (or `"firstboot"`) |
| time zone / keymap / language | tzdata / xkb / supported locales | configuration.nix | `loom.locale`, and `omanix.language` when not `en` |
| target disk | by-id path of a non-removable device | machine.nix | `loom.disk.device` |
| btrfs filesystem UUID (after mkfs) | — | machine.nix | `loom.disk.btrfsUuid` (→ `nuketown.btrfsDevice`, §a.3 C2) |
| unlock methods | capability matrix (§e.6) | machine.nix | `loom.disk.unlock.methods` |
| Secure Boot / loader | probe + choice (D4, D7) | machine.nix | `loom.boot.secureBoot.enable`; `loom.boot.loader` only when not the default |
| SEK | §g.10 | machine.nix | `loom.secrets.recipients.recovery`, `loom.secrets.recovery.fingerprint` |
| host age key (generated) | — | machine.nix | `loom.secrets.recipients.host` |
| human key (FIDO2, existing pubkey, or generated passphrase software key, D6) | key-type allowlist; software ⇒ passphrase (D10) | keys.nix | `loom.keys.humans.<n> = { key; owner; localPath; age; };` |
| host / agent ssh keys (generated) | — | keys.nix; `secrets/agents.yaml` | `loom.keys.host`, `loom.keys.agents.<n>` |
| use an AI agent (yes / later / no) | enum | configuration.nix | `loom.agent.enable` (false only for "no") |
| agent name / harness | `^[a-z][a-z0-9-]{0,15}$` / catalog enum | configuration.nix | `loom.agent = { name; harness; … };` |
| any-command approval sudo for the resident (D8) | yes/no, default no | configuration.nix | `sudo = "listed";` written explicitly, `"any"` on yes |
| theme, default apps, apps | catalog enums | configuration.nix | `omanix.theme.default`, `omanix.defaults`, `omanix.apps.<n>.enable` |
| hardware | loom-detect + `nixos-generate-config --no-filesystems` | hardware.json / hardware.nix | whole files, plus `omanix.hardware.quirks.<n>.enable = true;` per matching probe (§f.2.6) |
| stateVersion | release nixpkgs version | machine.nix / home.nix | `system.stateVersion`, `home.stateVersion` |
| Wi-Fi used during install | — | **not in the repo** | if the user ticks "remember", an NM keyfile in `/persist/etc/NetworkManager/system-connections/` (typed on this machine; nothing is copied from anywhere) |

**Commits.**
1. **Mint** (configure skill on the user's existing computer, or fresh mode in the installer; owner-signed, owner-pushed, §g.7): the template rendered from the configure answers, `keys.nix` with humans and `enroll`, the generated files, and a stub `machine.nix` with only `loom.host.id`. The mint commit is not expected to build (`checks.keys-sync` still passes on it).
2. **`install: apply answers`** (host-signed): sidecar answers re-rendered over the mint files. In fresh mode this commit carries all the answers.
3. **`install: <host> on <disk>`** (host-signed): `machine.nix`, `hardware.{nix,json}`, `secrets/*`, `keys.nix` (host and agents added, any generated human key, `enroll = null`) and the `loom keys sync` output.
4. First boot runs commit 3 (installed by `nixos-install`, so it needs no card). **Every later switch goes through a card** (H5).

### e.6 Unlock capability matrix (screen text; source in `loom/modules/loom/disk/unlock-text.nix`, also `catalog/unlock.json`)

The screen always says: **"Every method you add is an alternative way in. The disk is only as strong as the weakest method."**

| Method | Offered when | Pros (shown) | Cons (shown) | Autologin |
|---|---|---|---|---|
| **System encryption key** | always (**mandatory**) | Works when everything else is lost: dead TPM, lost key, forgotten passphrase, disk moved to a new machine. It also recovers your encrypted settings after a reinstall. 160-bit random, so it can't be guessed. | Must be kept offline. Anyone who has it can unlock the disk and read your encrypted settings. Typed at boot in the `SEK1-…` form. | n/a |
| **Passphrase** | always | Works on any hardware. Nothing to lose except your memory. | Typed every boot. It can be watched or guessed, and it is only as strong as you make it (score ≥ 3 required). The prompt uses the US layout if your layout is non-Latin. | allowed |
| **FIDO2 key** (PIN + touch) | token with hmac-secret detected | Can't be copied. The PIN locks after a few tries. Stealing the laptop alone doesn't unlock it. Strongest everyday choice. | Must be plugged in at boot. If you lose it, you need a backup key, the passphrase or the system encryption key. You are prompted to add a backup key. | allowed (**recommended**) |
| **TPM2 + PIN** | TPM2 detected | Short PIN, protected by TPM anti-hammering. The disk unlocks only in this machine. | A firmware update or TPM clear (common on AMD fTPM) disables it until you `loom unlock reseal`. **Without Secure Boot, someone with brief physical access can replace the boot files to capture your PIN.** | allowed |
| **TPM2 automatic** | TPM2 **and** firmware in setup mode, so we enroll our own Secure Boot keys | No typing at boot. The disk is unreadable outside this machine, or with any other boot media. | Anyone holding the laptop reaches the login screen, so **your login password is the real lock**. A firmware or Secure Boot key change needs the system encryption key. **Not offered without Secure Boot.** | **forced off** |
| **Tang** | the advanced TUI screen names URLs (servers) | Unattended unlock on a trusted network. | Needs the server to be reachable. For servers, not laptops. | forced off |

Rules, enforced both in the installer code and as assertions:
- `recovery ∈ methods`. This is the system-encryption-key slot.
- `tpm2 ∈ methods ⇒ loom.boot.secureBoot.enable` (D4: hands-free unlock only with SB on our keys).
- `omanix.session.autologin ⇒ methods ∩ {tpm2, tang} = ∅`.
- Any `tpm2*` choice also enrolls a passphrase or FIDO2 slot for first boot. `loom unlock remove` refuses to leave fewer than two independent methods, one of them the system encryption key.
- PCRs: `[7]`.
  - Under Secure Boot with our keys, PCR 7 covers our db. What the signed loader then guarantees depends on `loom.boot.loader` (D7):
    - **Limine** (default): the signed Limine binary with `enrollConfig` + `validateChecksums` + `panicOnChecksumMismatch` covers the kernel, initrd and cmdline.
    - **lanzaboote**: systemd-boot is signed, and each generation is a signed UKI that embeds kernel, initrd and cmdline, so the firmware's signature check covers all three.
  - Without Secure Boot, only TPM2+PIN is offered, and its cons show the evil-maid caveat (D4).

Generated config:
- `boot.initrd.systemd.enable = true`
- `boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" | "fido2-device=auto" ]`
- Plymouth asks for passwords through **`loom-askpass`**, the initrd password agent of §g.10. It replaces `systemd-ask-password-{plymouth,console}`, and the prompt is themed from omarchy.

### e.7 Partition and FDE

1. disko config from `loom.lib.diskoLayout` (a pure function of `loom.disk.*`), run with `destroy,format,mount`:
   ```
   GPT: ESP 1 GiB vfat /boot
        LUKS2 "cryptroot" (argon2id, allowDiscards, 16 MiB header for tokens)
          btrfs: @nix /nix (compress=zstd,noatime) · @persist /persist (neededForBoot) · @home /home
                 @agents /agents + @agents-blank (postCreateHook) · @snapshots /.snapshots · @swap (zram+file only)
   / = tmpfs (loom.disk.rootTmpfsSize)
   ```
2. LUKS is formatted with a **random 64-byte bootstrap keyfile** in `/run/loom/bootstrap.key` (tmpfs, 0400).
3. The system-encryption-key slot:
   - `cryptsetup luksAddKey --key-file /run/loom/bootstrap.key --pbkdf argon2id --new-keyfile - <dev>`, with stdin = `hex(K_luks)` (§g.10);
   - then `cryptsetup token import --key-slot <n>` of the `loom-sek` token with `state: "active"` (schema in §g.10).

   systemd's `--recovery-key` is **not** used.
4. `systemd-cryptenroll --unlock-key-file=/run/loom/bootstrap.key` adds `--password` and/or `--fido2-device=auto --fido2-with-client-pin=yes` (one or more tokens). **No TPM2 here.**
5. `--wipe-slot=<bootstrap>`. Then `cryptsetup luksDump --dump-json-metadata` is checked against the expected token and slot set: exactly one `loom-sek` token whose `fp` matches, and a test-open of that slot with `K_luks`. On a mismatch the installer aborts with a message.

### e.8 Secure Boot, keys, secrets, install, finish

1. **Secure Boot** (setup mode, user opted in):
   - `sbctl create-keys` with the key directory at `/mnt/persist/var/lib/sbctl`;
   - `sbctl enroll-keys --microsoft` (option ROMs);
   - set `loom.boot.secureBoot.enable = true` and `boot.loader.limine.secureBoot.enable = true`, with `autoEnrollKeys = false` (the installer already enrolled the keys). With `loom.boot.loader = "lanzaboote"` (D7), `boot.lanzaboote.pkiBundle = "/var/lib/sbctl"` instead.

   If this fails, the install continues with Secure Boot off, and `tpm2` is downgraded to `tpm2-pin` with a notice.
2. **Persist binds for the chroot.** For each path in `loom.persist.installBinds` (`/var/lib/sbctl`, `/etc/ssh`, `/var/lib/loom`), bind-mount `/mnt/persist<p>` onto `/mnt<p>` before `nixos-install`. Bootloader signing inside the chroot then finds the keys. This is tested by `installer-e2e-sb`.
3. Run `nixos-generate-config --root /mnt --no-filesystems --show-hardware-config`, which produces `hardware.nix`. Write the detect results to `hardware.json`.
4. **Keys generated on the target**, never shown, never leaving the machine:
   - the host SSH ed25519 key (silo transport, install-record signing);
   - the host age key (`file` backend: `/persist/var/lib/loom/sops/host.age`, 0400; D4);
   - the agent SSH ed25519 key per agent, written into `secrets/agents.yaml` and delivered by nuketown each boot (C3);
   - `/persist/etc/machine-id` from the sidecar (fresh mode: newly minted);
   - if chosen in step 0, the software owner/human key into `/mnt/home/<user>/.ssh/` (§e.5).
5. **Secrets.**
   - Render `.sops.yaml` with recipients host + human* + `recovery`. `recovery` is the age recipient derived from the system encryption key (§g.10).
   - `sops -e` for `user.yaml` (password hash) and `agents.yaml`.
   - Existing human-only `data.yaml` entries are re-encrypted with `sops updatekeys` if the YubiKey identity is present. Otherwise they are listed for the first-boot prompt.
6. **Commit.** `loom-hostgen` (§e.5a) writes `machine.nix` (device, btrfs UUID, unlock, recipients, `loom.secrets.recovery.fingerprint`, Secure Boot, stateVersion), `keys.nix` (host and agent keys added, any human key generated here, `enroll = null`), `hardware.{nix,json}` with the quirk enables, and the answer lines of `configuration.nix` (`loom.agent.enable`, `loom.agent.sudo`). `loom keys sync` writes `.authorized_keys` and `CODEOWNERS` in their **final** form (§g.7): the enroll key is gone, and host, agent and human keys are present. Commit `install: <host> on <disk model>`, signed with the host key.
7. **Offline-capable evaluation.**
   - `nix copy --from file:///run/loom/cache` all source paths listed in the cache's `flake-archive.json`, plus the install-cache, into the live store. Sigs are required.
   - Then evaluate with `--offline`. Locked inputs whose store paths are already valid are not fetched.
   - This is UNVERIFIED and gated by `checks.installer-offline-eval`, a VM with no network device.
8. **Install.**
   ```
   nixos-install --root /mnt --no-root-passwd --flake /mnt/persist/var/lib/loom/host#host \
     --option substituters "file:///run/loom/cache file:///run/loom/cfg/install-cache [network caches only if online]" \
     --option require-sigs true --option extra-trusted-public-keys "<install cache key from repo, if any>"
   ```
   If the install is offline and a path is missing, the installer lists the missing derivations as JSON and offers network or a local build (small derivations only).
9. **Enrollment** (§g.7).
   - Preconfigured mode: the enroll-key push.
   - Fresh online mode: the owner-key push.
   - Failure is not fatal. The enroll key (preconfigured) moves to `/mnt/persist/var/lib/loom/enroll/` (0400, inside LUKS) and is retried at first boot. Fresh mode falls back to `repo-publish` at first boot.
10. **Finish.**
    - Install the configured loader (D7): Limine (signed when Secure Boot is on), or with `loom.boot.loader = "lanzaboote"`, systemd-boot plus lanzaboote's signed UKIs (signed with the sbctl keys from step 1).
    - `efibootmgr`: omanix first, clear BootNext.
    - Overwrite, then delete `enroll.key`, `sidecar.json`, `host.bundle` and `install-cache/` on CFG (spec: "shred the sidecar"). The TUI message depends on the enrollment state from step 9:
      - preconfigured, enrollment verified: "Flash storage can keep copies. The enrollment key is already revoked on silo. Reformat the stick to be sure."
      - preconfigured, enrollment pending: "The enrollment key on this stick **still works on silo** until first-boot enrollment succeeds. Keep the stick safe or reformat it. If it is lost before then, run `configure revoke-enroll <id>` from your other computer."
      - fresh mode (no enroll key): "Flash storage can keep copies. Reformat the stick to be sure." (no enrollment-key sentence).
    - Show the summary: unlock methods, system encryption key confirmed, owner key (kind and where it lives), agent (`yes` | `later` | `no`) and agent sudo (`listed` | `any`), host id, enrollment state. Reboot.

### e.9 First boot (`loom.firstboot.steps`, idempotent, state in `/persist/var/lib/loom/firstboot/`)

1. **unlock-finalize** (if `tpm2*`).
   - The user unlocked with the passphrase or FIDO2, and Secure Boot is now final.
   - Run `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 [--tpm2-with-pin=yes]`.
   - Test the unseal with `systemd-cryptsetup attach --test`, or the equivalent token test.
   - Record the result in `/persist/var/lib/loom/unlock.json`.
2. **Enrollment catch-up** (`network-online`; idempotent):
   - **enroll-retry** (preconfigured mode, enrollment pending): the same push as §g.7 with `/persist/var/lib/loom/enroll/enroll.key`. On success the key is shredded.
   - **repo-publish** (fresh mode, offline at install). This step is **interactive**. The onboarding card says "Publish this computer's configuration to silo". Then:
     - **pre-check, immediately before the push:** `git ls-remote` of the repo must fail with `repository not found` (F7);
     - the owner key signs and pushes `master`, needing FIDO2 touch and PIN or the software key passphrase;
     - silo creates the repo with `.owner_key = owner` (F1);
     - the §a.4 HEAD check runs, and a `gate/probe-<rand>` push with the owner key must be accepted;
     - on success, write `/persist/var/lib/loom/firstboot/repo-publish.done`, which lets the resident agent start (§e.5 step 0).

     **Squatted id.** If the pre-check finds the repo already exists, or the push is refused with `access denied` (someone else is `.owner_key`), the step stops with "Someone else created this computer's repository on silo before it was published. It can't be used." and offers `loom fork` (§g.8): a new machine-id and id, the owner key pushes first, and secrets are carried over (the fork re-derives from the current SEK and shows a new one for the new id). The agent stays stopped until the fork's publish succeeds.

     Until this step is done, `loom status` shows `enrollment: unpublished`, switches work from the local mirror only, and the resident agent does not run.
3. **secrets-prompt**: for each `loom.secrets.prompted.*` entry still missing (Wi-Fi PSK and similar), ask once in the human session, encrypt, commit (as the host) and propose. The card appears right away and the human approves it.
4. **onboarding**: the desktop, welcome checklist, resident and reviewer sign-in and tour of §h.7. On an unpublished fresh-offline host the chat panel instead says "<agent> starts once this computer is published to silo" and shows the `repo-publish` step. Each resident signs in **through its own normal login flow on this machine**; nothing is pre-provisioned.

### e.10 Signed release tags and script self-verification

- Release signers are Josh's YubiKey SSH signing keys (D11), published on silo, on github and in the README.
- `scripts/*.sh` share one identical preamble (`checks.script-preamble-identical`):
  1. Require the **user-pinned** `~/.config/omanix/allowed_signers`. If it is missing, show the fingerprint and the publication URLs, and require typing `trust <fingerprint>`.
  2. Run `git verify-tag $(git describe --exact-match)` against that file, or verify `SHA256SUMS.sig` (namespace `omanix-release`) and `sha256sum -c` over `scripts/`, `pkgs/` and `fork/`.
  3. Refuse a dirty or untagged tree unless `OMANIX_DEV=1` is set, which prints a red banner.
  4. `exec nix run .#<tool>`.
- **Limit:** this catches tampered checkouts and stale forks, but not a user who pins an attacker's key.
- Installed hosts carry `loom.trust.releases.omanix.signers` in `/etc/loom/release-signers`.

---

## f) Runtime

### f.1 Impermanence

`/` is tmpfs. The persistent subvolumes are `/nix`, `/persist`, `/home` and `/.snapshots`.
- `/agents` is reset from `@agents-blank` in initrd. This is nuketown's existing rollback (§a.3 C2).
- `/tmp` is tmpfs, and nix-daemon's TMPDIR is `/var/cache/nix` (persisted).

**Baseline `loom.persist.system`.** Feature modules append to it.

| Kind | Paths |
|---|---|
| files | `/etc/machine-id`, `/etc/ssh/ssh_host_ed25519_key{,.pub}` |
| dirs | `/var/lib/nixos`, `/var/lib/loom`, `/var/lib/sbctl` (if SB), `/var/lib/systemd/{coredump,timers,backlight,rfkill}`, `/var/log`, `/var/cache/nix`, `/root` |
| appended by features | NetworkManager, bluetooth, fprint, cups, upower, alsa, docker, tailscale, `/var/lib/omanix` |

Nuketown handles agent persistence.

**Human home.** All of `/home` is the `@home` subvolume (H2), so HM's links, `~/.local/state/home-manager`, `~/.local/state/{omarchy,omanix}`, the user-data directories and app-owned files persist **with no per-path entries**. omanix makes no `environment.persistence` user entries.
- `omanix.persist.home` is read-only and derived from the runtime, user-data and app-owned paths in `fork/classify.toml` and `omanix.home.appOwned`. It is published in `catalog/persist.json` and used by `omanix persist audit`, so that a future ephemeral-home mode can generate `environment.persistence."/persist".users.<u>.directories` from the same list.
- An assertion requires `loom.home.enable ⇒ /home is a persisted subvolume`.
- btrbk snapshots of `@home` also snapshot the overlays, so a runtime tweak can be rolled back without touching git.

How correctness is checked:
- **Eval-time StateDirectory audit** (`loom.lib.persistAudit`): every enabled service's `StateDirectory` must be persisted or listed in `ephemeralOk`. The assertion names the option to set.
- **VM test `impermanence-survives-reboot`**:
  - sentinels in persisted and non-persisted paths;
  - machine-id stable and the journal continuing;
  - `/agents` reset;
  - an unexpected-write audit of `/var/lib` and `/etc` after a desktop session.
- `omanix persist audit` lists files written on tmpfs `/` that no entry covers, and names the owning option.

**Persistence for host modules and plugins** (the same rules, restated for module authors):

| Where state lives | What a module does |
|---|---|
| system state (`/var/lib/<svc>`, `/etc/<file>`) | `loom.persist.system.directories = [ "/var/lib/<svc>" ];` in the **same module** that enables the service; for third-party plugins, in the host's `modules/persist.nix` |
| `DynamicUser` services | persist `/var/lib/private/<svc>` (the audit maps `StateDirectory` to the right path) |
| the human's home | nothing: all of `/home` is the `@home` subvolume |
| a resident's home (`/agents/<n>`, reset every boot) | `nuketown.agents.<n>.persist.{directories,files}`; omanix persists `projects` and `.claude` for the resident; the reviewer persists `.claude` (its login) |
| deliberately throwaway state | `loom.persist.ephemeralOk = [ "/var/lib/<svc>" ];` with a comment explaining why |

`omanix persist add <path>` appends to `modules/persist.nix`. Because the audit is an eval-time assertion, a plugin that forgets persistence fails `omanix check`, not the first reboot.

### f.2 Desktop: the omarchy fork

**Fork point.** `v4.5.0-rc2` = `5978d93ae7da0a325b7493501911e3f1266cadd3` (a lightweight tag, confirmed with `git ls-remote` on 2026-10-27; D2). The survey behind the counts below ran on `bc220e7` (`quattro`, 5 ahead / 6 behind the tag), so every count is **PROVISIONAL** until `checks.fork-classify` is green at `5978d93` (U21). The omarchy tree is untrusted data. No omanix tool or agent executes upstream code with privileges or outside the nix build sandbox. The build stages read and parse it (`python3 -I`). `checks.themes-render` runs the upstream theme renderer inside the sandbox with no network. The shipped KEEP-AS-GUI and ASSET code (bash, QML, Python such as `typing_setup.py`) runs only as the human in the session, as upstream intends.

#### f.2.1 Classes and the decision rule

| Class | Meaning | Where it ends up |
|---|---|---|
| **KEEP-AS-GUI** | A human-facing tool that changes something, kept because asking the agent would be onerous. It applies its change live, as **runtime state**. | Shipped in `omarchy-src`; patched where it used to write an HM-owned or system path. |
| **AGENT-INTENT** | Dropped as a human tool. Its menu row and keybinding stay but **pre-fill a chat request**; the resident does the work by editing the host repo, landing via card + switch. | `fork/intents.toml` (menu side); a skill in `omanix-skills` (agent side); script removed from `$OMARCHY_PATH/bin`. |
| **ASSET** | Data or a non-mutating helper: QML, Lua, themes, templates, read-only probes, launchers, menu data, icons, manual. | `omarchy-src`, unchanged or patched. |
| **RE-EXPRESS-IN-NIX** | Logic that existed to set the system up, now NixOS/HM options, systemd units, first boot or session init. | `modules/omanix/**`, `loom.firstboot.steps`, session init; upstream file dropped or kept as data a module reads. |
| **DROP** | No equivalent: Arch packaging, migrations, pacman/limine/snapper, passwordless sudo, credential transfer, contributor tooling. | `fork/drop.txt`. |

**Decision procedure** (V2, applied in order):
1. Only **reads**, or is a library, launcher or data → **ASSET**.
2. Exists to install, configure or migrate the **system or package set**, or touches pacman/limine/snapper/mkinitcpio/sudoers → **RE-EXPRESS-IN-NIX** if NixOS needs the behavior, else **DROP**.
3. Needed to **reach or repair the agent**: network setup, keyboard layout, agent sign-in, approval, undo/rollback, lock, power, restarting wifi/audio/bluetooth/shell → **KEEP-AS-GUI**.
4. A **continuous or frequent control**: volume, brightness, scale/text size, monitor arrangement, window/workspace management, screenshots/recording, clipboard, emoji, sharing, reminders → **KEEP-AS-GUI**.
5. An **instant, reversible runtime toggle**: nightlight, DND, idle inhibit, screensaver, touchpad, bar/dock visibility, gaps, corners, transparency, animations, workspace layout → **KEEP-AS-GUI**.
6. **Visual browsing with live preview**: themes, wallpapers, monospace font, bar and dock placement → **KEEP-AS-GUI** (runtime; "make it stick" is an intent).
7. Everything else changes **persistent configuration** (defaults, DNS, language, timezone, kernel, boot screen, security, git identity, apps, web apps, TUIs, dev envs, plugins, theme repos, branding, clock format, updates) → **AGENT-INTENT**.

A **picker that ends in a persistent change** keeps its GUI picker, and its result becomes the intent text (Plymouth switcher → "Set the unlock screen to *Tokyo Night*"; language list → "Switch my language to *Deutsch*"). The row is AGENT-INTENT.

#### f.2.2 Counts (PROVISIONAL, surveyed on `bc220e7`)

| Scope | KEEP-AS-GUI | AGENT-INTENT | ASSET | RE-EXPRESS | DROP | NAV | Total |
|---|---|---|---|---|---|---|---|
| `bin/omarchy*` scripts | 101 | 128 | 241 | 22 | 66 | — | 558 |
| menu entries (`omarchy-menu.jsonc`) | 115 | 232 | 0 | 0 | 6 | 69 | 422 |
| files outside `bin/` | 0 | 11 | 3582 | 192 | 843 | — | 4628 |

About 101 of 558 scripts stay as human tools; 342 upstream scripts ship (KEEP-AS-GUI + ASSET) plus the `add/` replacements; 216 leave `$OMARCHY_PATH/bin`. In the menu, 232 of 353 actionable rows become intents and 115 stay GUI. The machine form of the per-script, per-entry and per-path mapping is `fork/classify.toml` and `fork/intents.toml`; `fork/fork.md` appendices A–C are the reviewed source they were generated from.

#### f.2.3 Subsystems

| Subsystem (upstream path) | Class | Mechanism |
|---|---|---|
| Quickshell shell `shell/**` (bar, dock, menu, panels, osd, notifications, lock, polkit, clipboard, emojis, reminders, image-picker, background, agents, services) | ASSET | Store path `$OMARCHY_PATH/shell`, launched by upstream `omarchy-launch-shell`; patches in §f.2.5. `shell/plugins/dev-gallery` is DROP. |
| omanix plugins `omanix.chat`, `omanix.approval`, `omanix.status`, `omanix.welcome` | new | `fork/add/shell/plugins/omanix-*`, discovered by upstream's plugin registry (§h.2). |
| Hyprland Lua `default/hypr/**`, `config/hypr/*.lua` | ASSET | Unchanged Lua. `config/hypr/*` templates become read-only HM files (§f.4.2). One patch rebinds the agent keys. |
| Menu data `default/omarchy/omarchy-menu.jsonc` | ASSET (transformed) | `lib/menu.nix` merges upstream JSONC with `fork/intents.toml` and `fork/menu-extra.jsonc` (§h.5). |
| Keybinding defaults `default/hypr/bindings/*.lua` | ASSET | Unchanged except the agent-key patch; `omanix.keybinds.*` emits HM `bindings.lua`. |
| Themes `themes/*` (23), templates `default/themed/*.tpl` | ASSET | Upstream renderer unchanged (§f.5). Big media is symlinked, never copied. A theme's `hyprland.lua` is **code**, so third-party themes are AGENT-INTENT (flake input, card). |
| Terminal/app defaults `default/{alacritty,foot,ghostty,bash,bashrc,xcompose,fontconfig,gtk,fonts,i18n,input-methods,…}`, `config/**` | ASSET | Store data and HM read-only files (D9). App-owned seeds are copied once at first login (§f.4.5). |
| Session env `default/{uwsm,environment.d,wayland-sessions,xdg-terminal-exec}` | RE-EXPRESS | `programs.hyprland.withUWSM`, the uwsm env drop-in, `environment.sessionVariables`, `sessionPackages`. |
| Boot visuals `default/{plymouth,sddm}` | ASSET | `omanix-plymouth`, `omanix-sddm-theme` with omanix logos (§f.2.8). |
| systemd units `default/systemd/**` | RE-EXPRESS | `systemd.packages` + `systemd.user.services.<n>.wantedBy`. `omarchy-migrate-notify.service` DROP. The NvPCR drop-ins (`systemd-{pcrlogin@,pcrproduct,tpm2-setup-early}.service.d`) are DROP pending U27 (interaction with D4's PCR 7 policy). |
| `etc/**` (56 files) | RE-EXPRESS mostly | sysctl, NetworkManager, logind, resolved, oomd, faillock, cups, docker, xkb, profile.d → options. sudoers.d, mkinitcpio, limine-entry-tool and nopasswd tmpfiles are DROP. fastfetch, mpv, xdg/kitty are ASSET. |
| Browser policy `default/{chromium,firefox}` | RE-EXPRESS | `programs.chromium.extraOpts`, `programs.firefox.policies`; theme color via the spool + root path unit (§f.5). |
| pacman, libalpm, limine, snapper, regions | DROP | loom owns boot (D7); generations replace snapshots. |
| Agent skills `default/agents/skills/{omarchy,omarchy-app,diagnose-crash}` | AGENT-INTENT | Rewritten as resident skills (§h.10). The upstream text ships in the store as reference only; it is **not** linked into the human's harnesses. |
| `install/*.packages`, `install/config/*.sh`, `install/user/**`, `install/login` | RE-EXPRESS | `omanix.packages.base` (x86_64 lists), base modules, session init / first login, SDDM. `xcompose.sh`, `language.sh`, `first-run/setup-agent.hook`, snapper and the dispatchers are DROP. |
| `install/hardware/**`, `install/user/hardware/**` | RE-EXPRESS | Quirk modules (§f.2.6). |
| `install/{helpers,post-install,provisioning}`, `migrations/` (211) | DROP | The loom installer and first boot replace provisioning; nix has no state to migrate. |
| `applications/*.desktop`, icons | ASSET | Catalog for `omanix.apps.webapps.<n>` (HM `xdg.desktopEntries`). |
| `manual/` | ASSET | Shipped read-only as resident reference; "Learn > Manual" points at an omanix-patched copy. |
| `docs/`, `plans/`, `test/`, `scripts/`, `agents/skills/`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `.github/` | DROP (from the store) | Readable in the pinned source; the porting report reads `docs/` and `test/`. |
| `LICENSE` | ASSET (required) | Shipped unmodified (`checks.fork-license`). |
| `logo.*`, `icon.*`, `oma.png`, About/screensaver branding text, `version` | DROP / replaced | omanix branding in `fork/add/branding/`; `omarchy-version` is re-expressed. |

**v1 targets x86_64-linux only.** aarch64 knowledge (Apple Silicon, Snapdragon X, NVIDIA N1x/GB10) is kept as `status = "deferred"` quirk rows citing the source script; no module is built.

#### f.2.4 Fork mechanics: pinned input + patch queue

Chosen over vendoring the tree (themes alone are 161 MB) and over a separate fork repo (a third repo to sign and protect): upstream stays byte-exact and hash-pinned, and `fork/` *is* the divergence.

```
fork/
  UPSTREAM.toml      # url, tag = "v4.5.0-rc2", rev, date, why this point (D2)
  NOTICE             # attribution (§f.2.8)
  classify.toml      # every bin script + path rule → class; `privilege = none|polkit|unit` for KEEP-AS-GUI (§f.2.5); owned by W3
  writers/{desktop,theme}.toml   # `writes =` per KEEP-AS-GUI writer, keyed by script (§f.4.4); owned by W15 / W16
  drop.txt           # globs removed from the tree (DROP + AGENT-INTENT scripts + RE-EXPRESS sources)
  rewrite.toml       # exact {file, from, to, count}: /usr/share/omarchy, /usr/bin/*, titlebars .so, runtime redirects
  intents.toml       # menu row → gui | intent | drop (§h.5)
  menu-extra.jsonc   # new omanix menu entries
  hw-quirks.toml     # probe + source script + status (§f.2.6)
  hl-symbols.txt     # hl.* API the Lua may use
  patches/0001-….patch … 0019-….patch   # file number == P-id (0001 = P1 … 0016 = P16 branding … 0019 = P19), §f.2.5
  add/               # new files overlaid on the tree; never silently replace an upstream path
    shell/plugins/omanix-{chat,approval,status,welcome}/
    bin/omarchy-{pkg-present,pkg-missing,pkg-defaults,update-available,update-restart,update-status,version,version-pkgs,locale-generate}
    bin/omarchy-{refresh-*,reinstall,reinstall-configs}   # overrides → omanix reset (header: "# replaces upstream <path> sha256 <x>")
    bin/omarchy-{default-browser,default-terminal,default-editor,default-dictation,default-agent,dns,channel-current}   # read-only readers (§f.2.5)
    bin/omarchy-{update-time,restart-trackpad,restart-audio,brightness-display-apple,toggle-hybrid-gpu}   # privilege-mapped overrides (§f.2.5)
    branding/  default/plymouth/logos/omanix.png  default/fonts/omanix-glyphs/
```

**Build stages** (`pkgs/by-name/omarchy-src`, all inside the sandbox; these stages execute no upstream code):
1. **unpack** `inputs.omarchy` (fixed rev and narHash).
2. **drop** `fork/drop.txt`.
3. **add** `fork/add/`. An add that collides with an upstream path must carry a `replaces … sha256` header matching the pinned file.
4. **patch** `fork/patches/*` in order, `patch -p1 --fuzz=0`.
5. **rewrite** `fork/rewrite.toml` with exact counts (mismatch fails), then `patchShebangs`.
6. **post-check:** no `/usr/(share|lib|bin)`, `pacman`, `yay` or `mkinitcpio` outside `allowResidual`; every shipped `bin/omarchy-*` is KEEP-AS-GUI, ASSET or an `add/` replacement; no shipped script or QML/JS file calls a dropped one (static call graph: `bashlex` for bash, plus string literals naming `omarchy-*` commands in `shell/**/*.{qml,js}`, including the menu's `GUARD_READERS` and its `checked:`/`disabled:` guards); `luac -p` passes and `hl.*` ⊆ `hl-symbols.txt`; `qmllint` on patched QML (U24); `LICENSE` present and unmodified.

`omanix-data` (the per-host tree) is built on top and adds the generated menu, the overlay loader, the theme registry and the language file (§f.2.9).

**Gates in `nix flake check`** (all read only the pinned tree): the build itself, `fork-classify`, `menu-intents`, `hm-owned-readonly`, `hw-quirks`, `skills-no-arch`, `fork-license`, `themes-render`. **Removed:** `upstream-pin-tag`, `upstream-drift`, `writer-map` as a coverage gate over all of upstream, `script-map-complete` (folded into `fork-classify`). No check fetches anything newer.

#### f.2.5 Patch list (QML and scripts that wrote files, ran dropped tools, needed root or called omarchy services)

Each patch is ≤ 60 changed lines, or it becomes an override in `fork/add/`.

| # | Upstream file | Upstream behavior | Patch | Runtime path / IPC |
|---|---|---|---|---|
| P1 | `shell/shell.qml` `userConfigPath` | writes `~/.config/omarchy/shell.json` | rewrite, count 1 | `~/.local/state/omanix/shell/shell.json` (+ `.base`, §f.4.7) |
| P2 | `bin/omarchy-shell-config` `CONFIG_FILE` | same file via `jq`+`mv` | rewrite | same as P1 |
| P3 | `shell/Commons/Color.qml` reader, `bin/omarchy-display-text-size` writer | `~/.config/omarchy/shell.toml` | rewrite | `~/.local/state/omanix/shell/shell.toml` |
| P4 | `bin/omarchy-hyprland-monitor-scaling`, `-monitor-clamshell` (reader), `-display-text-size`, `-font-set`, `-restart-terminal`, `-theme-set-glass`, `-chromium-add-feature` | `sed -i`/`cat >` on HM files | patches (rows in §f.4.4) | `~/.local/state/omanix/overlay/**`; live apply unchanged (`hyprctl eval`, terminal reload) |
| P5 | `shell/plugins/menu/MenuModel.js`, `Menu.qml` `runAction` | runs `action` through bash | `kind = action ? "action" : intent ? "intent" : …`; `intent` dispatches to `omanix.chat.prefill` through the shell's `IpcRegistry`, never bash | IPC only |
| P6 | `MenuModel.js` package snapshot (`pacman -Qq`) | reads pacman | reads `/run/current-system/sw/share/omanix/packages.txt` + `/etc/profiles/per-user/$USER/share/omanix/packages.txt` | read-only |
| P7 | `shell/plugins/bar/indicators/PasswordlessSudo.qml` | passwordless-sudo indicator | removed; `omanix.status` adds "approval pending" and "agent offline" indicators | `omanix.approval` IPC |
| P8 | `shell/plugins/bar/widgets/SystemUpdate.qml` | polls `omarchy-update-available`, runs `omarchy-update` | polls the re-expressed `omarchy-update-available` (loom update state); click opens the "Update ready" card | `omanix.approval open update` |
| P9 | `default/hypr/bindings/utilities.lua` | agent keybinds | §h.5 keybinding table | — |
| P10 | `shell/plugins/panels/network/Panel.qml` DNS section | `omarchy-dns <provider>` (sudo) | DNS buttons pre-fill the `network` intent; wifi/connect/captive portal unchanged | `omanix.chat.prefill` |
| P11 | `Menu.qml` providers `languages`, `kernels` | `omarchy-language` / `omarchy-kernel` | picker-then-intent (`intentFor`); the `fonts` provider stays GUI (runtime) | IPC |
| P12 | `shell/plugins/image-picker/*` theme remove | `omarchy-theme-remove` | user-installed themes stay removable; repo themes (`omanix.theme.extra`) show "Remove…" → `themes` intent | — |
| P13 | `shell/plugins/agents/Panel.qml` | account management for the human's own harnesses | unchanged; adds a read-only resident tile from `omanix.status` | — |
| P14 | `bin/omarchy-crash-watch`, `omarchy-launch-config-editor`, `omarchy-launch-{1password,signal,spotify}` | spawn `agent-crash` / open HM-owned files / run installers | pre-fill `diagnose` / open the host-repo module or the `look` intent / pre-fill an `apps` intent | IPC |
| P15 | `default/bash/env-bootstrap` | resets `OMARCHY_PATH` to `/usr/share/omarchy` | resets to `/run/current-system/omarchy` | — |
| P16 | branding strings | "Omarchy" in About, screensaver, window titles, bar logo | omanix (§f.2.8) | — |
| P17 | `bin/omarchy-weather-location`, `shell/plugins/panels/weather/Panel.qml` | geolocates through `https://geo.omarchy.org/` | the lookup URL comes from `omanix.weather.geoUrl` (default `null`: no lookup; the user sets a location by hand) | none by default |
| P18 | `shell/plugins/panels/tailscale/Service.qml` | `pkexec tailscale set --operator=$USER` | removed; the operator is declared (`services.tailscale.extraSetFlags = [ "--operator=<user>" ]` in the tailscale app module) | — |
| P19 | `shell/plugins/panels/clock/BarWidget.qml` middle-click | runs `omarchy-menu-timezone` (AGENT-INTENT, not shipped) | opens the menu at the `update.timezone` intent row (picker-then-intent) | IPC |

**KEEP-AS-GUI scripts that needed root.** omanix has no NOPASSWD rules and launches these without a TTY, so each one gets a narrow privilege mapping, recorded as `privilege = none | polkit | unit` in `classify.toml`. `checks.fork-classify` fails when a KEEP-AS-GUI script or kept QML file contains `sudo` or `pkexec` and has no mapping.

| Script | Upstream root use | omanix (`add/` override) |
|---|---|---|
| `omarchy-update-time` | `sudo systemctl restart systemd-timesyncd` | `systemctl restart systemd-timesyncd`, allowed by a polkit rule for the active local user on that one unit (`polkit`) |
| `omarchy-restart-trackpad` | `sudo tee …/i2c_hid_acpi/{unbind,bind}`, `sudo modprobe` | starts the root oneshot `omanix-trackpad-reset.service`, which the active local user may start through polkit (`unit`) |
| `omarchy-restart-audio` | `sudo usbreset` | root oneshot `omanix-usbreset@<id>.service`, with the id validated against `^[0-9a-f]{4}:[0-9a-f]{4}$` (`unit`) |
| `omarchy-brightness-display-apple` | `sudo asdcontrol` on every step | a udev `uaccess` rule on the Apple display's hiddev node, shipped with the `asdcontrol` app module; no sudo (`none`) |
| `omarchy-toggle-hybrid-gpu` | `omarchy-pkg-add supergfxctl`, `sudo tee /etc/supergfxd.conf`, `/usr/bin/install`, `systemctl enable --now` | `supergfxctl -m <mode>` through supergfxd's own D-Bus policy; the `hybrid-gpu` quirk declares `services.supergfxd` (`none`) |

**Read modes of removed scripts.** Removing an AGENT-INTENT or DROP script also removes its read mode, and kept QML uses some of them: the menu's `GUARD_READERS` batch runs `omarchy-default-{browser,terminal,editor,dictation,agent}`, `omarchy-dns` and `omarchy-channel-current` to compute checked states. Each one gets a read-only `add/` replacement that prints the declared value from `catalog/config.json` (`omanix.defaults.*`, `omanix.dns.provider`; `channel-current` prints the omanix release channel). Called with arguments, it exits 2 with "ask <agent>". The readers are classified ASSET, and the writer halves stay AGENT-INTENT.

Writers that already target runtime state are left as they are: QML `atomicWrites` in `notifications/Service.qml`, `clipboard/Clipboard.qml`, `agents/Main.qml` (all under `~/.local/state/omarchy/`), and every `toggle-*`, `theme-set*`, `bg-*`, `weather-location`, `reminder`, `powerprofiles-set`.

#### f.2.6 Hardware quirks as NixOS modules

`fork/hw-quirks.toml` holds one row per quirk (source script, declarative probe, status `v1 | deferred`); `modules/omanix/hardware/quirks/<name>.nix` declares `omanix.hardware.quirks.<name>.enable`; generic probe-driven defaults live in `hardware/{intel,nvidia,amd,vulkan,bluetooth,wireless}.nix`.

```toml
[quirk.asus-b9406-touchpad]
source = "install/hardware/asus/fix-asus-ptl-b9406-touchpad.sh"
probe  = { dmi.product_name = "*B9406*", dmi.sys_vendor = "ASUS*" }
status = "v1"
```

1. At install, `loom-detect` (stdlib python reading `/sys` and `lspci -nn`; never omarchy code) evaluates the probes and `loom-hostgen` writes `omanix.hardware.quirks.<n>.enable = true;` into `hardware.nix`.
2. After a hardware change, `omanix hw probe` (read-only) lists matching quirks that are not enabled; the `hardware` skill proposes them (a card), or the human runs `omanix hw probe --write` in their own working copy.
3. Where `nixos-hardware` has a module, the quirk imports it and adds only the omarchy delta (U26).

v1 quirk modules: `nouveau-cursor`, `vm-no-animations` (first-login runtime toggles), `intel-video`, `intel-thermald`, `intel-lpmd`, `intel-sof`, `intel-ptl-fred`, `intel-wifi7-eht`, `intel-ipu7-camera`, `asus-rog`, `asus-z13-touchpad`, `asus-b9406-{display,touchpad}`, `asus-ptl-backlight`, `asus-proart-p14-speakers` (if packaged), `dell-xps13-ptl`, `dell-xps-haptics`, `dell-xps-oled` (if packaged), `framework16`, `framework13-amd-mic`, `lenovo-yoga-pro7-bass`, `surface`, `apple-t2`, `bcm43xx` (unfree opt-in), `tuxedo-backlight`, `synaptics-intertouch`, `elgato-camlink-4k`, `speaker-tuning`, `nvidia` (open = GSP), `hybrid-gpu` (the toggle stays KEEP-AS-GUI). Deferred (aarch64): `qualcomm-*`, `thinkpad-t14s-camera`, `yoga-slim7x*`, `apple-silicon-*`, `n1x`, `gb10`. The per-row mechanism (kernel params, modprobe options, udev rules, packages, wireplumber rules) is in `fork/hw-quirks.toml` and `fork/fork.md` §7.

`checks.hw-quirks`: every `install/hardware/**` and `install/user/hardware/**` file maps to a row or a DROP line; every `v1` row has a module; each module evaluates on a fixture with its quirk on; `loom-detect`'s pytest has one sysfs fixture per probe.

#### f.2.7 Porting report (replaces the drift gate)

`nix run .#porting-report -- --to <tag|rev> [--json]` runs on a developer machine with network. It never runs in `nix flake check` and never executes upstream code.
1. Fetch the target into a fresh store path (read-only).
2. **Classified diff:** every changed or added file between `5978d93` and the target, grouped by its `classify.toml` class; unclassified paths get a **suggested class** from the family rules.
3. **Patch queue dry run:** each patch with `git apply --3way --check` → `clean | offset | conflict`; `add/` replacements whose `replaces` sha no longer matches.
4. **Rewrites:** `rewrite.toml` counts re-run against the target.
5. **Menu:** new, removed and changed ids against `intents.toml`, with a suggested `kind` from the §f.2.1 rule.
6. **Writers:** the write-site scanner lists new write sites into HM-owned paths.
7. **Runtime deps:** Hyprland/Quickshell/guiutils minimums from `hl.*` symbols and omarchy-pkgs `pkgver`s vs omanix's pins.
8. **Hardware:** new `install/hardware/**` files as candidate quirk rows.
9. **Themes and assets:** added/changed themes and their license/credit files.
10. **Effort summary** as `porting-report.md` + `.json`.

**Moving the fork point** is a human decision recorded as a new D-number. The resident may run the report and prepare the port on a `gate/*` branch of the omanix repo; on hosts, the resulting release bump is an "Update ready" card like any other.

`nix run .#fork-mirror -- <dir>` optionally builds a plain git repo (upstream at `5978d93`, then one commit each for drop, every patch, add and rewrite), signed on Josh's YubiKey (D11), for people who want to `git log` the divergence. It is regenerated per release and never committed to.

#### f.2.8 License and branding

- omarchy is MIT, `Copyright (c) David Heinemeier Hansson`. `$OMARCHY_PATH/LICENSE` is the unmodified upstream file (`checks.fork-license` asserts its sha and that `drop.txt` never matches it); `environment.etc."omanix/licenses/omarchy-MIT.txt"` ships it; the About panel shows "Based on omarchy v4.5.0-rc2 (MIT) — Licenses".
- The omanix repo carries `LICENSES/omarchy-MIT.txt` and `fork/NOTICE`: *omanix contains a modified copy of omarchy (https://github.com/omacom/omarchy) at v4.5.0-rc2, Copyright (c) David Heinemeier Hansson, used under the MIT License. Modifications are the files under fork/ and are Copyright (c) 2026 Joshua Perry and Ada. omanix is an independent project and is not affiliated with or endorsed by the omarchy project.* omanix itself is MIT, `Copyright (c) 2026 Joshua Perry and Ada`.
- Third-party files keep their notices; packaged dependencies keep their licenses (owe, ttfx, aether … MIT; titlebars BSD-3; asdcontrol GPL-2 as a separate program). Theme wallpapers may have their own terms (U23): anything unattributed is excluded from the default closure until cleared.
- **Branding:** user-visible name, logo and icon become **omanix** (About, screensaver, Plymouth `omanix.png`, SDDM, bar logo glyph, window titles). Internal identifiers stay: `OMARCHY_PATH`, the `omarchy-*` command names, the `omarchy.*` QML plugin ids (renaming 558 commands would make every patch unreadable). Describing the origin as omarchy is factual; presenting omanix *as* omarchy is not. Links to omarchy services are removed (`omarchy.org/manual` → omanix docs; Discord row and `logs.omarchy.org` upload are DROP; the `geo.omarchy.org` lookup is P17). The post-check fails on any `omarchy.org` hostname left in shipped files. `omanix-glyphs` replaces the brand codepoints of the private icon font (U22).

#### f.2.9 How the fork runs

`omanix-data` is `omarchy-src` plus generated files: `default/hypr/omanix-overlay.lua` (the overlay loader, §f.4.3), the merged intent menu (§h.5), the merged `config/omarchy/shell.json` defaults (upstream ⊕ `omanix.shell.settings`), the theme registry, `default/omanix/language` (from `omanix.language`; `OMARCHY_LANGUAGE_FILE` points here) and the package manifests P6 reads. Big media is symlinked to `omarchy-src`.

**OMARCHY_PATH = `/run/current-system/omarchy`**:
- `system.systemBuilderCommands` adds `ln -s ${omanix-data} $out/omarchy`. A switch retargets it atomically, and no `pathsToLink` is involved.
- The rewritten `env-bootstrap` resets stale values *to* this path.
- It is set in the uwsm env (with an `/etc/xdg/uwsm/env` drop-in), the systemd user environment and `/etc/profile.d`. `OMARCHY_LANGUAGE_FILE` is set in the same three places.

**Packages:**
- `hyprland-omarchy`: the hyprland flake v0.56.2 plus omarchy-pkgs' 4 patches. software-renderer helps the virtio VM tests. The porting report compares the version against the PKGBUILD `pkgver`.
- titlebars: built with `mkHyprlandPlugin` against **`config.omanix.hyprland.package`**.
- `quickshell-omarchy`: rev `2b4501a`, with the 611 patch only when Qt is 6.11.
- `hyprland-guiutils`: from its flake.
- the 13 missing packages from facts §4, plus `try-tobi` (binary name `try`).
- `omanix-overlay`.

walker, elephant, mako, hyprlock, hypridle, waybar and swayosd are **not packaged**: Quickshell is the polkit agent, lock screen, notifier and OSD.

**Session and greeter:**
- `programs.hyprland = { enable; package = omanix.hyprland.package; withUWSM = true; }`.
- The session is upstream's `omarchy.desktop` (`uwsm start … hyprland.desktop`) via `sessionPackages`.
- SDDM:
  - `services.displayManager.sddm = { enable; wayland.enable = true; wayland.compositorCommand = "${hyprland}/bin/Hyprland --config ${omanix-data}/default/sddm/hyprland.lua"; theme = omanix-sddm-theme; }`;
  - autologin is set from `omanix.session.autologin`.
  - UNVERIFIED (U34); `tests/desktop-boots` has a greeter variant. The fallback is greetd running the same Hyprland greeter config.
- **HM before login**: `systemd.services."home-manager-<user>" = { before = [ "display-manager.service" "systemd-user-sessions.service" ]; wantedBy = [ "multi-user.target" ]; }`. This is set by loom and does not rely on HM's own ordering. The first desktop never starts with missing dotfiles.
- User units come from upstream `default/systemd/user/*` via `systemd.packages`, and are enabled exactly as upstream's first run, through NixOS `systemd.user.services.<n>.wantedBy` in `/etc/systemd/user`. `systemctl --user enable` is never run, so `~/.config/systemd/user` holds no omanix links. `KillMode=mixed` keeps the shell alive.
- `misc.disable_autoreload = true`, plus one `hyprctl reload` per session **right after `switch-to-configuration test`** (which re-runs HM activation through `home-manager-<user>.service`) and before the watchdog loop. The watchdog's `configerrors` and IPC checks therefore test the new Lua (§g.4 step 3a). A rollback reloads again against the old files.

### f.3 GUI vs agent: what stays a control, what becomes a sentence

**Rule.** The agent is the front door for *change*, not for *control*. Anything continuous, instant or visual stays a GUI control and changes **runtime state** only. Anything that changes what the machine *is* (packages, services, defaults, hardware setup, keybindings, boot, security) is a sentence to the resident, which edits the host repo and lands it through a card (§g).

| Kept as GUI (runtime state) | Why | Make it stick? |
|---|---|---|
| Volume, brightness, keyboard backlight, audio device switching, power profile | continuous / frequent | no (layout list only for keyboard) |
| Text size / scale, monitor arrangement, mode, refresh, VRR | continuous / frequent | yes → `omanix.hyprland.monitors`, `gdkScale` |
| Window and workspace management, workspace layout, gaps, corners, opacity, animations, bar/dock visibility and position | instant toggles | yes → `omanix.hyprland.settings`, `omanix.shell.settings` |
| Screenshots, recording, OCR/QR capture, clipboard, emoji, LocalSend sharing, reminders | frequent controls | no |
| Nightlight, DND, idle inhibit, screensaver, touchpad on/off | instant runtime toggles | nightlight schedule only |
| Theme, wallpaper, monospace font pickers | visual browsing with live preview | yes → `omanix.theme.default`, `omanix.theme.background`, `omanix.fonts.monospace` |
| Keyboard layout cycling and layout picker | needed to type to the agent | layout list → `omanix.input.layouts` |
| Network panel (Wi-Fi, connect, band, captive portal), Bluetooth | reach the agent | no (DNS presets became intents) |
| Agent sign-in (resident and reviewer), agent status/restart | reach / repair the agent | — |
| Approval card, Undo last change, rollback to a generation | repair; the card is the gate | — |
| Lock, suspend, hibernate, logout, reboot, shutdown | power | — |
| Restart wifi/audio/bluetooth/trackpad/shell, `omanix reset` (replaces `refresh-*`, `reinstall-configs`) | repair | — |
| Shell plugin enable/disable | instant | yes → `omanix.shell.settings` |

Everything else in omarchy's menu (install/remove, defaults, language, timezone, DNS, kernel, boot screen, security setup, git identity, web apps, TUIs, dev envs, theme repos, shell plugin repos, branding, clock format, hibernation, updates) is an **intent** (§h.5). The human-only tools that never go through the agent (password change, disk encryption key, adding a human key, secret values) are in §h.11.

**Timezone is AGENT-INTENT** (picker-then-intent, §f.2.1 rule 7). Every host declares `time.timeZone` through `loom.locale.timeZone`. A non-null `time.timeZone` makes `/etc/localtime` a static store link and sets `NIXOS_STATIC_TIMEZONE` for systemd-timedated, so `timedatectl set-timezone` cannot work at runtime. `desktop-boots` asserts that the clock's middle-click opens the timezone intent row (P19).

**GUI changes are runtime state.** A kept tool writes `~/.local/state/omarchy/**` or an overlay under `~/.local/state/omanix/` and nothing else (§f.4.4). It never touches the host repo or `loom-switch`. After a change, the tool shows a toast ("Scale 1.25 (this session) · Make it stick"), and the chat panel shows a "Make <area> stick" chip until the change is stuck or reset (§f.4.6, §h.6).

### f.4 Mutable vs declarative state

#### f.4.1 Layers

| Layer (low → high precedence) | Owner | Where | Writable at runtime |
|---|---|---|---|
| 1. fork defaults, bin, shell | nix | `$OMARCHY_PATH` | no |
| 2. theme | `omarchy-theme-set` (KEEP-AS-GUI) | `~/.local/state/omarchy/current/**` (included by layer 3) | yes |
| 3. host dotfiles (`omanix.*`, `home.nix`) | nix via **HM**, read-only | `~/.config/**` files in §f.4.2, `~/.bashrc`, `~/.XCompose` | **no** |
| 4. runtime overlays | KEEP-AS-GUI writers, `omanix edit` | `~/.local/state/omanix/overlay/**`, `~/.local/state/omanix/shell/**` (sourced **last** by layer 3) | yes |
| 5. toggles | KEEP-AS-GUI toggles | `~/.local/state/omarchy/toggles/**` | yes |
| app-owned | the application | `omanix.home.appOwned` (btop.conf, fcitx5/**, chromium profile, mimeapps.list, dconf) | yes; never HM |
| user data | the user | `~/.config/omarchy/{themes,backgrounds,plugins,hooks,themed,branding}/` | yes; never HM |
| system state | services | `/var/lib/*` (persist list) | — |
| secrets | sops | `/run/secrets` | — |

Hyprland's Lua order (identical to upstream with "user" = nix): `bootstrap` → `default.hypr.omarchy` (defaults, then theme `hyprland.lua`) → HM `hypr.{monitors,input,bindings,looknfeel,autostart}` (each ends by loading its overlay) → `default.hypr.toggles` → HM tail of `hyprland.lua` (window rules, `extraLua`) → `hyprland` overlay.

**Hazard.** Upstream bootstrap puts `~/.local/state/?.lua` **before** `~/.config/?.lua` on `package.path`, so a file at `~/.local/state/hypr/<name>.lua` would silently shadow an HM file. No shipped writer targets it (`checks.hm-owned-readonly`), and `omanix doctor` flags any such file.

#### f.4.2 What HM owns (all `xdg.configFile` / `home.file`; files only, never directories)

| Target | Content | Owning omanix module | Overlay (sourced last) and mechanism |
|---|---|---|---|
| `~/.config/hypr/hyprland.lua` | upstream template structure: bootstrap, `omarchy_default_bindings = <keybinds.defaults>`, `omarchy_preinstalled_bindings`, requires, toggles, then `windowRules` and `extraLua` | `hyprland/default.nix` | `overlay/hypr/hyprland.lua`, via `require("default.hypr.omanix-overlay")("hyprland")` |
| `~/.config/hypr/monitors.lua` | `hl.monitor` per `omanix.hyprland.monitors` (default: upstream's catch-all `scale = "auto"`), `hl.env("GDK_SCALE", gdkScale)` | `hyprland/monitors.nix` | `overlay/hypr/monitors.lua` |
| `~/.config/hypr/input.lua` | `hl.config({ input = … })` from `omanix.input` | `input.nix` | `overlay/hypr/input.lua` |
| `~/.config/hypr/bindings.lua` | `hl.unbind` / `o.bind` from `omanix.keybinds.{binds,unbind}` | `keybinds.nix` | `overlay/hypr/bindings.lua` |
| `~/.config/hypr/looknfeel.lua` | `hl.config` from `omanix.hyprland.settings` | `hyprland/default.nix` | `overlay/hypr/looknfeel.lua` |
| `~/.config/hypr/autostart.lua` | `o.launch_on_start` for apps with `autostart` | `apps/default.nix` | `overlay/hypr/autostart.lua` |
| `~/.config/hypr/{hyprsunset,xdph}.conf` | upstream files | `hyprland/default.nix` | `overlay/hypr/hyprsunset.conf` via hyprlang `source =` (hyprsunset only) |
| `~/.config/omarchy/keyboard-layouts` | `XKBLAYOUT=`/`XKBVARIANT=` from `omanix.input.layouts` (read unchanged by upstream `keyboard.lua`) | `input.nix` | none (setting) |
| `~/.XCompose` | upstream `xcompose.sh` text with `loom.user.{fullName,email}`; its last line includes the overlay | `input.nix` | `overlay/xcompose` via `include "…"` |
| `~/.config/alacritty/alacritty.toml` | **only** `general.import = [theme, "~/.config/alacritty/omanix-base.toml", "~/.config/alacritty/omanix.toml", overlay]`. Alacritty loads the importing file **last**, so any key in this file would beat the overlay; it therefore holds no other key. | `home/terminals.nix` | `overlay/alacritty.toml` (last import, so it wins over every other file) |
| `~/.config/alacritty/omanix-base.toml` | the upstream template minus `general.import` and `[font]` (`[env]`, `[terminal]`, `[window]`, `[keyboard]`, …) | `home/terminals.nix` | — |
| `~/.config/alacritty/omanix.toml` | `[font]` from `omanix.fonts` | `home/terminals.nix` | — |
| `~/.config/kitty/kitty.conf` | upstream + `font_family` from `omanix.fonts.monospace`; last line `include` overlay | `home/terminals.nix` | `overlay/kitty.conf` |
| `~/.config/ghostty/config` | upstream + font; `config-file = ?"…overlay"` (loaded after the main file) | `home/terminals.nix` | `overlay/ghostty.conf` |
| `~/.config/foot/foot.ini` | upstream + font; `include=` as the **last key of `[main]`** | `home/terminals.nix` | `overlay/foot.ini` (`[main]` keys override; a later section in the main file still wins for that section) |
| `~/.config/fontconfig/fonts.conf` | `prepend_first` rule for `omanix.fonts.monospace`, then `<include ignore_missing="yes">~/.local/state/omanix/overlay/fontconfig/fonts.conf</include>` naming the **file** (a directory include would only load `[0-9]*.conf` files and never recurse). `~/.config/fontconfig/conf.d/` is **not** HM-owned: the system `50-user.conf` loads it, and the input-method writer keeps writing there. | `fonts.nix` | `overlay/fontconfig/fonts.conf` (a later `prepend_first`, so it wins; session init seeds it as a valid empty `<fontconfig/>` document) |
| `~/.config/gtk-4.0/gtk.css` | `@import url("file://<home>/.local/state/omanix/overlay/gtk4.css");` | `home/desktop.nix` | `overlay/gtk4.css` |
| `~/.config/btop/themes/current.theme` | `mkOutOfStoreSymlink ~/.local/state/omarchy/current/theme/btop.theme` | `home/desktop.nix` | — (theme state) |
| `~/.config/chromium-flags.conf` | upstream; read by omanix's chromium wrapper together with the overlay | `apps/default.nix` | `overlay/chromium-flags.conf` |
| `~/.config/git/config` | upstream + `[user]` from `loom.user` | `home/desktop.nix` | `~/.gitconfig` (regular file, created at first login; git reads it after the XDG file, and `--global` writes it when it exists) |
| `~/.bashrc` | upstream `default/bashrc` (rewritten), then `source` of the overlay | `home/desktop.nix` | `overlay/bashrc` |
| `~/.config/xdg-terminals.list` | from `omanix.defaults.terminal` | `defaults.nix` | none (setting) |
| `~/.config/omarchy/defaults/dictation`, `~/.local/state/omarchy/defaults/editor` | from `omanix.defaults.*` | `defaults.nix` | none (setting) |
| `~/.config/hyprland-mimeapps.list` | upstream | `defaults.nix` | none |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | upstream template (comments only; host items are merged into the default menu) | `menu.nix` | none (setting: `omanix.menu.items`) |
| `~/.config/{starship.toml,tmux/tmux.conf,herdr/config.toml,lazygit/config.yml,imv/config,obsidian/user-flags.conf,hyprland-preview-share-picker/config.yaml}`, `~/.config/xdg-desktop-portal/hyprland-portals.conf`, `~/.config/wireplumber/wireplumber.conf.d/*.conf`, `~/.config/autostart/{org.fcitx.Fcitx5,print-applet}.desktop` | upstream files (`limine-snapper-notify.desktop` dropped) | `home/desktop.nix` | none. Override with `lib.mkForce` on the target's `.source` in `home.nix`, or add an `omanix.*` option. |

`omanix.home.files` exports this table, with store paths, to `catalog/home.json`.

#### f.4.3 Writable state layout

```
~/.local/state/omanix/
  overlay/                      # writable includes, one per HM file that has one (§f.4.2)
    hypr/{hyprland,monitors,input,bindings,looknfeel,autostart}.lua  hypr/hyprsunset.conf
    alacritty.toml  kitty.conf  ghostty.conf  foot.ini  xcompose  bashrc  gtk4.css  chromium-flags.conf
    fontconfig/fonts.conf
  shell/shell.json              # Quickshell user config (redirected from ~/.config/omarchy/shell.json)
  shell/shell.json.base         # the defaults it was derived from (for rebase)
  shell/shell.toml              # Quickshell user TOML (redirected from ~/.config/omarchy/shell.toml)
  overlay.json                  # manifest: sha per overlay at last settle/reset, defaults sha for shell.json
  done/first-login
~/.local/state/loom/clobbered/<UTC timestamp>/<target path>   # reclaimed files (loom.home.reclaimDir)
~/.local/state/omarchy/**       # upstream state, unchanged (current theme, toggles, indicators, windows, …)
```

Every overlay file starts with a two-line header: what it overrides, then "Make it stick: ask <agent> (menu › Make my look permanent); `omanix reset <path>` clears it". The Lua loader is:

```lua
-- $OMARCHY_PATH/default/hypr/omanix-overlay.lua (generated)
local paths = require("default.hypr.paths")
return function(name)
  local f = paths.state_home .. "/omanix/overlay/hypr/" .. name .. ".lua"
  local h = io.open(f, "r"); if not h then return end; h:close()
  dofile(f)   -- dofile, not require: re-runs on every reload; errors surface in Hyprland's error bar like upstream user files
end
```

#### f.4.4 Runtime writers that remain (KEEP-AS-GUI)

Rev 2 classified **every** upstream writer and redirected the ones that set configuration (`setting` class → `omanix set`). The fork **drops** those writers instead: defaults, language, git identity, install shims, dictation backend and the like are AGENT-INTENT (§f.2.1), so their scripts are not shipped and need no redirect. What remains are the KEEP-AS-GUI tools that write; each is recorded in `fork/writers/{desktop,theme}.toml` with `writes = "<runtime path>"`, keyed by script.

| Tool (kept) | Upstream write | omanix mechanism | Make it stick → |
|---|---|---|---|
| Theme set, glass, bg next/switcher | `~/.local/state/omarchy/current/**`; glass also `~/.config/gtk-4.0/gtk.css` | state unchanged; glass gtk block → `overlay/gtk4.css` (rewrite) | `omanix.theme.default`, `omanix.theme.background` |
| Monitor scaling (panel, keys) | `sed -i` on HM `monitors.lua` | patch → `omanix-overlay hypr-scale` writes `overlay/hypr/monitors.lua` | `omanix.hyprland.monitors` + `gdkScale` |
| Monitor clamshell (reader, polls every 2 s) | reads HM `monitors.lua` as text and re-applies its scale | patch: reads the HM file **then** the overlay, last rule wins (otherwise a numeric HM scale reverts a panel change) | — |
| Font set | `sed -i` terminals, `cat >` `fontconfig/fonts.conf` | override → `omanix-overlay kv` per terminal overlay + `overlay/fontconfig/fonts.conf` (a full `prepend_first` document) | `omanix.fonts.monospace` |
| Display text size | terminal sizes, `shell.toml`, gsettings | overrides → terminal overlays, `shell/shell.toml`; gsettings stays app-owned | (none in v1) |
| Terminal reload | `touch` HM `alacritty.toml` | rewrite → `touch overlay/alacritty.toml` | — |
| Bar / dock / widgets / plugin enable (`shell.qml`, `omarchy-shell-config`, `omarchy-bar`, `dock`, `plugin-{enable,disable}`) | `~/.config/omarchy/shell.json` | P1/P2 → `shell/shell.json`; rebase §f.4.7 | `omanix.shell.settings` |
| Toggles, workspace layout, idle, transparency | `~/.local/state/omarchy/{toggles,indicators,workspace-layouts}/` | unchanged | matching `omanix.hyprland.settings` keys |
| Keyboard layout picker (`omarchy-setup-keyboard`) | HM `~/.config/omarchy/keyboard-layouts`, then reload and a live `kb_layout` check that rolls back on mismatch | override: upstream's picker (`typing_setup.py` catalog, imported with `python3 -I`) writes `kb_layout`/`kb_variant` into `overlay/hypr/input.lua` (loaded after the HM `input.lua`), reloads, checks the live `input:kb_layout`, then runs upstream's fcitx group step (U28) | `omanix.input.layouts` (also fixes console/initrd keymap) |
| Input method `configure` | `fontconfig/conf.d/50-omarchy-input-method.conf`, `fcitx5/**` | unchanged: both app-owned, not HM-owned | — |
| Chromium feature toggle | `~/.config/chromium-flags.conf` | rewrite → `overlay/chromium-flags.conf` | `omanix.apps.chromium.features` |
| Notifications, clipboard, weather, reminders, agents panel state | `~/.local/state/omarchy/**` | unchanged | — |
| User themes, backgrounds, hooks, branding, shell plugins installed by hand | `~/.config/omarchy/{themes,backgrounds,hooks,branding,plugins}/` | user-data, unchanged | repo versions are intents (flake inputs) |

**Dropped writers** (now intents or nix): `default-{terminal,browser,editor,agent,dictation}`, `dictation-use`, `language`, `setup-git`, `font-cjk`, `setup-input` persistence, `install-*`/`remove-*` side effects, `refresh-applications`, `provision-user`'s HM writes, `fix-nouveau-cursor.sh` (now quirk `nouveau-cursor`), `enable-user-units.sh` (NixOS `systemd.user`). `setup-git`'s XCompose identity lines come from `loom.user.{fullName,email}` in the HM `~/.XCompose`.

#### f.4.5 Activation, session init and first login

**Activation** runs at boot, before the display manager, and on every switch, through `home-manager-<user>.service`:
1. `loomReclaim` (`lib.hm.dag.entryBefore ["checkLinkTargets"]`): every target in this generation's file list that exists and is **not** a symlink into a `-home-manager-files` store path is moved to `<reclaimDir>/<ts>/<target>`, with one notification ("<file> was replaced by a program; saved to … — Ask <agent> why"). Nothing is deleted, and activation never stops on a collision.
2. HM links the files.
3. `omanixDefaults` sets the default browser and mailto handler when they differ (mimeapps.list stays app-owned).

**Session init** (`omanix-session-init.service`, user oneshot, `Before=graphical-session-pre.target`, idempotent):
- Create the §f.4.3 layout; **touch every missing overlay** (foot, kitty and hyprlang `source` fail on a missing include) with its header.
- Run the shell.json rebase (§f.4.7) and `omanix-overlay settle` (§f.4.6).
- If `omanix.home.overlays = "reset"`, empty every overlay and `shell/*`. If `omanix.theme.lock`, re-apply `omanix.theme.default`.
- Start `omanix-session-state.service`, which writes `/run/omanix/session/<uid>/runtime.json` (0640, group `omanix-resident`) on every overlay, theme or toggle change: **typed keys only** (theme name, wallpaper path, monitors as output/mode/position/scale/vrr, `gdkScale`, monospace font, shell.json delta keys, overlay keys parsed by the kv formats and the recording `hl.*` stub, toggles) plus each overlay's sha256. It holds no file contents and no free text. The resident reads this.

**First login** (once, gated on `done/first-login`, inside session init):
1. Copy app-owned seeds only if absent: `btop/btop.conf`, `fcitx5/**`, `chromium/Default/Preferences`, `opencode/opencode.json`, `omarchy/branding/{about,screensaver}.txt`.
2. Create `~/.gitconfig` with a header (git reads it after the XDG file; `--global` writes it).
3. The re-expressed `provision-user` steps: xdg-user-dirs, gtk bookmarks, keyring, mise base, quirk runtime seeds (e.g. `vm-no-animations` toggles), and `OMARCHY_THEME_WAIT=1 omarchy-theme-set <omanix.theme.default>`. The human's own coding harnesses get **no** omarchy/omanix skill links: the resident carries the skills.
4. omarchy's first-run invitations (`omarchy-*-invitation`, default-agent picker) are not shipped; the welcome flow (§h.7) replaces them.

**Never HM-owned:** `~/.ssh/` (D6's generated software owner key lives there; `programs.ssh` in HM is forced off), `~/.gnupg/`, `~/.claude/` and the other harness homes of the human, `~/.local/share/applications/`, `~/.config/systemd/user/` except nuketown's broker unit (§a.3 C4) (`checks.hm-unmanaged-paths`).

#### f.4.6 Make it stick, and settling overlays

1. The human chooses **Make it stick** (toast, chip, or menu "Make my look permanent").
2. The chat surface runs `omanix-runtime-snapshot <area>` **as the human**. Areas: `look`, `hypr`, `shell`, `theme`, `font`, `monitors`, `input`. The output is code-generated JSON (`loom.snapshot/v1`): typed keys and values, the overlay paths and their sha256, and, for Lua overlays that don't parse into typed keys, the overlay text. The panel shows a preview chip and pre-fills (unsent) "Make my current <area> permanent."
3. On Send, the panel sends the turn with the snapshot as an attachment of `kind = "runtime-snapshot"`, validated against `loom.snapshot/v1`.
4. The resident's `look` skill maps the snapshot to options: theme → `omanix.theme.default`; font → `omanix.fonts.monospace`; monitors → `omanix.hyprland.monitors` + `gdkScale`; shell → `omanix.shell.settings`; known hypr keys → `omanix.input` / `omanix.keybinds` / `omanix.hyprland.settings`; anything else in `hypr/<f>.lua` → `omanix.hyprland.fileLua.<f>` (same slot as the overlay, before toggles); the `hyprland` overlay → `omanix.hyprland.extraLua`. For each whole-file area it absorbs, it sets `omanix.runtime.absorbed.<area> = "<snapshot sha>"`. Free Lua that lands in `fileLua`/`extraLua` is code that runs as the human; the card shows it in the diff.
5. Card → approval → switch → HM activation. After the promoted switch, the per-session reload hook runs **`omanix-overlay settle`** in the human session:
   - kv overlays: remove each key whose effective declared value now equals the overlay value; leave the rest;
   - whole-file overlays: empty the overlay (backup in `reclaimDir`) only if its **current** sha equals `omanix.runtime.absorbed.<area>`; if the human changed it after the snapshot, leave it and let `omanix doctor` list it.
6. The chip disappears when nothing differs. "Forget this change" in the chip's menu runs `omanix reset <area>`.

The resident never reads the human's home: it sees `runtime.json` (typed summary) and what the human attached.

#### f.4.7 shell.json: snapshot semantics and rebase

Upstream's shell uses a valid user `shell.json` **instead of** the defaults, with no deep merge. So the first bar edit freezes a full snapshot.
- The overlay keeps that semantics, and also stores the defaults it was derived from (`shell.json.base`).
- When the nix defaults sha changes (a release bump, or a change to `omanix.shell.settings`), session init does a three-way JSON merge `(base, overlay, new defaults)`:
  - objects merge recursively;
  - arrays (bar layout lists) are atomic;
  - on a conflict, the overlay wins and the path is reported.
- The result is written atomically and `base` is updated. `omanix doctor` lists the conflicts.
- pytest covers the merge in `omanix-overlay`.

#### f.4.8 reset, edit, doctor

| Command (human session) | Effect |
|---|---|
| `omanix reset <area\|path>\|--all` | Empties overlays (backup in `reclaimDir`). Replaces upstream `refresh-*`, `reinstall-configs` and the config half of `reinstall` (KEEP-AS-GUI `add/` overrides). |
| `omanix edit <path>` | Opens the overlay for an HM-owned path in the editor. For an HM file without an overlay it shows the file read-only and offers the host-repo module that controls it (`catalog/home.json`) or the `look` intent. |
| `omanix doctor` | HM links not pointing at the current generation, non-empty overlays and the declared keys they shadow, rebase conflicts, `~/.local/state/hypr/*.lua` shadow files, reclaimed files, overlays not settled because they changed after their snapshot. |

`omanix keep` is **deleted**: "make it stick" (§f.4.6) replaces it.

#### f.4.9 Checks on the fork's runtime state

| Check | Rule (fails the build) |
|---|---|
| `checks.hm-owned-readonly` | Runs the write-site scanner (stdlib python, `-I`, never executes the tree) over **`omanix-data`** against the HM-owned target set exported by evaluating the ref hosts. Fails if any shipped write site, menu action or `omarchy-launch-config-editor` call targets an HM-owned path, if any site targets `~/.local/state/hypr/`, or if any shipped skill tells an agent to edit, copy over or `sed -i` an HM-owned path. |
| `checks.runtime-writers` | Every KEEP-AS-GUI script that writes has a `writes =` row in `fork/writers/*.toml`, and every `rewrite.toml` redirect matches its count. |
| `checks.home-files-golden` | The generated HM files for `ref-default` match goldens; every HM target that has an overlay includes it as its **last** directive. |
| `checks.home-owned` | For every omanix-owned target, `definitionsWithLocations` of `home.file.<t>.{text,source}` is inspected. A host-file definition fails with "owned by `omanix.<x>`; set the option, or `lib.mkForce` the `.source` to take the file over", unless it is a `.source` at `mkForce` priority. An app-owned target always fails. The check does not rely on HM raising an error: two `.text` definitions concatenate, and a user `.text` silently loses. |
| `checks.hm-unmanaged-paths` | No HM target under `~/.ssh/` or `~/.gnupg/`. |

### f.5 Theme switching

Runtime uses upstream unchanged:
- `omarchy-theme-set` renders `.tpl` files with upstream's renderer into `~/.local/state/omarchy/current/next-theme`, swaps atomically, pushes to the shell over IPC, and retints apps. **Every** theme write lands in `~/.local/state/omarchy/**` or in app-owned files (runtime state, §f.4.3), so theme switching needs no redirect.
- The HM-owned dotfiles reach the theme the same way upstream's seeded files do:
  - alacritty `general.import`
  - kitty `include`
  - ghostty `config-file = ?"…"`
  - foot `include=`
  - Hyprland `omarchy.current.theme.hyprland` (inside `default.hypr.omarchy`)
  - Quickshell's `currentThemePath`
  - btop through the HM `mkOutOfStoreSymlink` `current.theme`
  - GTK through dconf, which is app-owned and never HM.
- Glass mode edits theme state files (runtime state, §f.4.3), and its GTK4 block goes to `overlay/gtk4.css` (§f.4.4, glass row).
- **`checks.themes-render`** runs the upstream renderer in the nix build sandbox with no network (the only build-time execution of upstream code) over **every** theme and asserts no leftover `{{` and that all canonical keys exist.

What nix contributes:
- The registry: upstream themes plus `omanix.theme.extra`. Untrusted extras go through upstream's denylist. Themes the user installs at runtime go to `~/.config/omarchy/themes/`, which is user-data and never HM.
- First login runs `omarchy-theme-set <omanix.theme.default>` (§f.4.5).
- `omanix.theme.lock` re-applies the default at every login (session init), hides the picker, install and background menu items, and puts a guard wrapper on `omarchy-theme-set`.
- **Make it stick** on a theme turns the snapshot's `theme.name` into `omanix.theme.default` in `configuration.nix` (§f.4.6).
- Backgrounds: the current background is the state link `current/background`. Per-theme user backgrounds live in `~/.config/omarchy/backgrounds/<theme>/` (user-data). Nothing here is HM-owned.

Boot visuals (Plymouth, the SDDM theme and Limine style) are declarative from `omanix.theme.boot.theme`, built with `fromTOML` on the theme's `colors.toml`.

Browser policy color:
- The `omarchy-theme-set-browser-policy` override writes `#rrggbb` into `/var/lib/omanix/spool/browser-color`, which is group-writable by the human user.
- The root path unit `omanix-browser-policy.path` validates the value against `^#[0-9a-f]{6}$` and writes the policy JSON.
- There are no NOPASSWD sudo rules.
- Chromium feature flags that omarchy adds at runtime go to `overlay/chromium-flags.conf`. The omanix chromium wrapper reads the HM file and then the overlay. nixpkgs' chromium does not read `chromium-flags.conf` by itself.

---

## g) Change pipeline

This section is the path from something the human asks for to a switched generation, and the approval every root command for the resident goes through. The rule (H5): **nothing runs as root for the resident, and nothing is activated, until the human approves its card**; the watchdog's automatic rollback to the generation already running is the only exception.

### g.1 Principals

| Principal | Unix identity | Holds | Can | Cannot |
|---|---|---|---|---|
| human | `<user>`, uid 1000, wheel (sudo with password), group `nuketown-approval-read` | human ssh key(s): FIDO2 token, or `~/.ssh/id_ed25519` with a passphrase (D10); the SEK on paper | chat, approve or deny cards, edit the repo in a terminal, `loom propose`, `sudo` | — |
| resident | `ada`, uid 1100 (`loom.agent.name`) | agent ssh key (sops → `/agents/ada/.ssh/id_ed25519`); its own model login | edit its working copy `~/projects/host`, commit, build, `loom propose`, push `gate/*` and `refs/dit/*`, chat, read `runtime.json`; **ask** for `sudo` on its list (D8: any command) | read the human's home (0700), push `master` (not in CODEOWNERS), run anything as root without an approved card |
| approval service | `nuketown-approval` (system user, groups `nuketown-approval`, `nuketown-broker`) | nothing of its own | write request directories, read files *as the requester*, run the reviewer, ask the broker, run approved commands; each step a logged `sudo` call (K11) | be started by anyone but a sudo agent (or root, W1b) |
| reviewer | `reviewer`, uid 1101, group `nuketown-approval-read` | its own model login (`/agents/reviewer/.claude`, persisted) | read request directories, print a review | push anywhere (no key), sudo, approve |
| host | root; ssh host key `/persist/etc/ssh` | host ssh + age keys, the mirror `/persist/var/lib/loom/host`, switch records | run `loom-switch` after an approval, push `master` after a promoted switch, make update and maintenance commits | — |

### g.2 Chat and the request

```
Quickshell omanix.chat (human) ──► /run/loom/chat/<agent>.sock (0660 <agent>:loom-chat) ──► loom-agent-bridge@<agent> (agent uid)
```

- The bridge serves the socket and hosts the harness (§h.3). It is the resident's own process.
- **The request on a change card is the human's words as the resident relays them.** `loom propose --request "<text>"` writes them into the proposal and passes them as `--why`; the resident's prompt says to quote them verbatim. The card labels them "Your request (as ada relayed it)". A proposal with no request text says "No request given" and is always shown in the full form.
- **Other root commands** carry the resident's `--why` (K9), labelled "ada's stated reason".
- **Terminal users:** `loom propose` without `--request` uses the commit subjects ("Your own commit: …").
- **Updates and maintenance** use fixed text ("Scheduled update of flake inputs", "Undo: <subject>", "Secret you entered at first boot: <name>").

Rev 3's root-held request ledger, `SO_PEERCRED` attribution, paste and agent-choice tracking and `Request-Id` trailers are Appendix H.2.

### g.3 Approval and switching

```
any root command:
  resident: sudo [--why "…"] <cmd…> ─► nuketown shim ─► sudo -u nuketown-approval nuketown-approve
     approval list (K8) → request dir + snapshots read as the requester (K3, K4) → kind collector, if any (K7, W1b)
     → reviewer, up to its timeout (K5) → broker REQUEST:<id> → prompter (omanix card | nuketown's card) → Approve / Deny
     Approve ─► sudo <exec_argv> (snapshots in place of scripts; logged)    Deny ─► "Request denied." on the resident's stderr
     → journal record + audit copy (K12)

a switch is the same request, kind loom-switch:
  resident: edit ~/projects/host, omanix check, commit
            loom propose --request "…"  =  nix build → bundle deployed..tip → sudo --why "<request>" loom-switch --proposal <dir> <out>
  collector (root): bundle into the mirror → refusals → git diff, stat, flags → nvd diff /run/current-system <out> → card.json
  Approve ─► loom-switch: arm watchdog → test → health → promote → push master (host key)
```

**Every request.**
1. **Admission.** `nuketown-approve` refuses (exit 1, no dialog) a command that is not on the agent's approval list (K8): "not in ada's approval list; ask Josh to run it or to add it".
2. **Request directory and snapshots** (K3, K4). The resident sees on stderr which files were snapshotted and that the snapshot is what will run.
3. **Review** (§g.4) runs before the ask, for at most `reviewer.timeout`. It is skipped when the reviewer is disabled (and, W1b, when the requester is the human). A timeout, failure or bad output gives `status = unavailable` and the ask goes ahead.
4. **Ask.** The broker hands the directory to the prompter. As built, the card appears once the review is in (or unavailable); W1b lets omanix's card appear at once with "Reviewing…". Nothing is ever approved by itself: the zenity prompter times out after 120 s as **Deny**; a kind sets its own timeout (W1b; `loom-switch`: none, the request lives while `loom propose` waits).
5. **Run.** On Approve the service user runs `exec_argv` through sudo in the requester's cwd with the system PATH and a reset environment, passing stdio and the exit code back; then it writes the journal record and the audit copy (K12). On Deny the requester sees "Request denied." (W1b: plus the prompter's reason, which the resident's harness shows as Josh's reply).

**Switches** (`loom propose`, `loom-switch`).
1. **Propose** (resident or human). `loom propose [--ref <rev>] [--request <text>]` builds `nixosConfigurations.host` of the commit through nix-daemon (pure eval, no IFD, substituters from the running `nix.settings`), writes `<dir>/{host.bundle,request.txt,tip}` (bundle = `deployed..tip`), pushes `gate/<topic>` to silo with the agent key, then runs `sudo --why "<request>" loom-switch --proposal <dir> <out>`. An eval or build failure goes back verbatim (exit 1), with no card. The resident runs `loom propose` as a background command and is told the outcome when it ends. One proposal at a time: a newer one makes the pending request deny itself ("superseded").
2. **Collect** (root, K7: `loom-switch-collect`). **Refuse** (exit 5, no dialog) when `<out>` is not a NixOS toplevel in the store; when the bundle doesn't verify or its tip does not descend from the deployed commit ("rebase onto <sha>"); when an SEK rotation is in progress and the tip is not its recorded commit (§g.10); or when the tree lacks `.authorized_keys` or `CODEOWNERS` (F5). Otherwise fetch the bundle into the mirror as `refs/proposals/<id>` (fetching from a bundle file runs no hooks) and write into `kind/`: `nvd diff /run/current-system <out>`; `git diff --stat` and `git diff -U5` of `deployed..tip` (diff capped at 200 kB, beyond that the file list and stat); the changed files; and one line flagging files that change who controls the machine: `keys.nix`, `machine.nix`, `flake.lock` (with the inputs that moved), `secrets/**`, `.authorized_keys`/`CODEOWNERS`. The line is a label, not a gate. Add the previous rejection reason if the last change card was denied (O7), and `card.json` (§g.4).
3. **Review** with loom's switch prompt (§g.4); skipped when the requester is the human, for undo to a previously switched tree, and for signed-release-only updates.
4. **Ask** as above; the omanix card draws `kind = loom-switch` as the change card (§h.4).
5. **Activate** (§g.5) exactly `<out>`, under `/run/loom/switch.lock`.
6. **Record.** `/persist/var/lib/loom/switches/<n>/{card.json,review.json,nvd.txt,tip,out}`, copied from `NUKETOWN_APPROVAL_DIR` (W1b); denied change cards go to `switches/denied/`. nuketown's own audit copy (K12) holds every request regardless.

**Humans and timers.**
- The human's `loom propose` (and the no-agent panel's **Apply**) ends in `pkexec loom-switch-request …`. The polkit action `farm.loom.propose` is `yes` only for the human user in an active local session and `auth_admin` otherwise; `loom-switch-request` (root) calls `sudo -u nuketown-approval nuketown-approve --requester <human> -- loom-switch …` (W1b), so the human gets the same card, without a review. Over ssh with no session, `sudo loom-switch --proposal <dir> <out>` with the human's password is the approval.
- Root timers (`loom-update`) call `sudo -u nuketown-approval nuketown-approve --requester loom-update -- loom-switch …` (W1b).

**Silo master.** After a promoted switch `loom-switch` pushes `master` with the host key. If silo's `master` is not an ancestor of the new commit (a human pushed directly from elsewhere), it first pushes the old silo tip to `gate/diverged/<sha>`, then updates `master`, and the next card notes it.

### g.4 Card and reviewer

**Reviewer run** (K5, built). The service user runs, before asking,

```
timeout --kill-after=5 <reviewer.timeout> sudo -H -u reviewer -- <reviewer.command> /run/nuketown-approval/<id>  < /dev/null
```

The default command builds the prompt from nuketown's fixed adversarial prompt, `request.json` and each snapshot (capped at 200 kB in the prompt), runs `claude -p --output-format text` as the reviewer, and prints the JSON object it finds. The prompt: assume the agent may be mistaken or compromised; say concretely, step by step, what the command and every script will do; flag anything beyond the stated reason, anything that persists (users, keys, services, sudoers, ssh, shell rc files), sends data off the machine or destroys data; list what it can't see (files sourced or read at run time, downloads, scripts that find siblings via `$0`, which now point into the snapshot directory). Output, validated by the service user (summary ≤ 2000 chars, ≤ 20 notes of ≤ 500 chars):

```jsonc
{ "summary": "Restarts Wi-Fi and deletes all saved networks. …",   // 2-5 plain sentences
  "risk": "low|medium|high",
  "recommendation": "approve|deny|ask",
  "notes": [ "line 4 deletes /var/lib/iwd/*.psk, which the reason didn't mention" ],
  "not_shown": [ "line 6 runs ~/bin/fixwifi, which wasn't snapshotted" ] }
```

A loom kind (W1b) can replace the prompt; the review the card shows is the same object.

loom's switch prompt adds: compare the git diff and the nvd diff with the request, and say plainly anything the request didn't ask for. Invalid output, a timeout or a signed-out reviewer give `review.json = {status: "unavailable", reason}` → "No review: <reason>". All review text is rendered as plain text.

**Change card** (`kind/card.json`, written by the collector; the prompter merges `review.json`):

```jsonc
{ "n": 7, "tip": "…", "base": "…", "out": "/nix/store/…-nixos-system-kestrel",
  "kind": "change|update|undo|maintenance",
  "title": "Install Steam for gaming",                 // first line of the request, or the first commit subject
  "request": "install steam and set it up for gaming",
  "flags": [ "flake.lock: adds input steam-tweaks" ],  // §g.3 switch step 2
  "packages": "+3 (steam 1.0.0.81, …) · 0 removed · 2 upgraded",
  "lastRejection": null,
  "full": false }
```

**Form.** A change card is routine (one line, §h.4) when the reviewer said `approve` with `risk = low` and no `notes`, there are no `flags`, and there is a request; or for an undo or a release-only update. Everything else uses the full form. Root-command cards have one form (§h.4). This is a display choice, not a security property.

**nuketown's card** (signi, or no Quickshell; built): the built-in prompter (`nuketown-prompter`, GTK 4, X11 and Wayland) shows the requester and run-as user, the command, the agent's stated reason and kind, then the review line (risk badge, recommendation, headline, concerns) or "No review: <reason>" / "No reviewer configured" / a spinner while pending, updated in place; its ⓘ expands the summary, "Could not verify", the snapshotted and kind files (scrollable, monospace) and the full command. Deny and Approve only, the keys of §h.4.

### g.5 Activation, watchdog, rollback

```
1  baseline health snapshot (which checks pass NOW)
2  ARM, both BEFORE activation, both from the OLD generation's store paths:
     systemd-run --unit=loom-watchdog-<n> $(readlink -f /run/current-system)/loom/watchdog --new <out> --prev <old> --deadline <t>
     systemd-run --on-active=<t+30> --unit=loom-deadman-<n> $(readlink -f /run/current-system)/loom/rollback <old>
3  <out>/bin/switch-to-configuration test        (boot default untouched; re-runs HM activation)
3a per-session `hyprctl reload` as the session user, so step 4's configerrors and IPC checks test the new Lua
4  watchdog loop (every 5 s until the deadline), baseline-relative:
     reached the target; no new failed units; NM connectivity ≥ baseline; silo reachable with the host key (if it was);
     flavor checks (omanix: Hyprland answers `hyprctl -j monitors` in each session,
     omarchy-shell IPC answers, `hyprctl configerrors` empty; run as the session user); loom.home: hm-activation succeeded
5a pass → cancel the dead-man timer; nix-env -p /nix/var/nix/profiles/system --set <out>;
          <out>/bin/switch-to-configuration boot; overlay settle; update-ref master to <tip>;
          push master to silo with the host key (queued while offline); post "applied" to chat; exit 0
5b fail/timeout, or loom-switch or watchdog death (the dead-man timer fires) →
          <old>/bin/switch-to-configuration test; per-session hyprctl reload against the old files;
          push refs/heads/gate/rejected/<tip>; tell the human and the resident the failing check and
          journal cursor ("Rolled back: Hyprland didn't answer within 30 s"); exit 4
```

- The toplevel carries `$out/loom/{watchdog,rollback}` via `system.systemBuilderCommands`. Transient units aren't managed by `switch-to-configuration`, so activating the new generation can't stop them.
- **Rollback by default.** Nothing reaches the boot default before health passes. A crash or power loss boots the old generation. loom enables no boot counting with either loader (D7); the loader's generation menu is the manual fallback.

### g.6 Updates, undo and rollback

**Updates.**
- `loom-update.timer` (daily, `loom.switch.autoUpdate = "notify"`, the default) runs `nix flake update` for `loom.update.inputs` (default: omanix only) in a scratch worktree. omanix moves only to the newest **signed tag** on its channel (`git verify-tag` against `/etc/loom/release-signers`, D11). It commits as the host (`update: <inputs>`), builds, and requests `loom-switch` through `nuketown-approve` (W1b `--requester`). Plugin inputs are bumped only when asked.
- Card heading **Update ready**; routine one-liner when only signed omanix releases (and nixpkgs through omanix's lock) moved: `Update ready: omanix v0.1.0 → v0.1.1 (signed) · 312 packages upgraded · [Approve] [Details] [Later]`. `[Later]` denies with reason `later`; the timer asks again in 24 h. The reviewer is skipped for it.
- `"off"` disables the timer. **Nothing auto-switches, ever.** The menu's "Check for updates" runs the timer now; the resident's `omanix update [<input>]` does the same on request.
- Firmware: the `update` skill reports `fwupdmgr get-updates`; applying is `sudo fwupdmgr update` from the resident's list, approved on a card, or the human running it.

**Undo and rollback.**

| Action | Who | Approval? | Card |
|---|---|---|---|
| Watchdog / dead-man rollback during a switch | automatic | no (restores the running generation) | a notification afterwards ("Rolled back: … · Why?") |
| **Undo last change** (toast for 2 min after a switch, bar menu, `loom undo`) | human or resident | human: the Undo click (polkit `farm.loom.undo`, active session, no password); resident: a card | routine "Undo: <subject>"; no review (the tree equals an earlier switch record's tree) |
| Roll back to generation N (`loom rollback --to <n>`, GUI list) | same | yes | "Roll back to <date>: <subject>" |
| Boot an older generation from the loader menu | physical presence | no | at next login: "You booted an older generation (<date>). Make it the default?" → a rollback card |
| `sudo nixos-rebuild switch` outside loom | human with a password | — | the next card notes "the running system wasn't switched by loom" |

Undo and rollback are revert commits whose tree equals the target switch record's tree; `loom-switch --undo` / `--to <n>` makes them (host-authored) and the build is a store hit, so Undo is one click and seconds.

### g.7 Enrollment (spec bootstrap ownership)

Three pushes are possible over a host's life. The silo check that admits each one is named.

**Mint push** (configure, §e.2). The owner human key creates the repo:
```
configure (owner key)                                            silo
git push ssh://git@silo/omanix/<id>.git master            ── path missing → git init --bare; .owner_key := owner (F1)
  commit "mint" (owner-signed):                            ── pre-receive: pusher == .owner_key → bypass (F3)
    .authorized_keys = owner + humans… + enroll             ── post-receive: bare .authorized_keys := tree copy (F5)
    CODEOWNERS       = owner + humans… + enroll
verify: ls-remote --symref → HEAD = refs/heads/master, master = commit (F6 guard)
```

**Enrollment push** (installer step 9, preconfigured mode). The enroll key removes itself:
```
installer (enroll.key)                                           silo
check: ls-remote master == sidecar.host.commit, else STOP ("this host repo changed since configure;
       run `configure revoke-enroll` and re-mint, or reinstall")
git -c core.sshCommand="ssh -o IdentitiesOnly=yes -i enroll.key" push … master        (fast-forward only, never --force)
  commits: "install: apply answers", "install: <host> on <disk>" (host-signed):
    .authorized_keys = owner + humans… + host + agent…     ── transport: enroll ∈ bare .authorized_keys (F2) ✓
    CODEOWNERS       = owner + humans… + host               ── pre-receive: enroll ∈ HEAD:CODEOWNERS of "mint" (F4) ✓
                                                             ── post-receive: bare .authorized_keys := new copy (F5);
                                                                enroll is no longer transport-authorized
verify:
  1. ls-remote with the host key: master == install commit ✓
  2. push with the host key to refs/heads/gate/probe-<rand>, then delete it: accepted (host is transport-authorized) ✓
  3. push with enroll.key to refs/heads/gate/probe-<rand>: REJECTED "silo: access denied" ✓
     (gate/* passes pre-receive, so a rejection here proves the transport-level revocation)
  any ✗ → keep enroll.key under /persist/var/lib/loom/enroll/, retry at first boot, `loom status` shows the reason
```

**Fresh-mode push** (installer step 9 online, or first-boot `repo-publish`). There is no enroll key: the owner key (FIDO2 on this machine, or the generated software key) signs the tip and pushes the final tree. That one push creates the repo with `.owner_key = owner`, with the same verify steps (HEAD check; host key accepted on `gate/*`).

**Key powers** (reconciled with F1–F8; the kind of human key changes no row, D10):

| Key | Where it lives | Silo transport | `CODEOWNERS` | Push `master` | Push `gate/*` | Push `refs/dit/*` | sops |
|---|---|---|---|---|---|---|---|
| human, **owner** | FIDO2 token (recommended), or `~/.ssh/id_ed25519` with a passphrase | `.owner_key` (immutable in v1) | yes | yes (F3 bypass) | yes | yes | only with an `age` recipient |
| human, additional | token or another computer | `.authorized_keys` | yes | yes (F4) | yes | yes | same |
| host ssh | `/persist/etc/ssh` | `.authorized_keys` | yes | yes; used only by `loom-switch` after a passed switch | yes (update/maintenance proposals, probes) | yes | — |
| agent ssh | sops → `/agents/<n>/.ssh` | `.authorized_keys` | **never** | **no** (F4 rejects) | yes, always passes (F4) | new or fast-forward | — |
| enroll | `enroll.key` on the stick; shredded after use | mint commit only | mint commit only | **once** (the enrollment push) | until enrolled | — | never |
| host age | `/persist/var/lib/loom/sops/host.age` | — | — | — | — | — | all files |
| system encryption key | paper, with the human (§g.10) | — | — | — | — | — | all files, via the derived age identity |

- A proposal that adds the agent key to `CODEOWNERS` is flagged on the card (`keys.nix` changed); it would let the agent push `master`.
- **The agent key can force-push or delete any `gate/*` ref** (F4 has no fast-forward check on gate), including `gate/rejected/*`. That is denial of service only: switch records live under `/persist` (U15).
- silo `master` is the chain of switched commits, pushed by the host key. The host key is in `CODEOWNERS` and could rewrite it; v1 accepts that (§g.6, Appendix H.6).

After enrollment, nothing off the machine holds write access except the human keys, which are the intended exception (spec Bootstrap 4). **In v1 the owner key cannot be revoked on silo:** `.owner_key` is immutable until S1. If the owner key may be compromised, the response is a fork (§g.8).

### g.8 Reinstall, fork, key rotation

**Reinstall** (same id):
1. Boot with `loom.host=<id>`, or enter the id at the prompt. The installer clones the repo and shows hostname, user, owner key and the commit it will install (silo `master`) for confirmation.
2. The disk/unlock flow runs as for a new install. New host, agent and age keys are generated, plus a new machine-id.
3. **System encryption key** (§e.5 step 5).
   - If the user types it and its fingerprint matches, it is kept. The salt is the host id, so the same key derives the same LUKS passphrase for the new disk and the same age identity (§g.10).
   - Otherwise a new key is generated and shown.
4. **Re-encrypt secrets**, using the first identity available:
   - the YubiKey (`age-plugin-yubikey`);
   - the age identity derived from the typed system encryption key.

   Then the installer runs `sops updatekeys`. It swaps in the new host and agent recipients and sets `recovery` to the current system-encryption-key recipient. If a new key was generated, the old recipient is **removed** here and the data key is rotated (`sops rotate`), since the old key was not available. If no identity is available, secrets are dropped and listed for the first-boot prompt. The password is prompted in the TUI anyway.
5. **Authorize.** A commit replaces the old host and agent keys in `keys.nix` (and, through `loom keys sync`, in `.authorized_keys` and `CODEOWNERS`). It is **signed and pushed with a surviving human key**:
   - the owner, which silo admits via F3; or an additional human key, admitted because it is in `HEAD:CODEOWNERS` (F4);
   - a FIDO2 `ed25519-sk` key works in the installer;
   - or `loom authorize <id> --host <pub> --agent <pub>` on any machine that holds a human key. Until then the host runs read-only against silo, and `loom status` shows `enrollment: pending-human`.

   A software owner key that lived on the wiped disk does not survive, unless the user kept a copy.

   Optionally, a new software human key is generated here (§e.5) and added in the same commit.

**Fork** (no authorized human key survives, or the owner key may be compromised):
1. Mint a new machine-id and a new id.
2. The user **must create a new human key**: FIDO2 on this machine (recommended), or a passphrase software key generated here (§e.5), or a key on another computer via `configure fork <old id>`.
3. **That key makes the first push of the new repo, so it is the owner (F1).** No S1 is involved. In the installer the push follows the fresh-mode path, with no enroll key.
4. Secrets are kept only if the old system encryption key is typed. The fork derives the old age identity with the **old** id as salt, decrypts, and re-encrypts under a **new** system encryption key for the new id. Otherwise secrets are dropped and re-prompted.
5. Record `loom.host.forkedFrom = <old id>` in `machine.nix`. The old repo stays as an orphan; it is public, with ciphertext only.

**Rotation** (all `--json` except where a secret is shown; every resulting commit goes through a card):
- `loom keys list` shows every key in the §g.7 table, owner flagged, with the system-encryption-key fingerprint.
- `loom keys rotate host|agent <n>`.
- `loom keys rotate encryption-key`. Menu: "Rotate system encryption key". The procedure is in §g.10.
- `loom keys add-human [--generate]` / `remove-human <fp>`:
  - `--generate` creates a passphrase software key in `~/.ssh`, with the same rules as §e.5. It runs as the human in a terminal the human opened (it refuses `--json` and refuses to run as the agent uid); the passphrase is read by ssh-keygen's own prompt on that pty, **never passed on argv or in the environment**; and with a resident agent a passphrase equal to the login password is refused;
  - adding an existing software key file that has no passphrase is refused (D10);
  - `remove-human` refuses to remove the last human key;
  - removing the **owner** from `.authorized_keys` and `CODEOWNERS` is refused in v1, with "the owner key can't be revoked on silo until S1; fork if it is compromised".
  - No key kind is "downgraded", and no permission changes with key kind (D10).
- `loom unlock {status,add,remove,reseal}`, with the two-methods-including-the-system-encryption-key guard. `reseal` re-enrolls TPM2 after firmware updates and needs another factor.

### g.9 v1 trust stance

Josh, 2026-10-28: the input to the resident is almost always the user typing into a textbox. A rogue plugin or a README the user asks it to follow is the same risk as the `curl | bash` instructions on thousands of websites, and users already accept that. v1 therefore relies on:
- **unix users** (nuketown): the resident and the reviewer can't read the human's home, keys or session, and can't switch the system;
- **the card**: nothing runs as root for the resident and nothing is activated without the human's Approve; change cards carry the nvd and git diffs computed by root, and every card carries the reviewer's plain-English account of what will run, with the exact script contents one click away;
- **rollback**: a broken change rolls back by itself, and Undo is one click;
- the platform baseline that is not agent hardening: LUKS with the installer-chosen unlock, the system encryption key, sops (no plaintext secret in git), a human-owned silo repo, signed releases, flash and disk guards.

**Accepted limits in v1** (each answered by an Appendix H item):
- A compromised or prompt-injected resident can put anything in the request text and the `--why` it relays. The human's defence is the card, the review and the diffs (H.2, H.3).
- **The activated `<out>` is the resident's build.** The card's nvd diff is computed by root against that `<out>`, so it shows what will be activated, but nothing checks that `<out>` is the build of the reviewed commit; a mismatch would show up only as unexpected package changes in the nvd diff (H.3, H.4).
- Snapshots cover the program and its file arguments, not what a script reads, sources or downloads at run time. The reviewer is told to list those, and the card shows them under "Can't see" (H.4).
- The reviewer reads the request and the scripts, so text in them can steer its summary; it runs unsandboxed with its own network (H.5).
- With D8 `"any"`, an approved command is root for whatever it does.
- The host key is in `CODEOWNERS` and can rewrite silo `master`; reinstall installs silo's `master` as is (H.6).
- nuketown gaps not closed by K1–K3 stay: no peer check on the broker socket (a `nuketown-broker` member can still raise dialogs and DECRYPT requests directly, but nothing runs as root without the root wrapper), and an unrestricted `machinectl shell` polkit rule for the human (H.1).

### g.10 System encryption key (D12)

The user has **one** recovery secret, called the **system encryption key** (SEK) everywhere they see it. Code and options call it `recovery` or `sek`. Two independent keys are derived from it: the LUKS recovery passphrase and the sops recovery age identity.

**Root secret and encoding.**

| Item | Definition |
|---|---|
| `R` | 20 bytes (160 bits) from `getrandom()` |
| check | first 20 bits of `SHA-256("loom.sek/v1 check" ‖ R)` |
| text | `"SEK1-"` + Crockford base32 of `R` (32 chars) + the check (4 chars), in 9 groups of 4, e.g. `SEK1-7KQ3-M0ZD-…-H4WX` |
| parsing | case-insensitive; spaces and dashes ignored; `I`/`L`→`1`, `O`→`0`; the `SEK1` prefix is optional when typing; a wrong check is rejected with "one character is wrong in group N?" (it is a checksum, not a correction) |
| QR | same text, uppercase alphanumeric mode |

**Derivation** (RFC 5869 HKDF-SHA256; `salt = "loom.sek/v1" ‖ hostId`, where `hostId` is the 16 raw bytes of `loom.host.id`):

| Output | `info` | L | Used as |
|---|---|---|---|
| `K_luks` | `"loom.sek/v1 luks-passphrase"` | 32 | The LUKS2 keyslot passphrase is the **lowercase hex** of `K_luks` (64 ASCII bytes, no newline), behind the slot's own argon2id. |
| `K_age` | `"loom.sek/v1 age-x25519"` | 32 | age X25519 identity `AGE-SECRET-KEY-1` + bech32(`K_age`), uppercased. The recipient comes from `age-keygen -y`. Clamping happens inside X25519, as age does for any 32-byte key. |
| `fp` | `"loom.sek/v1 fingerprint"` | 8 | Public. Its 16 hex chars are stored in `loom.secrets.recovery.fingerprint` and in the LUKS `loom-sek` token. Tools use it to recognize the right key before trying it. |

Why this is safe:
- **No password KDF on `R`.** `R` is 160 uniformly random bits. Stretching would add about 20 bits of work to an attacker who already faces 2^160. Even against every omanix host at once (a multi-target attack on public sops ciphertext), the per-host salt plus 160 bits leaves more than 2^128 work. A memory-hard KDF would only slow the initrd. The LUKS slot still applies its own argon2id to `hex(K_luks)`.
- **No cross-misuse.** The `info` labels separate the outputs, so `K_luks` and `K_age` are independent PRF outputs. The LUKS slot accepts only `hex(K_luks)`. Typing the age identity, or a `K_age`-shaped string, at boot is passed through unchanged and fails. No tool accepts `K_luks` as an age identity: it isn't in age format, and `loom-sek` never emits it as one.
- **No path back to the root.** HKDF-Expand is one-way. Leaking `K_age` (say, from a tmpfs during reinstall) or `K_luks` (say, from argon2id cracking, which is infeasible) reveals neither `R` nor the other derived key. The `fp` is a 64-bit PRF output, so it gives an attacker nothing beyond the oracle the public ciphertext already gives.
- **Honest limit.** The user types `R` itself at the boot prompt. Whatever runs in that initrd sees `R`. Under Secure Boot the initrd is ours. After typing the key on a machine you don't trust, rotate it.

**Implementations.** There is one spec and two implementations, cross-checked:
- `loom-sek` (python stdlib, in `loom-cli` and `loom-installer`) does generate, parse, derive, `age-identity` (to stdout or a pipe), and `luks-passphrase` (to a pipe only).
- The initrd agent `loom-askpass` (POSIX sh + `openssl kdf … HKDF` + `plymouth` + `systemd-reply-password`) does derive only.
- **`checks.sek-vectors`** runs fixed vectors through both implementations and through `age-keygen -y`. The vectors are R, host id → text, `K_luks` hex, age identity and recipient, and fp.

**LUKS2 token `loom-sek`** (the one schema; used by the installer §e.7, rotation phase 2, `loom unlock`, and the rescue path):

```json
{ "type": "loom-sek", "keyslots": ["<n>"], "v": 1, "fp": "<16 hex>", "salt": "<loom.host.id, 32 hex>", "state": "active" | "pending" }
```

- It is always imported with `cryptsetup token import --key-slot <n>`, so `keyslots` binds it to exactly the slot that `hex(K_luks)` opens.
- `salt` is the host id the slot was derived with. The rescue path and `loom-askpass` fallbacks read it from here, so a disk can be unlocked without its repo.
- `state = "pending"` only during a rotation (phases 2–4). Outside a rotation, a disk has exactly one `loom-sek` token, and it is `active`.
- `checks.sek-vectors` includes a schema fixture; `luksDump` verification in §e.7 step 5 and rotation phase 5 checks every field.

**Boot unlock (`loom-askpass`, initrd).** This is a systemd password agent: it watches `/run/systemd/ask-password`, following the systemd password-agent protocol. It masks `systemd-ask-password-plymouth.path` and `systemd-ask-password-console.path`, and prompts through `plymouth ask-for-password`, or through the console with echo off when Plymouth is absent.
- For asks whose `Id=` starts with `cryptsetup:`: if the input parses as a SEK (36 base32 chars, valid check), the agent replies `hex(HKDF(R, salt("loom.sek/v1" ‖ hostId baked from loom.host.id), "loom.sek/v1 luks-passphrase"))`. Otherwise it replies with the input unchanged: the disk passphrase, the FIDO2 PIN, or the TPM PIN.
- For all other asks, the input is passed through unchanged.
- A real passphrase that happens to parse as a SEK has a 2^-20 chance per attempt even before the length rule, and the installer and `loom unlock add passphrase` refuse such passphrases.
- **Rescue without the installed initrd:** the installer image's menu has "Unlock a disk with my system encryption key". It reads `salt` from the disk's `loom-sek` token and runs `cryptsetup open` with the derived passphrase.
- UNVERIFIED: that systemd-cryptsetup and libcryptsetup ignore the unknown `loom-sek` token type. systemd's own `systemd-recovery` token shows that metadata-only tokens are tolerated. `fde-recovery` proves it for ours.

**Shown once.** The installer (§e.5 step 5) and `loom keys rotate encryption-key` are the only places a SEK is generated or displayed. Each requires typing the **complete** key back from paper after the screen clears, accepted only when its fp matches (a partial retype would leave transcription errors in the unchecked groups undetected until the key is needed). No file, log, sidecar, repo or catalog ever holds `R`, `K_luks` or `K_age`. While in use they live in process memory or on the live system's tmpfs, which has no swap.

**Reinstall re-derivation.** The user types the SEK. The tool parses it, computes `fp` with salt = repo id, and compares it with `loom.secrets.recovery.fingerprint`. On a match it derives `K_age` and exports it only via `SOPS_AGE_KEY` (environment, never a file) to `sops updatekeys`/`decrypt`. It derives `K_luks` for the new disk's slot (§e.7). A mismatch says "this is not the key for <hostname> (<id8>)".

**Rotation: `loom keys rotate encryption-key`** (menu "Rotate system encryption key"; skill `rotate-keys`).
- Run by the human: root comes from the polkit action `farm.loom.keys.rotate`, allowed only for `loom.user.name` in an active local session, with `auth_self`. The agent can't start it, and with `--json` it refuses phase 1 (exit 2, "needs you at the screen").
- **Switch gating without a shared lock.** The rotation tool never holds `/run/loom/switch.lock`. Instead, `sek-rotation.json` is the marker: while the file exists (from phase 1 until `done` or `--abort` deletes it), `loom-switch`'s collector (§g.3 switch step 2) admits only the commit recorded in `commit` (nothing until one is recorded) and answers every other commit with exit 5 "encryption key rotation in progress; resume it or run `loom keys rotate encryption-key --abort`". So no agent commit can encrypt to the old recipient mid-rotation, and the rotation's own proposal in phase 4 goes through `loom-switch` normally.
- State lives in `/persist/var/lib/loom/keys/sek-rotation.json`, written atomically (write, fsync, rename): `{v, phase, oldFp, newFp, slotsBefore, newSlot, oldSlots, commit, paperVerified}`. **It never contains `R'`.** Every phase first inspects the real state (`luksDump` slots and tokens, the git working tree, silo `master`), so re-running a phase that already completed is a no-op.
- **Resume** (the state file exists): the user either (i) retypes `R'` **in full from paper**, accepted only if its fp equals `newFp`, and the tool continues at the recorded phase; or (ii) before phase 3 only, chooses "I don't have the new key; start over", which runs the **pending cleanup** below and restarts at phase 1 with a fresh `R'`. After phase 3 has started, only (i) is offered, because the new recipient may already be in the working tree.
- **Pending cleanup** (start over, `--abort`, and the start of every phase 1): remove every `loom-sek` token with `state = "pending"` whose `fp` ≠ the current `newFp`, wipe the slots in its `keyslots`, and wipe every slot that is neither in `slotsBefore` nor bound to the `active` token or another recorded unlock method (`unlock.json`). This removes a slot whose token import never happened.
- **Paper check gate.** Phases 3b and 5 refuse to run unless `paperVerified` is set for the current `newFp`, which only a full retype of `R'` from paper (phase 1, or a resume) sets. This is what stops a transcription error from surviving into a state where the old key no longer works.

| Phase | Action | Verify before advancing | Crash/resume |
|---|---|---|---|
| 1 `generated` | Run pending cleanup. Generate `R'` and show it once. After the user confirms it is written down, the screen clears and the user types the **complete key back from paper**. Record `oldFp` (from settings), `newFp`, `paperVerified = newFp`. | The typed key parses and its fp equals `newFp`; otherwise show it again and repeat. | No state file yet (crash before the record): restart at phase 1; nothing has changed. State file present: resume rule above. |
| 2 `luks-added` | Unlock with an **existing** factor: the old SEK (typed; `--unlock-key-file` from a pipe of `hex(K_luks_old)`), the disk passphrase, or FIDO2 (`--unlock-fido2-device=auto`). (a) Record `slotsBefore` and `oldSlots` (the `keyslots` of the `active` token). (b) **Test every keyslot** with `cryptsetup open --test-passphrase` and `hex(K'_luks)`; if one opens, reuse it as `newSlot`. Otherwise add a slot via `systemd-cryptenroll --password` (with `NEWPASSWORD` in the env) and find `newSlot` as the one slot not in `slotsBefore`. (c) Record `newSlot` in the state file. (d) Import the `loom-sek` token (schema above) with `cryptsetup token import --key-slot <newSlot>`, `fp = newFp`, `salt = loom.host.id`, `state = "pending"`, unless a token with `newFp` already binds `newSlot`. | `cryptsetup open --test-passphrase --key-slot <newSlot>` with `hex(K'_luks)` succeeds. Exactly one token with `newFp` exists, and its `keyslots` = `[newSlot]`. | Re-run phase 2: steps (b) and (d) find and reuse what exists, so no second slot or token is ever added. |
| 3 `sops-staged` | In the root-owned mirror's working tree, decrypting with the host age key: (a) `sops rotate -i --add-age <new recipient>` on every `secrets/**` file; **verify (a)**; (b) (paper check gate) `sops rotate -i --rm-age <old recipient>`, which also generates a new data key; set `machine.nix` `loom.secrets.recipients.recovery` + `loom.secrets.recovery.fingerprint` and regenerate `.sops.yaml` (`loom keys sync`). | After (a): every file decrypts with `SOPS_AGE_KEY=K'_age` **alone**, and the plaintext hash equals the host-key decrypt of the deployed commit. After (b): the same check again; the old recipient is absent from every file's metadata; the host key still decrypts. | The working tree is disposable: `git checkout -- secrets .sops.yaml machine.nix`, then redo phase 3 from the deployed commit. |
| 4 `committed` | Commit `keys: rotate system encryption key <oldFp>→<newFp>` (authored by the human), **record `commit` in the state file**, then `loom propose --ref <commit>` → the collector admits it (marker) → card (flags `machine.nix` and `secrets/**`; reviewer skipped) → approval → promoted → push `master` (host key). | The proposal exits 0, and silo's `master` == `<commit>` (`ls-remote`). | `commit` recorded but not promoted ⇒ re-run `loom propose --ref <commit>`. Rejected or rolled back ⇒ back to phase 3, or `--abort`. |
| 5 `old-wiped` | (paper check gate) Wipe every slot in `oldSlots`; if the old SEK was typed in this run, also wipe every other slot that opens with `hex(K_luks_old)` (`cryptsetup open --test-passphrase` without `--key-slot`, looped until it fails). Remove every `loom-sek` token whose `fp` ≠ `newFp`. Set the new token's `state = "active"`. | `luksDump`: exactly one `loom-sek` token, all fields valid, `fp = newFp`, `state = "active"`, and its slot test-opens with `hex(K'_luks)`. Every keyslot is that slot or one recorded in `unlock.json`. The unlock guard (≥ 2 methods including the SEK) still holds. | Re-run phase 5: wiping and token removal are idempotent. |
| 6 `done` | Show "Done. Destroy the paper with key <oldFp>." Delete the state file. | `loom keys list` shows `newFp`; `unlock.json` is updated. | — |

- `--abort` is allowed only before phase 4 is promoted. It runs the pending cleanup for `newFp` too (wipes the new slot and token), discards the working tree, and deletes the state file. The old key stays valid. After promotion the procedure only moves forward.
- **Limit, shown on screen:** old ciphertext in the public repo history stays readable to the **old** key. Rotation protects everything after it, because phase 3b generates a new data key. If you rotate because the old key leaked, also change the secrets themselves (Wi-Fi passwords, login password) with `omanix secret set` / `loom user passwd`.
- **VM test `sek-rotate-crash`:** kill the tool after each phase **and** between every sub-step of phase 2 (after the slot add, after the state write, after the token import). Resume must reach `done` with exactly one new slot added, and at every point at least one SEK unlocks the disk and decrypts the deployed secrets. Also: "start over" after a crash in phase 2 leaves no orphan slot or pending token; a deliberately mistyped paper retype blocks 3b and 5; an agent commit sent during phases 3–4 gets exit 5 while the rotation commit is admitted; and after `done`, the installer image's rescue path ("Unlock a disk with my system encryption key", reading `salt` from the token) unlocks with the new SEK and fails with the old one.

### g.11 Script guards (every destructive tool)

- `--dry-run` / `plan` emits a JSON plan.
- An out-of-band confirmation is required: a TTY-typed token (serial, hostname, `ERASE`) or a broker approval. No `--force` bypasses device-class checks.
- Devices are resolved by-id and re-checked (major:minor, serial) right before writing.
- Writes are logged to `/persist/var/log/loom/<tool>.log`, or to `~/.local/state/omanix/log/` on the configuring computer.
- Shell code uses `writeShellApplication` + shellcheck. Python code has pytest in checks, and flash/installer guards are tested against a fake sysfs tree.

---

## h) Agent surfaces and UX

### h.1 Rules

1. **The agent is the front door for change, not for control** (§f.3).
2. **GUI changes are runtime state**; every kept tool offers **Make it stick**, which is a request to the agent.
3. **Every switch and every root command for the resident is a card the human approves**, with the reviewer's plain-English account. No exceptions except the watchdog's automatic rollback.
4. **Routine cards are one line.** Anything the reviewer questions, anything flagged, and anything with no request gets the full card.
5. **The diffs are always one click away.** nvd and git diff are computed by root (the switch collector), not taken from either agent; scripts are shown exactly as they will run.
6. **The resident is another user.** It can't see the human's screen, files, clipboard or Wayland socket; the human hands it context explicitly, with a preview.
7. **Chat renders plain text plus a safe Markdown subset.** The card is drawn by the `omanix.approval` plugin, never inside the transcript.
8. **The system is whole without the agent**: edit the host repo, `loom propose`, same card.
9. **One keystroke to the agent from anywhere:** `SUPER + A` opens the chat panel; typing in the `SUPER + SPACE` menu falls through to "Ask ada: …".

### h.2 Components

```
human session (uid 1000)                     root                                     residents
────────────────────────                     ────                                     ─────────
Quickshell omarchy-shell (fork)                                                      ada (1100)  UI agent
  omanix.chat     ── /run/loom/chat/ada.sock ──────────────────────────────────────▶ loom-agent-bridge@ada
  omanix.approval ◀── omanix-approval-prompt ◀── nuketown broker (HM unit) ◀── REQUEST:<id> ── nuketown-approve (nuketown-approval) ◀── sudo (ada)
  omanix.status   (bar dot, pending cards)      reads /run/nuketown-approval/<id>/   │ collector (switch kind)    reviewer (1101)
  omanix.welcome  (first boot, tour)                                                  ▼ loom-switch                systemd-run per request:
                                                                                                               reads the dir, prints JSON
```

| Component | Repo | Runs as | Job |
|---|---|---|---|
| `loom-agent-bridge@<agent>` | loom | the agent (system unit) | Serves the chat socket, hosts the harness in streaming mode in `~/projects/host`, translates harness events to `loom.chat/v1`, writes attachments to `/agents/<agent>/inbox/`. |
| `nuketown-approve`, `loom-switch` | nuketown, loom | `nuketown-approval` per request; `loom-switch` as root via its sudo | §g.3–§g.6. No daemon. |
| nuketown broker | nuketown (K3, K6) | human HM user unit | Hands each request directory to the prompter (`omanix-approval-prompt`). |
| `omanix.chat` | omanix (`fork/add`) | human | Panel, composer, transcript, activity rail, chips, attachments, options browser, bar widget. |
| `omanix.approval` | omanix | human | The prompter and card surface: change cards (routine banner, full card, diff view), root-command cards, pending badge, Undo toast. |
| `omanix.status` | omanix | human | Bar indicators: agent state, approval pending, agent offline. |
| `omanix.welcome` | omanix | human | First-boot checklist and tour. |
| `loom card show` | loom | caller | The same card as text in a terminal. |

### h.3 Chat surface

#### h.3.1 Shape

- **Panel:** right-edge drawer, layer-shell `top`, 34% width (min 420 px), full height minus bar. Toggled by `SUPER + A`, the bar widget, or any intent. It doesn't steal focus from fullscreen apps unless the human opened it.
- **Bar widget** (replaces `omarchy.agents` at the same `shell.json` slot): agent glyph + state dot. Idle (hollow), working (pulsing), needs you (accent, count of pending cards/questions), offline or signed out (struck).
- **Header:** agent name, state, "New chat", conversation list, overflow menu (Open in terminal, Sign in again, Restart agent, Stop, Do it myself).
- **Transcript:** human bubbles right, agent text left, activity rows inline and collapsed, card references ("Approval card opened" focuses the card; the card is never drawn here).
- **Composer:** multiline; Enter sends, Shift+Enter newline. Attach, context chips, Stop (while working).
- **Menu fallthrough:** a `SUPER + SPACE` query with no exact match shows a last row "Ask ada: <query>", which opens the panel with the text in the composer, unsent.

#### h.3.2 Transport

1. The panel connects to `/run/loom/chat/<agent>.sock` (0660 `<agent>:loom-chat`; the human is the only member of `loom-chat`) using `Quickshell.Io.Socket` with a `SplitParser` (U10). Framing is newline-delimited JSON (`loom.chat/v1`).
2. `loom-agent-bridge@<agent>.service` (system unit, `User=<agent>`, `Restart=always`, `ConditionPathExists=/persist/var/lib/loom/firstboot/repo-publish.done`) creates and serves the socket.
3. One surface at a time; a second connection takes over and the first gets `{t:"detached"}`.
4. The bridge carries conversation only; cards come from the approval path (§g.3).

#### h.3.3 Streaming: what the agent is doing

The claude-code adapter runs the harness long-lived in streaming JSON mode (`--input-format stream-json --output-format stream-json`, U11) in `~/projects/host`, with nuketown's generated prompt plus the loom/omanix fragments. Its permission mode inside the harness is its own business: its powers are bounded by its uid, `gate/*`-only push and approval sudo with a reviewed card. The `replay` adapter plays scripted transcripts (same events, real commits) for VM tests and the demo.

| `t` | Fields | UI |
|---|---|---|
| `text` | `delta` | Appended to the current agent bubble. Markdown subset: paragraphs, lists, inline code, code blocks, bold/italic, links shown as `text (domain)`. No images, no HTML. |
| `activity` | `kind` read\|edit\|run\|search\|web\|build\|commit\|propose, `label`, `detail` | Activity row: "Reading modules/apps.nix", "Editing home.nix", "Running `omanix check`", "Reading web page — github.com" (`web` rows carry an "external content" marker). Informational only; facts never come from it. |
| `progress` | `phase` eval\|build\|review, `done`, `total` | One row updated in place: "Checking · building 12/40 · review". |
| `card` | `id`, `presentation` | Reference row; focuses the card. |
| `question` | `text`, `choices[]` | Outlined buttons labelled "suggested by ada"; clicking sends the choice text. |
| `status` | idle\|working\|blocked\|offline\|signed-out | Bar dot and header. |
| `auth` | `url`, `token` | Sign-in handoff (§h.3.6). https only. |
| `rejected` | `tip`, `reason` | "You rejected <change>: <reason>". |
| `applied` / `rolledback` | `tip`, `check` | "Applied: …" with Undo; "Rolled back: … · Why?". |
| `error` | `text` | Inline error row (eval/build failures come back here verbatim). |

Input messages: `{t:"user", text, attachments[]}` (the bridge assigns the id), `{t:"stop"}`, `{t:"new-session"}`, `{t:"resume", session}`, `{t:"attach-begin"|"attach-chunk"|"attach-end", …}`.

#### h.3.4 Conversation storage

Sessions live in the resident's harness state (`/agents/<agent>/.claude`, persisted by nuketown). **Open in terminal** runs `portal-<agent>` and resumes the same session in the harness TUI when the bridge is idle (U11). Reinstall does not restore conversations: a new agent home, and history is the agent's.

#### h.3.5 Attachments and context

1. **Attach** offers: screenshot region, window, file, clipboard text, last error (most recent failed unit + `omanix why-failed --json` summary, computed in the human session), runtime snapshot (§f.4.6).
2. A preview chip shows a thumbnail or the first 400 characters and the byte count. Nothing is sent yet.
3. On send, the panel re-encodes images (metadata stripped), refuses anything over `loom.agent.chat.attachments.maxBytes` and any type other than PNG, JPEG, plain text and JSON, then streams the bytes to the bridge, which writes `/agents/<agent>/inbox/<id>/<name>`.

There is no agent tool for screenshots or the clipboard.

#### h.3.6 Sign-in handoff (normal provider flow, on this machine)

1. The panel (or welcome step, or a `signed-out` status) shows **Sign in ada**.
2. Click opens a floating terminal (`org.omanix.agent-login` app-id, float/center rule) running `machinectl shell <agent>@ <loginCommand>` (allowed by nuketown's portal polkit rule, §a.3 C7).
3. `BROWSER` inside that session is `loom-open-url`, which sends `{t:"auth", url}` through the bridge. The panel drops non-`https` URLs and shows the URL's domain and **Open in browser**, which starts the human's default browser binary with the URL as an argument and never `xdg-open`, so no custom-scheme handler can run.
4. The provider's flow completes as it normally does: the human pastes the code back into that terminal, or the browser hits the harness's localhost callback (U12).
5. Tokens land only in the agent's own state (`/agents/<agent>/.claude/`, persisted by nuketown). They never pass through the human's home, the installer, silo or git.
6. The same steps sign in the **reviewer** (`machinectl shell reviewer@ …`), offered right after; it has no bridge, so its sign-in URL is printed in that terminal. The two residents never share a token file.

### h.4 Card UI (`omanix.approval`)

`omanix-approval-prompt <request dir>` (K6) calls `qs ipc call omanix.approval show <dir>` and waits for the decision the plugin writes under `$XDG_RUNTIME_DIR/omanix-approval/<id>`; if the plugin isn't running it falls back to nuketown's own approval card (`nuketown.approvalDaemon.cardPrompter`, GTK 4, on the session's Wayland socket). A card lives as long as its request (the bar badge counts them); after a shell restart the plugin re-reads the open request directories.

**Change card, routine form** (`kind = loom-switch`). A one-line banner (layer-shell `overlay`, top-right, theme notification tokens, 560 px max):

```
 ⛉  "install steam and set it up for gaming"  ·  +3 pkgs  ·  Reviewer: matches   [Details]  [Approve]  [✕]
```

- The quoted text is the request (§g.2), truncated. For updates: `Update ready: omanix v0.1.1 (signed) · 212 pkgs`.
- `[Approve]` is the approval. `[✕]` = Deny (reason optional).
- The banner doesn't steal focus.

**Change card, full form.** A centered card (layer-shell `overlay`, keyboard focus only after the human clicks into it, U13), 720 px:

```
┌─ Approve a change to this computer ─────────────────────────────────── 1 of 2 pending ─┐
│ YOUR REQUEST (as ada relayed it)                                                       │
│   make my laptop last longer on battery                                                │
├─ WHAT CHANGES ─────────────────────────────────────────────────────────────────────────┤
│ Packages   +1 (tlp 1.7.0) · 0 removed · 0 upgraded                                     │
│ Files      configuration.nix, modules/power.nix                                        │
│ Build      ok                                                                          │
├─ AI REVIEW · can be wrong ─────────────────────────────────────────────────────────────┤
│ [MEDIUM] LOOK CLOSER · Saves battery, but also turns Bluetooth off at every boot.      │
│   • modules/power.nix line 9 sets hardware.bluetooth.powerOnBoot = false; the request  │
│   doesn't mention Bluetooth                                                            │
│                                                                                    (i) │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ [Show git diff]  [nvd diff]             [Deny]   [Approve]                             │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

(The text form of `tests/golden/cards/full.txt`.) Section order: (1) **Request**, or a line "No request given" / "Scheduled update" / "Your own commit"; (2) **What changes**: packages from nvd, files, the `flags` line (§g.3) in the warning color, build result; (3) **AI review**, or "No AI review (<reason>). Check the diff."; (4) the ⓘ; (5) buttons.
- The AI review sits on a tinted background under "AI REVIEW · can be wrong": a risk badge (the theme's red/yellow/green for high/medium/low, nearest tokens otherwise, text chosen for at least 4.5:1, `checks.card-badge-contrast`), the recommendation as a word and the reviewer's **headline** (at most 12 words; a review without one leads with its summary), then the concerns as bullets in italic. The rest of the card is monospace and comes from the collector (root).
- **ⓘ** (`Details (Ctrl+I)`) expands in place: the review's summary and "Can't see". While the review is pending the line is a spinner, "Reviewer is reading this request…", and the card updates in place when review.json lands (an open reason or details stay as they are).
- If the reviewer recommends deny, Approve is labelled "Approve anyway".

**Show git diff** expands `DiffView.qml`: file list left, unified diff right (syntax-colored for nix/lua/json). "Open in terminal" runs `git -C /persist/var/lib/loom/host diff --stat -p <deployed> refs/proposals/<id>` read-only. **Agent's notes** shows commit bodies, labelled agent-written.

**Root-command card** (every other request). Centered, 720 px, same focus rule:

```
┌─ ada wants to run a command as root ───────────────────────────────────────────────────┐
│   bash fix-wifi.sh                                                                     │
│ ADA'S STATED REASON                                                                    │
│   “wifi keeps dropping; reset the driver and NetworkManager”                           │
├─ AI REVIEW · can be wrong ─────────────────────────────────────────────────────────────┤
│ [MEDIUM] LOOK CLOSER · Restarts Wi-Fi, but line 9 also deletes every saved network.    │
│   • Line 9 deletes every saved Wi-Fi network and its password, which the reason        │
│   doesn't mention.                                                                     │
│                                                                                    (i) │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                         [Deny]   [Approve]                             │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

- The command (as displayed) is under the title. **ⓘ** adds to the review's summary and "Can't see" the argv as a list (one argument per line, control characters shown escaped) and every snapshot with line numbers and sha256, marking the one that runs (`tests/golden/cards/root-details.txt`).
- With no review: header "No AI review (<reason>). Read the command." and the details open by default.
- A `high` risk or a `deny` recommendation labels the button "Approve anyway".

**Deny**: opens an optional reason inside the card. Enter (or Deny again) sends it, empty or not; it reaches the resident as Josh's reply on the denied command's stderr. For a change card it is also passed to the reviewer of the next proposal (O7).

**Keys** (once the card has the keyboard, after a click into it, U13; the same on nuketown's card):

| Key | Action |
|---|---|
| Ctrl+Enter | Approve (never a bare Enter; Approve takes no keyboard focus) |
| Esc on the card | Opens the reason with the focus in it |
| Enter in the reason | Deny with the reason (empty allowed) |
| Esc in the reason | Deny with "aborted by the human (dismissed without a reason)", so Esc Esc is a quick deny |
| Ctrl+I | Toggles the details (ⓘ) |
| Ctrl+C | Copies selected text |

Tooltips name them: "Approve (Ctrl+Enter)", "Deny (Esc)", "Details (Ctrl+I)". No single-letter keys. A typing guard drops every key in the card's first second and ignores Approve clicks in its first half second. Closing nuketown's card denies with no reason; no answer within the prompt timeout denies with "no answer within Ns".

### h.5 The menu as an intent launcher

#### h.5.1 `fork/intents.toml`

Every non-submenu entry of the upstream menu has exactly one row, keyed by the upstream id; provider-backed submenus get one row covering all their runtime rows.

```toml
[defaults]
send = false                     # pre-fill only; the human presses Enter

[entry."setup.default.browser.firefox"]
kind    = "intent"               # gui | intent | drop
text    = "Make {label} my default browser."
skill   = "defaults"
manual  = "configuration.nix: omanix.defaults.browser = \"firefox\";"
touches = ["omanix.defaults.browser"]    # informational; shown as "expected area" in Details

[entry."install.gaming.steam"]
kind    = "intent"
text    = "Install Steam and set it up for gaming."
skill   = "apps"
manual  = "configuration.nix: programs.steam.enable = true;"
touches = ["programs.steam", "hardware.graphics.enable32Bit"]

[entry."setup.language"]         # provider-backed: one row for all language rows (picker-then-intent)
kind    = "intent"
text    = "Switch my language to {label}."
skill   = "locale"
manual  = "configuration.nix: omanix.language = \"{value}\";"

[entry."appearance.theme"]
kind = "gui"

[entry."setup.security.passwordless-sudo"]
kind = "drop"
why  = "omanix has no passwordless sudo; the resident uses approval sudo (D8)"
```

Template fields are only `{label}` (upstream row label after i18n), `{value}` (provider row value) and `{selection}` (picker result), all from the human's own session.

**New omanix entries** (`fork/menu-extra.jsonc`, all `gui`): `ask` "Ask ada…" (opens the panel empty), `whatcanichange` "What can I change?" (options browser, §h.6), `approvals` "Approvals" (card list), `undo` "Undo last change", `agent` "Agent" (status, sign-in, restart), `appearance.make-it-stick` "Make my look permanent", `learn.nixos` (replaces `learn.arch`). `learn.community` (omarchy Discord) is DROP.

**Disposition of omarchy's roots:** `apps`, `learn.*`, `system.*` kept; `trigger.*` (toggles, capture, emoji, clipboard, share, reminders, hardware) kept as runtime; `appearance.{theme,background,font}` kept with live preview + make it stick; `appearance.{top-bar,windows,dock,workspace-layout,animations}.*` kept as runtime toggles + make it stick; `setup.network.*` and Bluetooth kept (DNS presets → intents); `setup.monitors` kept (panel); `install.*`, `remove.*`, `setup.default.*`, `setup.{keybindings,input,typing.input,language,config.*,plugin.add/clone/remove,direct-boot}`, `setup.security.*`, `update.{channel,kernel,firmware,hardware,config}.*`, `appearance.{unlock,branding,top-bar.indicators.clock}.*` → intents; `setup.default.agent.*` and `setup.reset` dropped; `update.omarchy` → "Check for updates" (runs the update timer now; the result is an Update card); `update.password.{user,drive}` → **human-only tools** (§h.11); `update.timezone` → picker-then-intent (the `locale` skill sets `loom.locale.timeZone`); `update.time` dropped (NTP).

#### h.5.2 Build (`lib/menu.nix`)

1. Parse upstream JSONC with python `-I` at build time (upstream's own rules: whole-line `//` comments, trailing commas).
2. Per entry, look up `intents.toml`: `gui` → emitted unchanged; `intent` → `action` removed, `intent = "<rendered text>"` and `skill` added, description gains "Asks ada", Install rows keep their `disabled` guards (P6 manifests mark what is installed); `drop` → omitted (a submenu with only dropped children disappears by upstream's own rule).
3. Add the omanix entries and `omanix.menu.items.*` (host menu items may also be `intent`s).
4. `checks.menu-intents` fails if an upstream entry has no row, a `gui` row's action names a script that is not shipped (parsed with `bashlex`), an `intent` row has empty text or an unknown skill, or a template uses another field.
5. `~/.config/omarchy/extensions/omarchy-menu.jsonc` is HM-owned and read-only (§f.4.2). Host menu items, `intent` entries included, are declared with `omanix.menu.items`.

#### h.5.3 Runtime flow

1. The human selects a row. `Menu.qml` sees `kind === "intent"` (P5) and calls `omanix.chat.prefill({source: "menu", id, text, skill})` through the shell's IPC registry; nothing is spawned through bash and the menu closes.
2. The panel opens with `text` in the composer and a source chip ("from menu: Defaults › Browser › Firefox"), cursor at the end.
3. Enter sends; Escape sends nothing.
4. The resident runs the skill, edits, checks, proposes; the card quotes the request.
5. **Picker-then-intent** rows (Plymouth switcher, language, kernel, timezone): the upstream picker runs unchanged and its result fills `{selection}`.
6. Keybindings that ran a dropped script (e.g. `omarchy-menu summon install`) still open the menu at that route.
7. Agent not available → the panel opens on the row's **Do it yourself** view (§h.11).

#### h.5.4 Keybindings (patch P9)

| Key | Upstream | omanix |
|---|---|---|
| `SUPER + A` | upstream "Select all" in `clipboard.lua` (U25 was false) | `omarchy-shell omanix.chat toggle` (`omanix.chat.keybind`); Select all moves to `SUPER + SHIFT + CTRL + A`, freed by dropping `omarchy-agent --pick` (Josh, 2026-10-28) |
| `SUPER + SHIFT + CTRL + A` | `omarchy-agent --pick` (the human's own harness) | `omarchy-shell omanix.chat toggle` |
| `SUPER + ALT + A` | — | `omarchy-shell omanix.approval open` |
| `SUPER + grave` (qconsole) | `special:qconsole` with `omarchy-agent` | unchanged: the human's own terminal harness, if they set one |

### h.6 Discoverability

**Suggestion chips** (≤ 4 above an empty composer), generated in the human session from `data/chips/rules.json` and local state, never by the agent:

| Trigger (local state) | Chip |
|---|---|
| a runtime overlay or toggle differs from the declared value | "Make <area> stick" |
| a failed system/user unit since last view | "Why did <unit> fail?" |
| a pending Update card | "What's in this update?" |
| a watchdog rollback in the last hour | "What went wrong with my last change?" |
| a new USB/Bluetooth device class seen (udev) | "Set up <device>" |
| first 7 days | "What can I change?", "Show me around", "Install an app" |

**What can I change?** Two answers side by side: (1) the resident answers from the catalogs, grouped by everyday areas (look, apps, input, displays, power, network, security, updates); (2) the **Options browser** (`OptionsBrowser.qml`, works offline and signed out): a searchable list from `catalog/options/*.json` with description, current value (`catalog/config.json`) and origin. Each row has **Change this…** (prefilled intent "Change <option> from <value> to …") and **Where is it?** (runs `omanix where` against the human's working copy: file and line).

**Agent-driven preview** (from loom's `prompt.nix` live-tuning experiment): the resident may preview look-and-feel before committing with `omanix try <path> <value>`. Only a **typed allowlist** can be previewed: `omanix.hyprland.settings` keys with scalar types, `omanix.theme.default`, `omanix.theme.background` (an existing file in the theme registry) and `omanix.fonts.monospace` (an installed family), generated from the option types into `catalog/preview.json`. The bridge relays `{t:"preview-request", path, value}`. A helper in the human session validates the value against the option type and **renders the Lua call itself from a fixed template** (numbers as numbers, enums from the type, strings only for theme and font names checked against the registry), so no agent text is ever evaluated. The panel shows the rendered key and value, never agent-supplied labels: "ada wants to preview: general.gaps_out 10 → 4 · Allow / Not now". Allow applies it (`hyprctl eval` of the rendered call, theme link); the resident has no Wayland access. Previews revert on `try --reset` or panel close and never touch git. VM test `try-preview`: a value containing `") io.popen(` is refused.

### h.7 First boot and onboarding

§e.9 steps 1–3 (unlock-finalize, enrollment catch-up / repo-publish, secrets-prompt) run first. Then:

1. **Desktop first.** Login (autologin rules per H12) lands in the full omanix desktop: theme, bar, dock, menu, apps. omarchy's first-run invitations are not shipped.
2. **Welcome** (`omanix.welcome`, dismissible, reopen from the menu). A live checklist:
   - Network — ✓ on full NM connectivity; else **Connect** opens the network panel; captive portal opens the browser.
   - Publish this computer's configuration — only while `repo-publish` is pending (§e.9).
   - Write down your system encryption key — a confirmation (it was shown once at install).
   - Sign in ada — §h.3.6; enabled once network and publish are ✓.
   - Sign in the reviewer — **Skip** allowed ("cards will show the diffs without an AI summary").
   - Take the tour — optional.
3. **Tour** (agent-led when signed in, a static 5-slide version otherwise), each stop highlighted by the shell: the `SUPER + SPACE` menu ("things you do here; things you change, you ask for"); the `SUPER + A` panel; a sample card in a frame labelled **EXAMPLE — nothing will change**, without an Approve button (how to read the request, the changes and the AI review); the Undo toast; "What can I change?".
4. The resident's first turn (skill `onboarding`): `omanix context --json`, one sentence on what this machine is, three chips. It never asks for secrets.

**Install answer "Use an AI agent?"** (§e.5 4a): **yes** (residents enabled, welcome offers sign-in), **later** (residents exist but stay signed out; the panel shows "Sign in ada" above the no-agent view), **no** (`loom.agent.enable = false`, reviewer and bridge off; the panel becomes **Change settings**: options browser, how-tos, "Open host repo", "Apply"; the bar widget shows a wrench).

| Works before sign-in | Needs the resident |
|---|---|
| everything installed and declared; all kept GUI tools; lock, power, capture, network, Bluetooth | changing what's installed or declared by asking |
| Update cards and approving them; Undo / rollback; watchdog | reviewer summaries; diagnoses (`why-failed` output is still shown raw) |
| options browser, how-tos, the human-only path and tools | Make it stick (falls back to its how-to) |

### h.8 CLI contract and verbs

Every `omanix` and `loom` command takes `--json`, never reads a TTY when `--json` is given, and returns **0** ok, **1** failed, **2** usage/refused guard, **3** needs human approval (card waiting), **4** rolled back, **5** offline/busy/retry later. `checks.cli-contract` runs every command with `--help --json` and `--json` in a VM and validates outputs against their schemas. Every verb only edits files in the working copy and checks the result by evaluating it; none switches the system, and none is required (the same change can be made by hand). **No verb refuses for policy reasons** (V4).

| Command | What it does |
|---|---|
| `omanix context` | **First command of every session.** Host id, generation, deployed commit, working copy ahead/dirty, plugins, last switch and card result, runtime snapshot summary (`runtime.json`), enrollment, catalog index, skills. |
| `omanix options <q> [--origin <o>]` | Full-text search over the option catalogs: path, type, default, origin, description. |
| `omanix where <option\|file>` | **Live eval** in the working copy: `definitionsWithLocations` → file:line, priority and value per definition, host files marked editable and input files not; for an HM target, the owning `omanix.*` option, the overlay path and any shadowing key from `runtime.json`. |
| `omanix explain <option>` | `options` + `where` + current value. |
| `omanix set <path> <json>` / `unset` | Resolve with `where`; if **exactly one** host definition is a literal, rewrite it in place (rnix-based editor, U19); if none, append under the marker line of `configuration.nix` (`home.nix` for `home.*` paths); if several or an expression, exit 2 with file:line for each ("edit by hand"). Then `nixfmt`, evaluate `config.<path>`; if it doesn't equal the value, revert and exit 1 showing the winning definition. Reports `shadowedBy` from `runtime.json`. |
| `omanix plugin inspect/add/remove` | §b.4. |
| `omanix app add/remove <name>` | omarchy app → `omanix.apps.<n>.enable`; webapp/TUI → `omanix.apps.{webapps,tuis}.<N>`; otherwise a nixpkgs attr checked with `nix eval nixpkgs#<attr>.meta.mainProgram` → `home.packages` in `home.nix`. |
| `omanix secret set <file> <name>` | The value comes from the human through the chat panel's secure field (never shown to the resident) or stdin; encrypt-only, never echoed or decrypted. |
| `omanix persist add <path>` / `persist audit` | §f.1. |
| `omanix hw probe [--write]` | §f.2.6. |
| `omanix check` / `plan` / `propose` | eval + build + nvd; `propose --request <text>` pushes `gate/<topic>` and calls `loom propose`. |
| `omanix update [<input>]` | bumps omanix (or a named input) to the newest signed tag/rev and proposes ("Update ready"). |
| `omanix status` / `doctor` / `why-failed [--last]` | failed units, configerrors, persist gaps, sops decryptability, shadowing; `why-failed` gives the failing drv log plus origin option, or the watchdog check plus a journal excerpt. |
| `omanix try <path> <value>` / `try --reset` | live preview, no commit (§h.6). |
| `omanix reset` / `edit` | human-session overlay tools (§f.4.8). |
| `omanix repo open [<file>]` | human: opens the working copy `~/omanix-host` (created on demand from the local mirror) in the editor. |
| `loom propose [--request]` / `card show` / `approve <n>` / `reject <n>` / `undo` / `rollback --to <n>` | §g.3, §g.4. |
| `loom user passwd` | Human-only CLI form of the Change password dialog (§h.11); refuses `--json` and the agent uid. |
| `loom hw regen` | Re-runs `loom-detect` and `nixos-generate-config --no-filesystems` into the working copy's `hardware.{nix,json}`; no switch. |
| `loom status` / `keys {list,sync,add-human,remove-human,rotate}` / `unlock {status,add,remove,reseal}` | Platform. `keys rotate encryption-key` and `add-human --generate` show or take a secret, so they refuse `--json` and refuse to run as the agent uid (§g.8, §g.10). |

**Deleted:** `omanix keep`, `omanix apply` (→ `propose`), `omanix keybinds/menu/themes/apps/commands` listing verbs (→ `options` + catalogs), `loom policy explain/classify`, `loom switch` (→ `loom propose`); from rev 3: `loom facts`, `loom requests`, `loom audit`, `loom stats`, `card export`, `approve --card` (Appendix H).

### h.9 Catalogs and introspection

`/run/current-system/sw/share/omanix/catalog/`, built from the same eval as the toplevel:

| File | Content | Scope |
|---|---|---|
| `options/nixos.json` | `nixosOptionsDoc` of nixpkgs + loom + nuketown + omanix, with `origin` | shared per release |
| `options/home.json` | `nixosOptionsDoc` of the HM user submodule | shared per release |
| `options/host.json` | this host's eval minus the shared declarations: plugin and host-module options with `origin = "input:<name>" \| "host:<file>"` | per host |
| `config.json` | effective `config.{loom,omanix}` | per host |
| `host.json` | plugins (input → imported module names → option roots), host module files, files that `mkForce` an omanix-owned HM target, lock revs | per host |
| `home.json` | every HM-owned target with store source, owning module, generating option(s), overlay path and include mechanism | per host |
| `keybinds.json` | upstream Lua + the HM `hyprland.lua` chain replayed under a recording `hl.*` stub: `{keys, description, dispatcher, source file:line}` | per host |
| `menu.json` | the shipped menu with kind (gui/intent), intent text, skill, manual hint | per host |
| `themes.json`, `apps.json`, `persist.json`, `secrets.json` (names), `services.json`, `unlock.json`, `commands.json` (`omarchy commands --json` merged with omanix/loom, each with `origin`) | registries and status | per host |
| `host.md` | generated from `host.json` + `options/host.json`: plugin and host option roots with descriptions, overridden files, persistence additions | per host |
| `index.json` | every file with its sha256 | per host |

Deleted: `schema/settings.schema.json`, settable level/class columns, `definitions.json` (definitions are looked up live by `omanix where`). `checks.catalog-size`: per-host files < 2 MB; shared option files < 15 MB (U20).

### h.10 CLAUDE.md layers and skills

**omanix, loom and nuketown repos.** `CLAUDE.md` is `@AGENTS.md`, a router with: the layers; the rules (path == option, mkDefault, `nix flake check` is the single gate, never edit the pinned upstream (use `fork/`), never improvise disk ops); the task index into skills; "a KEEP-AS-GUI writer may only write runtime state; `checks.hm-owned-readonly` will tell you"; "generated dotfiles come from options; never hand-write a file under `~/.config` in a module".

**Host repo `CLAUDE.md`:** host notes only (§d.4).

**Resident prompt** (nuketown + `loom.agent.promptFragments` + omanix): working copy `~/projects/host` (auto-cloned from the local mirror, push to silo `gate/*`); the exit-code table; "batch one request into one proposal and pass the human's words with `--request`"; "never handle secrets; name the human-only tool"; a **generated** top-level option index (root descriptions of `loom.*`, `omanix.*` and plugin roots) and "read `catalog/host.md` before changing a plugin". It says: for root, use `sudo --why "<the human's words or your reason>"` on one command or one script, so the human sees a reviewed card; prefer a proposal for anything that should survive a reboot.

**Resident skills** (`omanix-skills`, linked into `/agents/<n>/.claude/skills/`; the human's harnesses get none by default):

| Skill | Replaces upstream / covers |
|---|---|
| `omanix-host` | the edit loop, where things live (generated from `catalog/home.json` + option roots), `set` vs hand edit, `propose` |
| `onboarding` | first turn, tour |
| `apps` | `install-*`, `remove-*`, `pkg-*`, `webapp-*`, `tui-*`, dev envs, gaming, `windows-vm`, retro games, mise tools |
| `defaults` | `default-{browser,terminal,editor,dictation}`, `dictation-use`, voxtype |
| `locale` | language, timezone, input methods, CJK fonts, persistent layouts |
| `look` | make it stick (§f.4.6), clock format, branding, corners and similar defaults |
| `themes` | theme install/remove/update as flake inputs + `omanix.theme.extra`; boot screen (`omanix.theme.boot`) |
| `shell-plugins` | `plugin-add/clone/remove/update` → `omanix.shell.plugins.<n>` from a flake input |
| `add-plugin` | §b.4 (NixOS/HM plugins) |
| `security` | sshd, fido2, fingerprint, ssh-agent, docker group; explain the effect on the card |
| `boot` | kernel, hibernation, plymouth |
| `network` | DNS (`omanix.dns.*`) |
| `hardware` | `omanix hw probe` → quirks, audio tuning |
| `update` | updates, channel moves, theme/plugin updates, firmware report |
| `persist`, `secrets` | §f.1; `omanix secret set` via the secure field |
| `diagnose-build`, `diagnose-unit`, `diagnose-crash`, `recover` | read-only diagnosis (journal through `systemd-journal`); crash capture pre-fills `diagnose` |
| `rotate-keys`, `reinstall` | human-driven procedures; the resident explains, never runs |

Upstream's `omarchy`, `omarchy-app` and `diagnose-crash` texts are folded into `apps`, `look` and `diagnose-crash` with their Arch instructions removed. `checks.skills-no-arch` greps every shipped skill for `pacman|yay|omarchy-pkg|omarchy-refresh|sed -i ~/.config` and fails on a match.

### h.11 Without the agent, and human-only tools

**Modes.**

| Mode | Cause | What changes |
|---|---|---|
| No agent | install answer "no" | No residents, no bridge. Panel = **Change settings** (options browser, how-tos, Open host repo, Apply). |
| Later | install answer "later" | Residents exist, signed out; "Sign in ada" above the no-agent panel. |
| Signed out / offline | token expired, no network, provider down | Banner in the panel; intents open their how-to; cards still work (reviewer absent → "No AI review"). |
| Preference | the human wants to do it themselves | "Do it myself" on every intent and in the panel header. |

**Human-only path (same gate).**
1. `~/omanix-host` is a working clone of the host repo, created on demand from the local mirror (origin = silo; the human key may push `gate/*` and `master` per CODEOWNERS).
2. The **how-to** for an intent comes from its `manual` hint: file, option, snippet, docs link. "Open in editor" opens `$EDITOR` at the line `omanix where` reports, or the end of the file; "Copy snippet".
3. The human commits, then `loom propose` (or the panel's **Apply**). it builds and shows the same card through `pkexec loom-switch-request`; the reviewer is skipped because the requester is the human (§g.3). Without a session, `loom card show <dir>` prints it and `sudo loom-switch …` with the password approves.
4. Watchdog, rollback and Undo are identical.

**Human-only tools** (secrets and keys never pass through a resident):
- **Change password** (System › Security): a Quickshell dialog runs `mkpasswd -m yescrypt` in the human session, `sops`-encrypts to host, human and SEK recipients, and hands the ciphertext to `loom secret commit` (through `pkexec`, polkit `farm.loom.propose`), which commits it as the host and requests `loom-switch` with the card (full form: `secrets/**` changed).
- **Drive encryption key** (`loom keys rotate encryption-key`), **add human key** (`loom keys add-human`), **secret values** (`omanix secret set` from the human's terminal or the panel's secure field): the resident can only say which command to run.
- **Agent sign-in** (§h.3.6) is done by the human in the resident's login terminal; the resident never sees the provider password.

---

## i) Testing (`nix flake check` = the single gate in every repo)

### i.1 Pure checks

| Group | Checks |
|---|---|
| eval | `eval-*` fixtures: ref-default, ref-nvidia, ref-laptop, vm-test, agent-sudo-approval, no-agent (`loom.agent.enable = false`), reviewer-off, server, **lanzaboote** (D7); omanix on `nixos-unstable` only, loom on 26.05 **and** unstable (D1) with the pinned, unmodified nuketown |
| conventions | `layout` (declaring file == option path via `declarationPositions`), `priorities` (+ force-allowlist), `documented`, `assertion-messages` |
| host repo | `host-template` (template + sample answers render, evaluate and build with IFD off; exactly one `nixpkgs` lock node, U29); `keys-sync` (render(`loom.keys`) == committed files; refusal cases: no owner, two owners, deleted CODEOWNERS; the mint stub tree passes); `hostgen-escape` (answers with `"`, `\`, `${`, newlines, unicode are rendered as data or refused); `home-owned` (U31); `set-roundtrip` (U19); `catalog-size` (U20) |
| card | `card-render` (collector fixture → `card.json`, routine/full form truth table); `review-parse` (valid, oversize and invalid reviewer output → shown or "No AI review"); `nuketown-glue` (C2 no `/agents` mount in disko; C8: the resident's only sudoers rule starts `nuketown-approve` as `nuketown-approval`, `approvalAllow` = `loom.agent.sudoCommands`, null with `"any"`; the `loom-switch` kind and reviewer options are set) |
| nuketown (nuketown's `checks.nix`, built) | `signi-compat` (K10); `module-sudo` (one agent rule, run-as `nuketown-approval`, K1); `module-approval-sudoers` (no agent rule runs as root, no old wrappers, no `SETENV` on agent or service-user rules, human in the read group, audit dir persisted; K1, K2, K11, K12); `module-approval-reviewer`; `module-broker-groups` (agents not in `nuketown-broker`) |
| fork | `fork-classify` (U21), `menu-intents`, `hw-quirks`, `skills-no-arch`, `fork-license`, `themes-render`, `jsonc-equivalence`, `keybind-conflicts` (both locations named), `hl-symbols` and the `omarchy-src` post-check (`no-usr-paths`, call graph, `luac -p`, `qmllint`) |
| home | `home-files-golden`, `hm-owned-readonly`, `runtime-writers`, `hm-unmanaged-paths` (allows exactly the nuketown broker unit, C4); `eval-*` fixtures assert `home-manager.users.<u>` builds with `home.enableNixpkgsReleaseCheck` on |
| catalogs | `catalogs` (all build and validate; `index.json` complete; U40), `cli-contract` |
| baseline | `no-plaintext-secrets`; `sidecar-schema` (v2 answers closed set) + secret-pattern rejection (incl. `SEK1-`); `script-preamble-identical`; `repo-id-vector`; `sek-vectors` (python ↔ initrd sh ↔ `age-keygen -y`, plus the token-schema fixture) |
| size and lint | `closure-budget`, `closure-dupes`, `lint` (nixfmt, statix, deadnix, shellcheck, pytest: `omanix-overlay` kv formats, shell.json rebase, settle semantics; `omanix-runtime-snapshot` schema; `loom-hostgen`; `loom-switch` collector and card; the write-site scanner fixtures) |

Rev 3's `facts-cases`, `presentation-rule`, `review-validate`, `suspicious-text`, `schemas` for the dropped formats, `approval-verify`, `preflight-vmvariant` and `signi-compat` are Appendix H.9.

### i.2 VM tests

Shared fixtures in `loom/tests/lib`:
- OVMF, swtpm, and canokey (FIDO2) through `virtualisation.qemu.package = pkgs.qemu.override { canokeySupport = true; }` (nixpkgs builds QEMU without it). `canokey-qemu` is marked broken on 26.05, so canokey-dependent tests (`fde-fido2`, the FIDO2 case of `silo-enrollment` S4) run only on the unstable/26.11 leg; the 26.05 leg skips them and says so
- the silo stand-in (`silo-standalone`, host `silo.test`, test host key)
- test human and release keys
- an approval stub: the human's broker gets a test prompter (K6) that records the request directory and approves or denies from a driver-controlled file (nuketown's `tests/approval-node.nix` does exactly this), so the real broker, request directories, snapshots and reviewer run are exercised (nuketown's runtime `mode` file is not used)
- **a `networking.hosts` tripwire mapping `silo.loom.farm` to `0.0.0.0` in every node**

The installer test image differs from the release image only in three ways: `loom.installer.tty = "ttyS0"`, the baked `loom.silo.host = "silo.test"`, and a red banner/label. **There is no answers file and no unattended code path.** The driver reads the line-mode TUI on the serial console and answers it, and passes `loom.host=<id>` on the cmdline. The release image asserts `silo.host != silo.test`.

| Test | Repo | Asserts |
|---|---|---|
| `fde-passphrase` / `fde-fido2` / `fde-tpm2-pin` / `fde-recovery` | loom | Unlock per method. `fde-recovery`: typing the `SEK1-…` text at the Plymouth prompt unlocks via `loom-askpass` after the swtpm state is wiped; the raw `R`, the age identity and a wrong-check key all fail; the unknown `loom-sek` token doesn't disturb `systemd-cryptsetup`. The bootstrap slot is absent (luksDump). |
| `sek-rotate-crash` | loom | §g.10: a crash after each phase, then resume, reaches `done`. At every point some SEK opens the disk and decrypts the deployed secrets. After `done`, the old SEK fails both. |
| `fde-tpm2-requires-sb` | loom | The assertion fires without SB. With Limine SB (test keys), first-boot `unlock-finalize` enrolls TPM2 and the next boot auto-unlocks. Autologin is forced off. |
| `boot-lanzaboote` | loom | D7: the same SB + TPM2 flow with `loom.boot.loader = "lanzaboote"`; a lanzaboote generation rolls back like a Limine one. |
| `impermanence-survives-reboot` | loom | §f.1, including nuketown's `/agents` reset from `@agents-blank` with the installer-written `btrfsDevice` (C2) and the resident's persisted `projects`/`.claude`. |
| `hm-reclaim` | loom | A regular file is put in place of an HM link, and a backup-restored `~/.config/hypr` tree is planted. The next switch reclaims both into `reclaimDir`, sends the notification, and activation succeeds. A deliberately failing HM activation trips the `hm-activation` watchdog check and rolls back. |
| `sops-host-key` / `sops-tpm-age1tag` | loom | The file backend decrypts, and the resident's ssh key arrives from `secrets/agents.yaml` (C3). The second test settles the UNVERIFIED age1tag round trip and gates the `tpm` backend. |
| `repo-id-vector` | loom | §d.5 |
| `pipeline-e2e` | loom | On the S3 stand-in: a replay resident commits and runs `loom propose --request …` → build → `sudo loom-switch` → collector (bundle into the mirror, git diff, nvd) → reviewer (`harness = "replay"`, run as uid 1101) → routine card → test prompter `APPROVED` → switch promoted → `master` pushed with the host key. Variants: `DENIED: keep bluetooth` reaches the resident's stderr and nothing switches; a bundle that doesn't descend from the deployed commit is refused (exit 5) with no dialog; a reviewer stub that prints garbage gives "No AI review" and the full form; the human's `loom propose` goes through `pkexec loom-switch-request` with no review. |
| `approval-dialog` | loom | With the **real** nuketown broker and the built-in prompter (nuketown's GTK card) in a Hyprland session (uwsm): a request shows the review line above the details, ⓘ shows the snapshot, and clicking Approve (ydotool) runs it (U37). nuketown's own `vm-approval-card` drives the card on X11/i3 and Wayland. |
| `switch-watchdog` | loom | A change → promoted. A commit that breaks the health check → rolled back, boot default unchanged, `gate/rejected/<tip>`. **`loom-switch` killed mid-test → the dead-man timer rolls back.** A proposal that breaks `~/.config/hypr/*.lua` fails `configerrors` inside the watchdog window, after the step-3a reload, and rolls back. |
| `undo-rollback` | loom | GUI Undo builds from the store and runs on the human's click through polkit `farm.loom.undo` (U43); the resident's `loom undo` is a routine card with no review; a watchdog failure needs none; booting an older generation from the loader yields the "make it the default?" card; `sudo nixos-rebuild switch` outside loom is noted on the next card. |
| `update-card` | loom | The timer produces a host `update:` commit; a signed omanix tag → routine "Update ready"; an unsigned rev is not taken; a plugin input bump on request → full card; nothing switches without the approval. |
| `agent-sudo-approval` | loom | With the default list: `sudo journalctl -n 5` as ada raises the card and runs only on approval; `sudo id` is refused with no dialog (K8); with `loom.agent.sudo = "any"`, `sudo id` raises the card. `/run/wrappers/bin/sudo -n -u root id` as ada fails (K1). |
| `vm-sudo-approval-bypass` (built, passes) | nuketown | K1, K2, K3, K4, K8: `sudo -l -U ada` shows only the `nuketown-approval` rule and `sudo -n -u root` fails; ada can't connect to the broker socket; `BASH_ENV=` and `-E` on the service-user rule are refused and nothing runs; a denied command doesn't run; `sh -c $'true\nSUDO:ada:ls'` is one argv element in `request.json` and one prompt; `--decrypt` with a newline is refused before asking; a 0700 root script is refused ("cannot read") both as `argv[0]` and as `bash <file>`, with no prompt; `approvalAllow = [ "id" ]` allows `id` and refuses `true` before asking; the root-only mock file still works and ada can't write it. Against the pre-`7a2b84e` code it reproduced all three bypasses. |
| `vm-approval-flow` (built, passes) | nuketown | K4–K6, K9, K12, with the real broker, a stub prompter and a stub reviewer: stdout and exit code (7) pass through; `sudo -u bob` runs as bob; relative paths resolve from the agent's cwd; for `sudo bash ./s.sh` and `sudo ./s.sh`, editing `s.sh` after the request is sent runs the original and the reviewer saw the same bytes; reviewer ok / hung (timeout) / garbage / failing → `review.json` ok or unavailable and the prompt still happens; `sudoex --decrypt` with a real GPG key is one request, decrypts, and the command reads the key; the journal record has requester, decision and exit code, the audit copy exists, the run directory is gone, and sudo logged the service user's commands. |
| `approval-kinds` (W1b) | nuketown | K7: a fixture kind's collector runs before the review; its non-zero exit refuses with its message and no dialog; `NUKETOWN_APPROVAL_DIR` reaches the command. |
| `silo-enrollment` | seed + loom | On the S3 stand-in: (1) the first push by the human test key ⇒ `.owner_key` = human, HEAD = master; (2) the enroll key pushes the install commit (CODEOWNERS at the mint HEAD); (3) afterward the enroll key is rejected on `master` **and** on `gate/*`; (4) the host key pushes `master`, the agent key only `gate/*` (U15); (5) a push without `CODEOWNERS` in HEAD is never produced by loom; (6) sk keys work as owner, in CODEOWNERS and in `.authorized_keys` (S4); (7) a second line in `.owner_key` loses the owner bypass (documents F3 for S1); (8) the enroll key force-pushes `master` with an extra attacker key in both files, then `configure revoke-enroll` lists the unsigned commit, recommends re-mint, and with `--reuse-anyway` restores the exact human-only set. |
| `installer-offline-eval` | loom | Network-less install evaluates the host flake from the archived inputs. |
| `installer-e2e` (loom-only profile) | loom | The driver runs `loom-mint` (human test key pushes) → flash a fake USB → console-driven install with agent sudo = listed (the SEK paper check first rejects a retype with one wrong group, then accepts the full key) → reboot → unlock with the SEK → `git ls-remote` shows the install commit → enroll key rejected → `nuketown.agents.ada.sudo.approvalAllow` = the default list → the first card (secrets-prompt) is approved through the stub. |
| `installer-e2e-fresh` | loom | Fresh mode with no sidecar: the software owner key is generated with a passphrase (an empty passphrase is refused) → online first push creates the repo with `.owner_key` = that key → `/home/<user>/.ssh/id_ed25519` exists (0600, uid 1000) after reboot and is not an HM symlink. Offline variant: `repo-publish` at first boot; until it succeeds the agent units are inactive. **Squat variant:** before first boot the driver pushes to the computed id with another key; `repo-publish` detects the foreign owner, the agent stays stopped, and `loom fork` publishes under a new id. |
| `installer-e2e-sb` | loom | Setup mode OVMF: sbctl keys reach the chroot, Limine is signed, TPM is enrolled at first boot. |
| `installer-reinstall` / `installer-fork` | loom | The same stand-in repo is reused. The human test key authorizes the key swap. Secrets are re-encrypted with the age identity derived from the typed SEK, and the same SEK unlocks the new disk. Fork: new id, new human key makes the first push and is owner, secrets are carried over under a new SEK. |
| `flash-guards` | loom | Only the USB device is offered. Mounted devices are refused. A token is required, and a changed device invalidates it. Readback catches an injected bit flip. |
| `verity-corruption` | loom | A flipped byte gives the "damaged" message. |
| `desktop-boots` (+ greeter variant) | omanix | SDDM greeter on Hyprland and autologin → uwsm → Hyprland 0.56.2 + omarchy-shell on virtio-gpu. No QML errors (U24), configerrors empty, `OMARCHY_PATH=/run/current-system/omarchy` in the user env. `home-manager-<user>.service` finished before `display-manager.service`; every HM target is a store link; every overlay file exists; the clock's middle-click opens the timezone intent row. Variant `desktop-intents` (W18): a menu intent row pre-fills the chat composer and sends nothing until Enter (screenshot); the bar shows the approval and agent indicators. |
| `chat-socket`, `approval-focus` | omanix | The QML panel connects to the bridge socket, survives a bridge restart and reconnects (U10). The full card over a fullscreen terminal takes focus only on click and returns focus (U13). |
| `approval-card` | omanix | `omanix-approval-prompt` draws a root-command card and a change card from fixture request directories (screenshots), returns `DENIED: <reason>` and `APPROVED`, covers the keys (Ctrl+I, Ctrl+C, Esc, Ctrl+Enter) and a review landing while a reason is typed, and falls back to nuketown's card (Esc Esc dismisses) when the plugin isn't running. |
| `theme-switch` | omanix | `omarchy-theme-set` works for two themes and kitty, alacritty and foot pick up the colors; lock resets the theme at the next login. No HM target changed. |
| `writers-respect-hm` | omanix | As rev 3: every KEEP-AS-GUI `writes =` smoke (font set, text size, monitor scale, `omarchy-bar` position, glass on, gaps toggle, `chromium-add-feature`, keyboard layout picker U28, `omanix reset hypr/hyprland.lua`, `reinstall-configs`), then: every HM target is still a link into the current generation; each runtime target changed; configerrors empty; `omanix doctor --json` lists the expected overlays and `omanix set omanix.fonts.monospace …` returns `shadowedBy`; `fc-match monospace` and `omarchy-font-current` return the new font; a panel scale change survives `omarchy-hyprland-monitor-clamshell`; an alacritty overlay key overrides `omanix-base.toml` (U35). |
| `make-it-stick` | omanix | Change scale and theme in the GUI → snapshot attached and sent → replay resident maps it → card → approval → `settle` removes the matching kv keys and empties the absorbed whole-file overlay; an overlay changed after the snapshot is left and listed by `doctor`. |
| `shell-json-rebase` | omanix | With an overlay snapshot present, a change to `omanix.shell.settings` appears after re-login unless it conflicts; the conflict is listed by doctor. |
| `human-commit` | omanix | No-agent fixture: the human edits `~/omanix-host/configuration.nix`, commits, `loom propose` → `pkexec loom-switch-request` → card with no review → approved through the test prompter → promoted; over ssh, `sudo loom-switch` with the password. |
| `plugin-fixture` | omanix | A fixture plugin flake (`nixosModules.default` with a `StateDirectory` service, `homeModules.default` with a file) added by `omanix plugin add`: one nixpkgs node (U29), HM half evaluates (U30), the persist audit fails before `omanix persist add` and passes after (U32); the card flags `flake.lock: adds input`. |
| `try-preview` | omanix | `omanix try` previews an allow-listed key; a value containing `") io.popen(` and a path outside `catalog/preview.json` are refused by the human-session helper. |
| `vm-demo-2` … `vm-demo-7` | omanix | Demo scenes 2–7 (§j) headless with the replay harnesses, asserting card form, reviewer recommendation, rejection delivery, the root-command card and rollback. |
| `installer-e2e-omanix` | omanix | Same as `installer-e2e` with the omanix flavor image and `cacheMiss = []` offline. |

### i.3 UNVERIFIED (each with the test that settles it)

Rev 3's U1–U9, U14, U16–U18 concerned dropped machinery and are listed in Appendix H.9. Numbers are kept so references stay stable.

| # | Claim | Settling test |
|---|---|---|
| U10 | Quickshell 0.3.2 `Quickshell.Io.Socket` speaks newline-delimited JSON over a unix socket with `SplitParser` and reconnects | `chat-socket` |
| U11 | Claude Code runs long-lived with stream-json in/out, emits tool events usable for the activity rail, and a session resumes in the TUI | adapter fixture test against the pinned package; manual resume check |
| U12 | The harness `/login` run as a non-human uid via `machinectl shell` completes with the browser in the human session (code paste or loopback) | manual VM test with a real account; adjust `loom-open-url` |
| U13 | A layer-shell overlay card takes keyboard focus on click and releases it under Hyprland 0.56 + Quickshell 0.3.2, above fullscreen windows | `approval-focus` |
| U15 | silo F4 lets the agent key push `gate/*` and new `refs/dit/*`, and rejects `master` | `silo-enrollment` on the S3 stand-in |
| U19 | `nix-editor` (rnix) rewrites nested attrs and list literals without losing comments; else a tree-sitter-nix editor | `set-roundtrip` against both backends |
| U20 | `nixosOptionsDoc` over the full eval with plugins builds without IFD and within budget | `catalog-size` on `ref-default` + the fixture plugin |
| U21 | The counts and classifications match the fork point `5978d93` (surveyed on `bc220e7`) | build `omarchy-src` at `5978d93`; `fork-classify` and `menu-intents` green |
| U22 | Which `omarchy` icon-font codepoints are brand glyphs, and whether the bar uses them | glyph dump + grep `shell/**`; VM screenshot with `omanix-glyphs` |
| U23 | Theme backgrounds/videos are redistributable or have separate credits | porting report step 9 at `5978d93`; unattributed files are excluded |
| U24 | Patched QML (P1, P5, P7, P8, P10–P13, P17–P19) loads under quickshell `2b4501a` with Qt 6.12 | `qmllint` post-check + `desktop-boots` |
| U25 | ~~`SUPER + A` is unbound in the upstream Lua at `5978d93`~~ **Settled false (W3):** it is "Select all". Josh chose chat on `SUPER + A`; P9 moves Select all to `SUPER + SHIFT + CTRL + A`. | — |
| U26 | nixpkgs/nixos-hardware cover intel-lpmd, ipu7, asus/dell firmware, framework-16, surface, apple-t2, tuxedo-drivers | `nix eval` each attribute; missing ones are packaged or deferred |
| U27 | omarchy's NvPCR drop-ins are neutral to loom's PCR 7 policy | swtpm + SB VM, enroll with and without them, reboot 3×; adopt only if neutral |
| U28 | The keyboard picker override works when the HM `keyboard-layouts`/`input.lua` are read-only and the live `kb_layout` check passes | `writers-respect-hm` keyboard case |
| U29 | `nixpkgs.follows = "omanix/nixpkgs"` plus a plugin's `inputs.nixpkgs.follows = "nixpkgs"` yields one nixpkgs node | `host-template`, `plugin-fixture` |
| U30 | `home-manager.extraSpecialArgs.inputs` is visible to modules imported via `home-manager.users.<u>.imports` and usable in their `imports` | `plugin-fixture` HM half |
| U31 | `definitionsWithLocations` of `home-manager.users.<u>.home.file.<t>.{text,source}` lists host-file definitions with their priority | `home-owned` fixtures |
| U32 | `persistAudit` maps a `DynamicUser` `StateDirectory` to `/var/lib/private/<svc>` and the bind works under impermanence | `plugin-fixture` sentinel survives reboot |
| U33 | systemd-cryptsetup and libcryptsetup ignore the unknown `loom-sek` token type | `fde-recovery` |
| U34 | SDDM `wayland.compositorCommand` with the Hyprland greeter config works | `desktop-boots` greeter variant; fallback greetd |
| U35 | foot/kitty with a missing include; GTK4 absolute `@import` honored by libadwaita; `xdg-settings` from activation without a session bus | `desktop-boots`, `writers-respect-hm` |
| U36 | Offline flake eval during install from archived inputs | `installer-offline-eval` |
| U37 | nuketown's HM broker unit, restarted by omanix autostart after uwsm imports the session environment, shows the built-in card on the Hyprland session (it sets only `DISPLAY=:0`; omanix-approval-prompt's fallback picks up the session's Wayland socket itself) | `approval-dialog`; fallback: a loom drop-in in `/etc/systemd/user/nuketown-broker.service.d/` adding `WAYLAND_DISPLAY` and `After=graphical-session.target` ordering via `PartOf=` |
| U38 | (rev 4's `\n`-escape claim for the dialog text; moot with K3 request directories) | — |
| U39 | ~~settled~~ by W1: the shim passes `--why` (`vm-approval-flow`); `SETENV` is gone and agent commands resolve in the system PATH (`vm-sudo-approval-bypass`) | — |
| U40 | The `unstable = final` alias satisfies `nixosOptionsDoc` for nuketown's `portal.command` default | `catalogs` |
| U41 | `sudo -H -u reviewer` from the service user lets `claude -p` use the reviewer's persisted login non-interactively, within the 45 s default timeout | manual run with a real login; stub reviewer in CI |
| U42 | (Retired: the zenity prompter is gone; nuketown's card has no extra buttons.) | — |
| U43 | polkit sees the human's Quickshell (uwsm) session as active and local, for `farm.loom.propose` and `farm.loom.undo` | `undo-rollback`, `human-commit` |

---

## j) Demo script (community proof of concept, ~12 min, VM on a laptop)

Deterministic runs use `loom.agent.harness = "replay"` and `loom.reviewer.harness = "replay"` (scripted transcripts, the same bridge events, real commits and real cards); a live run uses claude-code for both. Assets live in `omanix/demo/`; `checks.vm-demo-<n>` runs scenes 2–7 headless.

1. **"An omarchy that started on nix"** (90 s). Flash the USB image, install (time-lapse: SEK paper check, unlock choice, "Use an AI agent? yes"), first boot: the full desktop is there before anything else. Welcome: network ✓, sign in ada through the provider's normal login in the browser, sign in the reviewer. *Shows: polished desktop immediately; no credential copying.*
2. **"Install and configure X"** (2 min). Menu › Install › Gaming › Steam. The composer is prefilled; Enter. Activity rail: reading `configuration.nix`, editing, `omanix check`, building, review. A one-line card quoting what Josh asked; Approve; Steam is in the launcher. Then "and hide the dock unless I hover" → a second one-line card. *Shows: agent as UI; routine cards are one line.*
3. **"Try it, then keep it"** (1.5 min). Theme picker, live preview, pick Kanagawa; toast → Make it stick → one-line card → chip gone. `git log -1 -p` in the host repo: one line in `configuration.nix`. *Shows: GUI for visual browsing, nix for persistence.*
4. **"Read the card"** (1.5 min). "Make my laptop last longer on battery." The resident enables TLP, lowers the refresh rate and also turns Bluetooth off at boot. Full card: the reviewer says "also disables Bluetooth, which you didn't ask for; look closer". Show git diff, then nvd diff. Reject with reason "keep Bluetooth". The resident gets the reason, recommits without it, one-line card, Approve. *Shows: the reviewer and the diffs make an agent's change readable before it lands.*
5. **"Explain this sudo"** (1.5 min). "My wifi keeps dropping, fix it for now." ada writes a 14-line scratchpad script and runs `sudo --why "…" bash fix-wifi.sh`. The root-command card: the reviewer walks through it step by step and flags line 9, which deletes every saved network, as not part of the reason; **Show command and script** shows the snapshot that will run, with line numbers. Deny with reason "don't touch my saved networks"; ada drops the line and asks again; Approve; Wi-Fi is back. Then "keep Wi-Fi power saving off" → a change card. *Shows: a multi-step root script is readable before it runs, and what runs is what was reviewed.*
6. **"Break it, get it back"** (1.5 min). Ask for a change that breaks the compositor (a monitor rule the VM's virtio output rejects, so `hyprctl` stops answering). Approve; the screen glitches; within the watchdog deadline the old generation is back; panel: "Rolled back: Hyprland didn't answer" → "Why?" chip → `why-failed`. Then a working change and the Undo toast: one click, seconds. *Shows: rollback by default; nothing reaches the boot default until healthy.*
7. **"Two residents, one machine"** (1 min). Terminal as the human: `id ada`, `id reviewer`, `ls -ld /agents/*`, `sudo -u ada cat /home/josh/.ssh/id_ed25519` fails, ada's push to `master` on silo is refused (`gate/*` only), `journalctl -u 'nuketown-review-*'` shows the reviewer's one-shot runs as uid 1101, `sudo -l -U ada` lists only the two approval wrappers, and `ls /run/nuketown-approval/` shows the last requests with their snapshots. *Shows: nuketown's user partitioning.*
8. **"Reinstall from the repo"** (1.5 min). Wipe the VM disk, boot the USB with `loom.host=<id>`, type the SEK, same desktop, same Steam, same theme. ada must sign in again; its old conversations are gone; the machine is identical. *Shows: the host repo is the machine.*
9. **"No agent, same rules"** (1 min, optional). Network off. Menu › Appearance › Top bar › Clock › 24-hour opens the how-to; Open in editor; save; Apply. The card appears; Approve. *Shows: it's just NixOS.*

---

## Decisions

### Resolved

| # | Decision | Where |
|---|---|---|
| V1 | omanix is a proof of concept: omarchy as if it had started on nix. It **forks** omarchy at v4.5.0-rc2; omarchy is product spec and asset source; its bash state-mutation layer is replaced by nix; drift is an optional porting report, not a gate. | H3, §a.1, §f.2, §i.1 |
| V2 | Agent-first: the agent is the primary UI for change. GUI tools stay only for continuous controls, instant toggles, visual browsing with preview, and reaching or repairing the agent. GUI changes are runtime state; make it stick is a request. The menu is an intent launcher. Fully usable without the agent. | §f.3, §f.4.6, §h.5, §h.11, H19 |
| V3 | The UI agent is a nuketown resident (`ada`), not a process in the human's session; a Quickshell chat surface talks to it over the bridge's socket. Showcasing user partitioning is a goal. | §a.3, §c.3, §g.1, §g.2, §h.3, §j scene 7 |
| V4 | No settings registry, schema, settings file, tiers, `extraProtected` gate or unattended updates. The resident may edit any module and flake input. Every switch is approved by the human on a card; watchdog + automatic rollback stay; updates are "Update ready" cards. | H5, H6, §c, §d, §g.3, §g.6 |
| V5 | The card summary comes from a reviewer resident reading the request, git diff, nvd and the build result; the diffs are always one click away; routine cards are one line. | H8, §g.4, §h.4 |
| V6 | `omanix.lib.mkHost` returns a `nixosSystem` with loom + nuketown + the omanix base, then loads the host's plain NixOS/HM modules. Plugins are modules from any flake. Typed verbs remain as agent tools; option catalogs remain. | H4, §b.3, §b.4, §d, §h.8, §h.9 |
| **V7** | **2026-10-28, v1 security scope cut.** nuketown stays unchanged except for critical compatibility (none needed; §a.3 handles it in loom). v1 forgoes the hardening against a compromised resident: request ledger, human-signed approval merges, nonces, the deterministic facts engine and highlight list, the preflight VM, reviewer isolation and egress, reinstall chain audit, and N1–N15. Approval is nuketown's existing dialog. The material is kept as Appendix H. Amended by V8 (nuketown changes K1–K10). | §0, §a.3, §g, §h.4, §i, Appendix H |
| **V8** | **2026-10-28, reviewed sudo, no switch daemon.** `loom-switchd` is dropped; the resident switches with `sudo loom-switch` through nuketown approval, from a short per-agent approval list (mino-style; D8 decides "any command"). Every approval gets an adversarial plain-English review by the reviewer resident, over snapshotted scripts so what runs is what was reviewed. nuketown changes in v1: the `sudoex-run`, `SETENV` and request-line fixes, the swappable prompter, request kinds, the approval list and the approval reviewer (K1–K10). |
| **V8.1** | **2026-10-28, approval service user.** Root does not run the request work: an unprivileged `nuketown-approval` system user does (request directory, snapshots read as the requester, review, broker), and reaches root only through `sudo`, so every privileged step is logged; root only runs the approved command. Agents' only sudo rule starts `nuketown-approve` as that user; only it can reach the broker. Built as W1 (K1–K6, K8–K12). | §a.3, §g.1, §g.3, §g.4, §i, W1, W1b | H5, H7–H9, H18, §a.3, §c.3, §g.3, §g.4, §h.4, §j scene 5 |
| D1 | nixos-unstable (then 26.11) for the omanix stack; loom stays CI-green on 26.05 for signi. | H1, §b.1, §i.1 |
| D2 | Fork point v4.5.0-rc2 (`5978d93`); moved only by a recorded decision prepared by the porting report. | H3, §b.1, §f.2 |
| D3 | No Seed-side builder in v1 (local Nix / WSL2). | H15, §b.1, §e.2 |
| D4 | Hands-free TPM2 only with Secure Boot on our keys (PCR 7); else TPM2+PIN with the evil-maid caveat. The host sops age key is a file inside LUKS; the TPM age key is opt-in. | H12, H13, §e.6 |
| D5 | **Superseded by V7.** Rev 3's highlight list (the protected list turned into card facts) is deferred with the facts engine (Appendix H.4). v1 cards carry only the file-based flags of §g.3 switch step 2. | §g.3 |
| D6 | The human key creates the silo repo (owner); the enrollment key is temporary in CODEOWNERS/.authorized_keys and removes itself; S1 later; the installer can generate a passphrase-protected software owner key into `~/.ssh`. The agent key can push only `gate/*` and `refs/dit/*`, never `master` (never in CODEOWNERS). | H6, H17, §a.4, §d.3, §e.2, §e.5, §g.7 |
| D7 | Limine default; lanzaboote supported and CI-tested. | H16, §c.1, §e.8 |
| D8 | The resident may ask, with a reviewed card each, for a short list of commands (`loom.agent.sudoCommands`: `loom-switch`, `journalctl`, `systemctl`, `fwupdmgr`, `nix-collect-garbage`). Whether it may ask for **any** command is the install-time question, default no (`loom.agent.sudo = "listed" \| "any"`). Switching uses the list. | H18, §a.3 C8/K8, §c.3, §e.5 4a |
| D9 | Human dotfiles are read-only home-manager files, fed by `omanix.*` options and `home.nix` that the resident edits; only KEEP-AS-GUI writers remain, redirected to runtime overlays. `~/.ssh`, `~/.gnupg` never HM. | H14, §f.4 |
| D10 | Software human keys are allowed with no reduction of anything, but must have a passphrase (passphrase-less keys are refused). FIDO2 recommended. In v1 the human key owns the silo repo and authorizes reinstalls; card approval is the dialog click. | §c.1, §e.2, §e.5 |
| D11 | Release tags, `SHA256SUMS` and the fork mirror are signed on Josh's YubiKey; the `omanix-cache-1` key lives on signi in sops, used only by the `release` skill through an approval; no CI secrets. | §e.1, §e.10, §f.2.7, §g.6 |
| D12 | One system encryption key (SEK1) derives the LUKS recovery passphrase and the sops recovery age identity; crash-safe rotation tool whose final commit goes through a card. | H13, §e.5, §e.7, §g.10 |

**Calls carried from rev 3:** reviewer user `reviewer` with options under `loom.reviewer.*`; `loom propose` replaces `loom switch`; `SUPER + A` for chat; `loom.keys.*` replaces `loom.host.*Keys`; passphrase-less software keys refused; the chat bridge is a loom unit, not a nuketown daemon feature; make it stick settles kv overlays per key and whole-file overlays by snapshot sha.

### Still open

| # | Question | Default in this document |
|---|---|---|
| O1 | `omanix.home.overlays` default: `"keep"` (runtime tweaks persist until stuck or reset) or `"reset"` (overlays emptied at each login; fully declarative desktop). | `"keep"` |
| O3 | When does S1 (owner handoff/rotation, with the `grep -qxF` pre-receive fix) get scheduled? Until then a compromised owner key means a fork. | after v1 |
| O4 | Should the installer push the user to add a second human key before finishing when the only one is a generated software key? | advise only |
| O6 | Default reviewer model/provider and who pays for it. | claude-code, separate login |
| O7 | Pass the rejection reason of the previous card to the reviewer of the follow-up proposal? | yes |

O2 was settled in rev 2. O5 (second-device approval), O8 (host key in CODEOWNERS) and O9 (`requestMaxAge`) no longer apply in v1; they return with Appendix H. Rev 5 settled O10 (approval surface: the `omanix.approval` card is the prompter, zenity the fallback, K6) and O11 (the `sudoex-run` bypass is fixed in v1, K1).

---

## Work packages

Rules for all packages:
- Each package lands with its own checks green; the touched repo's `nix flake check` is its gate, so every package is independently buildable.
- File ownership is disjoint, so agents can work in parallel without editing the same files.
- Deps are hard prerequisites. "(test)" means the dep is needed only for an integration test, not to start.
- The installer critical path never waits on the desktop track; the desktop track never waits on the installer.
- **Only W1 edits nuketown** (V8). Other packages pin nuketown and use it through options; nuketown changes keep `checks.signi-compat` green.
- Every commit carries `Co-Authored-By: Joshua Perry <josh@6bit.com>`.

| ID | Title | Repo | Scope / files | Deps | Acceptance criteria |
|---|---|---|---|---|---|
| **W0** | Contract-first loom skeleton | loom | New flake layout; `lib/{mk-host,catalog,checks,repo-id,keys}.nix`, `force-allowlist.nix`; options-only skeletons for every `modules/loom/**` file in §c.1, except `modules/loom/{default,host,keys}.nix`, implemented fully (`loom.keys` and the `loom keys sync` renderer); `templates/host` (plain-module host: `configuration.nix`, `home.nix`, `machine.nix`, `keys.nix`, `modules/`); AGENTS.md; setup-remotes; CI matrix 26.05 + unstable (D1); lanzaboote input (D7); nuketown pinned; removal of the MVP auth/QR server and `installer.nix`. | — | `layout`, `priorities`, `documented`, `keys-sync` (incl. refusal fixtures and the mint stub tree) pass. The template host evaluates on both channels via `loom.lib.mkHost`. |
| **W1** | nuketown approval changes (**built**) | nuketown | K1–K6, K8–K12 (§a.3): `approval.nix` (service user, `nuketown-approve`, snapshots, reviewer, audit, sudoers), `module.nix` (shim with `--why`, `sudoex`, `sops-unlock`, `sudo.approvalAllow`), `approval-daemon.nix` (`REQUEST:<id>`, `prompter`, zenity renderer with **Show files**), `checks.nix`, `tests/{approval-node,sudo-approval-bypass,approval-flow}.nix` | — | Done 2026-10-28 on nuketown `master` (`7a2b84e`, `6b4960c`, `eafb45f`, `6b9e5c1`; only `7a2b84e` pushed): `nix flake check`, `vm-sudo-approval-bypass` and `vm-approval-flow` pass; mynix signi evaluates with `--override-input`. Not yet: a signi build/`nvd diff`/switch, and the zenity dialog seen on a real desktop (U42). |
| **W1b** | nuketown approval, rest | nuketown | K7 kinds; `--requester` from root; `NUKETOWN_APPROVAL_DIR`; deny reason to stderr; prompt before the review finishes; DECRYPT + command: show the dialog first and start gpg only after Approve (today pinentry opens behind the dialog and grabs the keyboard, so the PIN has to be typed blind) | W1 | `approval-kinds` passes; `decrypt-after-approve` (gpg not started before the prompter exits 0); `pipeline-e2e`'s human and timer variants reach the card. |
| **W2** | silo test infrastructure | seed | S3 `silo-standalone`, S4 sk-key test, the `silo-enrollment` seed half, the agent-gate cases (U15). **No change to `shell.nix` or `hooks.nix` behavior.** | — | `silo-enrollment` seed half passes: human first push ⇒ owner, HEAD = master, enroll self-removal, enroll rejected on gate/*, sk keys work, F3 multi-line note documented, U15 cases recorded. |
| **W3** | omarchy fork mechanics + packages | omanix | As rev 3: `flake.nix` (omarchy at `5978d93`), `fork/{UPSTREAM.toml,NOTICE,classify.toml,drop.txt,rewrite.toml,hl-symbols.txt,patches/*}` (P1–P4, P6, P9, P15, P16 branding, P17 weather; the shell-plugin patches are W18), `fork/add/bin/*`, `lib/fork.nix`, `pkgs/by-name/*`, `apps.{porting-report,fork-mirror}`, `LICENSES/`, `port-omarchy` skill | — | Every package builds. `fork-classify` is green **at `5978d93`** (U21); `fork-license`, the `omarchy-src` post-check, `hl-symbols` pass. The titlebars `.so` loads in a headless Hyprland smoke. `porting-report --to bc220e7` produces a report (smoke, not a gate). |
| **W4** | Disk, unlock, boot | loom | `modules/loom/disk/*` (incl. `@agents`/`@agents-blank` without a mount, C2), `boot/*`, `diskoLayout`, unlock text and assertions, the `loom-sek` LUKS slot + token, `loom-askpass`, the `unlock-finalize` first-boot step, `loom unlock`, lanzaboote (D7) | W0, W6, W11 (test) | `fde-passphrase`, `fde-fido2`, `fde-tpm2-pin`, `fde-recovery` (U33), `fde-tpm2-requires-sb`, `sek-vectors`, `eval-lanzaboote`, `boot-lanzaboote` pass. The autologin assertion has a negative fixture. |
| **W5** | Impermanence, persist audit, snapshots, home wiring | loom | `modules/loom/persist/*`, `lib/persist-audit.nix`, `installBinds`, `modules/loom/home.nix` (HM NixOS module, `loomReclaim`, ordering drop-in, `hm-activation` watchdog check) | W0, W11 (test), W8 (test) | `impermanence-survives-reboot` (incl. nuketown's `/agents` reset), audit assertion fixtures, `hm-reclaim` pass. |
| **W6** | Secrets lifecycle, keys CLI, SEK lib | loom | `modules/loom/secrets/*`, `.sops.yaml` render, prompted secrets, `pkgs/loom-cli/{sek.py,keys.py}` (`loom-sek`; `loom keys list/sync/add-human [--generate]/remove-human/rotate host|agent`, `loom user passwd`) | W0, W5 (test) | `sops-host-key` passes; `sops-tpm-age1tag` runs (red allowed, then `tpm` asserted off); `sek-vectors` (python half + token schema); pytest proves the `--generate` passphrase never reaches argv/env and that a passphrase-less key is refused. |
| **W8** | loom-switch, collector, watchdog, updates, undo | loom | `pkgs/loom-switch` (`loom-switch`, `loom-switch-collect`, `loom-switch-request`; mirror, refusals, diffs, flags, `card.json`, records), `pkgs/loom-watchdog`, `pkgs/loom-cli` (`propose`, `card show`, `undo`, `rollback`), polkit actions `farm.loom.{propose,undo}`, `modules/loom/{switch/*,update.nix,trust.nix}`, the `loom-switch` kind registration, the SEK-rotation marker refusal (used by W13) | W0, W1, W1b, W11, W2 (test) | `card-render`, `switch-watchdog`, `undo-rollback`, `update-card`, `agent-sudo-approval` and `pipeline-e2e` (reviewer disabled; terminal and replay-resident proposals) pass against the test prompter. |
| **W9** | Agent bridge | loom | `pkgs/loom-agent-bridge` (chat socket server, claude-code stream-json and replay adapters, `loom-open-url`, attachments to the inbox), `modules/loom/{chat.nix,agent/bridge.nix}`, `loom.chat/v1` | W0, W11 (test) | Adapter fixture tests (U11) pass; pytest covers framing, reconnect and attachment limits. |
| **W10** | Reviewer wiring | loom | `loom.reviewer.*` → `nuketown.approval.reviewer`, `pkgs/loom-switch-review` (the switch prompt), reviewer sign-in wiring | W1, W8, W11 | `review-parse` passes; `pipeline-e2e` with the replay reviewer passes, including the garbage-output and signed-out variants. |
| **W11** | Residents, user and base host modules, first boot | loom | `modules/loom/agent/{default,login,nuketown}.nix` (`loom.agent.*` and `loom.reviewer.*` → the two nuketown agents and approval options of §c.3; the C1–C8 glue of §a.3: persist-root assertion, `btrfsDevice`, `secrets/agents.yaml`, broker HM import, the uwsm restart hook option, the `pkgs.unstable` alias, portals; agent units gated on `repo-publish.done`), the approval test prompter (`tests/lib/approval-stub.nix`), `modules/loom/firstboot.nix`, `modules/loom/{user,locale,nix,hardware}.nix` | W0, W1 | `nuketown-glue`, `eval-agent-sudo-approval`, `eval-no-agent`, `eval-reviewer-off`, `layout` pass. A VM test shows the resident's units inactive without `repo-publish.done` and active with it. First-boot runner pytest passes. Catalogs of the template host build (U40). |
| **W12** | Mint, repo id, enrollment, hostgen | loom | `pkgs/{loom-mint,loom-enroll}`, `pkgs/loom-installer/hostgen.py` (§e.5a), owner-key first push, HEAD check, enroll self-removal push and verify, `configure revoke-enroll`, `repo-publish` + enroll-retry first-boot steps, `loom authorize`, `modules/loom/silo.nix`, squatted-id detection | W0, W6, W2 (test), W11 (test) | `repo-id-vector`, `hostgen-escape`, `host-template` (loom flavor) pass; `silo-enrollment` (loom half) passes against the stand-in; fork/authorize/revoke-enroll pytest passes. |
| **W13** | SEK rotation | loom | `loom keys rotate encryption-key` (§g.10 phases, pending cleanup, paper-check gate, `sek-rotation.json`; phase 4 commit + `loom propose`), polkit action `farm.loom.keys.rotate` | W6, W4, W8 | Rotation-state pytest passes. `sek-rotate-crash` passes, including phase-2 sub-step crashes, start-over cleanup, the exit-5 marker check, and the rescue-path unlock with the new SEK. |
| **W14** | Installer image, TUI, flash | loom | `lib/mk-installer.nix` (repart, verity, cache, flake-archive), `modules/loom/installer/*`, `pkgs/{loom-installer,loom-detect,loom-flash}`, `loom hw regen`, probes registry, test image variant, the SEK screen, owner-key generation into `~/.ssh`, the "Use an AI agent?" and "any command?" questions, the btrfs UUID → `machine.nix` (C2), sidecar v2 validation, the rescue entry | W4, W5, W6, W8, W11, W12, W2 (test) | `verity-corruption`, `flash-guards`, `installer-offline-eval` (U36), `installer-e2e` (loom-only), `installer-e2e-fresh`, `installer-e2e-sb`, `installer-reinstall`, `installer-fork` pass. |
| **W15** | omanix desktop core, HM dotfiles, runtime overlays | omanix | As rev 3: `lib/mk-host.nix`; `modules/omanix/{default,path,session,login,language,runtime,hyprland/*,keybinds,menu,shell,health,probes,residents}.nix`, `modules/omanix/home/*`, `lib/{lua,jsonc,menu,home/*}.nix`, `omanix-data`, `pkgs/{omanix-overlay,omanix-runtime-snapshot}`, `omanix-session-init`, `omanix-session-state`, the broker restart in autostart (C5), `fork/writers/desktop.toml`, `modules/omanix/{branding,hooks,fork,persist}.nix`, the `ref-*` fixtures | W0, W3, W5 | `desktop-boots` (+ greeter variant; U24, U34) passes. `keybind-conflicts`, `jsonc-equivalence`, `hm-owned-readonly`, `runtime-writers`, `home-owned` (U31), `home-files-golden` for W15's targets pass **at `5978d93`**. W15's `writers-respect-hm` cases (U28, U35), `shell-json-rebase` and the `omanix-overlay` pytest pass. |
| **W16** | Themes, boot visuals, browser policy | omanix | As rev 3 | W15 | `themes-render`, `theme-switch`, the glass and chromium-wrapper `writers-respect-hm` cases pass; golden boot-visual renders exist for 3 themes. |
| **W17** | Apps, services, hardware quirks | omanix | As rev 3 | W15, W11 | `hw-quirks` (U26, U27) passes; the `nouveau-cursor` fixture emits the cursor setting; omanix-flavor `eval-*` fixtures pass; the font-set, input, defaults and apps `writers-respect-hm` cases pass. |
| **W18** | Shell plugins and the intent menu | omanix | `fork/add/shell/plugins/omanix-{chat,approval,status,welcome}/`, patches P5, P7, P8, P10–P14, P18, P19, `fork/intents.toml`, `fork/menu-extra.jsonc`, `data/chips/rules.json`, `modules/omanix/{chat,approval,welcome}.nix`, `omanix-approval-prompt` (K6) and the root-command card, the Change password dialog | W15, W1, W8, W9 | `chat-socket` (U10), `approval-focus` (U13), `menu-intents` **at `5978d93`**, `desktop-intents`, `approval-card`, and routine/full/root-command card goldens pass. |
| **W19** | omanix CLI, verbs, catalogs, skills, host template | omanix | `pkgs/{omanix-cli,omanix-catalog,omanix-skills}`, `modules/omanix/{cli,catalog}.nix`, `templates/host` (omanix flavor), resident prompt fragments, `omanix context/options/where/explain/set/plugin/app/secret/persist/hw/check/plan/propose/update/try/reset/edit/repo` | W8, W15, W18 | `catalogs`, `catalog-size` (U20), `cli-contract`, `set-roundtrip` (U19), `skills-no-arch`, `host-template` (omanix) pass. `plugin-fixture` (U29, U30, U32) and `try-preview` pass. A VM script runs context → set → check → propose → card end to end. |
| **W20** | Configure/build-installer skills, scripts, release | omanix | As rev 3 | W14, W16, W17, W19 | `installer-e2e-omanix` passes offline with `cacheMiss = []`. `closure-budget`, `closure-dupes`, `script-preamble-identical` pass. A signed `v0.1.0` dry-run release verifies with `verify-release.sh`. CI holds no signing secret. |
| **W21** | Demo and end-to-end UX | omanix | `demo/` (replay transcripts, the battery and Wi-Fi scenes, bad monitor rule), `checks.vm-demo-{2..7}`, `make-it-stick`, `human-commit`, the demo runbook | W10, W17, W18, W19; W20 (and so W14) for the manual part | **VM part:** `vm-demo-2`…`vm-demo-7`, `human-commit`, `make-it-stick` pass. **Release-candidate part** (after W20): scenes 1, 8 and 9 are run manually once on the reference laptop and recorded. |

W7 (facts and highlight list) is withdrawn; its scope is Appendix H.4. W1 is nuketown's approval work (V8); the loom-side glue moved into W11.

**Parallelism.**
- Day one: W0, W1 (nuketown), W2, W3.
- After W0: W5, W6 and (with W1) W11 in parallel; W9 can start against W11's agent user stub. W4 starts once W6's `loom-sek` lib lands; W12 once W6's `keys sync` lands. W15 starts once W3 and W5's `loom.home` land.
- W8 follows W1 and W11. W10 follows W8. W13 follows W4 and W8. W14 joins W4, W5, W6, W8, W11, W12.
- Desktop track: W15 → W16, W17 (parallel) and W18 (also needs W8, W9) → W19 → W20; W21's VM part closes after W10, W17, W18, W19, and its manual part after W20.
- **Critical paths:** change pipeline **W0 + W1b → W11 → W8 → W10 → W21** (W1 is built; W1b is the rest of the nuketown work and can start now); installer **W0 → W6 → W4 → W14 → W20**; desktop **W3 + W5 → W15 → W18 → W19 → W20**. The desktop path is the longest; the demo needs all three.

---

## Appendix H: hardening track (post-v1)

Everything here was designed in rev 3 and deferred by V7. Section numbers are **rev 3's** (git history; `scratchpad/DESIGN.rev3.md`). Each item says what it answered, so it can be brought back one at a time.

**H.1 nuketown deltas** (rev 3 §a.3, §c.3; work package W1)
- **N1** → in v1 as K1 (a root-side wrapper instead of a token), with K2 (`SETENV`) and K3 (request directories).
- **N2** Python broker with `SO_PEERCRED`; socket independent of `sudo.enable`. Answered: any `nuketown-broker` member can raise dialogs or speak for another user.
- **N3** build-time mock approval only. Answered: a runtime mock file as an approval bypass.
- **N4** trap to remove the decrypted age key when `nuketown-switch` fails.
- **N5** (K6 brings `approvalDaemon.prompter` into v1) `persistRoot`, `sops.ageKey.*`, impermanence gating, `extraHomeConfig` as deferredModule, `promptFragments`, `switch.command`, `approvalDaemon.{prompter,display,target}`, `rollback.keepPrevious` with nested-subvolume delete. Convenience and generality; v1 covers what it needs in §a.3.
- **N6** → in v1 as K10.
- **N8** per-agent nftables egress (`proxy-only`). Answered: a reviewer with general network.
- **N9** `interactive = false`. Answered: a shell/portal/linger/sudo surface on the reviewer.
- **N10** `claudeCode.lockdown`. Answered: tools, MCP, hooks or CLAUDE.md in the reviewer's harness.
- **N11** broker `SIGN` from uid 0 only, `--card` prompter contract. Answered: a resident forging a card or a signature request.
- **N12** `switch.command = "loom propose"`.
- **N13** `homeMode 0700` assertion between residents.
- **N14** polkit `host-shell` limited to agent targets. Answered: password-less `machinectl shell root@` for any code running as the human (also on signi).
- **N15** NixOS-level broker unit instead of an HM unit.

**H.2 Request provenance** (rev 3 §g.2, H8). Root `loom-chatd` records every human chat turn with `SO_PEERCRED` attribution in a hash-chained ledger before the resident sees it; `Request-Id` trailers; paste, dictation and agent-choice surfaces; staleness (`requestMaxAge`, O9) and reuse checks; the reviewer gets requests from the ledger, never from the resident. Answered: an injected resident inventing or rewording the human's request.

**H.3 Human-signed approvals** (rev 3 §g.7, H5, H10). The approval is an ssh-signed merge commit by a human key (FIDO2 touch or passphrase) with host id, base, tip, facts/card hashes, a single-use nonce and expiry; switchd verifies it against the running `allowed_signers`; the broker signs only payloads from root. Includes approving on another machine (`loom card export`, `--approval-from-silo`), `keepClick`, hold-to-confirm for critical facts, the `owner-key-local` first-boot step, and O5 (second-device approval). Answered: replay, a forged dialog, and approval by anything but the human's key. Rev 3 blocker 2 (approve one tree, deploy another) lives here and in H.4.

**H.4 Deterministic facts and the highlight list** (rev 3 §g.4, H7, D5, W7). `loom-facts` from the running generation: the highlight view over security-relevant option paths, units (privileged detection, drop-ins), human exec surfaces, a deny-by-default diff of built `etc/`, polkit/dbus shares, `nix.conf` keys, nftables and initrd; `rebuilt` (same name, different `.drv`); inputs (`transitiveOverride`, `unreachableRev`, tag target = `locked.rev`); ports; `suspiciousText`; drift; the presentation truth table. Answered: a subtly malicious change looking routine. Rev 3 blockers 3 and 4 live here.

**H.5 Reviewer isolation** (rev 3 §g.5, H9). Transient unit with `ProtectSystem=strict`, `ProtectHome=tmpfs`, no tools, empty MCP, a fenced read-only bundle with commit bodies and attachments withheld, a CONNECT-only egress proxy (`loom-egress`) plus N8, a wiped auth dir, strict `loom.review/v1` validation, and "can add escalation, never remove". The reviewer quality corpus (rev 3 §i.3). U3–U5. Answered: injection through the diff steering or weaponizing the reviewer.

**H.6 Silo chain audit** (rev 3 §g.11–§g.12, O8). `loom audit --from-silo`; reinstall installs only the last valid approval merge; red screen on an invalid commit; removing the host key from `CODEOWNERS`. Answered: a compromised host rewriting silo `master`.

**H.7 Preflight VM** (rev 3 §g.3). Booting the proposal's `vmVariant` guest with the running generation's QEMU in a DynamicUser, network-less unit; ports from `ss`. Answered: an agent-chosen VM runner executing as root (rev 3 blocker 1), and gives listener facts.

**H.8 Smaller items.** Eval and fetch in DynamicUsers (`loom-eval`, `loom-fetch`) with `restrict-eval`; `stripRev` and `configurationRevision = narHash`; `loom stats` and fatigue tuning; repo-exec path class (`.claude/settings.json`, `.envrc`, …) as an escalation; `try` preview limits beyond the typed allowlist; sign-in `auth` token tied to an open portal; card `unlockDelayMs`; the threat table (rev 3 §g.15).

**H.9 Tests and claims tied to the above.** Pure: `facts-cases`, `presentation-rule`, `review-validate`, `suspicious-text`, `approval-verify`, `preflight-vmvariant`, `signi-compat`, schemas for `loom.{request,facts,review-bundle,review,card}/v1`. VM: `replay-refused`, `sign-from-nonroot-refused`, `ledger-forgery`, `provenance-facts`, `reviewer-isolation`, `reviewer-cannot-deescalate`, `reviewer-down`, `preflight-runner-untrusted`, `card-latency`, the nuketown tests (`nuketown-wayland-approval`, `-hostshell-target`, `-broker-peercred`, `-egress`, `-noninteractive`), and rev 3's `vm-demo-4` injection scene. UNVERIFIED: U1 (FIDO2 signing from the broker under Wayland), U2 (view function under `restrict-eval`), U3–U5 (reviewer harness), U6 (`%GS` principals), U7 (archive as DynamicUser), U8 (units from `systemd.packages`), U9 (reviewer can't read `runtime.json`), U14 (card latency with VM smoke), U16 (`diff-closures` parsing), U17 (ports stability), U18 (peer creds for the uwsm Quickshell).
