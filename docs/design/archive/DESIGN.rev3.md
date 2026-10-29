# omanix: design

Rev 3, 2026-10-27 (fork + agent-first redesign). Authors: Ada, with Joshua Perry.

**Inputs.**
- `spec.md` rev 16. It is authoritative for **install scope and the excluded vectors** (below) and overrides this document on those points. Its "Agent security" clauses are **superseded by V4/V5** (Josh, 2026-10-27): "the agent's signature suffices when nothing protected changed" → every switch needs a human-signed approval (H5); the protected-set gate → the deterministic highlight list that feeds card facts and is never a gate (D5, §g.4); "one approval gesture: the existing GUI sudo dialog" → the `omanix.approval` card plus the human key gesture (§g.7, §h.4).
- `design/facts.md` (toolchain facts, verified 2026-10-27).
- Josh's new direction V1–V6 (2026-10-27, fixed) and the standing decisions D1–D12.
- The four fork drafts: `fork/trust.md` (change pipeline and trust), `fork/host.md` (mkHost and host repo), `fork/fork.md` (omarchy fork classification and mechanics), `fork/ux.md` (agent-first UX). Where they disagreed, this document picks one answer and says so in `fork/changelog.md`.
- DESIGN.md rev 2. Its installer, disk/LUKS/unlock, Secure Boot, enrollment, system encryption key, impermanence and read-only home-manager sections are carried over here, corrected where the new direction changes them.

**Scope (spec rev 16).**
- Install is only from a standard bootable USB installer image, onto a whole disk.
- The installer never copies or embeds credentials.
- Secrets are sops-encrypted to keys generated on the host, or prompted for.
- **Not designed, on purpose:** in-place conversion of a running OS, kexec/infect vectors, Windows boot-chain vectors, and moving an existing AI-assistant login or token to the new machine. On the installed machine, each agent (the resident and the reviewer) signs in through its own normal login flow, or not at all.

---

## 0. Overview

### 0.1 Vision (V1–V6)

| # | Direction | What it means in this design |
|---|---|---|
| V1 | omanix is a proof of concept and a conversation piece: **what omarchy would look like if it had started on nix**. It **forks** omarchy at `v4.5.0-rc2`. | omarchy is the product spec and the asset source: Quickshell shell QML, themes and templates, default Hyprland Lua, menu data, keybinding defaults, branding, hardware-quirk knowledge. Its bash state-mutation layer (package install/remove, migrations, settings writers, refresh/reinstall, provisioning, update) is replaced by nix. Upstream drift is an optional **porting report**, never a `nix flake check` gate (§f.2.7). |
| V2 | **Agent-first.** The agent is the primary UI for change. | Mutating human tools are dropped in favour of asking the agent, except where asking would be onerous: continuous controls, instant toggles, visual browsing with live preview, and everything needed to reach or repair the agent (§f.3). GUI changes are runtime state; "make it stick" is a request to the agent. The menu is an intent launcher. The system stays fully usable without the agent (§h.11). |
| V3 | **Resident agent.** The UI agent is a nuketown resident (its own unix user), not a process in the human's session. | `ada` (uid 1100) runs under nuketown. A chat surface in the Quickshell shell talks to it through a root relay. Showing off nuketown's user partitioning is an explicit goal (demo scene 6). |
| V4 | **No settings registry, no tiers.** | The resident may edit any NixOS/home-manager module and any flake input in the host repo. **Every switch needs a human signature** (YubiKey touch or software-key passphrase). switchd activates only human-signed approvals. The watchdog and automatic rollback stay. Updates are "Update ready" cards. |
| V5 | **Approval card from an adversarial reviewer.** | A second resident, `reviewer` (uid 1101), with no general network and no write access, reads the human's recorded request, the diff, nvd, build/check results and a **deterministic facts** section computed by code. It never sees what the resident read. Facts are visually separate from AI text and the reviewer cannot change them. Routine cards are one line (§g.6). |
| V6 | **omanix ≈ a function.** | `omanix.lib.mkHost` returns a `nixosSystem` with loom + nuketown + the omanix base, then loads the host's own plain NixOS and home-manager modules. Plugins are ordinary modules from any flake (§b.4). Typed verbs (`omanix set`, `app add`, …) remain as agent tools, not gates. |

### 0.2 Hard calls

| # | Call | Reason |
|---|---|---|
| H1 | The whole omanix stack runs on **one nixpkgs: `nixos-unstable`**, moving to `nixos-26.11` at branch-off. Hyprland v0.56.2, quickshell and hyprland-guiutils come from their flakes with `inputs.nixpkgs.follows`. loom and nuketown keep CI green on **26.05 and unstable**, so signi is unaffected (D1). | Quattro needs Hyprland ≥ 0.56 and quickshell ≥ 0.3.2. One nixpkgs gives one Mesa and one Qt (facts §3). |
| H2 | `/` is **tmpfs**. `/nix`, `/persist` and **all of `/home`** are btrfs subvolumes. `/agents` is reset every boot by nuketown. | omarchy writes state all over `$HOME`; a persisted `/home` covers it with no per-path entries (§f.1). |
| H3 | **omanix forks omarchy at `v4.5.0-rc2`** as a pinned, unmodified, hash-locked input plus a patch queue under `fork/` (§f.2). Every bin script, menu entry and tree path has exactly one class: KEEP-AS-GUI, AGENT-INTENT, ASSET, RE-EXPRESS-IN-NIX or DROP. `checks.fork-classify` fails on an unclassified path. The bash state-mutation layer is **removed, not wrapped**. | V1. The divergence reads as a short list of drops and patches, and nothing in `nix flake check` compares against newer upstream. |
| H4 | **`omanix.lib.mkHost` returns a `nixosSystem`.** It adds loom (bundling nuketown, home-manager, sops-nix, impermanence, disko, lanzaboote), the omanix base, `specialArgs.inputs` and the human's HM entry point. Everything else is the host's plain modules, reached through ordinary `imports` (§b.3). | V6. A host flake can be read and debugged with plain NixOS knowledge. |
| H5 | **Every switch is a human-signed approval merge commit** whose tree equals the proposal's tree and which is bound to host, base, proposal, facts, card and a one-time nonce (§g.7). There are no tiers and no agent-only path. The watchdog's automatic rollback is the only activation without a new signature, and it only restores the generation that was already running. | V4. One rule is easier to audit, explain and test than a classifier. |
| H6 | The resident can edit **anything** in the host repo. Its key can push only `gate/*` and `refs/dit/*` (new or fast-forward) on silo, never `master` or tags, because it is never in `CODEOWNERS` (§g.11). switchd ignores `refs/dit/*` entirely. | V4, D6. The gate is the human signature, not limits on what can be edited. |
| H7 | **Facts are computed by code from the RUNNING generation** (`$current/loom/facts`, `$current/loom/view.nix`) applied to the proposal's evaluated config and built closure. The protected list of rev 2 survives as the **highlight list** in loom (D5): input to facts, never a gate. Hosts can add entries, never remove base entries. | A proposal that edits loom cannot change how its own card is computed. |
| H8 | **Request provenance is held by root.** `loom-chatd` records every human chat turn with the peer's `SO_PEERCRED` uid in a hash-chained ledger **before** the resident sees it. Proposals refer to requests by id. The reviewer reads the request from the ledger, never from the resident. | Root attestation of the uid is the strongest honest claim available, and switchd reads it without entering the human's home. |
| H9 | **The reviewer is its own nuketown resident** (`reviewer`, uid 1101). It runs one tool-less model call per proposal in a transient sandboxed unit, reaches only an allowlisting proxy to the model endpoint, reads a read-only bundle and returns JSON on stdout. It can **add** escalation, never remove it. | V5. A fooled reviewer can at worst make a card with empty structural facts look routine. Facts compare derivations and built effects, not only option values and names (§g.4), so changed root code never has empty facts. |
| H10 | **Card presentation is deterministic.** A card is routine (one line) only when no escalating fact fired, every check passed, a human request is linked (or the change is human-authored, a human-started rollback, or an update to verified releases only), and the reviewer said approve with `matchesRequest = yes` and no high concern, or was skipped under §g.3 step 10. Anything else is escalated. **Only root (switchd) may send `SIGN` to the broker.** | Approval-fatigue control decided by code, not by the AI. A resident cannot push a forged card into the human's signing dialog. |
| H11 | A **root `loom-switchd`** does intake → fetch → eval → build → checks → facts → review → card → SIGN → verify → arm watchdog → test → health → promote → push. The watchdog and a dead-man timer run as **transient units from the old generation's store paths**, armed before activation. | The pipeline can't be bypassed through sudo, and a broken new generation can't disable its own rollback. |
| H12 | **Every disk gets a system-encryption-key slot.** TPM2 without a PIN is offered **only with Secure Boot on our own keys** (PCR 7); all TPM2 enrollment happens at first boot. **Autologin is on only when no enrolled unlock method is automatic** (D4). | A stolen laptop never boots into a desktop without a human factor. |
| H13 | The **host sops key is a file under `/persist`**, protected by LUKS. The user has one recovery secret, the **system encryption key** (SEK), from which the LUKS recovery passphrase and the sops recovery age identity are derived by HKDF with separate labels (D12, §g.14). | AMD fTPM clears must not destroy the secrets key, and users get one thing to write down. |
| H14 | **Human dotfiles are read-only home-manager files** generated from `omanix.*` options and the host's `home.nix` (D9). The GUI tools omanix keeps write only runtime state: `~/.local/state/omarchy/**` and writable overlays under `~/.local/state/omanix/`, which the HM files include last (§f.4). | Reproducible dotfiles; the kept GUI tools keep working; the resident cannot write the human's home anyway (V3). |
| H15 | The **installer is deterministic**: no agent, no sshd, no answers file. It writes the host repo from a **closed, typed answer set** through one escaping renderer (`loom-hostgen`), never free-form Nix. No Seed-side builder in v1 (D3). | The medium that does destructive work holds no network credential and no remote shell, and untrusted input enters Nix only as data. |
| H16 | Boot loader: **Limine** by default; lanzaboote is the supported, CI-tested alternative (D7). | Under Secure Boot the config and the kernel/initrd checksums are signed, so PCR 7 is meaningful. |
| H17 | **The human key creates the host repo** (first push ⇒ silo `.owner_key`). The enrollment key is temporary and removes itself in the installer's push. No silo change in v1 (D6). | The host and the enrollment key can never seize the repo. |
| H18 | **Generic approval sudo for the resident is an install-time question, default off** (`loom.agent.sudo = "none" \| "approval"`, D8). Turning it on is a critical fact on the card that enables it. | Approved sudo bypasses the reviewed pipeline, so it is opt-in and visible. |
| H19 | **The system is whole without any agent.** A terminal user edits the host repo, commits with a human key and runs `loom propose`; the same facts, card, signature, watchdog and rollback apply. | V2: it is just NixOS. |

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
         loom-chatd (provenance), loom-facts + highlight list, reviewer harness + egress proxy,
         loom-switchd + watchdog, updates, firstboot, catalogs lib
   │ inputs.nuketown
nuketown agents as unix users (resident ada, reviewer), approval broker (+SIGN, root only), egress/lockdown
seed/silo: S3, S4 (v1, test infra only); S1, S2 later
```

**Rules.**
- loom never mentions Hyprland or omarchy. A flavor hooks in through registries such as `loom.installer.probes`, `loom.switch.watchdog.checks` and `loom.highlight.extra`.
- loom and omanix set nixpkgs/HM options and `loom.*` only with `mkDefault`, so a host module wins at normal priority (`checks.priorities`). The exceptions are listed in `lib/force-allowlist.nix`; they include the `.source` of every omanix-owned HM file target, which is set at normal priority (§c).
- nuketown changes are new options whose defaults reproduce today's behavior. signi (mynix) must evaluate unchanged (`checks.signi-compat`).

### 0.4 Errata pointer

Rev 2's §0.3 mapped 36 judge findings to fixes. That table is kept in git history (`DESIGN.md` rev 2) and in `reconcile-changelog.md`; it is not repeated here. Its status under rev 3:
- **Still in force** (implemented by the carried-over sections): 1–4 (autologin and TPM/SB rules, §e.6), 6 (watchdog armed before `test`, §g.8), 7 (reinstall re-encrypts sops, §g.12), 8 (every cache signed, no `trusted=1`, §e.3), 9 (exact repo-id algorithm, §d.5), 11 (eval in a DynamicUser, §g.3), 12 (password hash never encrypted to the enroll key, §d.6), 15 (fork needs a new human key, §g.12), 17–19, 20 (no owner change in v1), 21–34.
- **Superseded by the new direction:** 5 (Tier B for store-path churn; now facts normalize store paths and every switch is signed), 10 (writer redirects for every upstream writer; now only KEEP-AS-GUI writers are redirected, the rest are dropped, §f.4), 13 and 35 (protected view as a gate; now the highlight list feeds facts, §g.4), 14 (`omanix.home.extraModules`; now `home.nix` is plain HM), 16 and 36 (`settings.json`, Tier A `data.yaml`; both gone).
- Rev 3 findings and their resolutions are recorded in `fork/changelog.md`.

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
  demo/                         # replay transcripts, README-injection fixture, bad monitor rule (§j)
  checks/  tests/               # §i
  docs/                         # architecture.md, porting.md; options.md GENERATED, not committed
```

The omanix shell plugins (`omanix.chat`, `omanix.approval`, `omanix.status`, `omanix.welcome`) live in `fork/add/shell/plugins/` so that upstream's plugin registry discovers them like any first-party plugin.

Remotes: `scripts/setup-remotes.sh` sets `origin` fetch to `ssh://git@silo.loom.farm/omanix.git` and the pushurls to silo and github. loom and nuketown carry the same script.

**Removed from rev 2:** `upstream/` (pin.toml, manifest, overrides, packages.toml, install-map.toml, writers.toml), `lib/upstream.nix`, `lib/home/writer-scan.nix` as a gate, the `bump-omarchy`/`override-upstream` skills, generated `omarchy-install-*` shims.

### a.2 loom (`~/projects/loom`, refactor approved; the existing MVP is replaced)

```
loom/
  flake.nix flake.lock CLAUDE.md(@AGENTS.md) AGENTS.md .claude/skills/{add-option,vm-test,facts}/
  lib/
    default.nix  mk-host.nix  mk-installer.nix  catalog.nix  checks.nix  repo-id.nix  persist-audit.nix
    keys.nix                    # loom.keys → .authorized_keys / CODEOWNERS / allowed_signers / .sops.yaml
    highlight/{view.nix,severity.nix,suspicious.txt,port-options.nix,labels.nix}   # D5 highlight list
  modules/loom/                 # FILE PATH == OPTION PATH under loom.*
    default.nix host.nix keys.nix user.nix locale.nix silo.nix home.nix hardware.nix nix.nix
    disk/{default,unlock}.nix  boot/{default,secure-boot}.nix  persist/{default,snapshots}.nix
    secrets/{default,host-key,prompted}.nix  trust.nix  highlight.nix
    switch/{default,watchdog,preflight}.nix  update.nix  chat.nix  reviewer/{default,egress}.nix
    agent/{default,bridge,login}.nix  firstboot.nix  installer/{default,probes}.nix
  pkgs/                         # python3 stdlib only; pytest in checks
    loom-cli/ (incl. sek.py = loom-sek, keys.py)  loom-switchd/  loom-eval/  loom-fetch/  loom-watchdog/
    loom-facts/  loom-review/ (run + prompt.md)  loom-egress/  loom-chatd/  loom-agent-bridge/
      (adapters: claude-code stream-json, replay)  loom-card-tty/  loom-installer/ (incl. hostgen.py)
    loom-mint/  loom-enroll/  loom-flash/  loom-detect/  loom-askpass/ (initrd SEK agent, §g.14)
  schemas/                      # loom.request/v1 loom.chat/v1 loom.facts/v1 loom.review-bundle/v1
                                # loom.review/v1 loom.card/v1 loom.snapshot/v1 loom.sidecar/v2 (checks.schemas)
  templates/host/               # generic (DE-agnostic) host template
  tests/  tests/lib/{silo-standin,fixtures}.nix  tests/review-corpus/
  scripts/setup-remotes.sh
```

`modules/loom/home.nix` (`loom.home.*`) holds the DE-agnostic HM wiring: the HM NixOS module (`useGlobalPkgs`, `useUserPackages`, `backupFileExtension = null`, `home.enableNixpkgsReleaseCheck`), the `loomReclaim` activation entry, the `hm-activation` watchdog check and the ordering drop-in on `home-manager-<user>.service`. loom's `home-manager` input follows nixpkgs (HM master on unstable; `release-26.05` in the 26.05 CI eval through an input override).

**Removed:** `installer.nix` (dead code); the inline Python auth server and QR credential handoff; the `MOCK_APPROVED` runtime file; the `wheelNeedsPassword=false` default; the hardcoded Hyprland prompt snippets (loom `prompt.nix`'s live-tuning idea survives as `omanix try`, §h.6). From rev 2: `lib/settings.nix`, `lib/json-schema.nix`, `lib/policy-view.nix` (renamed into `lib/highlight/`), `modules/loom/{settings,policy}.nix`, `loom policy classify`.

### a.3 nuketown deltas (additive; signi defaults unchanged)

| id | Change |
|---|---|
| N1 | **sudoex-run bypass fix**: `sudoex-run` requires a one-time token minted by the broker and checks it as root. A direct `sudo sudoex-run …` fails. |
| N2 | Broker **replaced**, not extended: today's broker is a socat/bash HM user service with no peer-credential check. The new one is Python with an `SO_PEERCRED` check, on the same socket path, with its own tests (`nuketown-broker-peercred`, `sign-from-nonroot-refused`). The socket directory `/run/nuketown-broker` and the `nuketown-broker` group are created whenever the broker is enabled. Today's tmpfiles rule creates them only when some agent has `sudo.enable`, so with D8's default `"none"` the `SIGN` path would have no socket. |
| N3 | Mock approval exists only as `nuketown.testing.mockApproval` (build-time). The mock-path mismatch is fixed. |
| N4 | `nuketown-switch` removes the decrypted key on failure (trap). |
| N5 | New options: `persistRoot`, `sops.ageKey.{encryptedFile,keyFile}`, impermanence gated on `options ? environment.persistence`, `extraHomeConfig` as deferredModule, `promptFragments`, `switch.command` (`nuketown-switch` execs it when set), `approvalDaemon.{prompter,display,target}`, `rollback.keepPrevious` with nested-subvolume delete. |
| N6 | `checks.signi-compat`: a fixture mirroring the mynix signi options must evaluate unchanged on 26.05. |
| N8 | `agents.<n>.network.egress = enum ["full" "proxy-only" "none"]` (default `"full"`) plus `network.proxy = "127.0.0.1:3128"`. Generates nftables `meta skuid <uid>` output rules; `networking.nftables.enable` is asserted when the value isn't `"full"`. |
| N9 | `agents.<n>.interactive = bool true`. `false` gives `shell = nologin`, no portal shell, no daemon, no linger, no sudo (asserted), no polkit `host-shell`, and no `sudo -u` rule targeting the agent. A `login` portal entry remains for the harness's sign-in flow only. |
| N10 | `agents.<n>.claudeCode.lockdown = bool false`. `true` writes settings with every built-in tool denied, no MCP servers, no hooks, no plugins, `disableAllHooks`, and no CLAUDE.md generation for that agent. |
| N11 | Broker request kind **`SIGN { card, base, tip, tree, hostId, nonce, expires, factsSha, cardSha, author, committer, message }`**, accepted **only from uid 0** (`SO_PEERCRED`). The prompter contract gains `--card <json>`, rendered by the Quickshell `omanix.approval` plugin, with zenity as a facts-only fallback. Returns `{status, signature}`: an `ssh-keygen -Y sign -n git` signature over the commit object rebuilt from those fields. switchd assembles the commit (§g.7.2). `SUDO` and `DECRYPT` are unchanged. |
| N12 | `switch.command = "loom propose"` (via N5): the agent's habitual `nuketown-switch` prints "proposal sent; card #n waiting for approval" and exits 3. This is a convenience only: `nuketown-switch` is installed only for agents with `sudo.enable`, so the routing is inert by default, and nothing security-relevant relies on it (switchd is the gate). |
| N13 | `agents.<n>.homeMode` is asserted `0700` for every agent when `loom.reviewer.enable`, so the resident can't read the reviewer's state and the reverse. |
| N14 | The human's polkit `org.freedesktop.machine1.host-shell` rule returns YES **only when the target user (`action.lookup("user")`) is an enabled portal agent**. Today the rule has no target check, so any code running as the human can `machinectl shell root@` with no password. New option `portal.restrictHostShellTargets`: default `false` keeps signi unchanged (`checks.signi-compat`), and loom sets it to `true`. |
| N15 | The broker is also available as a NixOS `systemd.user.services.nuketown-broker` unit with `ConditionUser=<humanUser>`, through the option `approvalDaemon.unit = "hm" \| "nixos"`. The default `"hm"` keeps signi as it is (N6). loom uses `"nixos"`, so no HM `systemd.user` unit is written into the human's home (§c, `checks.hm-unmanaged-paths`). |

N7 of the trust draft (a chat transport inside the nuketown daemon) is **not adopted**: the chat bridge is a loom unit running as the agent uid (§h.3), so nuketown stays generic. `checks.signi-compat` (N6) must keep evaluating signi's options unchanged on 26.05.

### a.4 seed/silo deltas

**v1 needs no change to silo's behavior.** The only v1 seed work is test infrastructure.

**Silo behaviors relied on (F1–F8).** Checked against `seed/instances/silo/{shell,hooks}.nix` at HEAD. Every D6 argument in this document (§d.6, §e.2, §e.9, §g.11, §g.12) cites these rows.

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
- **Never delete `.authorized_keys` (F5).** switchd refuses a commit that removes `.authorized_keys` or `CODEOWNERS`, whoever signed it: removing the file would freeze the stale bare copy. `checks.keys-sync` also requires both files in every host repo commit.
- **Push only to `master` and `gate/*`.** loom never pushes another non-gate ref, so F4 always gates it.

---

## b) Flake interfaces and mkHost

### b.1 Inputs

| repo | inputs |
|---|---|
| loom | nixpkgs (`nixos-unstable`, then `nixos-26.11`; CI also evaluates 26.05 for signi, D1), home-manager (follows nixpkgs), disko v1.13.0, impermanence, sops-nix, lanzaboote (D7), nuketown, seed (only for `checks`: silo-standalone) |
| omanix | loom (and `follows` for all of loom's inputs), `omarchy` (`github:omacom/omarchy/5978d93ae7da0a325b7493501911e3f1266cadd3` = tag `v4.5.0-rc2`, `flake = false`, D2; moved only by a recorded decision, §f.2.7), `omarchy-pkgs` (`flake = false`; Hyprland patches and PKGBUILD versions), hyprland `v0.56.2`, quickshell at rev `2b4501a…`, hyprland-guiutils v0.2.2. All follow omanix's nixpkgs. |
| host flake | `omanix` (pinned to a release tag rev), `nixpkgs.follows = "omanix/nixpkgs"`, `home-manager.follows = "omanix/home-manager"`, plus **any plugin inputs** (each new one is a fact on the card that adds it). |

There is no Seed-side builder input or output in v1 (D3).

### b.2 Outputs

```nix
# loom
lib = { mkHost; mkInstallerImage; keys; highlight = { view; severity; }; persistAudit; repoId; catalog; checks; };
nixosModules = { default; };                      # bundle; sub-modules importable by path
packages.<sys> = { loom-cli loom-switchd loom-eval loom-fetch loom-watchdog loom-facts loom-review loom-egress
                   loom-chatd loom-agent-bridge loom-card-tty loom-installer loom-mint loom-enroll loom-flash
                   loom-detect loom-askpass installer-image installer-image-test; };
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
    specialArgs = { inputs = inputs // { self = stripRev self; }; omanix = omanixSelf; } // specialArgs;   # stripRev: §b.3 rules
    modules = [
      loom.nixosModules.default            # loom + nuketown + home-manager + sops-nix + impermanence + disko + lanzaboote
      omanixSelf.nixosModules.default      # omanix base (desktop fork, residents, catalogs, CLI)
      ({ config, ... }: {
        system.configurationRevision = self.narHash;   # tree-derived: identical for a tip and its approval merge (§g.7)
        loom.host.src = self;
        home-manager.extraSpecialArgs = { inputs = inputs // { self = stripRev self; }; omanix = omanixSelf; };
        home-manager.users.${config.loom.user.name}.imports = homeModules;
      })
    ] ++ modules;
  };
```

| Part | Provides | Host-visible options |
|---|---|---|
| loom | disk/LUKS/unlock, boot, Secure Boot, impermanence, sops lifecycle + SEK, `loom.keys`, silo working copy, chatd, facts + highlight list, reviewer harness, switchd + watchdog, updates, firstboot, catalogs lib | `loom.*` |
| nuketown (via loom) | agents as unix users, approval broker (`SIGN`), portal, egress rules | `nuketown.*`; loom sets the two residents from `loom.agent.*` and `loom.reviewer.*` |
| home-manager (via loom) | HM NixOS module, `home-manager-<u>.service` ordered before the display manager | the human's tree is `home.nix` |
| omanix base | the omarchy fork: Quickshell shell + omanix plugins, themes, Hyprland Lua, intent menu, keybinds, apps, quirks, HM read-only dotfiles (§f.4.2), runtime overlays, `omanix` CLI, catalogs, resident skills | `omanix.*` |
| host modules | everything reached from `configuration.nix` and `home.nix` | anything |

**Rules.**
- The output attribute is always `nixosConfigurations.host`. switchd evaluates `<commit>#nixosConfigurations.host`. Renaming the machine is a one-line edit.
- **What is activated is what was built.** mkHost gives modules nothing that differs between a proposal tip and its approval merge: `configurationRevision` is the tree's `narHash`, and `stripRev` removes `rev`, `shortRev`, `dirtyRev`, `dirtyShortRev`, `revCount`, `lastModified` and `lastModifiedDate` from `inputs.self`. Host code can still reach them by editing `flake.nix`, so the binding does not rely on this. switchd activates the exact `outPath` it built from the tip and recorded in `facts.proposal.toplevel` (§g.3, §g.8), and never re-evaluates the approval merge. The merge's commit sha is kept in the switch record.
- Evaluation is pure, with `allow-import-from-derivation = false` in `loom-eval` and in CI. A plugin that needs IFD fails with an error naming the input.
- mkHost does not read `hardware.nix`, `machine.nix`, `keys.nix` or `modules/` itself; `configuration.nix` imports them, so a reader can trace every file.
- The template also exports `checks.<system>.host = toplevel`, so `nix flake check` in a host clone builds the machine. omanix provides no other per-host outputs; catalogs and docs are part of the toplevel (§h.9).

### b.4 Plugins are modules

| Plugin flake output | Meaning | How a host uses it |
|---|---|---|
| `nixosModules.<n>` (and `.default`) | NixOS module | `imports` in `modules/plugins.nix` |
| `homeModules.<n>` (and `.default`) | HM module for the human | `imports` in `home.nix` |
| `homeManagerModules.<n>` | legacy alias; accepted, `omanix plugin add` prefers `homeModules` | same |
| `overlays.<n>` | optional; added via `nixpkgs.overlays` in `modules/plugins.nix` (overlays are a high fact) | same file |
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
4. **Propose.** Commit (agent-signed, `Request-Id`), `omanix propose`. The card always carries the fact `inputs.added`, so a new input is never a routine one-liner.
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
loom.disk.unlock.methods                   listOf (enum ["recovery" "passphrase" "fido2" "tpm2-pin" "tpm2" "tang"])
                                           "recovery" ∈ methods (asserted); it is the system-encryption-key slot (§g.14)
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

loom.highlight.extra                       listOf str []          host additions to the D5 highlight list
loom.highlight.portOptions                 listOf str (base ~40)  option paths that declare listening ports; hosts may add

loom.chat.enable                           bool = loom.agent.enable   (loom-chatd, sockets, ledger)
loom.chat.retention                        str "365d"
loom.chat.requestMaxAge                    str "24h"   a cited request older than this escalates (§g.2)

loom.switch.approvalTtl                    int 86400
loom.switch.keepClick                      enum ["never" "escalated" "always"] "escalated"
loom.switch.preflight.checks               listOf str []    host flake checks.<system>.* names to run
loom.switch.preflight.vm                   enum ["auto" "always" "never"] "auto"   (auto: /dev/kvm present and ≥ 8 GiB RAM; if U14 fails, auto also skips package-only diffs, recorded as a fact)
loom.switch.watchdog.timeout               int 120
loom.switch.watchdog.checks.<name>         { command; as = enum ["root" "session"]; critical = bool; baselineRelative = true; }
loom.switch.autoUpdate                     enum ["off" "notify"] "notify"   (never auto-switch)
loom.update.inputs                         listOf str (default: the inputs in loom.trust.releases; others only on request, §g.9)

loom.agent.enable                          bool true      install question "Use an AI agent?" yes / later / no (§h.7)
loom.agent.{name,uid}                      "ada", 1100
loom.agent.harness                         enum ["claude-code" "replay"] "claude-code"
loom.agent.{harnessPackage,loginCommand}   package; str (claude-code: "claude" then /login)
loom.agent.sudo                            enum ["none" "approval"] "none"   (D8; asked at install, never in the sidecar)
loom.agent.promptFragments                 listOf lines
loom.agent.chat.attachments.maxBytes       int 8388608

loom.reviewer.enable                       bool = loom.agent.enable
loom.reviewer.{name,uid}                   "reviewer", 1101
loom.reviewer.harness                      enum ["claude-code" "api" "replay"] "claude-code"
loom.reviewer.model                        nullOr str null   (null = harness default; a separate login from the resident)
loom.reviewer.timeout                      int 180
loom.reviewer.egress.allow                 listOf str [ "api.anthropic.com:443" ]   (harness module adds its login endpoints)
loom.reviewer.maxDiffBytes                 int 200000

loom.firstboot.steps.<name>                { order; description; command; interactive; doneWhen; }
loom.hardware.facts                        typed submodule from hardware.json
loom.hardware.firmware                     enum ["filtered" "full"] "filtered"
loom.installer.probes.<name>               { command (store path); emits = "quirk" | "fact"; }   (flavor-contributed)
loom.installer.tty                         str "tty1"   (test image: "ttyS0")
```

Every `loom.*` path above that touches keys, trust, unlock, Secure Boot, secrets, silo, the agent, the reviewer, the highlight list, the switch or updates is on the **base highlight list** (§g.4.1) as a critical or high fact. Nothing is "protected" in the gate sense: all of them are changed through the same signed card as any other option.

**Fixed by loom:** `users.users.${loom.user.name}.uid = 1000` (mkDefault), so the installer can write `~/.ssh` before first boot.

**Removed from rev 2:** `loom.settings.settable.*`, `loom.policy.{extraProtected,protectedRepoPaths,humanKeyKind}`, `loom.switch.confirmProtected` (→ `keepClick`), `autoUpdate = "stage"`, `loom.agent.mode` (`"user"` contradicts V3; `"none"` is `loom.agent.enable = false`), `loom.host.{humanKeys,hostKey,agentKeys}` and `loom.secrets.recipients.human` (→ `loom.keys.*`), `loom.home.stateVersion` (plain `home.stateVersion` in `home.nix`).

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
omanix.approval.unlockDelayMs              int 800   (card buttons inert this long after appearing)
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

### c.3 nuketown additions

`nuketown.agents.<n>.{network.egress, network.proxy, interactive, claudeCode.lockdown, homeMode}` and the broker `SIGN` kind (§a.3 N8–N13). loom sets two agents:

```nix
nuketown.agents.${cfg.agent.name} = {          # resident, default "ada", uid 1100
  enable = cfg.agent.enable; uid = cfg.agent.uid; role = "software";
  sudo.enable = cfg.agent.sudo == "approval";   # nuketown's option is sudo.{enable,commands}; guarded by the N1 assertion below
  persist.directories = [ "projects" ".claude" ];   # working copy + harness state (conversations, login)
  extraGroups = [ "loom-switch" "systemd-journal" ];   # omanix's residents.nix adds "omanix-resident" (§0.3: loom never names omanix)
};
nuketown.agents.${cfg.reviewer.name} = {       # reviewer, default "reviewer", uid 1101
  enable = cfg.reviewer.enable; uid = cfg.reviewer.uid; role = "review";
  interactive = false;                           # N9
  network.egress = "proxy-only";                 # N8
  persist.directories = [ ];                     # login lives in /persist/var/lib/loom/reviewer/auth (0700 reviewer)
  claudeCode = { enable = cfg.reviewer.harness == "claude-code"; lockdown = true; };   # N10
};
```

The reviewer is not in `loom-switch`, `systemd-journal`, `omanix-resident` or `.authorized_keys`, and has no ssh key.

**Mapping and the N1 guard.** nuketown's `sudo.enable = true` installs NOPASSWD sudo rules for `sudo-with-approval` and `sudoex-run`. Today `sudoex-run` is `exec "$@"`, so without N1 the mapping would be password-less root. loom asserts `cfg.agent.sudo == "approval" ⇒` the nuketown in use provides N1 (detected through the option N1 adds), with the message "D8 approval sudo needs nuketown with the sudoex-run token fix (N1)". The broker socket and group no longer depend on `sudo.enable` (N2).

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
  host.yaml  user.yaml (password hash, neededForUsers)  data.yaml (Wi-Fi PSKs, app tokens)  agents/<n>.yaml
.sops.yaml             # GENERATED from keys.nix + machine.nix
.authorized_keys       # GENERATED: humans + host + agents            (silo transport, F2/F5; never deleted)
CODEOWNERS             # GENERATED: humans + host; NEVER agents      (silo master gate, F4; never deleted)
allowed_signers        # GENERATED: <name>@human|host|agent principals (git verification in any clone)
.loom/install-cache.pub   # optional per-host install cache key (§e.3)
.gitignore             # result, result-*
CLAUDE.md              # host notes for the resident (§d.4)
.claude/skills/        # optional host-local skills (ordinary reviewed files)
```

**Who writes which file.** No file is restricted. Every change reaches the machine only through a human-signed switch. The last column lists facts a change always raises (D5).

| File | Written by | Facts when changed |
|---|---|---|
| `configuration.nix`, `home.nix`, `modules/**` | resident, terminal user | through the evaluated facts only (highlight, units, ports, packages) |
| `flake.nix`, `flake.lock` | `omanix plugin add`, `omanix update`, update timer, human | `inputs.*` (new input, changed `original`, follows, downgrade, unverified release, transitive override, rev change outside `loom.trust.releases`) |
| `machine.nix` | installer, `loom unlock`, `loom keys rotate` | highlight critical (boot, LUKS, `loom.secrets.*`, Secure Boot) |
| `keys.nix` + generated files | installer, `loom keys add-human/remove-human/sync` | `trust.*` (always escalates) |
| `hardware.nix`, `hardware.json` | installer, `loom hw regen`, `omanix hw probe --write` | boot.* and kernel modules via the highlight view |
| `secrets/**` | `omanix secret set` (encrypt-only), `loom keys` (re-encrypt) | `secrets.files` key names; `trust.sopsRecipients` |
| `CLAUDE.md`, `.claude/skills/**` | anyone | `paths` only ("agent notes changed"); no system effect |
| `.claude/settings*.json`, `.claude/hooks/**`, `.mcp.json`, `.envrc`, `.vscode/**`, `.gitattributes`, `.githooks/**` | anyone | `paths` class `repo-exec` (high, escalates). These run code as the human when the human opens a coding harness, a direnv shell or an editor in `~/omanix-host`. |

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
  loom.agent = { name = "ada"; harness = "claude-code"; sudo = "none"; };   # D8: written explicitly

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
| `CODEOWNERS` | humans + host (+ enroll in the mint commit); **never agents** | silo pre-receive on non-gate refs (F4) | the agent key can push **only `gate/*` and `refs/dit/*`** (new or fast-forward; silo checks no CODEOWNERS there, and switchd ignores them); master moves only by humans or by switchd (host key) after a promoted switch |
| `allowed_signers` | `<name>@human namespaces="git" <key>`, `<host>@host …`, `<n>@agent …` | `git log --show-signature` in any clone; `/etc/loom/allowed_signers` is built from the **running** generation | switchd requires the approval signature from a `*@human` principal of the running generation |
| `.sops.yaml` | creation rules: host + humans' `age` + recovery, per file in `secrets/` | sops | the agent can encrypt to recipients but never decrypt (it holds no identity) |

`checks.keys-sync` re-renders and compares byte for byte; switchd runs the same check on every proposal and refuses a mismatch. **Refused regardless of signer:** a commit that deletes `.authorized_keys` or `CODEOWNERS` (F5), or that leaves `loom.keys.humans` with no owner or more than one.

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
- Every change: edit → `omanix check` → commit (signed, with the Request-Id trailers) → `omanix propose`.
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
- **What the enrollment key can do.** From mint until the installer's enrollment push, `enroll.key` can push `master`, because it is in `.authorized_keys` and `HEAD:CODEOWNERS` (F2, F4). It cannot remove the owner (F1), it is never in `allowed_signers`, and it is never a sops recipient. **It can, however, rewrite or force-push `master`, including adding its own attacker keys to both files (F4 has no fast-forward or content check).** A lost or stolen stick before install is handled by `configure revoke-enroll <id>` (§e.2 step 7). The installer refuses to enroll if silo's `master` ≠ `sidecar.host.commit` (§g.11).
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
   - **agent sudo** (D8). The question is: "Should <agent> be able to ask you for administrator (sudo) commands? Each one shows an approval dialog. Approved commands bypass the reviewed change pipeline." Answers are `none` (default) or `approval`, written to `loom.agent.sudo`. The installer asks again with this answer preselected.
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
  - **Verify the chain before trusting `master`** (`loom audit --from-silo`, mandatory here). It starts from the owner-signed mint commit (signed by the `owner = true` key of its own tree). Every later commit on `master` must be either a host-signed install record directly after the mint (or directly after a human-signed `authorize` commit), or a human-signed approval merge that passes §g.7.3 rules 1–2 against the `allowed_signers` of its first parent. The host key is in `CODEOWNERS` and can force-push `master` (F4), so a compromised host could otherwise rewrite it. If the tip fails the check, the installer shows a red screen naming the first invalid commit and offers two choices: install **the last valid approval merge** (the default), or stop.
  - Test images bake `loom.silo.host = "silo.test"`; release images bake `silo.loom.farm`. There is no cmdline override of the silo host.
- Else: **fresh** mode. The installer asks the configure questions in gum forms and runs the same `loom-mint` engine. **There is no other computer, so the owner key must be one of these:**
  - **FIDO2 on this machine** (recommended): `ssh-keygen -t ed25519-sk -O resident -O verify-required -O application=ssh:omanix-<host>` on a plugged-in token. The token's PIN and touch are required.
  - **A software key generated here**: see "Owner key generated on this machine" below.

  A pasted public key alone is accepted only as an **additional** human key: it can't make the first push.
  - **Online:** there is no enroll key. After install, the owner key signs and pushes the **final** tree directly (§g.11, fresh variant). That is one push, and the repo is created with `.owner_key = owner`.
  - **Offline:** the first push waits for the first-boot step `repo-publish` (§e.9). Until then the repo id is unclaimed on silo, and the id is computable locally (machine-id, the rendered files), so anyone who pushes first would become owner (F1, F8). Therefore, **until `repo-publish` succeeds, the resident agent does not run**: every nuketown agent unit (and the agent's `user@<uid>` linger) carries `ConditionPathExists=/persist/var/lib/loom/firstboot/repo-publish.done` (set by `loom.agent` config in every mode). The installer writes that marker itself whenever the repo is already human-owned on silo (preconfigured, reinstall, fork, or a successful fresh-online push), so only offline fresh installs wait. No other local user exists besides the human. `repo-publish` also detects a repo that someone else claimed (§e.9).

**Owner key generated on this machine** (D6/D10). This is offered in every mode: in fresh mode as the owner, and in preconfigured or reinstall mode as an additional human key.
- Screen text: "Generate an SSH key on this computer to control its configuration. It is protected by a passphrase you type when you approve changes. A FIDO2 security key is safer: it can't be copied off this disk. Use this option for VMs and for trying omanix without a token."
- Passphrase:
  - entered twice;
  - pwquality score ≥ 3, otherwise refused;
  - must differ from the disk passphrase;
  - may equal the login password only when its score is ≥ 3, the same rule as the disk passphrase. **On the installed system** (`loom keys add-human --generate`, §g.12) with a resident agent enabled, a passphrase equal to the login password is refused.
- Generation: `ssh-keygen -t ed25519 -a 100 -C "<user>@<host> omanix" -f /run/loom/keys/id_ed25519`, on tmpfs, with the passphrase fed through a pty to ssh-keygen's own prompt. **The passphrase is never on argv or in the environment**, in the installer or on the installed system (where the agent could read `/proc/<pid>/cmdline`).
- Written to the installed home after step 6 mounts it:
  - `/mnt/home/<user>/.ssh/` with mode 0700, owner uid 1000, gid `users`;
  - `id_ed25519` (0600) and `id_ed25519.pub` (0644).

  For FIDO2, the key handle files `id_ed25519_sk{,.pub}` go to the same place. `/home` is a persistent subvolume (H2), so the files survive reboots with no impermanence entry.
- `keys.nix`: `loom.keys.humans.<user>-<host> = { key; owner = <fresh mode>; localPath = "~/.ssh/id_ed25519.pub"; }`.
- **`~/.ssh` is not managed by home-manager** (D9). The human HM profile may not declare any `home.file` target under `.ssh/`, and `programs.ssh` in HM is forced off. SSH client settings go to `/etc/ssh/ssh_config` via `programs.ssh.extraConfig`. `checks.hm-unmanaged-paths` enforces this for `.ssh/` and `.gnupg/`. The read-only HM git config may **reference** the key (`user.signingKey = ~/.ssh/id_ed25519.pub`, `gpg.format = ssh`), generated from `loom.keys.humans.*.localPath`.
- Final screen: "This key exists only on this disk. If the disk dies and you have no other human key, you keep your data through your system encryption key, but you must fork the configuration repo (§g.12). Add a FIDO2 key or another computer's key any time with `loom keys add-human`."

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
- Disk passphrase. "Same as login" is allowed only when the score is ≥ 3. The installer refuses a disk passphrase that parses as a system encryption key (§g.14).
- TPM PIN, if chosen.
- Software owner key passphrase, if that option was chosen (above).

**4a. Agent (V3, D8).** First: **Use an AI agent?** *Yes* (the resident `ada` and the reviewer are set up; each signs in through its own normal login after first boot), *Later* (set up, signed out), or *No* (`loom.agent.enable = false`: no residents; everything works through the menu how-tos and your own commits). Then, unless the answer is *No*, the sudo question below. In preconfigured and reinstall mode, the repo's values are preselected.

> **Can <agent> ask for administrator commands?**
> No (recommended): <agent> changes this computer only through reviewed changes, and anything sensitive needs your approval.
> Yes, with approval: <agent> may also request individual `sudo` commands. Each one opens an approval dialog. An approved command runs as root outside the review pipeline. Root can undo every protection the review pipeline gives (card history, approvals, the request record), so treat each approval as handing over root itself.
> You can change this later. Turning it on needs your key.

The answers are written to `loom.agent.enable` and `loom.agent.sudo` (`"none"` | `"approval"`) by `loom-hostgen` in the install commit.

**5. System encryption key** (replaces "Recovery kit"; §g.14).
- Generated in installer memory from `getrandom`. The live image has no swap.
- Shown once as text in the canonical format (`SEK1-XXXX-…`, 9 groups) and as a QR code.
- Screen text: "This is your **system encryption key**. It unlocks this disk and your encrypted settings when everything else is lost: a dead TPM, a lost security key, a forgotten passphrase, or a reinstall. Write it on paper and keep it somewhere safe. Omanix does not store it anywhere and cannot show it again. Anyone who has it can read this computer's disk."
- **Paper check:** after the user confirms it is written down, the screen clears and the user types the **complete key back from paper**. It is accepted only if it parses and its `fp` equals the generated one; otherwise the key is shown again and the check repeats. (The check group only detects a misread character; it cannot correct one, so every group must be verified from the paper copy.) This happens before §e.7 wipes the bootstrap slot, so a disk is never left with an unverified SEK as its only recovery path.
- The key is never written to the stick, the disk or the log. The installer keeps only the derived values (`K_luks` for step 6, the age recipient, and the fingerprint).
- **Reinstall mode:** the screen first asks "Do you have this computer's system encryption key?" If the user types it and its fingerprint matches `loom.secrets.recovery.fingerprint`, it is **kept**: the same key unlocks the new disk, and secrets stay readable (§g.12). Otherwise a new one is generated and shown.

**6. Partition and FDE** (§e.7). **7. Secure Boot** (optional). **8. Keys, secrets, install** (§e.8). **9. Enrollment** (§g.11). **10. Finish** (§e.8).

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
| unlock methods | capability matrix (§e.6) | machine.nix | `loom.disk.unlock.methods` |
| Secure Boot / loader | probe + choice (D4, D7) | machine.nix | `loom.boot.secureBoot.enable`; `loom.boot.loader` only when not the default |
| SEK | §g.14 | machine.nix | `loom.secrets.recipients.recovery`, `loom.secrets.recovery.fingerprint` |
| host age key (generated) | — | machine.nix | `loom.secrets.recipients.host` |
| human key (FIDO2, existing pubkey, or generated passphrase software key, D6) | key-type allowlist; software ⇒ passphrase (D10) | keys.nix | `loom.keys.humans.<n> = { key; owner; localPath; age; };` |
| host / agent ssh keys (generated) | — | keys.nix; `secrets/agents/<n>.yaml` | `loom.keys.host`, `loom.keys.agents.<n>` |
| use an AI agent (yes / later / no) | enum | configuration.nix | `loom.agent.enable` (false only for "no") |
| agent name / harness | `^[a-z][a-z0-9-]{0,15}$` / catalog enum | configuration.nix | `loom.agent = { name; harness; … };` |
| approval sudo for the resident (D8) | yes/no, default no | configuration.nix | `sudo = "none";` written explicitly, `"approval"` on yes |
| theme, default apps, apps | catalog enums | configuration.nix | `omanix.theme.default`, `omanix.defaults`, `omanix.apps.<n>.enable` |
| hardware | loom-detect + `nixos-generate-config --no-filesystems` | hardware.json / hardware.nix | whole files, plus `omanix.hardware.quirks.<n>.enable = true;` per matching probe (§f.2.6) |
| stateVersion | release nixpkgs version | machine.nix / home.nix | `system.stateVersion`, `home.stateVersion` |
| Wi-Fi used during install | — | **not in the repo** | if the user ticks "remember", an NM keyfile in `/persist/etc/NetworkManager/system-connections/` (typed on this machine; nothing is copied from anywhere) |

**Commits.**
1. **Mint** (configure skill on the user's existing computer, or fresh mode in the installer; owner-signed, owner-pushed, §g.11): the template rendered from the configure answers, `keys.nix` with humans and `enroll`, the generated files, and a stub `machine.nix` with only `loom.host.id`. The mint commit is not expected to build (`checks.keys-sync` still passes on it).
2. **`install: apply answers`** (host-signed): sidecar answers re-rendered over the mint files. In fresh mode this commit carries all the answers.
3. **`install: <host> on <disk>`** (host-signed): `machine.nix`, `hardware.{nix,json}`, `secrets/*`, `keys.nix` (host and agents added, any generated human key, `enroll = null`) and the `loom keys sync` output.
4. First boot deploys commit 3. Commits 2–3 are install records made by deterministic code; switchd accepts them **only as the installed baseline**, never as an approval. **Every later switch needs a human-signed approval** (H5).

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
- Plymouth asks for passwords through **`loom-askpass`**, the initrd password agent of §g.14. It replaces `systemd-ask-password-{plymouth,console}`, and the prompt is themed from omarchy.

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
   - `cryptsetup luksAddKey --key-file /run/loom/bootstrap.key --pbkdf argon2id --new-keyfile - <dev>`, with stdin = `hex(K_luks)` (§g.14);
   - then `cryptsetup token import --key-slot <n>` of the `loom-sek` token with `state: "active"` (schema in §g.14).

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
   - the agent SSH ed25519 key per agent, written into `secrets/agents/<n>.yaml` and delivered by nuketown each boot;
   - `/persist/etc/machine-id` from the sidecar (fresh mode: newly minted);
   - if chosen in step 0, the software owner/human key into `/mnt/home/<user>/.ssh/` (§e.5).
5. **Secrets.**
   - Render `.sops.yaml` with recipients host + human* + `recovery`. `recovery` is the age recipient derived from the system encryption key (§g.14).
   - `sops -e` for `user.yaml` (password hash) and `agents/<n>.yaml`.
   - Existing human-only `data.yaml` entries are re-encrypted with `sops updatekeys` if the YubiKey identity is present. Otherwise they are listed for the first-boot prompt.
6. **Commit.** `loom-hostgen` (§e.5a) writes `machine.nix` (device, unlock, recipients, `loom.secrets.recovery.fingerprint`, Secure Boot, stateVersion), `keys.nix` (host and agent keys added, any human key generated here, `enroll = null`), `hardware.{nix,json}` with the quirk enables, and the answer lines of `configuration.nix` (`loom.agent.enable`, `loom.agent.sudo`). `loom keys sync` writes `.authorized_keys` and `CODEOWNERS` in their **final** form (§g.11): the enroll key is gone, and host, agent and human keys are present. Commit `install: <host> on <disk model>`, signed with the host key.
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
9. **Enrollment** (§g.11).
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
    - Show the summary: unlock methods, system encryption key confirmed, owner key (kind and where it lives), agent (`yes` | `later` | `no`) and agent sudo (`none` | `approval`), host id, enrollment state. Reboot.

### e.9 First boot (`loom.firstboot.steps`, idempotent, state in `/persist/var/lib/loom/firstboot/`)

1. **unlock-finalize** (if `tpm2*`).
   - The user unlocked with the passphrase or FIDO2, and Secure Boot is now final.
   - Run `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 [--tpm2-with-pin=yes]`.
   - Test the unseal with `systemd-cryptsetup attach --test`, or the equivalent token test.
   - Record the result in `/persist/var/lib/loom/unlock.json`.
2. **Enrollment catch-up** (`network-online`; idempotent):
   - **enroll-retry** (preconfigured mode, enrollment pending): the same push as §g.11 with `/persist/var/lib/loom/enroll/enroll.key`. On success the key is shredded.
   - **repo-publish** (fresh mode, offline at install). This step is **interactive**. The onboarding card says "Publish this computer's configuration to silo". Then:
     - **pre-check, immediately before the push:** `git ls-remote` of the repo must fail with `repository not found` (F7);
     - the owner key signs and pushes `master`, needing FIDO2 touch and PIN or the software key passphrase;
     - silo creates the repo with `.owner_key = owner` (F1);
     - the §a.4 HEAD check runs, and a `gate/probe-<rand>` push with the owner key must be accepted;
     - on success, write `/persist/var/lib/loom/firstboot/repo-publish.done`, which lets the resident agent start (§e.5 step 0).

     **Squatted id.** If the pre-check finds the repo already exists, or the push is refused with `access denied` (someone else is `.owner_key`), the step stops with "Someone else created this computer's repository on silo before it was published. It can't be used." and offers `loom fork` (§g.12): a new machine-id and id, the owner key pushes first, and secrets are carried over (the fork re-derives from the current SEK and shows a new one for the new id). The agent stays stopped until the fork's publish succeeds.

     Until this step is done, `loom status` shows `enrollment: unpublished`, switches work from the local mirror only, and the resident agent does not run.
2a. **owner-key-local** (preconfigured mode, and reinstall or fork when the human key is not on this disk). Approvals need a local private key or FIDO2 handle (§g.7.2), and the installer never copies credentials, so in preconfigured mode the new machine has neither. This interactive step runs as the human.
   - For an `sk-ssh-ed25519` human key created with `-O resident`, it runs `ssh-keygen -K` in `~/.ssh` (PIN plus touch) and keeps the handle whose public blob equals a `loom.keys.humans` key.
   - For a software key, it says that the key lives on the configuring computer and offers two paths: (i) approve there (`loom card export` / `loom approve --card`, then `loom propose --approval-from-silo`, §g.7.3), or (ii) `loom keys add-human --generate`, whose card is approved on the configuring computer.
   - When `localPath` is null, `loom-approve-sign` finds the key by matching `~/.ssh/*.pub` and recovered handles against the running `loom.keys.humans`, so no card is needed before the first local approval. The `localPath` hint is written by the next card. The welcome checklist shows this step until a local key works.
3. **secrets-prompt**: for each `loom.secrets.prompted.*` entry still missing (Wi-Fi PSK and similar), ask once in the human session, encrypt, commit (host-signed, `provenance.kind = "maintenance"`) and propose. The card appears right away and the human approves it, on the configuring computer if step 2a found no local key.
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
- `/agents` is reset from `@agents-blank` in initrd. This is nuketown rollback with nested-subvolume delete, and it keeps `@agents-prev` for one boot.
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
| a resident's home (`/agents/<n>`, reset every boot) | `nuketown.agents.<n>.persist.{directories,files}`; omanix persists `projects` and `.claude` for the resident; the reviewer persists nothing in its home |
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
- `misc.disable_autoreload = true`, plus one `hyprctl reload` per session **right after `switch-to-configuration test`** (which re-runs HM activation through `home-manager-<user>.service`) and before the watchdog loop. The watchdog's `configerrors` and IPC checks therefore test the new Lua (§g.8 step 5a). A rollback reloads again against the old files.

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

**GUI changes are runtime state.** A kept tool writes `~/.local/state/omarchy/**` or an overlay under `~/.local/state/omanix/` and nothing else (§f.4.4). It never touches the host repo or switchd. After a change, the tool shows a toast ("Scale 1.25 (this session) · Make it stick"), and the chat panel shows a "Make <area> stick" chip until the change is stuck or reset (§f.4.6, §h.6).

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
- Start `omanix-session-state.service`, which writes `/run/omanix/session/<uid>/runtime.json` (0640, group `omanix-resident`) on every overlay, theme or toggle change: **typed keys only** (theme name, wallpaper path, monitors as output/mode/position/scale/vrr, `gdkScale`, monospace font, shell.json delta keys, overlay keys parsed by the kv formats and the recording `hl.*` stub, toggles) plus each overlay's sha256. It holds no file contents and no free text. The resident reads this; the reviewer cannot (U9).

**First login** (once, gated on `done/first-login`, inside session init):
1. Copy app-owned seeds only if absent: `btop/btop.conf`, `fcitx5/**`, `chromium/Default/Preferences`, `opencode/opencode.json`, `omarchy/branding/{about,screensaver}.txt`.
2. Create `~/.gitconfig` with a header (git reads it after the XDG file; `--global` writes it).
3. The re-expressed `provision-user` steps: xdg-user-dirs, gtk bookmarks, keyring, mise base, quirk runtime seeds (e.g. `vm-no-animations` toggles), and `OMARCHY_THEME_WAIT=1 omarchy-theme-set <omanix.theme.default>`. The human's own coding harnesses get **no** omarchy/omanix skill links: the resident carries the skills.
4. omarchy's first-run invitations (`omarchy-*-invitation`, default-agent picker) are not shipped; the welcome flow (§h.7) replaces them.

**Never HM-owned:** `~/.ssh/` (D6's generated software owner key lives there; `programs.ssh` in HM is forced off), `~/.gnupg/`, `~/.claude/` and the other harness homes of the human, `~/.local/share/applications/`, `~/.config/systemd/user/` (`checks.hm-unmanaged-paths`).

#### f.4.6 Make it stick, and settling overlays

1. The human chooses **Make it stick** (toast, chip, or menu "Make my look permanent").
2. The chat surface runs `omanix-runtime-snapshot <area>` **as the human**. Areas: `look`, `hypr`, `shell`, `theme`, `font`, `monitors`, `input`. The output is code-generated JSON (`loom.snapshot/v1`): typed keys and values, the overlay paths and their sha256, and, for Lua overlays that don't parse into typed keys, the overlay text. The panel shows a preview chip and pre-fills (unsent) "Make my current <area> permanent."
3. On Send, chatd records the turn with the snapshot as an attachment of `kind = "runtime-snapshot"`. chatd validates it against `loom.snapshot/v1`; the **typed part** (keys, enum/regex-checked values, shas) is passed to the reviewer as part of the request so it can check the diff against what the human was looking at. Free Lua text is never passed to the reviewer (only its sha).
4. The resident's `look` skill maps the snapshot to options: theme → `omanix.theme.default`; font → `omanix.fonts.monospace`; monitors → `omanix.hyprland.monitors` + `gdkScale`; shell → `omanix.shell.settings`; known hypr keys → `omanix.input` / `omanix.keybinds` / `omanix.hyprland.settings`; anything else in `hypr/<f>.lua` → `omanix.hyprland.fileLua.<f>` (same slot as the overlay, before toggles); the `hyprland` overlay → `omanix.hyprland.extraLua`. For each whole-file area it absorbs, it sets `omanix.runtime.absorbed.<area> = "<snapshot sha>"`. Free Lua that lands in `fileLua`/`extraLua` is code that runs as the human, so it is a critical `session` fact (§g.4.1). The facts code compares its sha with the attached snapshot's overlay sha, so the card says "identical to what you had on screen", or flags that it is not.
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

## g) Change pipeline and trust

This section is the path from something the human asks for to a switched generation. The single rule (H5): **the tip loom-switchd activates is always a human-signed approval merge commit**; the watchdog's automatic rollback to the generation already running is the only exception.

### g.1 Principals

| Principal | Unix identity | Holds | Can | Cannot |
|---|---|---|---|---|
| human | `<user>`, uid 1000, wheel (sudo with password; N14 restricts nuketown's `host-shell` polkit rule to agent targets, so there is no password-less `machinectl shell root@`) | human ssh key(s): FIDO2 token, or `~/.ssh/id_ed25519` with a passphrase (D10); the SEK on paper | chat, sign approvals, edit the repo in a terminal, `sudo` | (all limits are on the other principals) |
| resident | `ada`, uid 1100 (`loom.agent.name`) | agent ssh key (sops → `/agents/ada/.ssh/id_ed25519`); its own model login | edit its working copy `~/projects/host`, commit (agent-signed), `loom propose`, push `gate/*` and `refs/dit/*`, post agent chat turns, read `runtime.json` | read the human's home (0700), write ledger turns as the human, send `SIGN`, push `master` (not in CODEOWNERS), read `/run/loom/review/*`, reach the reviewer, sudo (unless D8 `"approval"`, a critical fact) |
| reviewer | `reviewer`, uid 1101, `interactive = false` | its own model login (`/persist/var/lib/loom/reviewer/auth`, 0700) | read one bundle, write stdout | network beyond the proxy, any write outside its auth dir, any tool use, any memory between reviews |
| host | root; ssh host key `/persist/etc/ssh` | host ssh + age keys | push `master` after a passed switch, author install records, update and maintenance proposals | count as an approval |
| switchd | root `loom-switchd.service` | nonces, ledger read, `/persist/var/lib/loom/*` | the pipeline in §g.3 | activate anything not bound by a valid approval |
| chatd | root `loom-chatd.service` | the request ledger | record and relay chat turns | call a model, run commands |
| eval / fetch | `DynamicUser` `loom-eval` (no network), `loom-fetch` (network, no repo write) | — | evaluate pure, fetch locked inputs | write the mirror, reach sockets |

`/etc/loom/allowed_signers` is generated from the **running** generation's `loom.keys`:
```
josh-yk@human  namespaces="git" sk-ssh-ed25519@openssh.com AAAA…
ada@agent      namespaces="git" ssh-ed25519 AAAA…
kestrel@host   namespaces="git" ssh-ed25519 AAAA…
```
The role is the principal suffix. switchd maps the signer principal from `git verify-commit` (`%GS`) to a role and never trusts author or committer fields.

### g.2 Request provenance (`loom-chatd`)

```
Quickshell omanix.chat (human uid) ──► /run/loom/chat.sock        (0660 root:loom-chat; peer uid must == loom.user uid)
                                            │
                                      loom-chatd (root, Type=notify; never calls a model, never runs commands)
                                            │  ledger: /persist/var/lib/loom/requests/ledger.jsonl (0600 root)
                                            ▼
loom-agent-bridge@ada (agent uid) ◄── /run/loom/chat-agent.sock   (0660 root:ada; peer uid must == ada)
```

- chatd is **recorder and relay**. A human frame is written to the ledger first, with `author` from `SO_PEERCRED` (never from the frame), and only then delivered to the resident as `{id, thread, text, attachments}`. The resident's frames are recorded with `author = agent:ada`; a resident frame claiming any other author is refused and the refusal logged.
- Agent → surface events (text deltas, activity rows, progress, questions, card references, §h.3) are relayed by chatd unchanged and recorded only as agent turns. Nothing the bridge sends can create a human record.
- **Intent prefill** (menu, chips, make-it-stick, "Ask ada" fallthrough) opens the panel with a draft. Nothing is recorded until the human presses **Send**; the record carries `surface = "intent"`, `intent = "<menu id>"`, and the text exactly as sent, edits included (`edited = true` when it differs from the template).
- Agent-offered choices (`question` events) clicked by the human are recorded with `surface = "agent-choice"`: real consent to the words, flagged on the card.
- **Dictation** records the transcript the human sent (`surface = "dictation"`).
- **Pasted text.** The composer reports paste events, and chatd records each pasted span's offsets in the turn (`pasted: [[start, end], …]`). A single insertion over 200 characters or 3 lines with no paste event is marked too. The card shows pasted spans as "text you pasted", and the reviewer gets them fenced as **untrusted data, not intent**: a README pasted into the composer is third-party content, like an attachment.
- **Tool actions.** The GUI Undo/rollback actions and the Change password dialog send a typed frame on `chat.sock`; chatd records it as a human turn (`surface = "undo" | "tool"`) with fixed text ("Undo: <subject>", "Change my login password").
- **Rejections** with a reason are recorded as human turns (`surface = "rejection"`) and delivered to the resident.

**Ledger record** (`loom.request/v1`, one JSON line):

```json
{ "schema": "loom.request/v1",
  "id": "r-01JBX6Q4M2…", "prev": "sha256:…", "ts": "2026-10-27T18:04:11Z", "thread": "t-01JBX6P…",
  "author": "human:josh", "uid": 1000, "session": "c2", "seat": "seat0",
  "surface": "chat|intent|agent-choice|dictation|rejection|undo|tool", "intent": "install.gaming.steam" | null, "edited": false,
  "text": "install steam and set it up for gaming", "pasted": [],
  "attachments": [ { "sha256": "…", "kind": "image|text|json|runtime-snapshot", "mime": "image/png", "bytes": 81233 } ] }
```

- The ledger is hash-chained; its head is written into every switch record, so an edit to old lines is detectable (only root can make one).
- Attachments are stored as `requests/blobs/<sha256>` (and delivered to `/agents/ada/inbox/<id>/`). **They are never sent to the reviewer**, which gets only `kind`, `mime` and `bytes` (an image is a free-form injection channel). The one exception is the validated typed part of a `runtime-snapshot` (§f.4.6).
- Retention `loom.chat.retention` (1 year); `loom requests gc` keeps every record a switch record references.

**How a proposal refers to requests.** The resident adds `Request-Id: r-…` trailers (one per contributing human turn). switchd collects them over `base..tip`:
- an unknown id, or an id whose author is not `human:*` → fact `provenance.invalid` (escalate);
- no ids and not every commit human-signed → `provenance.kind = "none"` (escalate; the reviewer is told "there is no human request");
- **every** human turn that follows an agent turn in its thread is sent with that agent turn, truncated to 500 characters and fenced `agent-authored, UNTRUSTED`. This is not limited to short replies: "sounds good, go ahead with what you proposed" takes its meaning from agent text. The reviewer is told that a justification resting only on agent-authored text is a mismatch;
- `provenance.stale` (escalates): a cited request older than `loom.chat.requestMaxAge` (24 h), a request from a different thread than the proposal's other requests, or a request id that already justified a promoted switch (each switch record lists the ids it consumed). The card says which one ("Linked request is 3 days old", "Request already used for the switch on <date>");
- any pasted span in a cited request sets `provenance.pasted` (escalates).

**Terminal users (no chat).** A human commits **signed with a human key** and runs `loom propose`. `provenance.kind = "terminal"`; the request shown is the human-signed commit messages with their signer principal ("Request: your own commit message (signed by josh-yk@human)"). That is not an escalation by itself. A commit authored by the resident without `Request-Id` never counts as terminal: the signer principal decides.

**Maintenance.** Host-signed commits made by deterministic tools carry `provenance.kind = "update" | "rollback" | "maintenance"` with fixed request text ("Scheduled update of flake inputs (no human request)", "Restore the state you approved on <date>", "Secret you entered at first boot: <name>"). A rollback or tool commit counts as human-started only when it cites a ledger record that the human uid sent (`surface = "undo"` or `"tool"`). Without one it is shown as "prepared by <agent>, not requested" and escalates (§g.10).

### g.3 Pipeline (switchd)

```
human ─chat─► chatd (ledger) ─► resident: edit ~/projects/host, commit (agent-signed, Request-Id)
   resident: loom propose ──bundle over /run/loom/switchd.sock──► switchd
            (and git push silo gate/<topic> with the agent key, for visibility and off-machine backup)
switchd: intake → signatures → structural refusals → fetch → eval → build → checks → FACTS → bundle → reviewer → card
card ─SIGN (root only)─► broker (human uid) ─► omanix.approval card ─► touch / passphrase
   ─► human-signed approval merge ─► switchd: verify → arm watchdog → test → health → promote → push master (host key)
```

One proposal at a time per host; `restartIfChanged = false`, `stopIfChanged = false`. State lives in `/persist/var/lib/loom/proposals/<tip>/`.

1. **Intake.** `loom propose [--ref <rev>] [--from-silo gate/<x>] [--queue]`, by any member of `loom-switch` (human, resident, host timers), streams `git bundle <deployed>..<tip>`; or switchd fetches the gate ref from silo with the host key. Data is unbundled into the root-owned mirror `/persist/var/lib/loom/host`. **Refuse** (exit 5) when the tip does not descend from the deployed commit ("rebase onto <sha>"), when an SEK rotation is in progress and the tip is not its recorded commit (§g.14), or when another proposal is mid-review (queued with `--queue`). A newer proposal from the **same thread** supersedes and withdraws the outstanding card.
2. **Signatures.** Every commit in `base..tip` must verify against the **running** `allowed_signers` with any role. Unsigned or unknown-key commits are refused (exit 2).
3. **Structural refusals** (no signature overrides them): the tree lacks `.authorized_keys` or `CODEOWNERS` (F5); `checks.keys-sync` fails on the tree; `flake.lock` has an unlocked node or one without `narHash` (`path:`, dirty tree); the "exactly one owner in `loom.keys.humans`" assertion fails.
4. **Fetch.** `loom-fetch` (DynamicUser, network, read-only mirror) runs `nix flake archive --json`; every node is fetched by `narHash`. For inputs in `loom.trust.releases` (running generation) it also fetches the tag object, runs `git verify-tag` against `/etc/loom/release-signers`, requires the tag's target to equal `locked.rev`, and fetches that release's own `flake.lock` (for `inputs.transitiveOverride`). For other git and GitHub inputs it checks with `git merge-base --is-ancestor` that `locked.rev` is reachable from the declared ref (`inputs.unreachableRev`). Offline → exit 5 "inputs not in store; connect to a network".
5. **Eval.** `loom-eval` (DynamicUser, `PrivateNetwork`, read-only mirror): `nix eval` with `pure-eval`, `restrict-eval`, `allow-import-from-derivation = false`. Outputs `toplevel.drvPath` and the **highlight view** — the running generation's `$current/loom/view.nix` applied to the new config — and the same view applied to the deployed generation's **recorded proposal tip** (from its switch record; the approval merge is never re-evaluated), so old and new are always compared through one function (U2). Errors are returned verbatim; **an eval or build failure produces no card** and goes back to the proposer (exit 1).
6. **Build.** Through nix-daemon (sandboxed), with substituters from the **running** `nix.settings` only. The built `drvPath` and `outPath` go into `facts.proposal.toplevel`; that store path is exactly what step 15 activates.
7. **Checks.** Into `results.json`: eval assertions and warnings; the host flake's `checks.<system>.*` named in the running `loom.switch.preflight.checks`; and, when `loom.switch.preflight.vm` resolves to on, the **preflight VM** (below) with a 180 s budget, recording `systemctl --failed` and `ss -Htlnu`. A failed check gives a card that can only be rejected (Approve hidden).
8. **Facts.** `$current/loom/facts compute --old … --new … --old-view … --new-view … --old-lock … --new-lock … --ledger …` → `facts.json` (§g.4).
9. **Bundle** (§g.5.2) → `/run/loom/review/<tip>/` (tmpfs, `root:reviewer 0750`).
10. **Review.** `systemd-run` with the reviewer unit properties (§g.5.1); stdout parsed as `loom.review/v1`. Timeout, non-zero exit, invalid JSON or schema violation → `review.status = "unavailable" | "invalid"`, escalated, no AI section. **The reviewer is skipped** (`status = "skipped"`) for (a) a human-started rollback (§g.10) whose tree equals an approved switch record's tree, (b) terminal proposals where every commit in the range is human-signed, and (c) `update` proposals that change only `flake.lock` and in which every changed input is a verified release (`release != null`); in both cases presentation is decided by facts and checks alone.
11. **Card.** `card.json` (§g.6) from ledger quotes, facts, review and results; `nonce` (128-bit) and `expires = now + loom.switch.approvalTtl`.
12. **Ask.** switchd sends the broker `SIGN {card, base, tip, tree, hostId, nonce, expires, factsSha, cardSha, author, committer, message}`; the broker shows it through `omanix.approval` (zenity fallback shows facts and "show diff" only). The resident is told "card #<n> waiting" through chatd. Without a broker (terminal-only or server) `loom card show <tip>` prints it and the client exits 3.
13. **Sign** as the human (§g.7.2) → an SSH signature over the commit object switchd specified → switchd assembles and writes the approval merge commit. `loom approve <tip>` in a terminal does the same on the pty (`loom-card-tty` renders the same blocks).
14. **Verify the approval** (§g.7.3). Any failure → refused, card stays open.
15. **Activate** (§g.8) exactly `facts.proposal.toplevel.outPath`: arm watchdog and dead-man timer, `test`, baseline-relative health, then promote or roll back. `loom.switch.keepClick = "escalated"` (default) also requires a "Keep these changes?" click inside the watchdog window for escalated cards.
16. **Record.** `switches/<n>/{card.json,facts.json,review.json,approval.sha,ledger-head,nvd.txt,journal-cursor}`.

**Preflight VM (the proposal's runner never runs).** The proposal's `system.build.vm` runner script and its `virtualisation.qemu.{package,options}` and `sharedDirectories` are agent-chosen host programs, so switchd **never executes them**. It builds only the guest toplevel of loom's `virtualisation.vmVariant` (`config.virtualisation.vmVariant.system.build.toplevel`, built in the nix sandbox) and boots it with `$current/loom/preflight-vm`, a QEMU binary and command line from the **running** generation. That runs in a transient unit with `DynamicUser=yes`, `PrivateNetwork=yes`, `DevicePolicy=closed`, `DeviceAllow=/dev/kvm rw`, `ProtectSystem=strict`, `ProtectHome=yes` and `TemporaryFileSystem=/persist /var /run /agents`. Only `/nix/store` is shared into the guest, read-only; the guest has no other host share and no network. loom's vmVariant module clears what a VM can't have: `boot.initrd.luks.devices`, disko, the impermanence binds (tmpfs `/persist`), sops (a fixed test host key), Secure Boot, and the TPM2/FIDO2 crypttab options. `checks.preflight-vmvariant` asserts the variant evaluates for every `eval-*` fixture. The VM test `preflight-runner-untrusted` sets `virtualisation.qemu.package` to a script that touches a sentinel and `sharedDirectories` onto `/persist`, and asserts that the script never runs and `/persist` is never exposed.

**Silo master.** After a promoted switch switchd pushes `master` with the host key. If silo's `master` is not an ancestor of the new commit (a human pushed directly from elsewhere), switchd first pushes the old silo tip to `gate/diverged/<sha>`, then updates `master`, and the next card notes it. switchd never deploys what silo `master` says without a valid approval chain from the deployed commit (`loom audit --from-silo` re-verifies the chain off the machine).

### g.4 Deterministic facts (`loom.facts/v1`)

#### g.4.1 Highlight view and list (D5)

`loom/lib/highlight/view.nix` is a function `config → JSON`, installed into every toplevel as `$out/loom/view.nix` and applied to both configs (§g.3 step 5). Store paths are **displayed** as `<pname>@<origin>` (origin `nixpkgs | omanix | loom | host | input:<name>`, from `definitionsWithLocations`), and each path records `definedBy: [host:<file> | input:<name>]`. **Change detection compares derivations, not names**: every store path in the view also carries its `.drv` hash, and "same name, different derivation" is a change (§g.4.3 `rebuilt`). Rebuild noise is hidden only when the `.drv` is identical, or when `nix-diff` shows that the only differing inputs are derivations from the nixpkgs input that are themselves reported as package upgrades. The **base list** lives in loom:

```
users.users.<n>.{uid,group,extraGroups,isNormalUser,shell,hashedPassword,hashedPasswordFile,password,
                 initialPassword,initialHashedPassword,openssh.authorizedKeys,linger}
users.groups.*.members ; users.mutableUsers ; users.users.root.*
security.* (whole subtree, sha per normalized sub-path; labelled rows for {sudo,sudo-rs,doas}.{extraRules,
            wheelNeedsPassword,extraConfig}, polkit.extraConfig, pam.services.<n>, wrappers.<n>.{owner,group,
            setuid,setgid,capabilities,source(drv)}, apparmor, tpm2, loginDefs)
nix.settings.* (every key) ; nix.extraOptions ; nix.package ; nix.buildMachines ; nix.distributedBuilds
nixpkgs.overlays (count + definedBy + sha of each overlay's source) ; nixpkgs.config (sha)
services.openssh.* (whole subtree; labelled: enable, ports, listenAddresses, settings, extraConfig,
                    authorizedKeysCommand, authorizedKeysCommandUser, authorizedKeysFiles)
networking.firewall.{enable,allowed*,trustedInterfaces,interfaces} + sha(extraCommands, extraInputRules)
networking.nftables.{enable,ruleset,tables} (sha)
boot.* (whole subtree; labelled: loader.*, kernelParams, kernelPackages(pname+version+drv), kernelPatches,
        extraModulePackages, kernel.sysctl, extraModprobeConfig, binfmt, kernelModules, blacklistedKernelModules,
        initrd.{luks.devices,network.*,secrets,systemd.services (content sha),availableKernelModules})
sha(system.activationScripts) ; sha(system.userActivationScripts) ; systemd.tmpfiles.rules (sha) ; systemd.generators
services.udev.{extraRules,packages} ; services.dbus.packages ; environment.etc.* (sha per target)
environment.{variables,extraInit,interactiveShellInit,loginShellInit,shellInit} (sha)
services.displayManager.autoLogin.* ; services.getty.autologinUser
loom.{keys.*,trust.*,highlight.*,reviewer.*,switch.*,update.*,chat.*,secrets.recipients.*,secrets.recovery.*,
      disk.unlock.*,boot.secureBoot.*,silo.*,agent.*}
nuketown.{humanUser,agents.<n>.{uid,sudo,devices,extraGroups,network,interactive,homeMode,claudeCode.settings(sha)}}
virtualisation.{docker,podman,libvirtd}.enable + their groups
home-manager.users.<human>: exec surfaces (below)
```

**Effects, not only options.** Option paths can't list every way NixOS hands out root, so the view is complemented by a **deny-by-default diff of built effects** (`effects`, §g.4.2), computed from both built toplevels:
- sha per file of `$out/etc/**`: critical under `polkit-1/`, `pam.d/`, `sudoers*`, `ssh/`, `nix/`, `udev/`, `modprobe.d/`, `sysctl.d/`, `systemd/` and `dbus-1/`, high elsewhere;
- `sw/share/polkit-1/**` and `sw/share/dbus-1/system-services/**`. NixOS links `/share/polkit-1` into the system path, so a package in `environment.systemPackages` that ships a polkit rule changes these and nothing else;
- every key of the final parsed `etc/nix/nix.conf` (`extra-trusted-users`, `extra-substituters`, `post-build-hook`, `accept-flake-config`, `builders`, `extra-sandbox-paths`, …);
- the nftables ruleset text, which could override nuketown's N8 egress rules;
- the initrd: its closure, its systemd units and its `/etc` (sha). The initrd sees the typed SEK (§g.14).

Any change under a critical effect path is critical. A file appearing anywhere under `etc/` that no option row explains is high.

**Human exec surfaces.** The resident can edit the human's HM config (V4), so code that runs *as the human* is a **critical** `session` fact. That uid holds the signing key and types its passphrase, so human exec amounts to root plus the signing seat. Covered:
- HM `home-files` paths (sha): `.bashrc .bash_profile .profile .zshrc .config/fish/** .config/environment.d/** .config/uwsm/env* .config/autostart/** .config/systemd/user/** .config/hypr/** .ssh/** .gnupg/** .config/git/** .local/share/applications/** .config/quickshell/**`, and any HM-installed QML or scripts under `$OMARCHY_PATH` overrides;
- **any** change to `.config/hypr/**` Lua, to `omanix.hyprland.{extraLua,fileLua}`, to `omanix.theme.extra.*`, or to an input that feeds them. omarchy's Lua has full `io`/`os` (`io.popen`, `os.execute`, `dofile`), so `hl.exec` is only a label, never the trigger;
- `hm-session-vars.sh` / `home.sessionVariables`, and `home.activation` entries by name **and body sha**;
- package-provided `etc/xdg/autostart/*.desktop`, session D-Bus services and systemd user units, in the human's profile or the system path;
- PATH collisions in the human's profile with `ssh ssh-keygen git gpg sudo loom omanix`;
- the system shell-init and env options and `system.userActivationScripts` from the base list.

`loom.highlight.extra` (listOf option path or glob) adds entries; it is itself in the view, so changing it is a critical fact. Base entries come from loom code in the running generation and **cannot be removed by a host**.

#### g.4.2 Schema

```jsonc
{
  "schema": "loom.facts/v1",
  "computedBy": "loom-facts 0.2.0 @ /nix/store/…-nixos-system-kestrel-…(running)",
  "host": "3f9c0a…", "base": "<sha>", "system": "x86_64-linux",
  "proposal": { "sha": "<sha>", "toplevel": { "drvPath": "/nix/store/…-nixos-system-kestrel.drv",
                                          "outPath": "/nix/store/…-nixos-system-kestrel" } },   // what step 15 activates
  "provenance": { "kind": "chat|terminal|update|rollback|maintenance|none",
                  "requests": ["r-…"], "invalid": [], "stale": [], "agentChoice": false, "pasted": false,
                  "agentPrepared": false, "terminalSigners": [] },
  "commits": [ { "sha": "…", "signer": "ada@agent", "subject": "bar: battery percent" } ],
  "paths": [ { "path": "modules/bar.nix", "status": "M",
               "class": "module|home|flake|lock|secret|trust-file|hardware|machine|keys|notes|repo-exec|other",
               "added": 12, "removed": 3 } ],
  "highlight": [ { "path": "users.users.josh.extraGroups", "change": "added|removed|changed",
                   "before": ["wheel"], "after": ["wheel","docker"], "severity": "critical|high|notice",
                   "label": "adds josh to docker (root-equivalent)", "definedBy": ["host:modules/dev.nix"] } ],
  "trust": { "allowedSigners": {"added":[],"removed":[]}, "authorizedKeys": {"added":[],"removed":[]},
             "codeowners": {"added":[],"removed":[]}, "sopsRecipients": {"added":[],"removed":[]},
             "substituters": {"added":[],"removed":[]}, "trustedPublicKeys": {"added":[],"removed":[]} },
  "units": { "system": { "added": [ { "name": "foo.service", "kind": "service|timer|socket|path|mount|automount|swap|generator", "privileged": true,
                                      "user": "root|<u>|dynamic", "wantedBy": ["multi-user.target"],
                                      "execStart": ["<pname>@nixpkgs/bin/foo --x"] } ],
                         "removed": [], "changed": [ { "name": "sshd.service", "user": "root",
                                                       "fields": { "ExecStart": ["<before>","<after>"] } } ] },
             "user":   { "added": [], "removed": [], "changed": [] } },
  "session": { "execSurfaces": [ { "path": ".config/hypr/autostart.lua", "sha": "…" } ], "activation": [],
               "autostart": [], "pathCollisions": [], "sessionVars": null, "freeLua": [ { "sha": "…", "matchesSnapshot": true } ] },
  "rebuilt": [ { "name": "sudo", "path": "security.wrappers.sudo.source", "referencedBy": ["wrapper:sudo"],
                 "drvBefore": "…", "drvAfter": "…", "nixDiff": "src: +1 patch" } ],
  "effects": { "etc": [ { "path": "polkit-1/rules.d/00.rules", "change": "added", "severity": "critical" } ],
               "share": [], "nixConf": [ { "key": "extra-trusted-users", "before": null, "after": "ada" } ],
               "nftables": { "changed": false }, "initrd": { "changed": false, "units": [] } },
  "ports": { "firewall": { "opened": [ { "proto": "tcp", "port": 8080, "iface": "*" } ], "closed": [],
                           "enabledBefore": true, "enabledAfter": true },
             "listeners": { "added": [ { "proto": "tcp", "addr": "0.0.0.0", "port": 8080,
                                         "source": "socket:foo.socket|option:services.foo.port|vm:ss" } ],
                            "removed": [], "complete": false },
             "exposedNew": [ { "proto": "tcp", "port": 8080 } ] },
  "inputs": { "added": [ { "name": "foo", "original": "github:bar/foo", "locked": { "rev": "…", "narHash": "…" } } ],
              "removed": [], "followsChanged": [], "unreachableRev": [],
              "transitiveOverride": [ { "node": "omanix/loom", "lockRev": "…", "releaseRev": "…" } ],
              "changed": [ { "name": "omanix", "fromRev": "…", "toRev": "…", "fromDate": "2026-10-01", "toDate": "2026-10-27",
                             "originalChanged": false, "release": { "tag": "v0.1.1", "verifiedBy": "release:josh-yk1" },
                             "trustedRelease": true, "downgrade": false } ] },
  "packages": { "added": ["obsidian-1.9.4"], "removed": [], "upgraded": [["firefox","143.0","144.0"]],
                "downgraded": [], "closureBytesDelta": 412000000, "nvdText": "nvd.txt" },
  "secrets": { "files": [ { "path": "secrets/data.yaml", "keysAdded": ["wifi/home"], "keysRemoved": [], "keysChanged": [] } ] },
  "diff": { "bytes": 18234, "truncated": false,
            "suspiciousText": [ { "file": "modules/x.nix", "line": 14, "match": "ignore previous instructions" } ] },
  "drift": { "unmanagedSwitch": false, "bootedOlder": false, "siloDiverged": false },
  "results": { "eval": "ok", "build": "ok", "checks": [ { "name": "host", "ok": true } ], "vm": { "ran": false } },
  "escalate": true,
  "escalationReasons": [ "highlight:critical users.users.josh.extraGroups", "ports:exposedNew tcp/8080" ]
}
```

#### g.4.3 How each fact is computed

Everything runs from `$current/loom/facts` (stdlib Python 3) except the view eval (§g.3 step 5).

| Fact | Source | Method |
|---|---|---|
| `paths`, `commits` | mirror | `git diff --numstat -M base..tip`; `git log --format=%H%x00%GS%x00%s` after verify. Class from a fixed path table: `flake.nix`, `flake.lock`, `secrets/**`, `.sops.yaml`/`.authorized_keys`/`CODEOWNERS`/`allowed_signers` (trust-file), `keys.nix`, `machine.nix`, `hardware*`, `home.nix`/`modules/home/**` (home), `.claude/settings*.json`/`.claude/hooks/**`/`.mcp.json`/`.envrc`/`.vscode/**`/`.gitattributes`/`.githooks/**` (repo-exec), `CLAUDE.md`/`.claude/skills/**` (notes), else module. |
| `highlight` | old and new view JSON | Diff keyed by option path, taking paths from the **old** view as well as the new (a vanished path counts as changed). Severity from `lib/highlight/severity.nix`: **critical** = users/groups (including password options), `security.*`, every nix setting (`nix.settings.*`, `extraOptions`, `package`, builders), `loom.keys.*`, `loom.trust.*`, `loom.reviewer.*`, `loom.highlight.*`, `loom.agent.*`, `loom.chat.*`, `nuketown.agents.*`, `services.openssh.*`, Secure Boot/unlock/recovery, autologin, udev rules, initrd content, the nftables ruleset, human exec surfaces; **high** = firewall, the rest of `boot.*` (sysctl, modprobe config, kernel and module packages, patches, binfmt), overlays, activation scripts, tmpfiles, generators, dbus packages, other `environment.etc`, docker/podman/libvirt, `loom.switch.*`, `loom.update.*`; **notice** = the rest. Labels come from a fixed template table (`labels.nix`), never from config text. |
| `trust` | trees at base and tip + views | Parse `.authorized_keys`/`CODEOWNERS`/`allowed_signers` (key blobs); sops recipients from `.sops.yaml` and each `secrets/*.yaml`'s metadata; substituters and keys from the view. |
| `units` | **built** toplevels | Each unit as systemd sees it: the base file plus every `<unit>.d/*.conf` drop-in, merged like `systemd-analyze cat-config` (NixOS delivers overrides of package units such as `nix-daemon`, `polkit` and systemd's own as `overrides.conf`). All unit types (`service timer socket path mount automount swap`) under `$out/etc/systemd/{system,user}` (following symlinks, plus `*.wants/` for `wantedBy`), `systemd.generators`, and every HM user's `home-files/.config/systemd/user`. Every key is compared; store paths are compared by `.drv`, so a rebuild with an identical drv is not a change. A unit is **privileged** when `User` is root (or unset without `DynamicUser`) or the human; when any `Exec*` line has a `+`, `!` or `!!` prefix (full root regardless of `User=`); when it has `AmbientCapabilities`, or a `CapabilityBoundingSet` beyond `CAP_NET_BIND_SERVICE`; or when it has `SupplementaryGroups` outside an allow-list (`audio video render input`). |
| `session` | built HM generation + system path | The human exec surfaces of §g.4.1: changed paths with sha; `home.activation` entries by name and body sha; package-provided autostart, D-Bus and user units; PATH collisions with the fixed security-tool set; hm-session-vars; free-Lua sha compared with the attached snapshot's overlay sha. |
| `ports.firewall` | views | `allowed{TCP,UDP}Ports{,Ranges}` and `interfaces.<i>.*`, with `enable` before and after. |
| `ports.listeners` | views + units + VM | (a) `Listen*` of new or changed socket units; (b) option paths in `loom.highlight.portOptions` (`services.openssh.ports`, `services.<x>.port`, `services.<x>.listenAddress(es)`, …); (c) `ss -Htlnu` from the preflight VM against the old generation's baseline. `complete = false` unless (c) ran. |
| `ports.exposedNew` | the rows above | a new listener whose port the new firewall allows, or any port when the firewall is disabled. |
| `inputs` | both `flake.lock` files + release tags | Pure JSON diff of `nodes`: root input added/removed, `original` changed, `locked.rev`/`lastModified`/`narHash` changed, follows changed. `downgrade` = new `lastModified` older. `release` = the tag verification from §g.3 step 4 for inputs in `loom.trust.releases`, which also requires the tag's target to equal `locked.rev`. **`transitiveOverride`** (critical): for each input in `loom.trust.releases`, every transitive node under it in the host lock must equal the matching node in that release's own `flake.lock`. Example: `omanix/loom` moved while omanix stays on its signed tag; nix uses the host lock for transitive nodes, so this would swap switchd, facts and the reviewer prompt for every later card. A `locked.rev` change of any input outside `loom.trust.releases` is **high** and shows `owner/repo`, the compare range as text and the commit count when `loom-fetch` can compute it. `unreachableRev` (critical): a git or GitHub rev not reachable from the declared ref, such as a fork-network commit under the same `original`. |
| `packages` | both toplevels | `nix store diff-closures old new` parsed (U16 stability); `nvd diff old new` kept as display text. |
| `rebuilt` | both toplevels' `.drv` graphs | For every store path referenced by a privileged unit's `Exec*`, a wrapper `source`, PAM, polkit, the kernel, the initrd or a base-list package, the old and new `.drv` are compared with `nix derivation show`. If they differ and `nix-diff` shows anything beyond nixpkgs-input derivations already reported as upgrades, a `rebuilt` row ("same name, different derivation") with a `nix-diff` summary is added. This covers a new body for a root unit's `script`, an overlay that patches sudo, and a same-version kernel patch. |
| `effects` | both built toplevels | §g.4.1 "Effects, not only options": sha per file under `etc/` and the listed `sw/share` trees, the final `nix.conf` parsed key by key, the nftables ruleset text, and the initrd closure, units and `/etc`. |
| `secrets` | sops files at base and tip | key names only (plaintext in sops YAML/JSON); values never decrypted. |
| `diff.suspiciousText` | added lines | Case-insensitive regexes from `lib/highlight/suspicious.txt`: `ignore (all )?previous`, `reviewer`, `approve this`, `system prompt`, `you are (an?\|the) `, `<\|`, zero-width and bidi control characters, base64 runs over 200 characters. |
| `drift` | `/run/booted-system`, `/run/current-system`, switch records, silo | booted or current toplevel not in any switch record (`sudo nixos-rebuild switch` outside loom, or a boot-menu older generation); silo master diverged. |
| `escalate` | all of the above | true if **any**: a critical or high `highlight`; any `trust` change; any critical or high `effects` change; any `rebuilt` row; a **privileged** unit added, removed or changed (any key, including `Environment` and drop-ins), or any timer or generator added; any `session` change; a `paths` change of class `repo-exec`; `ports.firewall.opened` or `exposedNew` non-empty; `inputs.added`, `originalChanged`, `followsChanged`, `transitiveOverride`, `unreachableRev`, `downgrade`, `trustedRelease && release == null`, or a `locked.rev` change outside `loom.trust.releases`; `provenance.kind = none`, non-empty `invalid` or `stale`, `pasted`, `agentPrepared` or `agentChoice`; `diff.truncated` or `suspiciousText`; any `drift`; any failed check. Notice highlights, non-privileged unit changes and package version changes are shown but never escalate on their own. |

`loom facts explain [<rev>]` runs the same code against the working copy; the resident runs it before proposing so it can tell the human what will be highlighted.

### g.5 Reviewer resident

#### g.5.1 Isolation

The review runs as a transient unit started by switchd:

```
systemd-run --wait --pipe --collect --unit=loom-review-<n> \
  -p User=reviewer -p Group=reviewer -p RuntimeMaxSec=<loom.reviewer.timeout> \
  -p ProtectSystem=strict -p ProtectHome=tmpfs -p PrivateTmp=yes -p PrivateDevices=yes -p PrivateIPC=yes \
  -p NoNewPrivileges=yes -p RestrictSUIDSGID=yes -p CapabilityBoundingSet= -p SystemCallFilter=@system-service \
  -p RestrictAddressFamilies="AF_INET AF_INET6 AF_UNIX" -p IPAddressDeny=any -p IPAddressAllow=127.0.0.1/32 \
  -p TemporaryFileSystem="/run /agents /persist /var" \
  -p BindReadOnlyPaths=/run/loom/review/<tip>:/bundle \
  -p BindPaths=/persist/var/lib/loom/reviewer/auth:/state \
  -p Environment="HOME=/state CLAUDE_CONFIG_DIR=/state/claude HTTPS_PROXY=http://127.0.0.1:3128 NO_PROXY=" \
  $current/loom/review/run /bundle
```

- **Two network layers:** `IPAddressAllow=127.0.0.1` plus the N8 nft rule (`meta skuid reviewer ip daddr != 127.0.0.1 drop; … tcp dport != 3128 drop; … udp drop`). The only reachable thing is `loom-egress`, a DynamicUser CONNECT proxy that resolves and admits only `loom.reviewer.egress.allow` (U3).
- `/state` (= `/persist/var/lib/loom/reviewer/auth`) is the only writable path. It holds the harness login (OAuth refresh) and nothing else, and it is 0700 reviewer, unreadable by `ada` (N13). Before each run switchd removes everything under `/state/claude` except `.credentials.json` and the harness's account file (`.claude.json`), and everything else under `/state`.
- `run` and the system prompt (`$current/loom/review/prompt.md`) come from the **running** generation, never from the bundle. With `harness = "claude-code"` it runs `claude -p --output-format json` with every built-in tool disabled, an empty strict MCP config, no hooks, no skills, no CLAUDE.md discovery, no setting sources, and the bundle on stdin (U4, U5); with `"api"` it does one Messages call with a structured-output schema; `"replay"` returns canned JSON for tests and the demo. Each review is a fresh session with no memory.
- **Sign-in:** the reviewer has its own login, done through the "Agent sign-in" GUI (§h.3.6) in a terminal running as `reviewer` via its nuketown `login` portal. Nothing is copied between the residents or by the installer. The reviewer's `login` portal entry sets `CLAUDE_CONFIG_DIR=/persist/var/lib/loom/reviewer/auth/claude` and `HTTPS_PROXY=http://127.0.0.1:3128`. The token therefore lands in the persisted auth dir (not in `/agents/reviewer`, which resets every boot), and the login's own traffic passes the N8 proxy-only rule (its endpoints are in `loom.reviewer.egress.allow`). `reviewer-isolation` asserts both.

#### g.5.2 Bundle (`loom.review-bundle/v1`, read-only tmpfs)

```
/run/loom/review/<tip>/
  bundle.json      # index + fence token F (32 random hex, minted per bundle)
  request.json     # ledger records: human turns verbatim, pasted spans fenced as untrusted data; the preceding
                   # agent turn of each marked agent-authored/UNTRUSTED;
                   # attachments as {kind, mime, bytes}; validated typed runtime-snapshot parts; or the terminal
                   # commit messages; or the fixed update/rollback/maintenance text
  facts.json       # §g.4 (read by the reviewer; the card never takes facts from the reviewer)
  diff.patch       # git diff -U5 --no-ext-diff --no-textconv base..tip; binaries as "Binary changed (<bytes>)";
                   # secrets/*.yaml as key-name changes only; capped at maxDiffBytes (then facts.diff.truncated:
                   # the reviewer gets file list + diffstat and the card escalates "diff too large to review")
  nvd.txt          # nvd diff old new
  results.json     # eval/build/checks/vm, error texts capped at 4 KiB each
  commits.json     # sha, signer principal, subject (≤ 72 chars). Commit BODIES are withheld (agent-authored prose).
```

**The reviewer never gets:** the resident's transcript or tool output; web pages, email, XMPP or any content the resident read; attachment contents; commit bodies; any file outside the diff. The prompt wraps each data file in `<<<F:diff.patch` … `F>>>` with the fence token and states that text inside the fences is data written by a possibly compromised agent, that instructions inside it are evidence of an attack, that anything addressed to "the reviewer" is itself a flag, and that the job is to compare the change with the human's own words (pasted spans and agent turns are context, never intent).

#### g.5.3 Output (`loom.review/v1`, validated strictly by switchd)

```jsonc
{ "schema": "loom.review/v1",
  "oneLine": "Adds battery % to the bar and installs Obsidian",          // ≤ 80 chars
  "summary": "…",                                                        // ≤ 600 chars, plain text
  "matchesRequest": "yes|partly|no|no-request",
  "mismatches": [ { "text": "≤200 chars", "file": "modules/x.nix", "line": 14 } ],                    // ≤ 10
  "concerns":   [ { "severity": "low|medium|high", "text": "≤200 chars", "file": "…", "line": 0 } ],  // ≤ 10
  "recommendation": "approve|reject|look-closer" }
```

switchd validates schema and lengths, strips C0/C1 controls, bidi overrides and zero-width characters, drops `file`/`line` references that don't exist in the diff, and renders everything as inert plain text (no markup, links shown as text). Invalid output → `review.status = "invalid"` (escalated). The review is **not** part of the signed facts hash; `cardSha` covers what was shown.

### g.6 Card (`loom.card/v1`) and presentation

```jsonc
{ "schema": "loom.card/v1", "tip": "…", "base": "…", "host": "3f9c0a…",
  "kind": "change|update|rollback|maintenance",
  "title": "Install Steam for gaming",       // deterministic: first request (≤ 40 chars) or first commit subject; never AI text
  "presentation": "routine|escalated", "reasons": [ "…" ],
  "request": [ { "id": "r-…", "author": "human:josh", "ts": "…", "surface": "intent", "text": "…" } ],   // ledger, verbatim
  "facts": { "summary": [ "+3 packages: steam 1.0.0.81, …", "hardware.graphics.enable32Bit false → true" ],
             "critical": [], "high": [], "ref": "facts.json" },                 // rendered from facts by loom code
  "review": { "status": "ok|unavailable|invalid|skipped", "oneLine": "…", "summary": "…",
              "matchesRequest": "yes", "mismatches": [], "concerns": [], "recommendation": "approve" },
  "results": { "build": "ok", "checks": "3/3", "vm": "ok|skipped (no KVM)" },
  "actions": [ "approve", "reject", "details", "git-diff" ],
  "nonce": "…", "expires": "…" }
```

**Presentation rule** (in switchd, deterministic). `routine` only when **all** hold: `facts.escalate = false`; every check passed; provenance is `chat` with at least one valid, non-stale human request, or `terminal`, or a **human-started** rollback to an approved tree (§g.10), or `update` in which every changed input is a verified release and `inputs.added` is empty; and the review is `ok` with `recommendation = approve`, `matchesRequest = yes` and no high concern, **or** `skipped` under the §g.3 step 10 rules. Everything else is `escalated`; `reasons[]` lists every trigger. The reviewer can add escalation and can never remove a fact's escalation.

**Fatigue controls.**
- One card per proposal; a newer proposal in the same thread withdraws the older card. The resident's prompt says to batch everything for one request into one proposal.
- Updates at most once a day; a human-started rollback to an approved state, and a verified-release update, skip the reviewer.
- Hold-to-confirm only for cards with a **critical** fact (Approve disabled for 5 s, then hold, then touch/passphrase): a reflexive token touch is too easy for "adds a signing key".
- `loom stats` reports cards per week and the escalated share (target ≥ 80% routine in normal use; nothing leaves the machine). When escalated cards exceed 30% over 14 days, the resident is told to ask the human whether `loom.highlight.extra` or the update cadence should be tuned; that change is itself a card.

The UI of both forms is in §h.4.

### g.7 Approval commit

#### g.7.1 Format (human-signed merge)

```
parents: <base = deployed commit>  <tip = proposal>
tree:    == tree(<tip>)                          (the approval adds no content)
message:
  approve: <card.title>                          (≤ 72 chars)

  Loom-Approve: v1
  Loom-Host: 3f9c0a…                             (loom.host.id)
  Loom-Base: <base sha>
  Loom-Proposal: <tip sha>
  Loom-Facts: sha256:<facts.json>
  Loom-Card: sha256:<card.json>
  Loom-Nonce: <32 hex>
  Loom-Expires: 2026-10-28T18:05:00Z
  Loom-Presentation: routine | escalated
  Request-Id: r-01JBX6Q4M2…                      (copied from the proposal)
```

Signed with `gpg.format=ssh` by a key from the running `loom.keys.humans`; the committer is the human.

#### g.7.2 Producing it (broker, human uid)

- **No git runs as the human.** The only full copy of the objects is root's mirror, which the human uid can't write (and git refuses to work in a root-owned repo). So switchd puts `tree`, the parents (`base`, `tip`), `author`, `committer` and the full `message` into the `SIGN` payload. The broker's `loom-approve-sign` rebuilds the exact commit object text from those fields and signs it with `env -u SSH_AUTH_SOCK ssh-keygen -Y sign -n git`, using the **private key file** (`localPath` minus `.pub`, or the FIDO2 handle; when `localPath` is null, the `~/.ssh` key or handle whose public blob matches a running `loom.keys.humans` entry). It never uses an ssh-agent, so a key cached in any agent (including omarchy's optional `gcr-ssh-agent`) is never used for approvals. It returns only the signature. switchd inserts it as the `gpgsig` header, writes the commit into the mirror with `git hash-object -t commit -w`, and verifies it (§g.7.3).
- **FIDO2:** the touch (and PIN if set) is the approval (U1).
- **Software key:** typing the passphrase in the card (`SSH_ASKPASS_REQUIRE=force`, the Quickshell askpass) is the approval. Software keys without a passphrase are refused when added (D10), so there is no third gesture.
- The broker builds the message **only from the `SIGN` payload that came from root** (N11), never from anything the card UI sends back. The resident can't read `~/.ssh` (home 0700, separate uid) and can't send `SIGN`.

#### g.7.3 Verification (switchd step 14; all must hold)

1. `git verify-commit` succeeds and `%GS` has role `human` in the **running** `allowed_signers` (U6).
2. Parents are exactly `[deployed, tip]`, and `tree == tree(tip)`.
3. `Loom-Host` equals the running `loom.host.id` (no cross-host replay of one human key's approvals).
4. `Loom-Base` equals the deployed commit (an approval can't be applied on top of later changes).
5. `Loom-Nonce` equals the outstanding nonce for `tip` and is not in `/persist/var/lib/loom/approvals/used`; it is appended atomically **before** activation.
6. `now < Loom-Expires`.
7. `Loom-Facts` and `Loom-Card` equal the stored hashes: what was shown is what was approved.
8. For an escalated card where `keepClick` applies, the Keep click arrives inside the watchdog window.
9. The store path activated is `facts.proposal.toplevel.outPath` (bound by rule 7). The approval merge itself is never evaluated.

**Approving elsewhere.** `loom card export <tip> > card.json` and `loom approve --card card.json` work on any machine holding the human key (e.g. the FIDO2 token is plugged into another computer). That machine pushes to `gate/approve/<tip>`; `loom propose --approval-from-silo` fetches it. Same checks.

### g.8 Activation, watchdog, rollback

- switchd **accepts commits only, never store paths from a caller**. It evaluates and builds the proposal tip itself. `<new>` below is exactly the `outPath` it built and recorded in `facts.proposal.toplevel` (bound by `Loom-Facts`); the approval merge is never re-evaluated.

```
1  intake under /run/loom/switch.lock (§g.3 step 1, including the SEK-rotation marker rule of §g.14)
2  … steps 2–14 of §g.3 (signatures, refusals, fetch, eval, build, checks, facts, review, card, SIGN, verify)
3  nvd diff → switches/<n>/ ; baseline health snapshot (which checks pass NOW)
4  ARM, both BEFORE activation, both from the OLD generation's store paths:
     systemd-run --unit=loom-watchdog-<n> $(readlink -f /run/current-system)/loom/watchdog --new <new> --prev <old> --deadline <t>
     systemd-run --on-active=<t+30> --unit=loom-deadman-<n> $(readlink -f /run/current-system)/loom/rollback <old>
5  <new>/bin/switch-to-configuration test        (boot default untouched; re-runs HM activation)
5a per-session `hyprctl reload` as the session user, so step 6's configerrors and IPC checks test the new Lua
6  watchdog loop (every 5 s until the deadline), baseline-relative:
     reached the target; no new failed units; NM connectivity ≥ baseline; silo reachable with the host key (if it was);
     loom-switchd answers, and loom-chatd when loom.chat.enable; flavor checks (omanix: Hyprland answers `hyprctl -j monitors` in each session,
     omarchy-shell IPC answers, `hyprctl configerrors` empty; run as the session user); loom.home: hm-activation
     succeeded; escalated card with keepClick: "Keep" clicked
7a pass → cancel the dead-man timer; nix-env -p /nix/var/nix/profiles/system --set <new>;
          <new>/bin/switch-to-configuration boot; overlay settle; update-ref master to the approval merge M
          (the switch record maps M → tip → outPath);
          push master to silo with the host key (CODEOWNERS; queued while offline); post "applied" to chat; exit 0
7b fail/timeout, or switchd or watchdog death (the dead-man timer fires) →
          <old>/bin/switch-to-configuration test; per-session hyprctl reload against the old files;
          push refs/heads/gate/rejected/<tip>; tell the human and the
          resident the failing check and journal cursor ("Rolled back: Hyprland didn't answer within 30 s"); exit 4
```

- The toplevel carries `$out/loom/{watchdog,rollback,view.nix,facts,review/run,review/prompt.md}` via `system.systemBuilderCommands`. Transient units aren't managed by `switch-to-configuration`, so activating the new generation can't stop them.
- **Rollback by default.** Nothing reaches the boot default before health passes. A crash or power loss boots the old generation. loom enables no boot counting with either loader (D7); the loader's generation menu is the manual fallback.
- `nuketown.switch.command = "loom propose"` (N12) routes the resident's habitual `nuketown-switch` through the same gate. This is a convenience: `nuketown-switch` is installed only for sudo agents, and nothing depends on it.

### g.9 Updates as "Update ready" cards

- `loom-update.timer` (daily, when `loom.switch.autoUpdate = "notify"`, the default) runs as switchd's `loom-fetch` helper in a scratch worktree: `nix flake update` for the inputs in `loom.update.inputs` (default: the inputs in `loom.trust.releases`, i.e. omanix. Third-party plugin inputs are bumped only on request, as escalated cards, because a routine daily bump would give every plugin upstream a standing route to root); for inputs in `loom.trust.releases` (omanix) it moves only to the newest signed tag on the same channel (`git ls-remote --tags`, `git verify-tag`); it commits **host-signed** as `update: <inputs>` on `gate/update/<date>` and proposes.
- `provenance.kind = "update"`; the reviewer's request text is the fixed string "Scheduled update of flake inputs (no human request)".
- The card heading is **Update ready**. It is routine when every changed input is a verified release and no fact escalates (§g.6), and the reviewer is skipped for it (§g.3 step 10). Routine one-liner: `Update ready: omanix v0.1.0 → v0.1.1 (signed) · nixpkgs +9 days · 312 packages upgraded · [Approve ⌁] [Details] [Later]`. `[Later]` snoozes 24 h.
- An input in `loom.trust.releases` whose new rev is not a verified tag, or that moves backwards, gives `inputs.unverified_release` / `inputs.downgrade` (escalate). Any new or removed input escalates as usual. A host that adds other inputs to `loom.update.inputs` gets their rev changes as high facts, so those cards are escalated.
- `"off"` disables the timer. **Nothing auto-switches, ever.** The resident's `omanix update [<input>]` makes the same kind of commit with the agent key on request; the menu's "Check for updates" runs the timer now.
- Firmware: the `update` skill reports `fwupdmgr get-updates`; applying needs `loom.agent.sudo = "approval"` or the human running `fwupdmgr update` in their own polkit session.

### g.10 Undo and rollback

| Action | Who | Signature? | Card |
|---|---|---|---|
| Watchdog / dead-man rollback during a switch | automatic | no (restores the running generation; H5) | a notification afterwards ("Rolled back: … · Why?") |
| **Undo last change** (toast for 2 min after a switch, bar menu, System menu, `loom undo`) | human (GUI or terminal) or resident | **yes**: one gesture, the approval | "Undo: <subject of the switch being undone>"; "prepared by <agent>, not requested" when the resident started it without a linked request |
| Roll back to generation N (`loom rollback --to <n>`, GUI list) | same | **yes**: one gesture | "Roll back to <date>: <subject>"; same rule |
| Boot an older generation from the loader menu | physical presence | no | at next login: "You booted an older generation (<date>). Make it the default?" → a rollback card |
| `sudo nixos-rebuild switch` outside loom | human with a password | — | the next card carries `drift.unmanagedSwitch` (escalate) |

- Undo and rollback proposals are revert-style commits whose tree equals the target switch record's tree, with `provenance.kind = "rollback"`. A **GUI or terminal action by the human** produces a ledger turn (`surface = "undo"`, recorded by chatd from the human uid; `loom undo` run by the human uid goes through chatd the same way). switchd then makes the revert commit **host-signed**, with the `Request-Id` of that record, so the approval merge is the only human gesture. The resident's revert is agent-signed.
- **Human-started** (a linked `undo` record, or a human-signed revert): the reviewer is skipped when `tree ==` the tree of an approved switch record that is an ancestor of the deployed commit. The card says "Restores a state you approved on <date>" and is routine unless facts escalate (e.g. `drift`). The build is a store hit, so Undo is one touch and seconds.
- **Agent-prepared** without a linked human request: `provenance.agentPrepared` is set, the card says "prepared by <agent>, not requested", the reviewer runs, and the card is escalated. Reverting a fix the human approved earlier is exactly what an injected resident would try.
- Rev 2's "rollback always allowed without a human" and the UX draft's "human-uid rollback needs no key" are both **rejected**: V4 says every switch is signed. If the human key is unavailable, the loader menu is the physical-presence fallback.

### g.11 Enrollment (spec bootstrap ownership)

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

| Key | Where it lives | Silo transport | `CODEOWNERS` | Push `master` | Push `gate/*` | Push `refs/dit/*` | sops | Counts as approval |
|---|---|---|---|---|---|---|---|---|
| human, **owner** | FIDO2 token (recommended), or `~/.ssh/id_ed25519` with a passphrase | `.owner_key` (immutable in v1) | yes | yes (F3 bypass) | yes | yes | only with an `age` recipient | **yes** |
| human, additional | token or another computer | `.authorized_keys` | yes | yes (F4) | yes | yes | same | **yes** |
| host ssh | `/persist/etc/ssh` | `.authorized_keys` | yes | yes; used only by switchd after a passed switch | yes (update/maintenance proposals, probes) | yes | — | no (install records only as baseline) |
| agent ssh | sops → `/agents/<n>/.ssh` | `.authorized_keys` | **never** | **no** (F4 rejects) | yes, always passes (F4) | new or fast-forward | — | no |
| enroll | `enroll.key` on the stick; shredded after use | mint commit only | mint commit only | **once** (the enrollment push) | until enrolled | — | never | no (not in `allowed_signers`) |
| host age | `/persist/var/lib/loom/sops/host.age` | — | — | — | — | — | all files | — |
| system encryption key | paper, with the human (§g.14) | — | — | — | — | — | all files, via the derived age identity | — (also opens the LUKS slot) |

- A proposal that adds the agent key to `CODEOWNERS` is a critical `trust.codeowners` fact, and pointless: the agent key never counts as an approval to switchd.
- **The agent key can force-push or delete any `gate/*` ref** (F4 has no fast-forward check on gate), including `gate/approve/*` and `gate/rejected/*`. That is denial of service only: approvals are verified by signature, nonce and base, and switchd's records live under `/persist` (U15).
- silo `master` should be a chain of human-signed approval merges after the install records, which can be verified off the machine with the same `allowed_signers` (`loom audit --from-silo <id>`). This is verified, not assumed: the host key can force-push `master` (F4), so reinstall runs `loom audit --from-silo` and installs only the last valid approval merge (§e.5 step 0). Whether to remove the host key from `CODEOWNERS` is open (O8).

After enrollment, nothing off the machine holds write access except the human keys, which are the intended exception (spec Bootstrap 4). **In v1 the owner key cannot be revoked on silo:** `.owner_key` is immutable until S1. If the owner key may be compromised, the response is a fork (§g.12).

### g.12 Reinstall, fork, key rotation

**Reinstall** (same id):
1. Boot with `loom.host=<id>`, or enter the id at the prompt. The installer clones the repo, runs the chain check of §e.5 step 0, and shows hostname, user, owner key and the commit it will install (the last valid approval merge) for confirmation.
2. The disk/unlock flow runs as for a new install. New host, agent and age keys are generated, plus a new machine-id.
3. **System encryption key** (§e.5 step 5).
   - If the user types it and its fingerprint matches, it is kept. The salt is the host id, so the same key derives the same LUKS passphrase for the new disk and the same age identity (§g.14).
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
- `loom keys list` shows every key in the §g.11 table, owner flagged, with the system-encryption-key fingerprint.
- `loom keys rotate host|agent <n>`.
- `loom keys rotate encryption-key`. Menu: "Rotate system encryption key". The procedure is in §g.14.
- `loom keys add-human [--generate]` / `remove-human <fp>`:
  - `--generate` creates a passphrase software key in `~/.ssh`, with the same rules as §e.5. It runs as the human in a terminal the human opened (it refuses `--json` and refuses to run as the agent uid); the passphrase is read by ssh-keygen's own prompt on that pty, **never passed on argv or in the environment**; and with a resident agent a passphrase equal to the login password is refused;
  - adding an existing software key file that has no passphrase is refused (D10);
  - `remove-human` refuses to remove the last human key;
  - removing the **owner** from `.authorized_keys` and `CODEOWNERS` is refused in v1, with "the owner key can't be revoked on silo until S1; fork if it is compromised".
  - No key kind is "downgraded", and no permission changes with key kind (D10).
- `loom unlock {status,add,remove,reseal}`, with the two-methods-including-the-system-encryption-key guard. `reseal` re-enrolls TPM2 after firmware updates and needs another factor.

### g.13 Script guards (every destructive tool)

- `--dry-run` / `plan` emits a JSON plan.
- An out-of-band confirmation is required: a TTY-typed token (serial, hostname, `ERASE`) or a broker approval. No `--force` bypasses device-class checks.
- Devices are resolved by-id and re-checked (major:minor, serial) right before writing.
- Writes are logged to `/persist/var/log/loom/<tool>.log`, or to `~/.local/state/omanix/log/` on the configuring computer.
- Shell code uses `writeShellApplication` + shellcheck. Python code has pytest in checks, and flash/installer guards are tested against a fake sysfs tree.

### g.14 System encryption key (D12)

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
- **Switch gating without a shared lock.** The rotation tool never holds `/run/loom/switch.lock`. Instead, `sek-rotation.json` is the marker: while the file exists (from phase 1 until `done` or `--abort` deletes it), switchd (§g.8 step 1) admits only the commit recorded in `commit` (nothing until one is recorded) and answers every other commit with exit 5 "encryption key rotation in progress; resume it or run `loom keys rotate encryption-key --abort`". So no agent commit can encrypt to the old recipient mid-rotation, and the rotation's own proposal in phase 4 goes through switchd normally.
- State lives in `/persist/var/lib/loom/keys/sek-rotation.json`, written atomically (write, fsync, rename): `{v, phase, oldFp, newFp, slotsBefore, newSlot, oldSlots, commit, paperVerified}`. **It never contains `R'`.** Every phase first inspects the real state (`luksDump` slots and tokens, the git working tree, silo `master`), so re-running a phase that already completed is a no-op.
- **Resume** (the state file exists): the user either (i) retypes `R'` **in full from paper**, accepted only if its fp equals `newFp`, and the tool continues at the recorded phase; or (ii) before phase 3 only, chooses "I don't have the new key; start over", which runs the **pending cleanup** below and restarts at phase 1 with a fresh `R'`. After phase 3 has started, only (i) is offered, because the new recipient may already be in the working tree.
- **Pending cleanup** (start over, `--abort`, and the start of every phase 1): remove every `loom-sek` token with `state = "pending"` whose `fp` ≠ the current `newFp`, wipe the slots in its `keyslots`, and wipe every slot that is neither in `slotsBefore` nor bound to the `active` token or another recorded unlock method (`unlock.json`). This removes a slot whose token import never happened.
- **Paper check gate.** Phases 3b and 5 refuse to run unless `paperVerified` is set for the current `newFp`, which only a full retype of `R'` from paper (phase 1, or a resume) sets. This is what stops a transcription error from surviving into a state where the old key no longer works.

| Phase | Action | Verify before advancing | Crash/resume |
|---|---|---|---|
| 1 `generated` | Run pending cleanup. Generate `R'` and show it once. After the user confirms it is written down, the screen clears and the user types the **complete key back from paper**. Record `oldFp` (from settings), `newFp`, `paperVerified = newFp`. | The typed key parses and its fp equals `newFp`; otherwise show it again and repeat. | No state file yet (crash before the record): restart at phase 1; nothing has changed. State file present: resume rule above. |
| 2 `luks-added` | Unlock with an **existing** factor: the old SEK (typed; `--unlock-key-file` from a pipe of `hex(K_luks_old)`), the disk passphrase, or FIDO2 (`--unlock-fido2-device=auto`). (a) Record `slotsBefore` and `oldSlots` (the `keyslots` of the `active` token). (b) **Test every keyslot** with `cryptsetup open --test-passphrase` and `hex(K'_luks)`; if one opens, reuse it as `newSlot`. Otherwise add a slot via `systemd-cryptenroll --password` (with `NEWPASSWORD` in the env) and find `newSlot` as the one slot not in `slotsBefore`. (c) Record `newSlot` in the state file. (d) Import the `loom-sek` token (schema above) with `cryptsetup token import --key-slot <newSlot>`, `fp = newFp`, `salt = loom.host.id`, `state = "pending"`, unless a token with `newFp` already binds `newSlot`. | `cryptsetup open --test-passphrase --key-slot <newSlot>` with `hex(K'_luks)` succeeds. Exactly one token with `newFp` exists, and its `keyslots` = `[newSlot]`. | Re-run phase 2: steps (b) and (d) find and reuse what exists, so no second slot or token is ever added. |
| 3 `sops-staged` | In the root-owned mirror's working tree, decrypting with the host age key: (a) `sops rotate -i --add-age <new recipient>` on every `secrets/**` file; **verify (a)**; (b) (paper check gate) `sops rotate -i --rm-age <old recipient>`, which also generates a new data key; set `machine.nix` `loom.secrets.recipients.recovery` + `loom.secrets.recovery.fingerprint` and regenerate `.sops.yaml` (`loom keys sync`). | After (a): every file decrypts with `SOPS_AGE_KEY=K'_age` **alone**, and the plaintext hash equals the host-key decrypt of the deployed commit. After (b): the same check again; the old recipient is absent from every file's metadata; the host key still decrypts. | The working tree is disposable: `git checkout -- secrets .sops.yaml machine.nix`, then redo phase 3 from the deployed commit. |
| 4 `committed` | Commit `keys: rotate system encryption key <oldFp>→<newFp>`, **signed with the human key** (the commit step runs as the invoking human, in the session that started the tool: FIDO2 touch or passphrase), **record `commit` in the state file**, then `loom propose --ref <commit>` → switchd admits it (marker) → facts (critical: recovery recipient and fingerprint, sops recipients) → reviewer skipped (every commit human-signed) → escalated card → human-signed approval merge (§g.7) → promoted → push `master` (host key). | The proposal exits 0, and silo's `master` == the approval merge (`ls-remote`). | `commit` recorded but not promoted ⇒ re-run `loom propose --ref <commit>`. Rejected or rolled back ⇒ back to phase 3, or `--abort`. |
| 5 `old-wiped` | (paper check gate) Wipe every slot in `oldSlots`; if the old SEK was typed in this run, also wipe every other slot that opens with `hex(K_luks_old)` (`cryptsetup open --test-passphrase` without `--key-slot`, looped until it fails). Remove every `loom-sek` token whose `fp` ≠ `newFp`. Set the new token's `state = "active"`. | `luksDump`: exactly one `loom-sek` token, all fields valid, `fp = newFp`, `state = "active"`, and its slot test-opens with `hex(K'_luks)`. Every keyslot is that slot or one recorded in `unlock.json`. The unlock guard (≥ 2 methods including the SEK) still holds. | Re-run phase 5: wiping and token removal are idempotent. |
| 6 `done` | Show "Done. Destroy the paper with key <oldFp>." Delete the state file. | `loom keys list` shows `newFp`; `unlock.json` is updated. | — |

- `--abort` is allowed only before phase 4 is promoted. It runs the pending cleanup for `newFp` too (wipes the new slot and token), discards the working tree, and deletes the state file. The old key stays valid. After promotion the procedure only moves forward.
- **Limit, shown on screen:** old ciphertext in the public repo history stays readable to the **old** key. Rotation protects everything after it, because phase 3b generates a new data key. If you rotate because the old key leaked, also change the secrets themselves (Wi-Fi passwords, login password) with `omanix secret set` / `loom user passwd`.
- **VM test `sek-rotate-crash`:** kill the tool after each phase **and** between every sub-step of phase 2 (after the slot add, after the state write, after the token import). Resume must reach `done` with exactly one new slot added, and at every point at least one SEK unlocks the disk and decrypts the deployed secrets. Also: "start over" after a crash in phase 2 leaves no orphan slot or pending token; a deliberately mistyped paper retype blocks 3b and 5; an agent commit sent during phases 3–4 gets exit 5 while the rotation commit is admitted; and after `done`, the installer image's rescue path ("Unlock a disk with my system encryption key", reading `salt` from the token) unlocks with the new SEK and fails with the old one.

### g.15 Threats

| # | Threat | What the attacker gets | Defenses | Residual |
|---|---|---|---|---|
| 1 | **Prompt injection into the resident** (web page, email, tool output, a malicious flake README, an attached file) | Full control of the `ada` uid: edits the repo, proposes, chats, pushes `gate/*` | It cannot sign (H5), forge the ledger (H8), send `SIGN` (N11), read the human's keys (0700) or touch the facts (H7). Its proposals show the human's real words next to a deterministic list of what changed; suspicious text in the diff escalates. With `loom.agent.sudo = "none"` (D8 default) it has no runtime root. | A change that fits the request, touches nothing on the highlight list and is subtly malicious (e.g. a changed program option in a non-highlighted module that exfiltrates data). Only the reviewer and the human's reading of the diff stand in the way. **This is the stated limit of the design.** |
| 2 | **Injection into the reviewer through the diff** (comments, strings, file names, commit subjects) | The reviewer's text and recommendation | Fenced data with a per-bundle token; commit bodies withheld; `suspiciousText` escalates on its own; the reviewer can only add escalation; output schema-validated, length-capped, rendered inert; no tools, no network beyond the model endpoint, no writable output except stdout, no memory. | A fooled reviewer can make a card **routine** only if the facts are clean (see 1). Facts compare derivations and built effects (§g.4), so changed root code is never "clean". |
| 3 | **Approval fatigue** | A human who approves without reading | Routine one-liners, batching, superseding, daily updates at most, no review on rollbacks, hold-to-confirm only for critical facts, inert buttons after appearing, no default button, `loom stats`. | A human who taps through critical cards; the design keeps those rare enough to stand out. |
| 4 | **Replay of an old approval** | Re-activating an old or other proposal | Approval bound to host id, base, proposal sha, facts/card hashes, single-use nonce (recorded before activation), expiry (§g.7.3). | None known. |
| 5 | **Agent key on silo** | Pushes `gate/*` and `refs/dit/*`; deletes gate refs | No `master` (CODEOWNERS); no other refs or tags; switchd ignores silo `master` without a valid approval chain, and ignores `refs/dit/*` entirely. | DoS on gate refs; spam on `refs/dit` (the issue tracker). |
| 6 | **Compromised human session** (code running as uid 1000) | Write ledger turns *as the human*, drive the card UI, replace the card renderer through HM files, keylog a software-key passphrase | With FIDO2 every approval still needs a physical touch, but the attacker can substitute what is signed. With a software key the attacker can sign once it has the passphrase. Human exec surfaces are critical facts (§g.4.1), so the resident's path *into* that compromise is visible. N14 removes the password-less `machinectl shell root@` that nuketown's polkit rule gave uid 1000. | **Equivalent to compromising the human**, as on any desktop where the user is the admin. Future: show the card on a second device (XMPP, phone) bound to the nonce. |
| 7 | **Reviewer down or offline** (no network, quota, crash, model change, not signed in) | — | `review.status = unavailable`, escalated, with facts + diff + request; approval still works. `loom.reviewer.enable = false` gives the same permanently. | More escalated cards while it's down. |
| 8 | **Resident down** | — | GUI repair tools (network, sign-in, restart, undo/rollback, lock, power); terminal `loom propose`/`approve`; loader menu. | — |
| 9 | **Malicious change to loom/omanix via an input bump** | New facts code, view, reviewer prompt | All take effect only **after** a human-approved switch; the bump's card is computed by the old code; release-tag verification (tag target == `locked.rev`) is a fact. A transitive node under a trusted release that differs from that release's own lock (`omanix/loom` moved alone) is a critical `inputs.transitiveOverride`. Third-party input rev changes are high, and those inputs are not in the daily update by default. | A trusted signed release that is itself malicious (D11 key compromise). |
| 10 | **Weakening the reviewer or facts** (`loom.reviewer.*`, `loom.highlight.*`, `nuketown.agents.reviewer.*`, the chat relay) | Future cards routine when they shouldn't be | All are critical facts in the base list, which hosts cannot remove. | — |
| 11 | **Agent fabricates a "human" request** via prefill, chips or a `question` | — | Records exist only for frames the human uid sends on `chat.sock`; prefill is recorded only after Send; agent choices are flagged `agent-choice` (escalates). | The human sends what the agent suggested: real consent to the words they sent. |
| 12 | **Forged SIGN or card to the broker** | A signature over attacker content | Broker accepts `SIGN` only from uid 0 (N11); the message is built only from the root payload. | — |
| 13 | **Generic sudo for the resident** (D8 `"approval"`) | Runtime root through per-command approvals, bypassing the pipeline | Off by default; turning it on is a critical fact; each command shows the raw command in an approval dialog (N1 bypass fix). | **Equivalent to disabling the pipeline's guarantees**, not only to untracked changes. Root can edit the switch records (which define "approved trees", so any tree becomes a reviewer-skipped routine restore), `approvals/used` and the ledger (root writes its hash chain and root checks it), and can read the host ssh key (CODEOWNERS on silo). The D8 TUI text says so. The approval wrapper also refuses commands naming `/persist/var/lib/loom/**` or `/persist/etc/ssh`, or `systemctl` on `loom-*` units; such a deny-list cannot be complete. `drift.unmanagedSwitch` catches switches only. |
| 14 | **Resident draws a fake card or "Reviewer: approved" in chat** | Social engineering | Chat renders plain text plus a safe Markdown subset, no images/HTML; cards exist only in `omanix.approval`'s own layer-shell surface; approval needs a key gesture only the human uid can produce; "Reviewer: approved" in a nix comment is a reviewer flag and a `suspiciousText` hit. | — |
| 15 | **Sensitive data in an attachment** | Resident reads a screenshot | Attachments are explicit, previewed, human-initiated; the resident has no screenshot, clipboard or Wayland access. | The human attaches something sensitive on purpose. |
| 16 | **Agent-chosen code reaching the host or the human session before approval** (preflight VM runner, `omanix try` values, sign-in URLs) | Root or human-uid execution with no card | The preflight boots only the guest toplevel with the running generation's QEMU in a DynamicUser, network-less unit (§g.3); `try` previews only typed option values rendered from templates (§h.6); `auth` URLs need an open login portal token, https and an allow-listed host, and never go through `xdg-open` (§h.3.6). | — |

---

## h) Agent surfaces and UX

### h.1 Rules

1. **The agent is the front door for change, not for control** (§f.3).
2. **GUI changes are runtime state**; every kept tool offers **Make it stick**, which is a request to the agent.
3. **Every switch is a card, and every card needs the human's key.** No exceptions except the watchdog's automatic rollback.
4. **Routine cards are one line.** Code (facts) or the reviewer escalates; the reviewer never de-escalates.
5. **Facts are code, never AI**: computed by loom, shown in their own frame, hashed into the approval.
6. **Provenance is held by root**: what the human typed is recorded by chatd before the resident sees it.
7. **The resident is another user.** It can't see the human's screen, files, clipboard or Wayland socket; the human hands it context explicitly, with a preview.
8. **Nothing the agent writes can look like system UI.** Chat renders plain text plus a safe Markdown subset; cards are drawn by a separate plugin in a separate layer-shell surface.
9. **The system is whole without the agent**: edit the host repo, `loom propose`, same card, same key.
10. **One keystroke to the agent from anywhere:** `SUPER + A` opens the chat panel; typing in the `SUPER + SPACE` menu falls through to "Ask ada: …".

### h.2 Components

```
human session (uid 1000)                     root                                       residents
────────────────────────                     ────                                       ─────────
Quickshell omarchy-shell (fork)              loom-chatd   /run/loom/chat.sock           ada (1100)  UI agent
  omanix.chat     ── turns, attachments ───▶   ledger      /run/loom/chat-agent.sock ◀── loom-agent-bridge@ada
  omanix.approval ◀── card (IPC) ── nuketown broker (human user svc) ◀─ SIGN ─┐          (harness: claude-code stream-json)
  omanix.status   (bar dot, pending cards)   loom-switchd /run/loom/switchd.sock          reviewer (1101)
  omanix.welcome  (first boot, tour)           loom-facts (running gen), loom-eval ──────▶ systemd-run per review:
  undo toast/menu ── loom undo ────────────▶   loom-egress (CONNECT allowlist) ◀────────   reads bundle, prints JSON
```

| Component | Repo | Runs as | Job |
|---|---|---|---|
| `loom-chatd` | loom | root | Records human turns (ledger) and relays turns/events between the surface and the bridge (§g.2). |
| `loom-agent-bridge@<agent>` | loom | the agent (system unit) | Hosts the harness in streaming mode in `~/projects/host`; translates harness events to `loom.chat/v1`; writes attachments to `/agents/<agent>/inbox/`. **Untrusted**: it is the agent's own process. |
| `loom-switchd`, `loom-eval`, `loom-fetch`, `loom-egress` | loom | root / DynamicUser | §g.3, §g.5. |
| nuketown broker (+`SIGN`) | nuketown | human user service (NixOS `systemd.user` unit, N15) | Relays the card to the prompter, runs `loom-approve-sign`, returns the signature. Prompter = `qs ipc call omanix.approval show <card.json>`; zenity fallback. |
| `omanix.chat` | omanix (`fork/add`) | human | Panel, composer, transcript, activity rail, chips, attachments, options browser, bar widget. |
| `omanix.approval` | omanix | human | Card surface (routine banner, escalated card, diff view), pending-cards badge, Undo toast. |
| `omanix.status` | omanix | human | Bar indicators: agent state, approval pending, agent offline; resident tile in the agents panel. |
| `omanix.welcome` | omanix | human | First-boot checklist and tour. |
| `loom-card-tty` | loom | caller | The same card in a terminal for `loom approve` without a session and for the no-agent path. |

### h.3 Chat surface

#### h.3.1 Shape

- **Panel:** right-edge drawer, layer-shell `top`, 34% width (min 420 px), full height minus bar. Toggled by `SUPER + A`, the bar widget, or any intent. It doesn't steal focus from fullscreen apps unless the human opened it.
- **Bar widget** (replaces `omarchy.agents` at the same `shell.json` slot): agent glyph + state dot. Idle (hollow), working (pulsing), needs you (accent, count of pending cards/questions), offline or signed out (struck).
- **Header:** agent name, state, "New chat", conversation list, overflow menu (Open in terminal, Sign in again, Restart agent, Stop, Do it myself).
- **Transcript:** human bubbles right, agent text left, activity rows inline and collapsed, card references ("Approval card opened" focuses the card; the card is never drawn here).
- **Composer:** multiline; Enter sends, Shift+Enter newline. Attach, context chips, Stop (while working).
- **Menu fallthrough:** a `SUPER + SPACE` query with no exact match shows a last row "Ask ada: <query>", which opens the panel with the text in the composer, unsent.

#### h.3.2 Transport

1. The panel connects to `/run/loom/chat.sock` (0660 `root:loom-chat`; the human is the only member; chatd also checks `SO_PEERCRED` against `loom.user`) using `Quickshell.Io.Socket` with a `SplitParser` (U10). Framing is newline-delimited JSON (`loom.chat/v1`).
2. `loom-agent-bridge@<agent>.service` (system unit, `User=<agent>`, `Restart=always`, `ConditionPathExists=/persist/var/lib/loom/firstboot/repo-publish.done`) connects to chatd's listening socket `/run/loom/chat-agent.sock`. chatd checks `SO_PEERCRED` and accepts only the agent uid there.
3. One surface at a time; a second connection takes over and the first gets `{t:"detached"}`.
4. The bridge is not trusted for anything security-relevant: requests are recorded by chatd, cards come from switchd via the broker, and the bridge carries only conversation.

#### h.3.3 Streaming: what the agent is doing

The claude-code adapter runs the harness long-lived in streaming JSON mode (`--input-format stream-json --output-format stream-json`, U11) in `~/projects/host`, with nuketown's generated prompt plus the loom/omanix fragments. Its permission mode inside the harness is its own business: its powers are bounded by its uid, `gate/*`-only push and switchd. The `replay` adapter plays scripted transcripts (same events, real commits) for VM tests and the demo.

| `t` | Fields | UI |
|---|---|---|
| `text` | `delta` | Appended to the current agent bubble. Markdown subset: paragraphs, lists, inline code, code blocks, bold/italic, links shown as `text (domain)`. No images, no HTML. |
| `activity` | `kind` read\|edit\|run\|search\|web\|build\|commit\|propose, `label`, `detail` | Activity row: "Reading modules/apps.nix", "Editing home.nix", "Running `omanix check`", "Reading web page — github.com" (`web` rows carry an "external content" marker). Informational only; facts never come from it. |
| `progress` | `phase` eval\|build\|vm\|review, `done`, `total` | One row updated in place: "Checking · building 12/40 · VM smoke · review". |
| `card` | `id`, `presentation` | Reference row; focuses the card. |
| `question` | `text`, `choices[]` | Outlined buttons labelled "suggested by ada"; clicking sends the choice text (`surface = "agent-choice"`). |
| `status` | idle\|working\|blocked\|offline\|signed-out | Bar dot and header. |
| `auth` | `url`, `token` | Sign-in handoff (§h.3.6). Accepted only while a login portal is open, https only, allow-listed hosts only. |
| `rejected` | `tip`, `reason` | "You rejected <change>: <reason>". |
| `applied` / `rolledback` | `tip`, `check` | "Applied: …" with Undo; "Rolled back: … · Why?". |
| `error` | `text` | Inline error row (eval/build failures come back here verbatim). |

Input messages: `{t:"user", text, attachments[]}` (chatd assigns the id), `{t:"stop"}`, `{t:"new-session"}`, `{t:"resume", session}`, `{t:"attach-begin"|"attach-chunk"|"attach-end", …}`.

#### h.3.4 Conversation storage

Sessions live in the resident's harness state (`/agents/<agent>/.claude`, persisted by nuketown). **Open in terminal** runs `portal-<agent>` and resumes the same session in the harness TUI when the bridge is idle (U11). Reinstall does not restore conversations: a new agent home, and history is the agent's.

#### h.3.5 Attachments and context

1. **Attach** offers: screenshot region, window, file, clipboard text, last error (most recent failed unit + `omanix why-failed --json` summary, computed in the human session), runtime snapshot (§f.4.6).
2. A preview chip shows a thumbnail or the first 400 characters and the byte count. Nothing is sent yet.
3. On send, the panel re-encodes images (metadata stripped), refuses anything over `loom.agent.chat.attachments.maxBytes` and any type other than PNG, JPEG, plain text and JSON, then streams the bytes to chatd, which stores the blob and delivers it to `/agents/<agent>/inbox/<id>/<name>`.
4. The ledger records `{kind, mime, sha256, bytes}`; the card's request block shows "with 1 screenshot".

There is no agent tool for screenshots or the clipboard.

#### h.3.6 Sign-in handoff (normal provider flow, on this machine)

1. The panel (or welcome step, or a `signed-out` status) shows **Sign in ada**.
2. Click opens a floating terminal (`org.omanix.agent-login` app-id, float/center rule) running `portal-<agent> login`, which execs `loom.agent.loginCommand` as the agent via `machinectl shell` (nuketown portal path).
3. `BROWSER` inside that session is `loom-open-url`, which sends `{t:"auth", url, token}` through the bridge. `portal-<agent> login` registers a one-time token with chatd when it starts and revokes it when it exits. chatd drops an `auth` event if its token is not the open portal's, its scheme is not `https`, or its host is not on the allow-list for `loom.agent.harness` (claude-code: the provider's OAuth hosts). The panel shows the URL's domain and **Open in browser**, which starts the human's default browser binary with the URL as an argument and never `xdg-open`, so no custom-scheme handler can run.
4. The provider's flow completes as it normally does: the human pastes the code back into that terminal, or the browser hits the harness's localhost callback (U12).
5. Tokens land only in the agent's own state (`/agents/ada/.claude/`, or `/persist/var/lib/loom/reviewer/auth` for the reviewer). They never pass through the human's home, the installer, silo or git.
6. The same steps sign in the **reviewer** (`portal-reviewer login`), offered right after. The two residents never share a token file.

### h.4 Card UI (`omanix.approval`)

**Routine form.** A one-line banner (layer-shell `overlay`, top-right, theme notification tokens, 560 px max):

```
 ⛉  "install steam and set it up for gaming"  ·  +3 pkgs  ·  Reviewer: matches   [Details]  [Approve ⌁]  [✕]
```

- The quoted text is **the human's request** from the ledger (truncated), never the agent's commit subject. For updates: `Update ready: omanix v0.1.1 (signed) · 212 pkgs · nothing highlighted`.
- `[Approve ⌁]` starts the key gesture inline: FIDO2 → "Touch your key"; software key → an inline passphrase field (typing it and Enter is the approval).
- `[✕]` = Reject (reason optional for routine).
- The banner doesn't steal focus; buttons are inert for `omanix.approval.unlockDelayMs`; there is no default button and Enter alone never approves.

**Escalated form.** A centered card (layer-shell `overlay`, exclusive keyboard focus only after the human clicks into it, U13), 720 px:

```
┌─ Approve a change to this computer ───────────────────────────────── 1 of 2 pending ─┐
│ YOU ASKED   "summarize the README in ~/Downloads/fooctl and install the tool"          │
│             12:41 · typed in chat · with 1 file                                       │
├─ FACTS · computed by your system · not AI ─────────────────────────────────────────────┤
│ ▲ Trust    Adds substituter https://cache.fooctl.dev and trusts its key  host:configuration.nix
│ ▲ SSH      services.openssh.enable false → true; TCP 22 open             host:modules/foo.nix
│ ● Service  New system service fooctl-agent (root, starts at boot)        host:modules/foo.nix
│ ○ Packages +2 (fooctl 1.4.0, …)                                                       │
│ ○ Checks   build ok · VM smoke ok                                                     │
├─ AI REVIEW · can be wrong ─────────────────────────────────────────────────────────────┤
│ Installs fooctl. It also turns on SSH and trusts a new binary cache, which you did   │
│ not ask for.   Matches your request: partly.   Recommends: REJECT                      │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ [Show git diff]  [nvd diff]  [Agent's notes]  [Facts JSON]                             │
│                                   [Reject with reason…]        [Approve anyway ⌁]      │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

Section order: (1) **Request** verbatim with author, time and surface, or a red line "No request from you is linked to this change" / "Scheduled update" / "Your own commit message"; (2) **Facts**, critical first; (3) **AI review**, or "No AI review (reviewer unavailable: <reason>). Check the facts and the diff."; (4) results; (5) buttons.

Visual separation is fixed in `FactsBlock.qml` / `ReviewerBlock.qml`:
- Facts: monospace, theme foreground on the card base color, a warning-colored left rule on ▲ rows, a header that literally says "computed by your system · not AI". Rows are generated from `facts.v1` fields by loom templates; the only agent-written strings are config values themselves, rendered monospace and elided at 120 characters.
- AI review: proportional italic on a tinted background, header "AI REVIEW · can be wrong", recommendation as a word, not only a color.
- Severity glyphs: ▲ critical/high (highlight, trust, inputs, provenance, session, root units); ● ports and non-root units; ○ informational.
- A card with any **critical** fact: Approve disabled for 5 s, then hold-to-confirm, then the key gesture. If the reviewer recommends reject, Approve stays available, labelled "Approve anyway".

**Show git diff** expands `DiffView.qml`: file list left, unified diff right (syntax-colored for nix/lua/json), agent-written comments dimmed and marked so instructions in comments don't read as UI. "Open in terminal" runs `git -C /persist/var/lib/loom/host show --stat -p base..tip` read-only. **Agent's notes** shows commit bodies, labelled agent-written.

**Reject with reason** (required for escalated cards): recorded by chatd as a human turn (`surface = "rejection"`), switchd pushes `gate/rejected/<tip>`, and the resident receives "Josh rejected <change>: <reason>" as a user turn.

Pending cards survive panel close and session restart (the broker keeps them; the bar badge counts them). A card expires after `loom.switch.approvalTtl` and is auto-rejected with reason `expired`.

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
3. Enter sends; chatd records `surface = "intent"`, `intent = <id>`, `edited` if changed. Escape records nothing.
4. The resident runs the skill, edits, checks, proposes; the card quotes the request verbatim.
5. **Picker-then-intent** rows (Plymouth switcher, language, kernel, timezone): the upstream picker runs unchanged and its result fills `{selection}`.
6. Keybindings that ran a dropped script (e.g. `omarchy-menu summon install`) still open the menu at that route.
7. Agent not available → the panel opens on the row's **Do it yourself** view (§h.11).

#### h.5.4 Keybindings (patch P9)

| Key | Upstream | omanix |
|---|---|---|
| `SUPER + A` | unbound in `utilities.lua` (U25) | `omarchy-shell omanix.chat toggle` (`omanix.chat.keybind`) |
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

**Agent-driven preview** (from loom's `prompt.nix` live-tuning experiment): the resident may preview look-and-feel before committing with `omanix try <path> <value>`. Only a **typed allowlist** can be previewed: `omanix.hyprland.settings` keys with scalar types, `omanix.theme.default`, `omanix.theme.background` (an existing file in the theme registry) and `omanix.fonts.monospace` (an installed family), generated from the option types into `catalog/preview.json`. The bridge relays `{t:"preview-request", path, value}`. A helper in the human session validates the value against the option type and **renders the Lua call itself from a fixed template** (numbers as numbers, enums from the type, strings only for theme and font names checked against the registry), so no agent text is ever evaluated. The panel shows the rendered key and value, never agent-supplied labels: "ada wants to preview: general.gaps_out 10 → 4 · Allow / Not now". Allow applies it (`hyprctl eval` of the rendered call, theme link); the resident has no Wayland access. Previews revert on `try --reset` or panel close and never touch git. VM test `try-injection`: a value containing `") io.popen(` is refused.

### h.7 First boot and onboarding

§e.9 steps 1–3 (unlock-finalize, enrollment catch-up / repo-publish, secrets-prompt) run first. Then:

1. **Desktop first.** Login (autologin rules per H12) lands in the full omanix desktop: theme, bar, dock, menu, apps. omarchy's first-run invitations are not shipped.
2. **Welcome** (`omanix.welcome`, dismissible, reopen from the menu). A live checklist:
   - Network — ✓ on full NM connectivity; else **Connect** opens the network panel; captive portal opens the browser.
   - Publish this computer's configuration — only while `repo-publish` is pending (§e.9).
   - Write down your system encryption key — a confirmation (it was shown once at install).
   - Sign in ada — §h.3.6; enabled once network and publish are ✓.
   - Sign in the reviewer — **Skip** allowed ("cards will show facts only and always ask for a closer look").
   - Take the tour — optional.
3. **Tour** (agent-led when signed in, a static 5-slide version otherwise), each stop highlighted by the shell: the `SUPER + SPACE` menu ("things you do here; things you change, you ask for"); the `SUPER + A` panel; a sample card in a frame labelled **EXAMPLE — nothing will change**, without an Approve button (how to read Facts vs AI review); the Undo toast; "What can I change?".
4. The resident's first turn (skill `onboarding`): `omanix context --json`, one sentence on what this machine is, three chips. It never asks for secrets.

**Install answer "Use an AI agent?"** (§e.5 4a): **yes** (residents enabled, welcome offers sign-in), **later** (residents exist but stay signed out; the panel shows "Sign in ada" above the no-agent view), **no** (`loom.agent.enable = false`, reviewer and chatd off; the panel becomes **Change settings**: options browser, how-tos, "Open host repo", "Apply"; the bar widget shows a wrench).

| Works before sign-in | Needs the resident |
|---|---|
| everything installed and declared; all kept GUI tools; lock, power, capture, network, Bluetooth | changing what's installed or declared by asking |
| Update cards (routine when every changed input is a verified release, otherwise escalated) and approving them; Undo / rollback; watchdog | reviewer summaries; diagnoses (`why-failed` output is still shown raw) |
| options browser, how-tos, the human-only path and tools | Make it stick (falls back to its how-to) |

### h.8 CLI contract and verbs

Every `omanix` and `loom` command takes `--json`, never reads a TTY when `--json` is given, and returns **0** ok, **1** failed, **2** usage/refused guard, **3** needs human approval (card waiting), **4** rolled back, **5** offline/busy/retry later. `checks.cli-contract` runs every command with `--help --json` and `--json` in a VM and validates outputs against their schemas. Every verb only edits files in the working copy and checks the result by evaluating it; none switches the system, and none is required (the same change can be made by hand). **No verb refuses for policy reasons** (V4).

| Command | What it does |
|---|---|
| `omanix context` | **First command of every session.** Host id, generation, deployed commit, working copy ahead/dirty, plugins, last switch and card result, runtime snapshot summary (`runtime.json`), enrollment, catalog index, skills. |
| `omanix options <q> [--origin <o>]` | Full-text search over the option catalogs: path, type, default, origin, description. |
| `omanix where <option\|file>` | **Live eval** in the working copy: `definitionsWithLocations` → file:line, priority and value per definition, host files marked editable and input files not; for an HM target, the owning `omanix.*` option, the overlay path and any shadowing key from `runtime.json`. |
| `omanix explain <option>` | `options` + `where` + current value + whether and why the path is on the highlight list (`loom facts explain`). |
| `omanix set <path> <json>` / `unset` | Resolve with `where`; if **exactly one** host definition is a literal, rewrite it in place (rnix-based editor, U19); if none, append under the marker line of `configuration.nix` (`home.nix` for `home.*` paths); if several or an expression, exit 2 with file:line for each ("edit by hand"). Then `nixfmt`, evaluate `config.<path>`; if it doesn't equal the value, revert and exit 1 showing the winning definition. Reports `shadowedBy` from `runtime.json`. |
| `omanix plugin inspect/add/remove` | §b.4. |
| `omanix app add/remove <name>` | omarchy app → `omanix.apps.<n>.enable`; webapp/TUI → `omanix.apps.{webapps,tuis}.<N>`; otherwise a nixpkgs attr checked with `nix eval nixpkgs#<attr>.meta.mainProgram` → `home.packages` in `home.nix`. |
| `omanix secret set <file> <name>` | The value comes from the human through the chat panel's secure field (never recorded in the ledger, never shown to the resident) or stdin; encrypt-only, never echoed or decrypted. |
| `omanix persist add <path>` / `persist audit` | §f.1. |
| `omanix hw probe [--write]` | §f.2.6. |
| `omanix check` / `plan` / `propose` | eval + build + nvd (+ `loom facts explain`); `propose` pushes `gate/<topic>` and calls `loom propose`. |
| `omanix update [<input>]` | bumps omanix (or a named input) to the newest signed tag/rev and proposes ("Update ready"). |
| `omanix status` / `doctor` / `why-failed [--last]` | failed units, configerrors, persist gaps, sops decryptability, shadowing; `why-failed` gives the failing drv log plus origin option, or the watchdog check plus a journal excerpt. |
| `omanix try <path> <value>` / `try --reset` | live preview, no commit (§h.6). |
| `omanix reset` / `edit` | human-session overlay tools (§f.4.8). |
| `omanix repo open [<file>]` | human: opens the working copy `~/omanix-host` (created on demand from the local mirror) in the editor. |
| `loom propose` / `card {show,export}` / `approve [<tip>\|--card f]` / `undo` / `rollback --to <n>` | §g.3, §g.7, §g.10. |
| `loom facts {compute,explain}` / `requests {show,gc}` / `audit [--from-silo]` / `stats` | §g.4, §g.2, §g.11, §g.6. |
| `loom user passwd` | Human-only CLI form of the Change password dialog (§h.11); refuses `--json` and the agent uid. |
| `loom hw regen` | Re-runs `loom-detect` and `nixos-generate-config --no-filesystems` into the working copy's `hardware.{nix,json}`; no switch. |
| `loom status` / `keys {list,sync,add-human,remove-human,rotate}` / `unlock {status,add,remove,reseal}` | Platform. `keys rotate encryption-key` and `add-human --generate` show or take a secret, so they refuse `--json` and refuse to run as the agent uid (§g.12, §g.14). |

**Deleted:** `omanix keep`, `omanix apply` (→ `propose`), `omanix keybinds/menu/themes/apps/commands` listing verbs (→ `options` + catalogs), `loom policy explain/classify`, `loom switch` (→ `loom propose`).

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
| `themes.json`, `apps.json`, `persist.json`, `secrets.json` (names), `services.json`, `unlock.json`, `commands.json` (`omarchy commands --json` merged with omanix/loom, each with `origin`), `highlight.json` (the effective highlight list) | registries and status | per host |
| `host.md` | generated from `host.json` + `options/host.json`: plugin and host option roots with descriptions, overridden files, persistence additions | per host |
| `index.json` | every file with its sha256 | per host |

Deleted: `schema/settings.schema.json`, settable level/class columns, `definitions.json` (definitions are looked up live by `omanix where`). `checks.catalog-size`: per-host files < 2 MB; shared option files < 15 MB (U20).

### h.10 CLAUDE.md layers and skills

**omanix, loom and nuketown repos.** `CLAUDE.md` is `@AGENTS.md`, a router with: the layers; the rules (path == option, mkDefault, `nix flake check` is the single gate, never edit the pinned upstream (use `fork/`), never improvise disk ops); the task index into skills; "a KEEP-AS-GUI writer may only write runtime state; `checks.hm-owned-readonly` will tell you"; "generated dotfiles come from options; never hand-write a file under `~/.config` in a module".

**Host repo `CLAUDE.md`:** host notes only (§d.4).

**Resident prompt** (nuketown + `loom.agent.promptFragments` + omanix): working copy `~/projects/host` (auto-cloned from the local mirror, push to silo `gate/*`); the exit-code table; "batch one request into one proposal and add a `Request-Id` trailer per human turn"; "run `loom facts explain` before proposing and tell the human what will be highlighted"; "never handle secrets; name the human-only tool"; a **generated** top-level option index (root descriptions of `loom.*`, `omanix.*` and plugin roots) and "read `catalog/host.md` before changing a plugin". With `loom.agent.sudo = "approval"` it adds "approved sudo bypasses review; prefer a proposal".

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
| `security` | sshd, fido2, fingerprint, ssh-agent, docker group; always highlighted |
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
| No agent | install answer "no" | No residents, no chatd. Panel = **Change settings** (options browser, how-tos, Open host repo, Apply). |
| Later | install answer "later" | Residents exist, signed out; "Sign in ada" above the no-agent panel. |
| Signed out / offline | token expired, no network, provider down | Banner in the panel; intents open their how-to; cards still work (reviewer absent → escalated). |
| Preference | the human wants to do it themselves | "Do it myself" on every intent and in the panel header. |

**Human-only path (same gate).**
1. `~/omanix-host` is a working clone of the host repo, created on demand from the local mirror (origin = silo; the human key may push `gate/*` and `master` per CODEOWNERS).
2. The **how-to** for an intent comes from its `manual` hint: file, option, snippet, docs link. "Open in editor" opens `$EDITOR` at the line `omanix where` reports, or the end of the file; "Copy snippet".
3. The human commits **with their own key**, then `loom propose` (or the panel's **Apply**). switchd computes facts and shows the card; the reviewer is skipped because every commit is human-signed (§g.3 step 10); the approval merge uses the same gesture. Without a session, `loom-card-tty` renders the card and asks for the touch or passphrase on the pty.
4. Watchdog, rollback and Undo are identical.

**Human-only tools** (secrets and keys never pass through a resident):
- **Change password** (System › Security): a Quickshell dialog runs `mkpasswd -m yescrypt` in the human session, `sops`-encrypts to host, human and SEK recipients, and hands the ciphertext to switchd. switchd commits it **host-signed** with `provenance.kind = "maintenance"` and the `Request-Id` of the dialog's ledger turn (`surface = "tool"`), so the approval is the only key gesture (escalated: `users.users.<u>.hashedPasswordFile` content and `secrets/user.yaml`).
- **Drive encryption key** (`loom keys rotate encryption-key`), **add human key** (`loom keys add-human`), **secret values** (`omanix secret set` from the human's terminal or the panel's secure field): the resident can only say which command to run.
- **Agent sign-in** (§h.3.6) is done by the human in the resident's login terminal; the resident never sees the provider password.

---

## i) Testing (`nix flake check` = the single gate in every repo)

### i.1 Pure checks

| Group | Checks |
|---|---|
| eval | `eval-*` fixtures: ref-default, ref-nvidia, ref-laptop, vm-test, agent-sudo-approval, no-agent (`loom.agent.enable = false`), reviewer-off, server, **lanzaboote** (D7); omanix on `nixos-unstable` only, loom/nuketown on 26.05 **and** unstable (D1); `signi-compat` (N6); `preflight-vmvariant` (loom's `virtualisation.vmVariant` evaluates for every fixture) |
| conventions | `layout` (declaring file == option path via `declarationPositions`), `priorities` (+ force-allowlist), `documented`, `assertion-messages` |
| host repo | `host-template` (template + sample answers render, evaluate and build with IFD off; exactly one `nixpkgs` lock node, U29); `keys-sync` (render(`loom.keys`) == committed files; refusal cases: no owner, two owners, deleted CODEOWNERS; the mint stub tree passes); `hostgen-escape` (answers with `"`, `\`, `${`, newlines, unicode are rendered as data or refused); `home-owned` (U31); `set-roundtrip` (literal rewrite, append, nested attrs, `with pkgs; [ ]` lists, comments kept, multi-definition refusal; U19); `catalog-size` (U20) |
| facts and trust | `facts-cases`: ~30 fixture pairs (old/new view, lock, unit trees, HM generations) → the exact `facts.json` including `escalate` — docker group add, new root timer, firewall port, port option + socket, new input, follows change, unverified release, downgrade, overlay add, `.bashrc` / autostart change, `loom.reviewer.enable = false`, `highlight.extra` change, `loom.agent.sudo` none→approval, recovery fingerprint change, CODEOWNERS gains the agent key, a rebuild with an identical drv → no unit fact; plus one fixture per effects and derivation class: a package shipping `share/polkit-1/rules.d/00.rules`, `nix.extraOptions = "extra-trusted-users = ada"`, `services.udev.extraRules` with `RUN+=`, `boot.kernel.sysctl."kernel.core_pattern"`, a `boot.extraModprobeConfig` `install` line, an initrd unit content change, `environment.etc."pam.d/sudo"` via `mkForce`, `services.dbus.packages`, `networking.nftables.ruleset`, `services.openssh.{extraConfig,authorizedKeysCommand}`, autologin, `users.users.<n>.initialPassword`, `boot.initrd.secrets`, an overlay patching sudo, a changed `systemd.services.x.script`, a same-version kernel patch, `ExecStartPre=+` on a `User=` unit, `AmbientCapabilities` on a DynamicUser unit, a `nix-daemon` drop-in with `Environment=LD_PRELOAD`, a `.mount` unit, a moved `omanix/loom` lock node, a tag whose target ≠ `locked.rev`, a plugin input rev bump, a `.claude/settings.json` hook, an `hm-session-vars` change, and a free-Lua `io.popen` line (U8, U16); `presentation-rule` (truth table: facts × checks × provenance × review status → routine/escalated); `review-validate` (switchd's validator: oversize, control/bidi/zero-width characters, nonexistent file refs, bad enum → `invalid`); `suspicious-text` fixtures; `schemas` (every `loom.*/v1` schema validates its fixtures); `approval-verify` pure fixtures for §g.7.3 (U6) |
| fork | `fork-classify` (U21), `menu-intents`, `hw-quirks`, `skills-no-arch`, `fork-license`, `themes-render`, `jsonc-equivalence`, `keybind-conflicts` (both locations named), `hl-symbols` and the `omarchy-src` post-check (`no-usr-paths`, call graph, `luac -p`, `qmllint`) |
| home | `home-files-golden`, `hm-owned-readonly`, `runtime-writers`, `hm-unmanaged-paths`; `eval-*` fixtures assert `home-manager.users.<u>` builds with `home.enableNixpkgsReleaseCheck` on |
| catalogs | `catalogs` (all build and validate; `index.json` complete), `cli-contract` |
| security | `no-plaintext-secrets`; `sidecar-schema` (v2 answers closed set) + secret-pattern rejection (incl. `SEK1-`); `script-preamble-identical`; `repo-id-vector`; `sek-vectors` (python ↔ initrd sh ↔ `age-keygen -y`, plus the token-schema fixture) |
| size and lint | `closure-budget`, `closure-dupes`, `lint` (nixfmt, statix, deadnix, shellcheck, pytest: `omanix-overlay` kv formats, shell.json rebase, settle semantics; `omanix-runtime-snapshot` schema; `loom-chatd` ledger chain and peer checks; `loom-hostgen`; `loom-facts`; the write-site scanner fixtures) |

**Removed:** `schema`, `settable-review`, `settings-guard`, `policy-view-golden`, `policy-classify-cases`, `upstream-pin-tag`, `upstream-drift`, `script-map-complete`, `writer-map` (coverage over all upstream writers), `authorized-keys-in-sync` (folded into `keys-sync` and switchd's structural refusals).

### i.2 VM tests

Shared fixtures in `loom/tests/lib`:
- OVMF, swtpm, and canokey (FIDO2) through `virtualisation.qemu.package = pkgs.qemu.override { canokeySupport = true; }` (nixpkgs builds QEMU without it). `canokey-qemu` is marked broken on 26.05, so the canokey-dependent tests (`fde-fido2`, the FIDO2 cases of `pipeline-e2e` and `silo-enrollment` S4, U1) run only on the unstable/26.11 leg; the 26.05 CI leg skips them and says so
- **nested KVM:** a test that boots a preflight VM inside a test VM declares `requiredSystemFeatures = [ "kvm" "nixos-test" ]` and skips when nested virtualisation is missing; every other test exercises the preflight path with a stubbed VM runner
- the silo stand-in (`silo-standalone`, host `silo.test`, test host key)
- test human and release keys
- **a `networking.hosts` tripwire mapping `silo.loom.farm` to `0.0.0.0` in every node**

The installer test image differs from the release image only in three ways: `loom.installer.tty = "ttyS0"`, the baked `loom.silo.host = "silo.test"`, and a red banner/label. **There is no answers file and no unattended code path.** The driver reads the line-mode TUI on the serial console and answers it, and passes `loom.host=<id>` on the cmdline. The release image asserts `silo.host != silo.test`.

| Test | Repo | Asserts |
|---|---|---|
| `fde-passphrase` / `fde-fido2` / `fde-tpm2-pin` / `fde-recovery` | loom | Unlock per method. `fde-recovery`: typing the `SEK1-…` text at the Plymouth prompt unlocks via `loom-askpass` after the swtpm state is wiped; the raw `R`, the age identity and a wrong-check key all fail; the unknown `loom-sek` token doesn't disturb `systemd-cryptsetup`. The bootstrap slot is absent (luksDump). |
| `sek-rotate-crash` | loom | §g.14: a crash after each phase, then resume, reaches `done`. At every point some SEK opens the disk and decrypts the deployed secrets. After `done`, the old SEK fails both. |
| `fde-tpm2-requires-sb` | loom | The assertion fires without SB. With Limine SB (test keys), first-boot `unlock-finalize` enrolls TPM2 and the next boot auto-unlocks. Autologin is forced off. |
| `boot-lanzaboote` | loom | D7: the same SB + TPM2 flow with `loom.boot.loader = "lanzaboote"` (signed UKIs from the installer's sbctl keys); a lanzaboote generation rolls back like a Limine one. |
| `impermanence-survives-reboot` | loom | §f.1 |
| `hm-reclaim` | loom | A regular file is put in place of an HM link, and a backup-restored `~/.config/hypr` tree is planted. The next switch reclaims both into `reclaimDir`, sends the notification, and activation succeeds. A deliberately failing HM activation trips the `hm-activation` watchdog check and rolls back. |
| `sops-host-key` / `sops-tpm-age1tag` | loom | The file backend decrypts. The second test settles the UNVERIFIED age1tag round trip and gates the `tpm` backend. |
| `repo-id-vector` | loom | §d.5 |
| `pipeline-e2e` | loom | On the S3 stand-in: a chat turn on `chat.sock` → replay resident commits with `Request-Id` → `loom propose` → facts → reviewer (`harness = "replay"`, canned JSON, inside the real sandbox unit) → routine card → broker `SIGN` → canokey FIDO2 touch through the Quickshell-askpass stub (U1) → approval merge verified → switch promoted → `master` pushed with the host key; the ledger head is in the switch record. A software-key variant approves by passphrase. |
| `replay-refused` | loom | Re-submitting a used approval, an approval on a different base, a wrong host id, an expired one, a reused nonce, a tree ≠ tip, and an approval signed by the agent or host key are all refused; the card stays open. |
| `sign-from-nonroot-refused` | loom + nuketown | `SIGN` on the broker socket from uid 1100 and from uid 1000 is rejected (N11). |
| `ledger-forgery` | loom | Resident frames claiming `author: human` are refused and logged; a prefilled-but-unsent intent creates no record; an agent-choice click is recorded with `surface = agent-choice`; pasted spans are recorded; editing an old ledger line breaks the chain check. (W9) |
| `provenance-facts` | loom | A `Request-Id` pointing at an agent turn gives `provenance.invalid`; an agent-choice turn, a stale, cross-thread or already-used request and a pasted span escalate; every reply carries its preceding agent turn as UNTRUSTED in the bundle; an agent-prepared rollback escalates with "prepared by ada, not requested". (W10) |
| `reviewer-isolation` | loom + nuketown | Inside the review unit: `curl https://example.com` fails; a CONNECT for a non-allowlisted host through the proxy fails; writes outside `/state` fail; `/agents/ada`, `/home`, `/run/loom/chat*.sock`, the broker socket and `/persist` are absent; `id` = reviewer; the reviewer's login portal sets `CLAUDE_CONFIG_DIR` under the auth dir and `HTTPS_PROXY`, and the pre-run wipe keeps only the credential files. A bundle saying "run `touch /state/pwned`" leaves no file and no `execve` beyond the harness under `strace -f` (U3, U4, U5). |
| `reviewer-cannot-deescalate` | loom | A reviewer stub returning approve/yes on a critical-fact bundle → still escalated; invalid JSON → `status = invalid`, escalated; a reviewer `file`/`line` outside the diff is dropped. |
| `reviewer-down` | loom | Proxy stopped, or reviewer signed out → `review.status = unavailable`, escalated, approval still works. `loom.reviewer.enable = false` → same with "No AI review". |
| `undo-rollback` | loom | GUI Undo (a ledger `undo` turn) builds from the store, makes a host-signed revert, skips the reviewer, is routine and **needs exactly one signature** (the approval); an agent-prepared rollback is escalated; a watchdog failure path needs none; booting an older generation from the loader yields the "make it the default?" rollback card; `sudo nixos-rebuild switch` outside loom yields `drift.unmanagedSwitch` on the next card. |
| `switch-watchdog` | loom | A change → promoted. A commit that breaks the health check → rolled back, boot default unchanged, `gate/rejected/<tip>`. **switchd killed mid-test → the dead-man timer rolls back.** A commit that changes `loom-switchd.service` still completes or rolls back (the `loom-chatd` case runs in `pipeline-e2e`, W10). A proposal that breaks `~/.config/hypr/*.lua` fails `configerrors` inside the watchdog window, after the step-5a reload, and rolls back. An escalated card without the Keep click rolls back. |
| `preflight-runner-untrusted` | loom | A proposal setting `virtualisation.qemu.package` to a sentinel-touching script and `sharedDirectories` onto `/persist`: the script never runs, `/persist` is never visible in the guest, and the guest has no network. Uses the stubbed runner; a nested-KVM variant (`requiredSystemFeatures = [ "kvm" "nixos-test" ]`) boots the real guest and skips without nested virtualisation. |
| `update-card` | loom | The timer produces a host-signed `update:` commit on `gate/update/<date>`; a signed omanix tag → routine "Update ready"; an unsigned rev or downgrade → escalated with the fact; a plugin input rev bump → escalated; nothing switches without the approval. |
| `card-latency` (benchmark, **not a gate**) | omanix | A nightly job on the reference laptop, like §i.3: a cache-hit package add with VM smoke reaches the routine card in ≤ 2 min (U14); the ports fact is identical across 20 smoke runs of the same generation (U17). |
| `silo-enrollment` | seed + loom | On the S3 stand-in: (1) the first push by the human test key ⇒ `.owner_key` = human, HEAD = master; (2) the enroll key pushes the install commit (CODEOWNERS at the mint HEAD); (3) afterward the enroll key is rejected on `master` **and** on `gate/*`; (4) the host key pushes `master`, the agent key only `gate/*` and may force-push/delete `gate/*` (U15); (5) a push without `CODEOWNERS` in HEAD is never produced by loom; (6) sk keys work as owner, in CODEOWNERS and in `.authorized_keys` (S4); (7) a second line in `.owner_key` loses the owner bypass (documents F3 for S1); (8) the enroll key force-pushes `master` with an extra attacker key in both files, then `configure revoke-enroll` lists the unsigned commit, recommends re-mint, and with `--reuse-anyway` restores the exact human-only set so the attacker key is rejected on `master` and `gate/*`. |
| `installer-offline-eval` | loom | Network-less install evaluates the host flake from the archived inputs. |
| `installer-e2e` (loom-only profile) | loom | The driver runs `loom-mint` (human test key pushes) → flash a fake USB → console-driven install with agent sudo = none (the SEK paper check first rejects a retype with one wrong group, then accepts the full key) → reboot → unlock with the SEK → `git ls-remote` shows the install commit → enroll key rejected → `nuketown.agents.ada.sudo` off. **Preconfigured variant:** after reboot, first-boot `owner-key-local` recovers the resident FIDO2 handle with `ssh-keygen -K` (canokey) and the first card (secrets-prompt) is approved locally; with a software owner key that stayed on the configuring computer, the first card is approved through `loom card export` / `loom approve --card` and `--approval-from-silo`. |
| `installer-e2e-fresh` | loom | Fresh mode with no sidecar: the software owner key is generated with a passphrase (an empty passphrase is refused) → online first push creates the repo with `.owner_key` = that key → `/home/<user>/.ssh/id_ed25519` exists (0600, uid 1000) after reboot and is not an HM symlink → the first change card is approved by typing the key's passphrase. Offline variant: `repo-publish` at first boot; until it succeeds the agent units are inactive. **Squat variant:** before first boot the driver pushes to the computed id with another key; `repo-publish` detects the foreign owner, the agent stays stopped, and `loom fork` publishes under a new id. |
| `installer-e2e-sb` | loom | Setup mode OVMF: sbctl keys reach the chroot, Limine is signed, TPM is enrolled at first boot. |
| `installer-reinstall` / `installer-fork` | loom | The same stand-in repo is reused. The human test key authorizes the key swap. Secrets are re-encrypted with the age identity derived from the typed SEK, and the same SEK unlocks the new disk. Fork: new id, new human key makes the first push and is owner, secrets are carried over under a new SEK. A `master` rewritten with the host key (a commit that is not a valid approval merge) gives the red screen, and the default installs the last valid approval merge. |
| `flash-guards` | loom | Only the USB device is offered. Mounted devices are refused. A token is required, and a changed device invalidates it. Readback catches an injected bit flip. |
| `verity-corruption` | loom | A flipped byte gives the "damaged" message. |
| `nuketown-sudoex-bypass`, `nuketown-wayland-approval` | nuketown | N1. The broker works with `display = null` under Wayland. |
| `nuketown-hostshell-target`, `nuketown-broker-peercred` | nuketown | N14: with `restrictHostShellTargets`, the human can `machinectl shell ada@` but not `root@`; signi defaults unchanged. N2: the new broker rejects a peer whose uid is not allowed for the request kind; its socket directory exists with no sudo agent. |
| `nuketown-egress`, `nuketown-noninteractive` | nuketown | N8: `proxy-only` agent reaches only the proxy port; `full` unchanged. N9: `interactive = false` has nologin, no portal shell, no daemon, no linger, no sudo; its `login` portal entry still runs the harness login. |
| `desktop-boots` (+ greeter variant) | omanix | SDDM greeter on Hyprland and autologin → uwsm → Hyprland 0.56.2 + omarchy-shell on virtio-gpu. No QML errors (U24), configerrors empty, `OMARCHY_PATH=/run/current-system/omarchy` in the user env. `home-manager-<user>.service` finished before `display-manager.service`; every HM target is a store link; every overlay file exists; the clock's middle-click opens the timezone intent row instead of running a missing script. Variant `desktop-intents` (W18): a menu intent row pre-fills the chat composer and records nothing until Send (screenshot); the bar shows the approval and agent indicators. |
| `chat-socket`, `approval-focus` | omanix | The QML panel connects to chatd, survives a chatd restart and reconnects (U10); chatd records `uid = 1000` and the right session for the uwsm-launched Quickshell (U18). The escalated card over a fullscreen terminal takes focus only on click, accepts the passphrase, and returns focus (U13). |
| `theme-switch` | omanix | `omarchy-theme-set` works for two themes and kitty, alacritty and foot pick up the colors; lock resets the theme at the next login. No HM target changed. (The make-it-stick half is in `make-it-stick`, W21.) |
| `writers-respect-hm` | omanix | Runs every KEEP-AS-GUI `writes =` smoke: font set, text size, monitor scale, `omarchy-bar` position, glass on, gaps toggle, `chromium-add-feature`, keyboard layout picker (U28), `omanix reset hypr/hyprland.lua`, `reinstall-configs`. Then asserts: every HM target is still a link into the current generation; each runtime target changed; configerrors empty; `omanix doctor --json` lists the expected overlays and `omanix set omanix.fonts.monospace …` returns `shadowedBy`; `fc-match monospace` and `omarchy-font-current` return the new font; with a numeric HM scale, a panel scale change survives `omarchy-hyprland-monitor-clamshell`; an alacritty overlay key overrides `omanix-base.toml`. GTK4 absolute `@import`, missing-include and activation `xdg-settings` behaviour are settled here (U35). |
| `make-it-stick` | omanix | Change scale and theme in the GUI → snapshot attached and sent → replay resident maps it → card → approval → `settle` removes the matching kv keys and empties the absorbed whole-file overlay; an overlay changed after the snapshot is left and listed by `doctor`; the reviewer bundle holds only the typed snapshot part. |
| `shell-json-rebase` | omanix | With an overlay snapshot present, a change to `omanix.shell.settings` appears after re-login unless it conflicts; the conflict is listed by doctor. |
| `human-commit` | omanix | No-agent fixture: the human edits `~/omanix-host/configuration.nix`, commits with the human key, `loom propose` → reviewer skipped → card in `loom-card-tty` → passphrase → promoted. |
| `plugin-fixture` | omanix | A fixture plugin flake (`nixosModules.default` with a `StateDirectory` service, `homeModules.default` with a file) added by `omanix plugin add`: one nixpkgs node (U29), HM half evaluates (U30), the persist audit fails before `omanix persist add` and passes after (U32); the card carries `inputs.added`. |
| `try-injection` | omanix | `omanix try` with a value containing `") io.popen(` and with a path outside `catalog/preview.json` is refused by the human-session helper; the dialog shows the rendered key and value. |
| `vm-demo-2` … `vm-demo-6` | omanix | Demo scenes 2–6 (§j) headless with the replay harnesses, asserting card presentation, fact ids, reviewer recommendation, rejection delivery and rollback. `vm-demo-4` is the **injection scenario**: a README attachment with hidden instructions makes the replay resident add a substituter, enable sshd and a root service; the card must be escalated with ▲ trust, ▲ sshd/port 22, ● service facts, the replay reviewer flags the mismatch, the rejection reason reaches the resident, and the follow-up package-only proposal is routine. |
| `installer-e2e-omanix` | omanix | Same as `installer-e2e` with the omanix flavor image and `cacheMiss = []` offline. |

### i.3 Reviewer quality corpus (not a gate)

`loom/tests/review-corpus/`: about 50 adversarial diffs (injection strings, hidden exfiltration, mismatches against the request) plus ordinary asks. A nightly networked job (never `nix flake check`) measures the reviewer's flag rate and false-reject rate per model. The deterministic share (`suspiciousText` + facts) is asserted at 100% in `facts-cases` for corpus items tagged `structural`.

### i.4 UNVERIFIED (each with the test that settles it)

| # | Claim | Settling test |
|---|---|---|
| U1 | `ssh-keygen -Y sign` with an `sk-ssh-ed25519` key from the broker user service under Wayland prompts touch/PIN through `SSH_ASKPASS` with no TTY | `pipeline-e2e` with `-device canokey` and a Quickshell-askpass stub |
| U2 | `nix eval` under `restrict-eval` can apply a view function from the running generation's store path to the proposal's config | VM: `--apply "import $current/loom/view.nix"`; else add the path to `allowed-uris` or use `builtins.getFlake` on a locked `path:`; record which works |
| U3 | The reviewer harness honors `HTTPS_PROXY` for every request (incl. OAuth refresh, telemetry) through a CONNECT-only proxy with the nft drop rule | `reviewer-isolation` + a live run on signi with the proxy log showing only allowlisted hosts; fallback `harness = "api"` |
| U4 | Claude Code `-p` with all built-in tools disabled, no MCP, no setting sources executes nothing | `reviewer-isolation` strace case; record the exact flags in `loom-review/run` |
| U5 | That configuration still returns valid `loom.review/v1` with no tool_use events | adapter test with a prompt asking it to read a file |
| U6 | `git verify-commit` on an ssh-signed merge reports the `allowed_signers` principal (`%GS`) and honors `namespaces="git"` | `approval-verify` fixtures |
| U7 | `nix flake archive` as a DynamicUser fetches every locked node so a later networkless `loom-eval` succeeds | VM: archive, cut network, eval |
| U8 | Units from `systemd.packages` appear under `$out/etc/systemd/system` in a parseable form | `facts-cases` fixture with a unit-shipping package (cups) |
| U9 | `/run/omanix/session/<uid>/runtime.json` is readable by the resident (group `omanix-resident`) and not by the reviewer | VM: `sudo -u ada cat` succeeds, `sudo -u reviewer cat` fails |
| U10 | Quickshell 0.3.2 `Quickshell.Io.Socket` speaks newline-delimited JSON over a unix socket with `SplitParser` and reconnects | `chat-socket` |
| U11 | Claude Code runs long-lived with stream-json in/out, emits tool events usable for the activity rail, and a session resumes in the TUI | adapter fixture test against the pinned package; manual resume check |
| U12 | The harness `/login` run as a non-human uid via `machinectl shell` completes with the browser in the human session (code paste or loopback) | manual VM test with a real account; adjust `loom-open-url` |
| U13 | A layer-shell overlay card takes keyboard focus on click and releases it under Hyprland 0.56 + Quickshell 0.3.2, above fullscreen windows, without leaking content to other clients | `approval-focus` |
| U14 | Routine card latency ≤ 2 min for a cache-hit package add including VM smoke | `card-latency`; if over, `preflight.vm = "auto"` skips the smoke for package-only diffs (recorded as a fact) |
| U15 | silo F4 lets the agent key force-push and delete `gate/*` and push new `refs/dit/*`, and rejects `master` | `silo-enrollment` additions on the S3 stand-in |
| U16 | `nix store diff-closures` output parses stably on nix 2.34 and unstable's nix | pure fixture on two known toplevels, both versions |
| U17 | The ports fact from the VM smoke is stable (no flapping ephemeral listeners) | `card-latency` repeat runs |
| U18 | `SO_PEERCRED` and the logind session lookup are right for the uwsm-launched Quickshell | `chat-socket` (W18) asserts `uid = 1000` and the session |
| U19 | `nix-editor` (rnix) rewrites nested attrs and list literals without losing comments; else a tree-sitter-nix editor | `set-roundtrip` against both backends |
| U20 | `nixosOptionsDoc` over the full eval with plugins builds without IFD and within budget | `catalog-size` on `ref-default` + the fixture plugin |
| U21 | The counts and classifications match the fork point `5978d93` (surveyed on `bc220e7`) | build `omarchy-src` at `5978d93`; `fork-classify` and `menu-intents` green (unclassified paths print a ready-to-paste stub) |
| U22 | Which `omarchy` icon-font codepoints are brand glyphs, and whether the bar uses them | glyph dump + grep `shell/**`; VM screenshot with `omanix-glyphs` |
| U23 | Theme backgrounds/videos are redistributable or have separate credits | porting report step 9 at `5978d93`; unattributed files are excluded |
| U24 | Patched QML (P1, P5, P7, P8, P10–P13, P17–P19) loads under quickshell `2b4501a` with Qt 6.12 | `qmllint` post-check + `desktop-boots` |
| U25 | `SUPER + A` is unbound in the upstream Lua at `5978d93` | replay bindings under the recording `hl.*` stub; otherwise pick the first free chord |
| U26 | nixpkgs/nixos-hardware cover intel-lpmd, ipu7, asus/dell firmware, framework-16, surface, apple-t2, tuxedo-drivers | `nix eval` each attribute; missing ones are packaged or deferred |
| U27 | omarchy's NvPCR drop-ins are neutral to loom's PCR 7 policy | swtpm + SB VM, enroll with and without them, reboot 3×; adopt only if neutral |
| U28 | The keyboard picker override works when the HM `keyboard-layouts`/`input.lua` are read-only and the live `kb_layout` check passes | `writers-respect-hm` keyboard case |
| U29 | `nixpkgs.follows = "omanix/nixpkgs"` plus a plugin's `inputs.nixpkgs.follows = "nixpkgs"` yields one nixpkgs node | `host-template`, `plugin-fixture` |
| U30 | `home-manager.extraSpecialArgs.inputs` is visible to modules imported via `home-manager.users.<u>.imports` and usable in their `imports` | `plugin-fixture` HM half |
| U31 | `definitionsWithLocations` of `home-manager.users.<u>.home.file.<t>.{text,source}` lists host-file definitions with their priority, so `checks.home-owned` can detect a user `.text` (which would silently lose) and a non-`mkForce` `.source` | `home-owned` fixtures: user `.text`, user `.source`, user `mkForce` `.source` |
| U32 | `persistAudit` maps a `DynamicUser` `StateDirectory` to `/var/lib/private/<svc>` and the bind works under impermanence | `plugin-fixture` sentinel survives reboot |
| U33 | systemd-cryptsetup and libcryptsetup ignore the unknown `loom-sek` token type | `fde-recovery` |
| U34 | SDDM `wayland.compositorCommand` with the Hyprland greeter config works | `desktop-boots` greeter variant; fallback greetd |
| U35 | foot/kitty with a missing include; GTK4 absolute `@import` honored by libadwaita; `xdg-settings` from activation without a session bus | `desktop-boots`, `writers-respect-hm` |
| U36 | Offline flake eval during install from archived inputs | `installer-offline-eval` |

---

## j) Demo script (community proof of concept, ~12 min, VM on a laptop)

Deterministic runs use `loom.agent.harness = "replay"` and `loom.reviewer.harness = "replay"` (scripted transcripts, the same bridge events, real commits and real cards); a live run uses claude-code for both. Assets live in `omanix/demo/`; `checks.vm-demo-<n>` runs scenes 2–6 headless.

1. **"An omarchy that started on nix"** (90 s). Flash the USB image, install (time-lapse: SEK paper check, unlock choice, "Use an AI agent? yes"), first boot: the full desktop is there before anything else. Welcome: network ✓, sign in ada through the provider's normal login in the browser, sign in the reviewer. *Shows: polished desktop immediately; no credential copying.*
2. **"Install and configure X"** (2 min). Menu › Install › Gaming › Steam. The composer is prefilled; Enter. Activity rail: reading `configuration.nix`, editing, `omanix check`, building, VM smoke, review. (VM smoke needs nested KVM and ≥ 8 GiB guest RAM, which are demo prerequisites; without them the rail shows "VM smoke skipped (no KVM)".) A one-line card quoting what Josh asked; touch the YubiKey; Steam is in the launcher. Then "and hide the dock unless I hover" → a second one-line card. *Shows: agent as UI; routine cards are one line.*
3. **"Try it, then keep it"** (1.5 min). Theme picker, live preview, pick Kanagawa; toast → Make it stick → one-line card → chip gone. `git log -1 -p` in the host repo: one line in `configuration.nix`. *Shows: GUI for visual browsing, nix for persistence.*
4. **"The README that wanted root"** (2 min). Attach a downloaded project README ("summarize this and install the tool"). It hides instructions to add a binary cache and enable SSH; the resident follows them. Escalated card: ▲ trust substituter, ▲ SSH on + TCP 22, ● new root service; AI review: "you asked to install fooctl; this also trusts a cache and opens SSH; recommend reject". Show git diff. Reject with reason "only the tool, nothing else". The resident gets the reason, recommits just the package, one-line card. *Shows: deterministic facts + independent reviewer + provenance.*
5. **"Break it, get it back"** (1.5 min). Ask for a change that breaks the compositor (a monitor rule the VM's virtio output rejects, so `hyprctl` stops answering). Approve; the screen glitches; within the watchdog deadline the old generation is back; panel: "Rolled back: Hyprland didn't answer" → "Why?" chip → `why-failed`. Then a working change and the Undo toast: one touch, seconds. *Shows: rollback by default; nothing reaches the boot default until healthy; even undo is signed.*
6. **"Two residents, one machine"** (1.5 min). Terminal as the human: `id ada`, `id reviewer`, `ls -ld /agents/*` (0700), `sudo -u reviewer curl https://example.com` fails, `sudo -u ada cat /home/josh/.ssh/id_ed25519` fails, ada's push to `master` on silo refused (`gate/*` only), `journalctl -u 'loom-review-*'` shows the reviewer's sandbox, `loom requests show` shows the root-held ledger. *Shows: nuketown user partitioning as the security boundary.*
7. **"Reinstall from the repo"** (1.5 min). Wipe the VM disk, boot the USB with `loom.host=<id>`, type the SEK, same desktop, same Steam, same theme. ada must sign in again; her old conversations are gone; the machine is identical. *Shows: the host repo is the machine.*
8. **"No agent, same rules"** (1 min, optional). Network off. Menu › Appearance › Top bar › Clock › 24-hour opens the how-to (Steam is already installed, so its Install row is disabled); Open in editor; save; Apply. It is a text-file change whose closure builds from the local store, so it needs no network. The card in the terminal (`loom-card-tty`); touch. *Shows: it's just NixOS.*

---

## Decisions

### Resolved (2026-10-27)

| # | Decision | Where |
|---|---|---|
| V1 | omanix is a proof of concept: omarchy as if it had started on nix. It **forks** omarchy at v4.5.0-rc2; omarchy is product spec and asset source; its bash state-mutation layer is replaced by nix; drift is an optional porting report, not a gate. | H3, §a.1, §f.2, §i.1 |
| V2 | Agent-first: the agent is the primary UI for change. GUI tools stay only for continuous controls, instant toggles, visual browsing with preview, and reaching or repairing the agent. GUI changes are runtime state; make it stick is a request. The menu is an intent launcher. Fully usable without the agent. | §f.3, §f.4.6, §h.5, §h.11, H19 |
| V3 | The UI agent is a nuketown resident (`ada`), not a process in the human's session; a Quickshell chat surface talks to it through a root relay. Showcasing user partitioning is a goal. | §a.3, §c.3, §g.1, §g.2, §h.3, §j scene 6 |
| V4 | No settings registry, schema, settings file, tiers, `extraProtected` gate, `humanKeyKind` or unattended updates. The resident may edit any module and flake input. Every switch needs a human signature; switchd activates only human-signed approvals; watchdog + automatic rollback stay; updates are "Update ready" cards. | H5, H6, §c, §d, §g.3, §g.7, §g.9, §g.10 |
| V5 | The approval card comes from an adversarial reviewer resident (no general network, read-only, writes nothing) reading the recorded request, git diff, nvd, results and deterministic facts — never the content the resident read. Facts are visually separate and unalterable by the reviewer; experts get "show git diff"; routine cards are one line. | H7–H10, §g.4–§g.6, §h.4 |
| V6 | `omanix.lib.mkHost` returns a `nixosSystem` with loom + nuketown + the omanix base, then loads the host's plain NixOS/HM modules. Plugins are modules from any flake. Typed verbs remain as agent tools; option catalogs remain. | H4, §b.3, §b.4, §d, §h.8, §h.9 |
| D1 | nixos-unstable (then 26.11) for the omanix stack; loom and nuketown stay CI-green on 26.05 for signi. | H1, §b.1, §i.1 |
| D2 | Fork point v4.5.0-rc2 (`5978d93`); moved only by a recorded decision prepared by the porting report. | H3, §b.1, §f.2 |
| D3 | No Seed-side builder in v1 (local Nix / WSL2). | H15, §b.1, §e.2 |
| D4 | Hands-free TPM2 only with Secure Boot on our keys (PCR 7); else TPM2+PIN with the evil-maid caveat. The host sops age key is a file inside LUKS; the TPM age key is opt-in. | H12, H13, §e.6 |
| D5 | The protected list is now a **deterministic highlight list** in loom that feeds card facts; it is not a gate. Hosts may only add (`loom.highlight.extra`); changing it is itself a critical fact. | H7, §g.4.1 |
| D6 | The human key creates the silo repo (owner); the enrollment key is temporary in CODEOWNERS/.authorized_keys and removes itself; S1 later; the installer can generate a passphrase-protected software owner key into `~/.ssh`. The agent key can push only `gate/*` and `refs/dit/*` (fast-forward), never `master` or tags (never in CODEOWNERS). | H6, H17, §a.4, §d.3, §e.2, §e.5, §g.11 |
| D7 | Limine default; lanzaboote supported and CI-tested. | H16, §c.1, §e.8 |
| D8 | Generic approval sudo for the resident is an install-time question, default off; turning it on is a critical fact on its card. It is equivalent to disabling the pipeline's guarantees (§g.15 #13), and requires nuketown's N1 (asserted). | H18, §c.1, §e.5 4a, §g.15 #13 |
| D9 | Human dotfiles are read-only home-manager files, now fed by `omanix.*` options and `home.nix` that the resident edits; only KEEP-AS-GUI writers remain, redirected to runtime overlays. `~/.ssh`, `~/.gnupg` never HM. | H14, §f.4 |
| D10 | Software human keys are allowed with no reduction of anything, but must have a passphrase (passphrase-less keys are refused). FIDO2 recommended. | §c.1, §e.2, §g.7.2 |
| D11 | Release tags, `SHA256SUMS` and the fork mirror are signed on Josh's YubiKey; the `omanix-cache-1` key lives on signi in sops, used only by the `release` skill through an approval; no CI secrets. | §e.1, §e.10, §f.2.7 |
| D12 | One system encryption key (SEK1) derives the LUKS recovery passphrase and the sops recovery age identity; crash-safe rotation tool, whose final commit is human-signed and goes through a card. | H13, §e.5, §e.7, §g.14 |

**Reconciliation calls made in this revision** (between the four drafts; details in `fork/changelog.md`): one root daemon `loom-chatd` (recorder + relay) instead of separate `loom-askd` + an agent-side recorder; trailer `Request-Id:`; reviewer user `reviewer` with options under `loom.reviewer.*`; the trust draft's approval-merge format and review schema; **Undo and rollback-to-generation need a signature** (the UX draft's key-less human rollback is rejected under V4); `loom propose` replaces `loom switch`; `SUPER + A` for chat; `loom.keys.*` replaces `loom.host.*Keys`; passphrase-less software keys refused; the chat bridge is a loom unit, not a nuketown daemon feature (N7 dropped); make it stick settles kv overlays per key and whole-file overlays by snapshot sha.

### Still open

| # | Question | Default in this document |
|---|---|---|
| O1 | `omanix.home.overlays` default: `"keep"` (runtime tweaks persist until stuck or reset) or `"reset"` (overlays emptied at each login; fully declarative desktop). | `"keep"` |
| O3 | When does S1 (owner handoff/rotation, with the `grep -qxF` pre-receive fix) get scheduled? Until then a compromised owner key means a fork. | after v1 |
| O4 | Should the installer push the user to add a second human key before finishing when the only one is a generated software key? | advise only |
| O5 | Second-device approval (card shown on XMPP/phone bound to the nonce) to close threat #6 for FIDO2 users. | not in v1 |
| O6 | Default reviewer model/provider and who pays for it; whether `harness = "api"` should be the default if U3/U4 fail. | claude-code, separate login |
| O7 | Should a rejected card's reason ever be shown to the reviewer of the follow-up proposal (it is a human turn, so it could be)? | yes, as a linked request |
| O8 | Remove the host key from silo `CODEOWNERS`? It can force-push `master` (F4); reinstall now verifies the chain and installs the last valid approval merge, but someone must still push `master` after a switch. | keep it in v1 (chain verified on reinstall) |
| O9 | `loom.chat.requestMaxAge` default: a cited request older than this escalates. Shorter catches broad old requests; longer means fewer escalated cards for slow work. | 24 h |

---

## Work packages

Rules for all packages:
- Each package lands with its own checks green; the touched repo's `nix flake check` is its gate, so every package is independently buildable.
- File ownership is disjoint, so agents can work in parallel without editing the same files.
- Deps are hard prerequisites. "(test)" means the dep is needed only for an integration test, not to start.
- The installer critical path never waits on the desktop track; the desktop track never waits on the installer.
- Every commit carries `Co-Authored-By: Joshua Perry <josh@6bit.com>`.

| ID | Title | Repo | Scope / files | Deps | Acceptance criteria |
|---|---|---|---|---|---|
| **W0** | Contract-first loom skeleton | loom | New flake layout; `lib/{mk-host,catalog,checks,repo-id,keys}.nix`, `force-allowlist.nix`; options-only skeletons for every `modules/loom/**` file in §c.1, except `modules/loom/{default,host,keys}.nix`, implemented fully (`loom.keys` and the `loom keys sync` renderer); `schemas/` with fixtures; `templates/host` (plain-module host: `configuration.nix`, `home.nix`, `machine.nix`, `keys.nix`, `modules/`); AGENTS.md; setup-remotes; CI matrix 26.05 + unstable (D1); lanzaboote input (D7); removal of the MVP auth/QR server and `installer.nix`. | — | `layout`, `priorities`, `documented`, `schemas`, `keys-sync` (incl. refusal fixtures and the mint stub tree) pass. The template host evaluates on both channels via `loom.lib.mkHost`. |
| **W1** | nuketown deltas | nuketown | N1–N6, N8–N15 (§a.3): `module.nix`, `approval-daemon.nix`, `broker/` (python, SO_PEERCRED, `SIGN` root-only, `--card` prompter contract), egress nft rules, `interactive = false`, `claudeCode.lockdown`, `homeMode` assertion, `checks.nix` | — | Existing checks pass. `nuketown-sudoex-bypass` fails before and passes after. `nuketown-egress`, `nuketown-noninteractive`, `nuketown-hostshell-target` (N14), `nuketown-broker-peercred` (N2) and the nuketown half of `sign-from-nonroot-refused` pass; the N15 NixOS broker unit evaluates. `signi-compat` passes; a mynix signi build's `nvd diff` shows only the broker package. |
| **W2** | silo test infrastructure | seed | S3 `silo-standalone`, S4 sk-key test, the `silo-enrollment` seed half, the agent-gate cases (U15: agent key rejected on `master`, accepted and able to force-push/delete `gate/*`, new `refs/dit/*`). **No change to `shell.nix` or `hooks.nix` behavior.** | — | `silo-enrollment` seed half passes: human first push ⇒ owner, HEAD = master, enroll self-removal, enroll rejected on gate/*, sk keys work, F3 multi-line note documented, U15 cases recorded. |
| **W3** | omarchy fork mechanics + packages | omanix | `flake.nix` (omarchy at `5978d93`), `fork/{UPSTREAM.toml,NOTICE,classify.toml,drop.txt,rewrite.toml,hl-symbols.txt,patches/*}` (P1–P4, P6, P9, P15, P16 branding, P17 weather; the shell-plugin patches P5, P7, P8, P10–P14, P18, P19 are W18; patch file numbers equal P-ids), `fork/add/bin/*` replacements (including the privilege-mapped overrides and read-only readers of §f.2.5), `lib/fork.nix`, `pkgs/by-name/*` (omarchy-src, hyprland-omarchy with 4 patches, titlebars, quickshell-omarchy, guiutils, the 13 apps, try-tobi, omanix-glyphs), `apps.{porting-report,fork-mirror}`, `LICENSES/`, `port-omarchy` skill | — | Every package builds. `fork-classify` is green **at `5978d93`** (U21) and Appendix-A/B/C-derived counts are regenerated there; `fork-license`, the `omarchy-src` post-check, `hl-symbols` pass. The titlebars `.so` loads in a headless Hyprland smoke. `porting-report --to bc220e7` produces a report (smoke, not a gate). |
| **W4** | Disk, unlock, boot | loom | `modules/loom/disk/*`, `boot/*`, `diskoLayout`, unlock text and assertions, the `loom-sek` LUKS slot + token, `loom-askpass`, the `unlock-finalize` first-boot step (declared from `disk/unlock.nix` into W11's runner), `loom unlock`, lanzaboote (D7) | W0, W6, W11 (test) | `fde-passphrase`, `fde-fido2`, `fde-tpm2-pin`, `fde-recovery` (U33), `fde-tpm2-requires-sb`, `sek-vectors`, `eval-lanzaboote`, `boot-lanzaboote` pass. The autologin assertion has a negative fixture. |
| **W5** | Impermanence, persist audit, snapshots, home wiring | loom | `modules/loom/persist/*`, `lib/persist-audit.nix`, `installBinds`, nuketown `@agents` rollback wiring, `modules/loom/home.nix` (HM NixOS module, `loomReclaim`, ordering drop-in, `hm-activation` watchdog check) | W0, W1 (test), W8 (test) | `impermanence-survives-reboot`, audit assertion fixtures, `hm-reclaim` pass; the `/home`-persisted assertion has a negative fixture. |
| **W6** | Secrets lifecycle, keys CLI, SEK lib | loom | `modules/loom/secrets/*`, `.sops.yaml` render, prompted secrets, `pkgs/loom-cli/{sek.py,keys.py}` (`loom-sek`; `loom keys list/sync/add-human [--generate]/remove-human/rotate host|agent`, `loom user passwd`; passphrase-less software keys refused) | W0, W5 (test) | `sops-host-key` passes; `sops-tpm-age1tag` runs (red allowed, then `tpm` asserted off); `sek-vectors` (python half + token schema); pytest proves the `--generate` passphrase never reaches argv/env and that a passphrase-less key is refused. |
| **W7** | Facts and the highlight list | loom | `lib/highlight/{view,severity,labels,port-options}.nix` + `suspicious.txt`, `modules/loom/highlight.nix` (`loom.highlight.*`, toplevel `$out/loom/{view.nix,facts}`), `pkgs/loom-facts`, `loom facts {compute,explain}` | W0 | `facts-cases` (full list in §i.1, U8, U16), `suspicious-text`, the facts schema fixtures pass; a host cannot remove a base entry (eval fixture). |
| **W8** | switchd, approvals, watchdog, updates, undo | loom | `pkgs/{loom-switchd,loom-eval,loom-fetch,loom-watchdog,loom-card-tty}`, `pkgs/loom-cli` (`propose`, `card`, `approve`, `undo`, `rollback`, `audit`, `stats`, `requests` client), `modules/loom/{switch/*,update.nix,trust.nix}`, card assembly + presentation rule + nonce + §g.7.3 verification, broker `SIGN` client, `loom-approve-sign`, polkit, the SEK-rotation marker admission rule (library used by W13), `nuketown.switch.command` | W7, W1 (test), W2 (test) | `switch-watchdog`, `replay-refused`, `undo-rollback`, `update-card`, `approval-verify`, `presentation-rule`, `preflight-runner-untrusted`, `preflight-vmvariant` and the loom part of `cli-contract` pass with the reviewer disabled (`reviewer-off` fixture) and terminal/maintenance provenance. |
| **W9** | chatd and the agent bridge | loom | `pkgs/loom-chatd` (ledger, hash chain, peer checks, relay, attachment store, snapshot validation), `pkgs/loom-agent-bridge` (claude-code stream-json and replay adapters, `loom-open-url`), `modules/loom/{chat.nix,agent/bridge.nix}`, `loom requests {show,gc}` server side, `loom.chat/v1` and `loom.request/v1` schemas | W0, W11 (test) | `ledger-forgery` (ledger and peer-cred cases) passes; adapter fixture tests (U11) pass; pytest covers chain verification, retention GC that keeps referenced records, and refusal of agent frames claiming a human author. |
| **W10** | Reviewer resident and egress | loom | `pkgs/{loom-review,loom-egress}` (run, `prompt.md`, review-bundle writer, output validator), `modules/loom/reviewer/{default,egress}.nix`, reviewer sign-in portal wiring, `tests/review-corpus/` | W7, W8, W9, W11, W1, W2 (test) | `reviewer-isolation` (U3, U4, U5), `reviewer-cannot-deescalate`, `reviewer-down`, `review-validate`, `provenance-facts` pass. **`pipeline-e2e`** (chat → propose → facts → reviewer → card → canokey `SIGN` → promote → push; U1) passes. |
| **W11** | Residents, user and base host modules, first boot | loom | `modules/loom/agent/{default,login}.nix` (`loom.agent.*` and `loom.reviewer.*` → the two nuketown agents of §c.3; `"approval"` sudo routing; agent units gated on `repo-publish.done`), `modules/loom/firstboot.nix` (runner, state, ordering; steps declared by W4/W12), `modules/loom/{user,locale,nix,hardware}.nix` | W0, W1 | `eval-agent-sudo-approval`, `eval-no-agent`, `eval-reviewer-off`, `layout` pass. A VM test shows the resident's units inactive without `repo-publish.done` and active with it, and the reviewer as `nologin` with no portal shell. First-boot runner pytest passes. |
| **W12** | Mint, repo id, enrollment, hostgen | loom | `pkgs/{loom-mint,loom-enroll}`, `pkgs/loom-installer/hostgen.py` (`loom-hostgen`, §e.5a), owner-key first push, HEAD check, enroll self-removal push and verify, `configure revoke-enroll`, `repo-publish` + enroll-retry first-boot steps, `loom authorize`, `modules/loom/silo.nix`, squatted-id detection | W0, W6, W2 (test), W11 (test) | `repo-id-vector`, `hostgen-escape`, `host-template` (loom flavor) pass; `silo-enrollment` (loom half) passes against the stand-in; fork/authorize/revoke-enroll pytest passes. |
| **W13** | SEK rotation | loom | `loom keys rotate encryption-key` (§g.14 phases, pending cleanup, paper-check gate, `sek-rotation.json`; phase 4 human-signed commit + `loom propose`), polkit action `farm.loom.keys.rotate` | W6, W4, W8, W1 (test) | Rotation-state pytest passes. `sek-rotate-crash` passes, including phase-2 sub-step crashes, start-over cleanup, the exit-5 marker check, the escalated rotation card, and the rescue-path unlock with the new SEK. |
| **W14** | Installer image, TUI, flash | loom | `lib/mk-installer.nix` (repart, verity, cache, flake-archive), `modules/loom/installer/*`, `pkgs/{loom-installer,loom-detect,loom-flash}`, `loom hw regen`, probes registry, test image variant, the SEK screen, owner-key generation into `~/.ssh`, the "Use an AI agent?" and agent-sudo questions, sidecar v2 validation, the rescue "unlock with my system encryption key" entry | W4, W5, W6, W7, W8, W11, W12, W1 (test), W2 (test) | `verity-corruption`, `flash-guards`, `installer-offline-eval` (U36), `installer-e2e` (loom-only), `installer-e2e-fresh` (first change approved by passphrase on a card), `installer-e2e-sb`, `installer-reinstall`, `installer-fork` pass. |
| **W15** | omanix desktop core, HM dotfiles, runtime overlays | omanix | `lib/mk-host.nix`; `modules/omanix/{default,path,session,login,language,runtime,hyprland/*,keybinds,menu,shell,health,probes,residents}.nix`, `modules/omanix/home/*`, `lib/{lua,jsonc,menu,home/*}.nix`, `omanix-data` (overlay loader, menu merge with `intents.toml` data), `pkgs/{omanix-overlay,omanix-runtime-snapshot}`, `omanix-session-init`, `omanix-session-state`, `fork/writers/desktop.toml`, `modules/omanix/{branding,hooks,fork,persist}.nix`, the `nixosConfigurations.ref-{default,nvidia,laptop}` fixtures (later packages' modules join them through `omanix.nixosModules.default`) | W0, W3, W5 | `desktop-boots` (+ greeter variant; U24, U34) passes, including HM-before-DM and overlays-exist asserts (its intent-prefill and indicator asserts are `desktop-intents`, W18). `keybind-conflicts`, `jsonc-equivalence`, `hm-owned-readonly`, `runtime-writers`, `home-owned` (U31) and `home-files-golden` for the targets W15 emits pass **at `5978d93`** on the W15 ref fixtures. The `writers-respect-hm` cases for W15's writers (monitor scale, bar position, gaps, keyboard picker U28, reset; U35), `shell-json-rebase` and the `omanix-overlay` pytest (settle semantics) pass. |
| **W16** | Themes, boot visuals, browser policy | omanix | `modules/omanix/theme/*` (registry, lock, `omanix.theme.extra` from flake inputs), `browser-policy.nix`, the chromium wrapper (flags + overlay), `omanix-plymouth`, `omanix-sddm-theme`, Limine style, `fork/writers/theme.toml` | W15 | `themes-render` covers every theme (U23 exclusions applied). `theme-switch` passes, including "no HM target changed". The glass and chromium-wrapper `writers-respect-hm` cases and their `home-files-golden` entries pass. Golden boot-visual renders exist for 3 themes. |
| **W17** | Apps, services, hardware quirks | omanix | `modules/omanix/{apps/*,defaults,packages,input,fonts,audio,network,power,printing,region,dns,weather}.nix`, `modules/omanix/hardware/**`, `fork/hw-quirks.toml`, the omanix probes for `loom.installer.probes`, crash capture | W15, W11 | `hw-quirks` (U26, U27) passes; the `nouveau-cursor` fixture emits the cursor setting into HM `looknfeel.lua`; omanix-flavor `eval-*` fixtures pass; a crash-capture coredump produces the notification (its "Ask ada" prefill is asserted in W21); the font-set, input, defaults and apps `writers-respect-hm` cases and `home-files-golden` entries pass. |
| **W18** | Shell plugins and the intent menu | omanix | `fork/add/shell/plugins/omanix-{chat,approval,status,welcome}/`, patches P5, P7, P8, P10–P14, P18, P19, `fork/intents.toml`, `fork/menu-extra.jsonc`, `data/chips/rules.json`, `modules/omanix/{chat,approval,welcome}.nix`, the Quickshell askpass, the Change password dialog | W15, W8, W9, W1 | `chat-socket` (U10, U18), `approval-focus` (U13), `menu-intents` with every upstream entry classified **at `5978d93`**, `desktop-intents` (intent prefill screenshot, indicators), and the routine/escalated card goldens (screenshots of FactsBlock vs ReviewerBlock) pass. |
| **W19** | omanix CLI, verbs, catalogs, skills, host template | omanix | `pkgs/{omanix-cli,omanix-catalog,omanix-skills}`, `modules/omanix/{cli,catalog}.nix`, `templates/host` (omanix flavor), resident prompt fragments, `omanix context/options/where/explain/set/plugin/app/secret/persist/hw/check/plan/propose/update/try/reset/edit/repo` | W7, W8, W15, W18 | `catalogs`, `catalog-size` (U20), `cli-contract`, `set-roundtrip` (U19), `skills-no-arch`, `host-template` (omanix) pass. `plugin-fixture` (U29, U30, U32) and `try-injection` pass. A VM script runs context → set → check → propose → card end to end, and `omanix update` with a locally signed tag yields a routine "Update ready" card. |
| **W20** | Configure/build-installer skills, scripts, release | omanix | `.claude/skills/{configure,build-installer,release}`, `scripts/*` + preamble, configure engine wiring (mint via hostgen, stage-cache with the signed install cache), `base-cache` from the W15 ref hosts, `installer-offline`/`-net`, closure budgets, release signing (D11) | W14, W16, W17, W19 | `installer-e2e-omanix` passes offline with `cacheMiss = []`. `closure-budget`, `closure-dupes`, `script-preamble-identical` pass. A signed `v0.1.0` dry-run release verifies with `verify-release.sh`. CI holds no signing secret. |
| **W21** | Demo and end-to-end UX | omanix | `demo/` (replay transcripts, README-injection fixture, bad monitor rule), `checks.vm-demo-{2..6}`, `make-it-stick`, `card-latency` (benchmark), `human-commit`, the demo runbook | W10, W17, W18, W19; W20 (and so W14) for the manual part | **VM part:** `vm-demo-2`…`vm-demo-6` (incl. the injection scenario), `human-commit`, `make-it-stick`, the `theme-switch` make-it-stick case and the crash-capture "Ask ada" prefill pass. **Release-candidate part** (after W20): scenes 1, 7 and 8 are run manually once on the reference laptop and recorded; `card-latency` (U14, U17) is run as a benchmark and recorded, not gated. |

**Parallelism.**
- Day one: W0, W1, W2, W3.
- After W0: W5, W6, W7, W11 in parallel; W9 can start against W11's agent user stub. W4 starts once W6's `loom-sek` lib lands; W12 once W6's `keys sync` lands. W15 starts once W3 and W5's `loom.home` land.
- W8 follows W7. W10 joins W7, W8, W9, W11. W13 follows W4 and W8. W14 joins W4, W5, W6, W7, W8, W11, W12.
- Desktop track: W15 → W16, W17 (parallel) and W18 (also needs W8, W9) → W19 → W20; W21's VM part closes after W10, W17, W18, W19, and its manual part after W20.
- **Critical paths:** trust **W0 → W7 → W8 → W10 → W21**; installer **W0 → W6 → W4 → W14 → W20**; desktop **W3 + W5 → W15 → W18 → W19 → W20**. W13 (rotation) hangs off W4 + W8 and is on none of them.
