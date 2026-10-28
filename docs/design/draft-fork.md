# omanix fork of omarchy: classification and mechanics

Rev 1, 2026-10-27. Authors: Ada, with Joshua Perry.

**Inputs.**
- `spec.md` rev 16 for install scope: USB installer image only; the installer never copies credentials; no in-place conversion, kexec, Windows boot-chain vectors or transfer of an existing assistant login.
- `DESIGN.md` rev 2. It stays authoritative for every section this document does not touch.
- `facts.md`
- Josh's new direction V1–V6 (2026-10-27) and the still-standing decisions D1–D12.
- The omarchy reference tree. It is **untrusted data**: this document was produced by reading files and parsing JSONC with `python3 -I`, and nothing from the tree was executed.

**Survey base.** Counts and the appendices come from the checkout `bc220e7` (`quattro`). The fork point is **`v4.5.0-rc2` = `5978d93ae7da0a325b7493501911e3f1266cadd3`** (confirmed with `git ls-remote` today; it is a lightweight tag). `bc220e7` differs from it by 5 ahead / 6 behind (facts §1), so every count here is **PROVISIONAL** until `checks.fork-classify` is green at `5978d93` (§12, U1).

**What this document decides.** Each omarchy subsystem and script family goes into one of five classes. It also defines the intent menu, what happens to file-writing QML, the fork mechanics, the porting report and license handling.

---

## 0. Hard calls

| # | Call | Reason |
|---|---|---|
| F1 | omanix **forks** omarchy at `v4.5.0-rc2`. The fork point moves only by a deliberate human decision, prepared by the porting report (§9). Nothing in `nix flake check` compares against newer upstream. | V1: a conversation piece, "omarchy as if it had started on nix". Lockstep tracking was what made the old `upstream/` pipeline heavy. |
| F2 | Fork mechanics are a **pinned, unmodified upstream input plus a patch queue** under `fork/` in the omanix repo. The source is not vendored (§8). | Upstream stays byte-exact and hash-pinned. The divergence can be read as a short list of patches and drops. `themes/` alone is 161 MB, and vendoring it would bloat the omanix repo. |
| F3 | Every bin script, every menu entry and every file in the tree has exactly one class: **KEEP-AS-GUI, AGENT-INTENT, ASSET, RE-EXPRESS-IN-NIX or DROP**. `fork/classify.toml` holds this, and `checks.fork-classify` fails on any unclassified path. | It replaces `writers.toml`'s role as the completeness gate. The check reads only the pinned tree, so it is deterministic. |
| F4 | omarchy's bash state-mutation layer is **removed, not wrapped**. That means pkg/install/remove, migrations, refresh/reinstall-pkgs, update, provisioning, channel, snapshot, factory reset and sudo helpers. There are no `omanix set` shims that pretend to be `omarchy-pkg-add`. | V1. A shim keeps the old mental model ("a GUI that installs things") alive. V2 replaces that model with "ask the agent". |
| F5 | The menu is an **intent launcher**. An intent row **pre-fills** the chat surface and never sends. The human presses Enter, so the request on record is always text the human submitted (§4). | V2 plus V5 provenance: the reviewer compares the diff with what the human actually asked. |
| F6 | GUI tools that are kept write **runtime state only**: `~/.local/state/omarchy/**` and `~/.local/state/omanix/{overlay,shell}/**`. "Make it stick" is an agent request carrying a code-generated runtime snapshot. A later switch absorbs the snapshot by sha (§5). | V2 says GUI changes are runtime state. D9 says HM dotfiles are read-only. The resident is a different unix user and cannot write the human's home (V3). |
| F7 | Hardware-quirk knowledge becomes `modules/omanix/hardware/quirks/<name>.nix` plus `fork/hw-quirks.toml` probes. The installer's `loom-detect` enables matches in the host repo's `hardware.nix`. The omarchy scripts that installed the quirks are dropped (§7). | Spec: hardware goes into the host flake at install time. Quirks become reviewable, plain NixOS. |
| F8 | **v1 targets x86_64-linux only.** aarch64 quirk knowledge (Apple Silicon, Snapdragon X, NVIDIA N1x/GB10) is recorded as `status = "deferred"` rows with the source script cited, and no module is built. | No aarch64 VM or hardware lane exists in the omanix test plan. Recording the knowledge keeps it from being lost. |
| F9 | User-visible branding becomes omanix. Internal identifiers stay: `OMARCHY_PATH`, the `omarchy-*` command names and the `omarchy.*` QML plugin ids. The MIT notice ships unmodified (§10). | Renaming 558 commands would make every patch and every porting report unreadable. MIT covers the code, not the name or logo. |
| F10 | The system is **fully usable without the agent**. Every intent row has a `manual` hint naming the module/option and the file in the host repo. A terminal user edits that file, commits, and switches through the same `loom switch` + approval card path. | V2. It also gives each intent a deterministic "what this should touch" that the reviewer's facts section can show. |

---

## 1. The classes and the decision rule

### 1.1 Classes

| Class | Meaning | Where it ends up |
|---|---|---|
| **KEEP-AS-GUI** | A human-facing tool that changes something, kept because asking the agent would be onerous (rule §1.2). It applies its change live and the change is **runtime state**. | Shipped in `omarchy-src`. Patched where it used to write an HM-owned or system path. |
| **AGENT-INTENT** | Dropped as a human tool. The menu row and keybinding stay, but they pre-fill a chat request. The resident does the work through an agent skill/verb by editing the host repo, and the change lands via card + switch. | `fork/intents.toml` (menu side). Skill in `omanix-skills` (agent side). Script removed from `$OMARCHY_PATH/bin`. |
| **ASSET** | Data or a non-mutating helper consumed from the fork point: QML, Lua, themes, templates, read-only probes, launchers, menu data, icons, docs. | `omarchy-src` (store path), unchanged or patched. |
| **RE-EXPRESS-IN-NIX** | Logic that existed to set up the system, now NixOS/HM options, activation, systemd units or first-boot. | `modules/omanix/**`, `loom.firstboot.steps`, session init. Upstream file dropped from the tree, or kept as a data file the module reads. |
| **DROP** | No equivalent in omanix: Arch packaging, migrations, pacman/limine/snapper, passwordless sudo, credential transfer, contributor tooling. | `fork/drop.txt`. Not in the store path. |

### 1.2 The V2 rule as a decision procedure (applied in this order)

1. Does it only **read**, or is it a library, launcher or data? → **ASSET**.
2. Does it exist to install, configure or migrate the **system or package set**? Does it touch pacman/limine/snapper/mkinitcpio/sudoers? → **RE-EXPRESS-IN-NIX** if NixOS needs the behavior, otherwise **DROP**.
3. Is it needed to **reach or repair the agent**? That covers network setup, keyboard layout, agent sign-in, approval, undo/rollback, lock, power, and restarting wifi/audio/bluetooth/shell. → **KEEP-AS-GUI**.
4. Is it a **continuous or frequent control**? That covers volume, brightness, scale/text size, monitor arrangement, window/workspace management, screenshots/recording, clipboard, emoji, sharing and reminders. → **KEEP-AS-GUI**.
5. Is it an **instant, reversible runtime toggle**? That covers nightlight, DND, idle, screensaver, touchpad, bar/dock visibility, gaps, corners, transparency, animations and workspace layout. → **KEEP-AS-GUI**.
6. Is it **visual browsing with live preview**? That covers themes, wallpapers, the monospace font, bar and dock placement. → **KEEP-AS-GUI** (runtime; "make it stick" is an intent).
7. Everything else changes **persistent configuration**: defaults, DNS, language, timezone, kernel, boot screen, security, git identity, apps, web apps, TUIs, dev envs, plugins, theme repos, branding, clock format, updates. → **AGENT-INTENT**.

A **picker that ends in a persistent change** keeps its GUI picker, and its result becomes the intent text. Examples: the Plymouth switcher → "Set the unlock screen to *Tokyo Night*", and the language list → "Switch my language to *Deutsch*". That row is classed AGENT-INTENT.

---

## 2. Counts

| Scope | KEEP-AS-GUI | AGENT-INTENT | ASSET | RE-EXPRESS-IN-NIX | DROP | NAV | Total |
|---|---|---|---|---|---|---|---|
| `bin/omarchy*` scripts | 101 | 128 | 241 | 22 | 66 | — | 558 |
| menu entries (`omarchy-menu.jsonc`) | 115 | 232 | 0 | 0 | 6 | 69 | 422 |
| files outside `bin/` | 0 | 11 | 3582 | 192 | 843 | — | 4628 |

Files outside `bin/`, by top-level directory:

| Directory | KEEP-AS-GUI | AGENT-INTENT | ASSET | RE-EXPRESS-IN-NIX | DROP |
|---|---|---|---|---|---|
| `(top)` |  |  | 1 |  | 11 |
| `.github` |  |  |  |  | 5 |
| `.greptile` |  |  |  |  | 1 |
| `agents` |  |  |  |  | 9 |
| `applications` |  |  | 33 |  |  |
| `config` |  |  | 47 |  | 1 |
| `default` |  | 11 | 354 | 61 | 33 |
| `docs` |  |  |  |  | 16 |
| `etc` |  |  | 3 | 38 | 15 |
| `install` |  |  |  | 93 | 24 |
| `manual` |  |  | 2594 |  |  |
| `migrations` |  |  |  |  | 211 |
| `plans` |  |  |  |  | 7 |
| `scripts` |  |  |  |  | 1 |
| `shell` |  |  | 276 |  | 2 |
| `test` |  |  |  |  | 507 |
| `themes` |  |  | 274 |  |  |

Shipped executables after the fork: 342 upstream scripts (KEEP-AS-GUI + ASSET) plus the `add/` replacements. 216 upstream scripts leave `$OMARCHY_PATH/bin` (AGENT-INTENT + RE-EXPRESS + DROP).

**Reading the numbers.**
- About **101** of 558 scripts stay as human tools.
- ASSET is the largest class (241). These are helpers that the kept tools and the shell call: probes, launchers, theme appliers, usage collectors.
- The 22 RE-EXPRESS scripts are replaced by modules or by small `fork/add/` reimplementations over nix state (`pkg-present`, `update-available`, `version`).
- The menu moves the other way: 232 of 353 actionable rows become intents, and 115 stay GUI.
- The removed human-facing mutating surface is the AGENT-INTENT and DROP rows: the whole install/remove catalog, defaults, security setup, boot, update.

---

## 3. Subsystem classification (non-bin trees)

| Subsystem (upstream path) | Class | Mechanism |
|---|---|---|
| Quickshell shell `shell/**` (shell.qml, Commons, Ui, services, plugins: bar, dock, menu, panels, osd, notifications, lock, polkit, clipboard, emojis, reminders, image-picker, background, agents, services/*) | ASSET | Store path `$OMARCHY_PATH/shell`, launched by upstream `omarchy-launch-shell`. Patched as listed in §6. |
| `shell/plugins/dev-gallery` | DROP | Contributor UI kit preview. |
| omanix shell plugins `omanix.chat`, `omanix.approval`, `omanix.status` | (new, omanix-owned) | `fork/add/shell/plugins/omanix-*`. Discovered by upstream's plugin registry like any first-party plugin. Their IPC contract is in §4.3, §4.4 and §6. |
| Hyprland Lua `default/hypr/**`, `config/hypr/*.lua` | ASSET | Unchanged Lua. The `config/hypr/*` templates become read-only HM files (DESIGN §f.3.2). One patch rebinds the agent keys (§4.6). |
| Menu data `default/omarchy/omarchy-menu.jsonc` | ASSET (transformed) | `lib/menu.nix` merges upstream JSONC with `fork/intents.toml` and emits the shipped menu (§4.2). |
| Keybinding defaults `default/hypr/bindings/*.lua`, `default/omarchy/shortcuts` | ASSET | Unchanged, except the agent-key patch. `omanix.keybinds.*` stays as HM `bindings.lua`. |
| Themes `themes/*` (23), templates `default/themed/*.tpl` | ASSET | Upstream renderer unchanged (DESIGN §f.4). Big media is symlinked, never copied. A theme's `hyprland.lua` is **code**, so third-party themes are AGENT-INTENT (flake input, reviewed card). |
| Terminal/app defaults `default/{alacritty,foot,ghostty,bash,bashrc,xcompose,fontconfig,gtk,fonts,i18n,input-methods,nautilus-python,voxtype,wireplumber,tensaku,applications}` and `config/**` | ASSET | Store data and HM read-only files (D9). App-owned seeds are copied once at first login (DESIGN §f.3.5). |
| Session env `default/{uwsm,environment.d,wayland-sessions,xdg-terminal-exec}` | RE-EXPRESS | `programs.hyprland.withUWSM`, the uwsm env drop-in and `environment.sessionVariables`. The session `.desktop` goes in via `sessionPackages`. |
| Boot visuals `default/{plymouth,sddm}` | ASSET | `omanix-plymouth`, `omanix-sddm-theme` packages with omanix logos (§10). |
| systemd units `default/systemd/**` | RE-EXPRESS | `systemd.packages` + `systemd.user.services.<n>.wantedBy` (DESIGN §f.2). `omarchy-migrate-notify.service` is dropped. The `system-sleep` hooks become `powerManagement`/`systemd.services` hooks. |
| `etc/**` (56 files) | RE-EXPRESS mostly | sysctl, NetworkManager, logind, resolved, oomd, faillock, cups, docker, xkb and profile.d map to options. sudoers.d, mkinitcpio, limine-entry-tool and nopasswd tmpfiles are DROP. fastfetch, mpv and xdg/kitty are ASSET (Appendix C). |
| Browser policy `default/{chromium,firefox}` | RE-EXPRESS | `programs.chromium.extraOpts`, `programs.firefox.policies`. The theme color uses the spool + root path unit (DESIGN §f.4). |
| udev/v4l2/audio/alsa `default/{udev,v4l2-relayd,audio,alsa}` | RE-EXPRESS | Data files consumed by quirk modules (§7). |
| pacman, libalpm, limine, snapper, regions `default/{pacman,libalpm,limine,snapper,regions}` | DROP | Boot loader is loom (D7). Generations replace snapshots. Region mirrors are pacman-only. |
| Agent skills `default/agents/skills/{omarchy,omarchy-app,diagnose-crash}` | AGENT-INTENT | Rewritten as resident skills (§4.5). The upstream text is kept as a reference in the store and is **not** linked into the human's harnesses as instructions to edit `~/.config`. |
| `install/*.packages` (8 lists) | RE-EXPRESS | `omanix.packages.base` (x86_64 lists). The aarch64 lists are deferred (F8). |
| `install/config/*.sh` | RE-EXPRESS | Base modules: firewall, docker, ssh, locale, lockscreen PAM, browser policy, services. Snapper is DROP. |
| `install/hardware/**`, `install/user/hardware/**` | RE-EXPRESS | Quirk modules (§7). `all.sh`, `pacman.sh` and `platform-setup.sh` are DROP. |
| `install/user/**`, `install/user/first-run/**` | RE-EXPRESS | Session init / first login (DESIGN §f.3.5). `xcompose.sh`, `language.sh` and `first-run/setup-agent.hook` are DROP (the resident onboarding replaces the "choose an agent" invitation). |
| `install/{helpers,post-install,provisioning}`, `install/login` | DROP / RE-EXPRESS | The loom installer and firstboot replace provisioning. Login (SDDM) is re-expressed. |
| `migrations/` (211) | DROP | Nix has no state to migrate. A fork-point move is a porting report plus a commit. |
| `applications/*.desktop`, `applications/icons` | ASSET | Catalog for `omanix.apps.webapps.<n>` (HM `xdg.desktopEntries`). Icons go in the store. |
| `manual/` | ASSET | Shipped read-only under `$OMARCHY_PATH/manual` as resident reference. The menu "Learn > Manual" points at an omanix-patched copy. |
| `docs/`, `plans/`, `test/`, `scripts/`, `agents/skills/`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `.github/` | DROP (from the store) | They remain readable in the pinned source. The porting report reads `docs/` and `test/`. |
| `LICENSE` | ASSET (required) | Shipped unmodified. `checks.fork-license` asserts it (§10). |
| `logo.svg`, `logo.txt`, `icon.png`, `icon.txt`, `default/plymouth/logos/oma.png`, About/screensaver branding text | DROP / replaced | omanix branding in `fork/add/branding/` (§10). |
| `version` | DROP | It reads `4.0.0.alpha` on every tag (facts §1). `omarchy-version` is re-expressed (Appendix A). |

---

## 4. The menu as an intent launcher

### 4.1 Data format: `fork/intents.toml`

Every non-submenu entry of the upstream menu has exactly one row, keyed by the upstream id. Provider-backed submenus get one row covering all their runtime rows.

```toml
[defaults]                       # applied to every intent row
send = false                     # pre-fill only; the human presses Enter (F5)

[entry."setup.default.browser.firefox"]
kind    = "intent"               # gui | intent | drop
text    = "Make {label} my default browser."
skill   = "defaults"             # agent skill that handles it (§4.5)
manual  = "home.nix: omanix.defaults.browser = \"firefox\";"
touches = ["omanix.defaults.browser"]   # informational: shown in the card's facts as "expected area"

[entry."install.gaming.steam"]
kind    = "intent"
text    = "Install Steam, with the right graphics drivers for this machine."
skill   = "apps"
manual  = "configuration.nix: programs.steam.enable = true;"
touches = ["programs.steam", "hardware.graphics.enable32Bit"]

[entry."setup.language"]          # provider-backed: one row for all language rows
kind    = "intent"
text    = "Switch my language to {label}."
skill   = "locale"
manual  = "configuration.nix: omanix.language = \"{value}\";"

[entry."appearance.theme"]
kind = "gui"                     # action kept verbatim from upstream

[entry."setup.security.passwordless-sudo"]
kind = "drop"
why  = "omanix has no passwordless sudo; the resident uses approval (D8)"

[entry."setup.keybindings"]
kind    = "intent"
text    = "Change a keybinding: "          # open-ended: cursor left at the end
skill   = "keybinds"
manual  = "home.nix: omanix.keybinds.binds.<name> = { … };"
```

**Template fields.** These are the only substitutions:
- `{label}`: the upstream row label, after i18n.
- `{value}`: the provider row value.
- `{selection}`: a picker result, for picker-then-intent rows.

Text is never built from untrusted runtime data other than these three, all of which come from the human's own session.

**New omanix entries.** These are omanix data, not upstream. They are added through upstream's own extension merge, and every one is `gui`:

| id | Label | Action |
|---|---|---|
| `ask` | Ask Ada… | Opens the chat surface empty (`SUPER + A`) |
| `approvals` | Approvals | Opens the approval card list (`omanix.approval` IPC `open`) |
| `undo` | Undo last change | `loom rollback --confirm`, through the GUI confirm dialog |
| `agent` | Agent | Resident status, sign-in and restart (`omanix.status`) |
| `appearance.make-it-stick` | Make my look permanent | Pre-fills "Make my current look permanent." plus a runtime snapshot attachment (§5) |
| `learn.nixos` | NixOS manual | Replaces `learn.arch` |

`learn.community` (the omarchy Discord) is DROP. omanix does not route its users to omarchy's support channels.

### 4.2 Build: `lib/menu.nix` → `omanix-data/default/omarchy/omarchy-menu.jsonc`

1. Parse upstream JSONC with python `-I` at build time (whole-line `//` comments stripped, trailing commas removed, which matches upstream's own parser rules in `docs/menu.md`).
2. For each entry, look up `intents.toml`:
   - `gui`: the entry is emitted unchanged.
   - `intent`: emitted with `action` removed and `intent = "<rendered text>"` and `skill` added. `description` gets "Asks Ada" appended. For Install rows, `disabled` guards are kept (they mark what is already installed).
   - `drop`: the entry is omitted. A submenu whose children are all dropped disappears through upstream's own rule.
3. Add the omanix entries from §4.1.
4. `checks.menu-intents` fails if:
   - an upstream entry has no row;
   - a `gui` row's action names a script that is not shipped (it parses the action with `bashlex`, the same as the writer scanner);
   - an `intent` row has empty `text` or an unknown `skill`;
   - a template uses a field other than the three above.
5. User extensions (`~/.config/omarchy/extensions/omarchy-menu.jsonc`) may also declare `intent` entries. They stay pre-fill only, so they cannot act on their own.

### 4.3 Runtime flow (intent row)

1. The human selects a row (keyboard, pointer or search). `Menu.qml` sees `kind === "intent"` (patch P5, §6).
2. `Menu.qml` calls the shell-internal IPC `omanix.chat.prefill({source: "menu", id, text, skill, attachments: []})`. Nothing is spawned through bash, and the menu closes.
3. The chat surface opens with `text` in the input box and a source chip ("from menu: Defaults › Browser › Firefox"). The cursor sits at the end.
4. The human edits and/or presses Enter. Only then does the chat surface write the request record: `{id, ts, uid, source: "menu:<id>"|"typed"|"voice", text (as sent), attachments: [{kind, sha256}]}`. The record goes over the chat socket to the request log the reviewer reads (V5).
5. The resident runs the skill, edits the host repo, builds, and requests a switch. The approval card shows the request record verbatim next to the deterministic facts.
6. Escape or closing the chat without sending records nothing.

**Picker-then-intent rows** (Plymouth switcher, language, kernel, timezone): the upstream picker runs unchanged and returns `selection`. The row's `intent` is then rendered with `{selection}` and pre-filled. This is how the kept GUI picker and the agent path connect.

**Keybindings that ran a dropped script** (for example `omarchy-menu summon install`) still open the menu at that route, so they keep working.

### 4.4 Without the agent (F10)

When the resident is not running, not signed in, or the human prefers not to ask, the chat surface still opens with the pre-filled text. It shows:
- "Ada is unavailable: <reason>" with the buttons **Sign in** / **Restart agent** (these are KEEP-AS-GUI);
- **Do it yourself**, which shows the row's `manual` hint and two actions:
  - "Open the host repo": `omanix repo open <file>` opens the human's working copy in their editor. **[assumption: §12, U7]** The working copy is created on demand at `~/omanix-host`.
  - "Copy snippet".

The human commits with their own key. `loom switch` and the card then work exactly as for agent commits, with the reviewer's request field reading "none: human-authored commit".

### 4.5 Agent skills that replace the dropped tools

These ship in `omanix-skills` and are linked into the resident's harness. Typed verbs are convenience tools for the agent and gate nothing (V6).

| Skill | Replaces upstream | Verbs it may use |
|---|---|---|
| `apps` | `install-*`, `remove-*`, `pkg-*` TUIs, `webapp-*`, `tui-*`, `install-dev-env`, gaming, `windows-vm`, `games-retro-install`, `mise-default-tools` | `omanix app add/remove <n>`, edits `configuration.nix`/`home.nix`/`modules/*` |
| `defaults` | `default-{browser,terminal,editor,agent,dictation}`, `dictation-use`, voxtype config/model | `omanix set omanix.defaults.*` |
| `locale` | `language`, `menu-timezone`, `setup-input`, `font-cjk`, persistent keyboard layouts | `omanix set omanix.language`, `time.timeZone`, `omanix.input.layouts` |
| `look` | "make it stick" (§5), clock format, branding, `hyprland-corners` and similar defaults | absorbs runtime snapshots into `home.nix` options |
| `themes` | `theme-install/remove/update`, `plymouth-set*` | adds a theme flake input + `omanix.theme.extra.<n>`; `omanix.theme.boot.*` |
| `shell-plugins` | `plugin-add/clone/remove/update` | `omanix.shell.plugins.<n> = { src = inputs.<n>; }` |
| `security` | `setup-security-*`, `remove-security-*` | sshd, fido2, fingerprint, ssh-agent, docker group. These always hit the card's protected-option facts (D5). |
| `boot` | `kernel`, `hibernation-*`, plymouth | `boot.kernelPackages`, `loom.disk.swap.hibernate`, `omanix.theme.boot` |
| `network` | `dns` | `omanix.dns.provider` / `services.resolved` |
| `hardware` | `audio-tuning`, `apply-hardware`, new quirk probes | `omanix hw probe` → proposes `omanix.hardware.quirks.<n>.enable` |
| `update` | `update`, `channel-set`, `theme-update`, `plugin-update`, `update-firmware` | bumps `flake.lock` inputs → "Update ready" card. Firmware goes through `fwupdmgr` with approval sudo when `loom.agent.sudo = "approval"`; otherwise the skill stops at "firmware updates are available" and tells the human to run `fwupdmgr update`, which runs under their own polkit session. |
| `diagnose` | `agent-crash`, `crash-watch` "ask the agent", failed units/builds | read-only; journal through the `systemd-journal` group |

Upstream's `omarchy`, `omarchy-app` and `diagnose-crash` skill texts are folded into `apps`, `look` and `diagnose`. Their Arch instructions (pacman, `~/.config` edits, `omarchy refresh`) are removed. `checks.skills-no-arch` greps every shipped skill for `pacman|yay|omarchy-pkg|omarchy-refresh|sed -i ~/.config` and fails on a match.

### 4.6 Keybinding changes (one patch, P9)

| Key | Upstream | omanix |
|---|---|---|
| `SUPER + A` | not bound in `utilities.lua` **[U5]** | `omarchy-shell omanix.chat toggle` |
| `SUPER + SHIFT + CTRL + A` | `omarchy-agent --pick` (the human's default harness) | `omarchy-shell omanix.chat toggle` |
| `SUPER + grave` (qconsole) | `special:qconsole` seeded with `omarchy-agent` | unchanged: the human's own terminal harness, if they set one |
| `SUPER + ALT + A` | — | `omarchy-shell omanix.approval open` |

---

## 5. Runtime state and "make it stick"

**Layers.** These are DESIGN §f.3.1 with V4 applied: the settings.json layer and `omanix keep` are gone.

| Layer | Owner | Writable at runtime |
|---|---|---|
| upstream defaults, bin, shell (`$OMARCHY_PATH`) | nix (fork) | no |
| host dotfiles (HM, read-only, from the host repo's `home.nix` / `omanix.*`) | nix | no |
| runtime overlays `~/.local/state/omanix/{overlay,shell}/**` | KEEP-AS-GUI tools | yes |
| upstream state `~/.local/state/omarchy/**` (theme, toggles, indicators) | KEEP-AS-GUI tools | yes |
| app-owned and user-data | apps / human | yes |

The redirect mechanism stays as in DESIGN §f.3: writers target the overlay files that HM includes last. Every redirect is now a **patch or rewrite in `fork/`**, recorded in `classify.toml` with `writes = "<runtime path>"`.

**Make it stick:**
1. The human picks "Make my look permanent" (menu, chat button, or the notification a kept tool shows after a change: "Changed scale to 1.25 — Make permanent?").
2. The chat surface runs `omanix-runtime-snapshot <area>` **as the human**. Areas are `look`, `hypr`, `shell`, `theme`, `font`, `monitors`, `input`. The output is JSON produced by code: overlay file contents, `theme.name`, active toggles and `shell.json` diffed against defaults. Each part carries `sha256` and the file path. The output is attached to the pre-filled request.
3. The resident's `look` skill maps the snapshot to options in the host repo:
   - theme → `omanix.theme.default`;
   - font → `omanix.fonts.monospace`;
   - monitors → `omanix.hyprland.monitors`;
   - shell → `omanix.shell.settings`;
   - Lua overlays → `omanix.hyprland.fileLua.<file>`.
   It also writes `omanix.runtime.absorbed.<area> = "<sha256>"`.
4. Card → switch → HM activation. Session init sees `absorbed.<area>` equal to the **current** overlay sha, then backs up and empties that overlay. If the human changed the overlay after the snapshot, the sha differs: the overlay is left alone and `omanix doctor` lists it.
5. `omanix reset <area>|--all` (KEEP-AS-GUI; it replaces `refresh-*`, `reinstall-configs` and `reinstall`) empties overlays without asking anyone.

The resident never reads the human's home. It sees only what the human attached (step 2) and the session summary `/run/omanix/session/<uid>/overlays.json` (keys and shas only, DESIGN §f.3.5).

---

## 6. QML and scripts that write files: the patch list

Patches are ordered and live in `fork/patches/`. Each one is ≤ 60 changed lines, or it is an override in `fork/add/`.

| # | Upstream file | Upstream write/behavior | Patch | Runtime path / IPC |
|---|---|---|---|---|
| P1 | `shell/shell.qml` `userConfigPath` (persistShellConfig, atomicWrites) | `~/.config/omarchy/shell.json` | rewrite, count 1 | `~/.local/state/omanix/shell/shell.json` (+ `.base` for rebase, DESIGN §f.3.6) |
| P2 | `bin/omarchy-shell-config` `CONFIG_FILE` (used by `bar`, `dock`, plugin enable) | same file via `jq`+`mv` | rewrite | same as P1 |
| P3 | `shell/Commons/Color.qml` reader, `bin/omarchy-display-text-size` writer | `~/.config/omarchy/shell.toml` | rewrite | `~/.local/state/omanix/shell/shell.toml` |
| P4 | `bin/omarchy-hyprland-monitor-scaling`, `-monitor-clamshell` (reader), `-display-text-size`, `-font-set`, `-restart-terminal`, `-theme-set-glass` (gtk.css), `-chromium-add-feature` | `sed -i`/`cat >` on HM files | patches (DESIGN §f.3.4 rows, unchanged) | `~/.local/state/omanix/overlay/**`; live apply is `hyprctl eval` / terminal reload, unchanged |
| P5 | `shell/plugins/menu/MenuModel.js` `kind` inference, `Menu.qml` `runAction` | runs `action` through bash | `kind = value.action ? "action" : value.intent ? "intent" : …`; `runAction` dispatches `intent` to `omanix.chat.prefill` through the shell's `IpcRegistry`, without bash | IPC only |
| P6 | `shell/plugins/menu/MenuModel.js` package snapshot (`pacman -Qq`/`-Qi`, DBPath stamp) | reads pacman | replaced by reading `/run/current-system/sw/share/omanix/packages.txt` plus `/etc/profiles/per-user/$USER/share/omanix/packages.txt`, stamped by the generation path | read-only |
| P7 | `shell/plugins/bar/indicators/PasswordlessSudo.qml` + `Indicators.qml` list | shows passwordless-sudo state, clicks `omarchy-sudo-passwordless` | indicator removed; `omanix.status` adds "approval pending" and "agent offline" indicators | `omanix.approval` IPC |
| P8 | `shell/plugins/bar/widgets/SystemUpdate.qml` | polls `omarchy-update-available`, click runs `omarchy-update` | polls the re-expressed `omarchy-update-available` (loom update state); click opens the "Update ready" card | `omanix.approval open update` |
| P9 | `default/hypr/bindings/utilities.lua` | agent keybinds | §4.6 | — |
| P10 | `shell/plugins/panels/network/Panel.qml` DNS section | runs `omarchy-dns <provider>` (sudo) | DNS buttons pre-fill the `network` intent; wifi/connect/band/captive portal unchanged (reach-the-agent) | `omanix.chat.prefill` |
| P11 | `shell/plugins/menu/Menu.qml` providers `languages`, `kernels` | `actionFor` runs `omarchy-language` / `omarchy-kernel` | `intentFor` (picker-then-intent, §4.3); the `fonts` provider stays `gui` (`omarchy-font-set`, runtime) | IPC |
| P12 | `shell/plugins/image-picker/*` theme remove | `omarchy-theme-remove` (deletes `~/.config/omarchy/themes/<t>`) | user-installed themes (user-data) still removable; repo themes (from `omanix.theme.extra`) show "Remove…" → `themes` intent | — |
| P13 | `shell/plugins/agents/Panel.qml` | account add/use/rename/mode for the human's harnesses | unchanged. A resident tile ("Ada: signed in / usage") is added from `omanix.status` and is read-only | — |
| P14 | `bin/omarchy-crash-watch`, `bin/omarchy-launch-config-editor`, `bin/omarchy-launch-{1password,signal,spotify}` | spawn `omarchy-agent-crash` / open HM-owned files / run installers | pre-fill `diagnose` / open the host repo module, or the `look` intent / pre-fill an `apps` intent | IPC |
| P15 | `default/bash/env-bootstrap` | force-resets `OMARCHY_PATH` to `/usr/share/omarchy` | resets to `/run/current-system/omarchy` (DESIGN §f.2) | — |

Writers that already target runtime state are left as they are. These are QML `atomicWrites` in `notifications/Service.qml`, `clipboard/Clipboard.qml` and `agents/Main.qml` (all under `~/.local/state/omarchy/`), plus every `toggle-*`, `theme-set*`, `bg-*`, `weather-location`, `reminder` and `powerprofiles-set` (state files or daemon state).

`checks.hm-owned-readonly` (DESIGN §f.3.8) stays. It still scans `omanix-data` after the patches and fails if any shipped write site targets an HM-owned path. This is a check on the pinned tree and is unaffected by the drift-gate removal.

---

## 7. Hardware quirks as NixOS modules

**Layout:**
```
fork/hw-quirks.toml                          # probe + source script + status, one row per quirk
modules/omanix/hardware/quirks/<name>.nix    # omanix.hardware.quirks.<name>.enable (mkEnableOption)
modules/omanix/hardware/{intel,nvidia,amd,vulkan,bluetooth,wireless}.nix   # generic, probe-driven defaults
```

**Probe rows** are declarative and evaluated by `loom-detect` (stdlib python, reads `/sys` and `lspci -nn` output, never runs omarchy code). An example row:

```toml
[quirk.asus-b9406-touchpad]
source = "install/hardware/asus/fix-asus-ptl-b9406-touchpad.sh"
probe  = { dmi.product_name = "*B9406*", dmi.sys_vendor = "ASUS*" }   # from omarchy-hw-asus-expertbook-b9406
status = "v1"                                                           # v1 | deferred
```

**Flow:**
1. At install (spec step 3), `loom-detect` writes `omanix.hardware.quirks.<n>.enable = true;` lines into the host repo's `hardware.nix`, next to `nixos-generate-config` output.
2. After a hardware change, `omanix hw probe` (read-only) lists matching quirks that are not enabled. The `hardware` skill proposes them, which produces a card. The human can also run `omanix hw probe --write` in their own working copy.
3. Where `nixos-hardware` already has a module, the quirk imports it and adds only the omarchy delta **[U6]**.

| Quirk module | Upstream source | Probe | NixOS mechanism | v1 |
|---|---|---|---|---|
| `nouveau-cursor` | `user/hardware/fix-nouveau-cursor.sh` | kernel driver nouveau | HM `looknfeel.lua`: `cursor.no_hardware_cursors = true` | v1 |
| `vm-no-animations` | `user/hardware/vm-no-animations.sh` | `systemd-detect-virt` ≠ none | first-login seeds toggles `no-animations`, `window-opaque` (runtime state, so the human can toggle them back) | v1 |
| `intel-video` | `intel/video-acceleration.sh` | Intel GPU class | `hardware.graphics.extraPackages = [intel-media-driver vpl-gpu-rt]` (GMA: `intel-vaapi-driver`) | v1 |
| `intel-thermald`, `intel-lpmd` | `intel/thermald.sh`, `intel/lpmd.sh` | Intel CPU + battery (+ model list for lpmd) | `services.thermald.enable`; lpmd: package + unit **[U6]** | v1 |
| `intel-sof` | `intel/sof-firmware.sh` | SOF DSP | `hardware.enableRedistributableFirmware` (sof-firmware) | v1 |
| `intel-ptl-fred` | `intel/fred.sh` | Panther Lake GPU | `boot.kernelParams = ["fred=on"]` | v1 |
| `intel-wifi7-eht` | `intel/fix-wifi7-eht.sh` | PCI 8086:e440/272b | `boot.extraModprobeConfig = "options iwlwifi disable_11be=Y"` | v1 |
| `intel-ipu7-camera` | `intel/ipu7-camera.sh` | ACPI HID OVTI08F4 | `hardware.ipu7` / package **[U6]** | v1 |
| `asus-rog` | `asus-rog.sh`, `user/hardware/asus/fix-{audio-mixer,mic}.sh` | DMI ROG | `services.asusd.enable`, `services.supergfxd.enable`; wireplumber `alsa-soft-mixer.conf` via `services.pipewire.wireplumber.extraConfig`; ALC285 mixer levels as a oneshot `alsactl` unit | v1 |
| `asus-z13-touchpad` | `asus/fix-z13-touchpad.sh` | ROG + GZ302 | `services.udev.extraRules` (verbatim rule) | v1 |
| `asus-b9406-display`, `asus-ptl-backlight`, `asus-b9406-touchpad` | `asus/fix-asus-ptl-*.sh` | DMI B9406 / UX5406AA | `boot.kernelParams` (`xe.enable_panel_replay=0`, `xe.enable_dpcd_backlight=1`); `environment.etc."libinput/local-overrides.quirks"` | v1 |
| `asus-proart-p14-speakers` | `asus/fix-asus-proart-p14-speakers.sh` | DMI H7407BA | firmware package (omarchy-pkgs) **[U6]** | v1 if packaged |
| `dell-xps13-ptl` (speaker firmware, sidecar amps, text scaling), `dell-xps-haptics`, `dell-xps-oled` | `dell-xps13-*.sh`, `dell-xps-touchpad-haptics.sh`, `user/hardware/dell/xps13-text-scaling.sh` | DMI DX13260 / haptic touchpad / OLED+PTL | firmware + helper packages from omarchy-pkgs; text size as a first-login runtime default (not HM) | v1 if packaged |
| `framework16` | `framework16.sh`, `framework/qmk-hid.sh`, `default/udev/framework16-qmk-hid.rules` | DMI Laptop 16 | `nixos-hardware` framework-16 + `qmk-hid` + udev rule | v1 |
| `framework13-amd-mic` | `user/hardware/framework/fix-f13-amd-audio-input.sh` | AMD Family 17h/19h audio | wireplumber card-profile rule | v1 |
| `lenovo-yoga-pro7-bass` | `lenovo/fix-yoga-pro7-bass-speakers.sh` | DMI Yoga Pro 7 14IAH10 | `boot.extraModprobeConfig` | v1 |
| `surface` | `surface.sh`, `fix-surface-keyboard.sh` | DMI Surface + x86 | `nixos-hardware` microsoft-surface; initrd pinctrl module (`boot.initrd.kernelModules`, probed per model) | v1 |
| `apple-t2` | `apple/fix-t2.sh`, `hardware/pacman.sh` (t2 repo) | PCI 106b:1801/1802 | `nixos-hardware` apple-t2 | v1 |
| `bcm43xx` | `fix-bcm43xx.sh` | PCI 14e4:43a0/4331 | `boot.extraModulePackages = [broadcom_sta]`, unfree opt-in | v1 |
| `tuxedo-backlight` | `fix-tuxedo-backlight.sh` | DMI vendor TUXEDO/Slimbook | `hardware.tuxedo-drivers.enable`; blacklist `clevo_xsm_wmi` | v1 |
| `synaptics-intertouch` | `fix-synaptic-touchpad.sh` | synaptics in input devices | `boot.extraModprobeConfig = "options psmouse synaptics_intertouch=1"` | v1 |
| `elgato-camlink-4k` | `fix-elgato-camlink-4k.sh`, `default/udev/elgato-camlink-4k.rules`, `default/v4l2-relayd/camlink.conf`, `camlink-4k-loopback.service` | USB Cam Link 4K | `boot.extraModulePackages = [v4l2loopback]`, `services.v4l2-relayd.instances.camlink`, udev rule | v1 |
| `speaker-tuning` | `speaker-tuning.sh`, `bin/omarchy-audio-tuning`, `default/audio/tunings`, `filter-chain-host.conf` | `audio-tuning match` table (data) | pipewire filter-chain from the tuning file, plus `lsp-plugins` | v1 |
| `nvidia` | `nvidia.sh` (x86 part), `nvidia-apps.sh`, `hw-nvidia-{gsp,without-gsp}` | NVIDIA GPU, GSP or not | `hardware.nvidia.{open = gsp; modesetting}`, Hyprland env (`default/hypr/nvidia.lua` unchanged) | v1 |
| `hybrid-gpu` | `toggle-hybrid-gpu`, `default/systemd/system/supergfxd.service.d`, `system-sleep/force-igpu` | hybrid GPU | `services.supergfxd.enable` + drop-in; the toggle stays KEEP-AS-GUI | v1 |
| `thinkpad-t14s-camera`, `qualcomm-*` (camera, video-decode, dtb-uki, firmware, initramfs, kernel-params), `yoga-slim7x*` | `lenovo/*`, `qualcomm/*`, `install-{camera,video-decode}` | aarch64 Snapdragon | — | deferred |
| `apple-silicon-*` (brcmfmac, spi-keyboard, suspend-nvme, fkeys) | `apple/*`, `fix-fkeys.sh` | aarch64 Apple | — (nixos-apple-silicon) | deferred |
| `n1x`, `gb10` | `n1x.sh`, `fix-n1x-gpu-memory.sh`, `gb10/sleep.sh`, `nvidia/dgx-spark-boot.sh` | aarch64 NVIDIA | — | deferred |
| generic: `bluetooth`, `wireless-regdom`, `network`, `vulkan` | `bluetooth.sh`, `set-wireless-regdom.sh`, `network.sh`, `vulkan.sh` | always / by vendor | base modules: `hardware.bluetooth`, `hardware.wirelessRegulatoryDatabase` + regdom from timezone (first boot), NetworkManager, vendor Vulkan ICDs | v1 |
| `fix-yt6801-ethernet-adapter.sh` | — | — | empty upstream file (0 effective lines) | DROP |
| `default/systemd/system/systemd-{pcrlogin@,pcrproduct,tpm2-setup-early}.service.d/*nvpcr*` | — | — | **not adopted**: it interacts with loom's TPM/PCR policy (D4) **[U8]** | DROP pending U8 |

`checks.hw-quirks`:
- every `install/hardware/**` and `install/user/hardware/**` file maps to a row or a DROP line;
- every `v1` row has a module;
- each module evaluates on a fixture with its quirk on;
- `loom-detect`'s pytest has one sysfs fixture per probe.

---

## 8. Fork mechanics

### 8.1 Options

| | A. Vendor the tree in the omanix repo | **B. Pinned input + patch queue (chosen)** | C. Separate fork repo (branch on the tag) |
|---|---|---|---|
| Repo size | +200 MB (161 MB of themes) in omanix history | none; the source is a fixed-output fetch | in a second repo |
| Seeing the divergence | needs a diff tool against upstream | `fork/` *is* the divergence: drops, patches, adds, rewrites | `git log tag..branch` |
| Byte-exact upstream with provenance | no: it is just files in our tree | yes: `flake.lock` narHash of rev `5978d93` | yes, if signed |
| Porting to a new tag | manual three-way merge | `git apply --3way` of the queue onto the new tag (§9) | rebase |
| Review in a card | huge diffs if someone edits vendored files | patches are small text files | flake input bump |
| Trust (spec: a malicious fork is an attack) | the omanix repo carries it | the omanix repo plus the upstream hash | a third repo to sign and protect |

**Choice: B.** For people who want to browse the fork as git history, the conversation-piece angle is served by a generated mirror (§8.4). It is not a second source of truth.

### 8.2 Layout (omanix repo)

```
omanix/
  flake.nix                 # inputs.omarchy = { url = "github:omacom/omarchy/5978d93ae7da0a325b7493501911e3f1266cadd3"; flake = false; }
  fork/
    UPSTREAM.toml           # url, tag = "v4.5.0-rc2", rev, date, why this point (D2)
    NOTICE                  # attribution (§10)
    classify.toml           # every bin script + path rule → class (machine form of Appendices A–C)
    drop.txt                # globs removed from the tree (DROP + AGENT-INTENT scripts + RE-EXPRESS sources)
    rewrite.toml            # exact {file, from, to, count}: /usr/share/omarchy, /usr/bin/*, titlebars .so, writer redirects
    patches/
      0001-shell-runtime-shell-json.patch           # P1–P3
      0002-writers-to-runtime-overlay.patch         # P4
      0003-menu-intent-kind.patch                   # P5, P11
      0004-menu-package-manifest.patch              # P6
      0005-bar-approval-and-update.patch            # P7, P8
      0006-agent-keybinds.patch                     # P9
      0007-network-panel-dns-intent.patch           # P10
      0008-image-picker-repo-themes.patch           # P12
      0009-launchers-and-crash-to-intent.patch      # P14
      0010-env-bootstrap-path.patch                 # P15
      0011-branding.patch                           # §10 user-visible strings
    add/                    # new files overlaid on the tree (they never replace an upstream path silently)
      shell/plugins/omanix-chat/  omanix-approval/  omanix-status/
      bin/omarchy-{pkg-present,pkg-missing,pkg-defaults,update-available,update-restart,update-status,version,version-pkgs,locale-generate}   # RE-EXPRESS replacements
      bin/omarchy-{refresh-*,reinstall,reinstall-configs}   # overrides → omanix reset (header: "# replaces upstream <path> sha256 <x>")
      branding/  default/plymouth/logos/omanix.png  default/fonts/omanix-glyphs/
    intents.toml            # §4.1
    hw-quirks.toml          # §7
    menu-extra.jsonc        # §4.1 new entries
  pkgs/by-name/omarchy-src/ # applies stages 1–6 below
  lib/menu.nix              # §4.2
```

### 8.3 Build stages (`omarchy-src`, all inside the sandbox; nothing from upstream is executed at build time)

1. **unpack** `inputs.omarchy` (fixed rev and narHash).
2. **drop** `fork/drop.txt`.
3. **add** `fork/add/`. An add that collides with an upstream path must carry a `replaces … sha256` header that matches the pinned file.
4. **patch** `fork/patches/*` in order with `patch -p1 --no-backup-if-mismatch --fuzz=0`.
5. **rewrite** `fork/rewrite.toml`: exact counts, and the build fails on a mismatch. Then `patchShebangs`.
6. **post-check**:
   - no `/usr/(share|lib|bin)`, `pacman`, `yay` or `mkinitcpio` outside `allowResidual`;
   - every shipped `bin/omarchy-*` is classified KEEP-AS-GUI or ASSET (or is an `add/` replacement);
   - no shipped script references a dropped one (static call graph from `bashlex`, with an allowlist for menu guards);
   - `luac -p` passes and `hl.*` ⊆ `hl-symbols.txt`;
   - `qmllint` runs on patched QML files **[U4]**;
   - `LICENSE` is present and unmodified.

`omanix-data` (the per-host tree, DESIGN §f.2) is built on top of this and adds the generated menu, overlay loader, theme registry and language file.

**Gates that stay in `nix flake check`.** All of them read only the pinned tree:
- the build itself;
- `fork-classify` (coverage);
- `menu-intents`;
- `hm-owned-readonly`;
- `hw-quirks`;
- `skills-no-arch`;
- `fork-license`;
- `themes-render`.

**Removed.** `upstream-drift`, `upstream-pin-tag` and the `writers.toml` "new upstream site" category are gone, and no check fetches anything newer.

### 8.4 Optional mirror for browsing

`nix run .#fork-mirror -- <dir>` builds a plain git repo:
1. commit 1 is upstream at `5978d93`;
2. then one commit for `drop`;
3. then one per patch;
4. then one for `add`;
5. then one for `rewrite`.

Josh's YubiKey signs it (D11). It can be pushed to a read-only `omarchy-on-nix` repo for people who want to `git log` the divergence. It is regenerated from `fork/` on every omanix release, and nobody commits to it.

---

## 9. Porting report (replaces the drift gate)

`nix run .#porting-report -- --to <tag|rev> [--json]`, run on a developer machine (network on). It never runs in `nix flake check`, and it never executes anything from upstream.

1. Fetch the target into a fresh store path (`builtins.fetchGit`, read-only).
2. **Classified diff.** Every changed or added file between `5978d93` and the target is grouped by its class in `classify.toml`. Unclassified new paths and bin scripts get a **suggested class** from the family rules in Appendix A (for example, a new `omarchy-install-*` → AGENT-INTENT).
3. **Patch queue dry run.** Each patch is tried with `git apply --3way --check` on the target and reported as `clean | offset | conflict` with the hunks. Each `add/` replacement whose `replaces` sha no longer matches is listed.
4. **Rewrites.** `rewrite.toml` counts are re-run against the target, with mismatches listed.
5. **Menu.** New, removed and changed entry ids against `intents.toml`, with a suggested `kind` from the §1.2 rule (by action prefix).
6. **Writers.** The writer scanner (DESIGN §f.3.8) runs on the target and lists new write sites into HM-owned paths.
7. **Runtime deps.** The Hyprland/Quickshell/guiutils minimums are read from `hl.*` symbols and omarchy-pkgs PKGBUILD `pkgver`s and compared with the omanix pins (facts §2, §3).
8. **Hardware.** New `install/hardware/**` files are listed as candidate quirk rows with their guard expression.
9. **Themes and assets.** Added and changed themes, background files, and their license/credit files (§10).
10. **Effort summary.** Counts per class, patch conflicts and unclassified items, written as `porting-report.md` + `.json`.

**Moving the fork point** is a human decision recorded as a new D-number. The resident may run the report and prepare the port on a `gate/*` branch. The card is always escalated, because the change includes a new flake input rev and a `fork/` diff.

---

## 10. License and attribution (MIT)

omarchy is MIT, `Copyright (c) David Heinemeier Hansson` (`LICENSE`). MIT requires the copyright and permission notice in all copies or substantial portions. It grants no trademark rights.

1. **Ship the notice.** `$OMARCHY_PATH/LICENSE` is the unmodified upstream file. `checks.fork-license` asserts its sha against the pinned tree and that `drop.txt` never matches it. The NixOS module sets `environment.etc."omanix/licenses/omarchy-MIT.txt"`, and the About panel shows "Based on omarchy v4.5.0-rc2 (MIT) — Licenses".
2. **omanix repo.** It has `LICENSES/omarchy-MIT.txt` (a copy) and `fork/NOTICE`:
   > omanix contains a modified copy of omarchy (https://github.com/omacom/omarchy) at v4.5.0-rc2, Copyright (c) David Heinemeier Hansson, used under the MIT License. Modifications are the files under fork/ and are Copyright (c) 2026 Joshua Perry and Ada. omanix is an independent project and is not affiliated with or endorsed by the omarchy project.
3. **omanix's own license:** MIT, `Copyright (c) 2026 Joshua Perry and Ada`. It is compatible, so patches (derivative works) can carry the same terms. Commits carry `Co-Authored-By: Joshua Perry <josh@6bit.com>`.
4. **Third-party files in the tree keep their own notices.**
   - `default/alsa/ucm2/Qualcomm/x1e80100/LICENSE.HP-EliteBook` stays next to its file (deferred aarch64, so it is not shipped in v1).
   - Packaged dependencies keep their licenses: owe, ttfx, aether, etc. are MIT, titlebars is BSD-3, and asdcontrol is GPL-2 as a separate program (facts §4).
   - Theme wallpapers and videos may have their own terms **[U3]**.
5. **Branding (patch 0011 + `add/branding/`).**
   - User-visible name, logo and icon become **omanix**: About text, screensaver text, the Plymouth logo (`oma.png` → `omanix.png`), SDDM, `logo.svg`/`icon.png`, the bar's logo glyph and window titles that say "Omarchy".
   - Internal identifiers stay (F9). Saying "omarchy" when describing the origin is factual and allowed. Presenting omanix *as* omarchy is not.
   - Links to omarchy services are removed: `omarchy.org/manual` → omanix docs; the Discord row and `logs.omarchy.org` upload are DROP.
6. **Fonts.** The private `omarchy` icon font contains brand glyphs. omanix builds `omanix-glyphs`, which keeps upstream's non-brand glyphs and replaces the logo codepoint **[U2]**.

---

## 11. Deltas to DESIGN.md this implies

These are not applied here. They are listed for the integrating pass.

| DESIGN.md | Change |
|---|---|
| H3, H4, §c settable registry, §d.2 tiers, `settings.json`, `omanix keep` | Superseded by V4: no registry and no tiers. `omanix set` survives only as an agent convenience verb that edits `home.nix`/`configuration.nix` options (V6). |
| H8, §a.1 `upstream/` (pin.toml, manifest, overrides, packages.toml, install-map.toml, writers.toml), `checks.upstream-pin-tag`, `upstream-drift` | Replaced by `fork/` (§8.2). `writers.toml` content moves into `classify.toml` (`writes =` fields). Drift becomes the porting report (§9). |
| §f.2 overrides "`omarchy-pkg-*` → `omanix set`", "`omarchy-install-*` shims", "`omarchy-update*` → `omanix update`" | Removed (F4). Those scripts are AGENT-INTENT/DROP, and the menu carries intents. |
| §f.3.4 class c rows (defaults, language, keyboard, git) | AGENT-INTENT. `setup-keyboard` becomes KEEP-AS-GUI with a runtime overlay (it is needed to type to the agent). |
| §f.3.7 `keep` | Replaced by the "make it stick" flow (§5). `reset`, `edit` and `doctor` stay. `edit` opens the overlay, or for HM-owned paths the host-repo module. |
| §h.3 skills | The skill list becomes §4.5. The host `CLAUDE.md` loses the "edit only via settings.json" rule. |
| §f.3.5 first login: "skill symlinks of the D9-overridden `omarchy` skill into the human's harnesses" | Dropped. The human's harnesses get no omarchy/omanix skill by default. The resident carries the skills. |

---

## 12. UNVERIFIED (each with the test that settles it)

| # | Claim | Test |
|---|---|---|
| U1 | The counts and Appendix A/B/C classifications match the fork point `5978d93` (surveyed on `bc220e7`). | Build `omarchy-src` at `5978d93`; `checks.fork-classify` and `checks.menu-intents` must be green. Any unclassified path is printed with a ready-to-paste `classify.toml` stub. |
| U2 | Which codepoint(s) of the `omarchy` icon font are brand glyphs, and whether the bar uses them. | `fc-query` + glyph dump of `default/fonts/omarchy`, then grep `shell/**` for those codepoints. VM screenshot of the bar with `omanix-glyphs`. |
| U3 | Theme backgrounds/videos are redistributable under MIT, or have separate credits. | Porting-report step 9 at `5978d93`: list every file under `themes/*/backgrounds` with any LICENSE/CREDITS/README and upstream git log authorship. Anything unattributed is excluded from the default closure until cleared. |
| U4 | Patched QML (P1, P5, P7, P8, P10–P13) loads under quickshell `2b4501a` with Qt 6.12. | `qmllint` in post-check, plus VM `desktop-boots`: `qs -p $OMARCHY_PATH/shell` with no QML errors, menu intent row → chat pre-fill (screenshot), bar shows the approval indicator. |
| U5 | `SUPER + A` is unbound in the upstream Lua at `5978d93`. | Replay the bindings under the recording `hl.*` stub (DESIGN §h.2 `keybinds.json`) and assert no binding on `SUPER + A`. Otherwise pick the first free chord and update §4.6. |
| U6 | nixpkgs/nixos-hardware cover: intel-lpmd, ipu7 camera, asus/dell firmware packages, framework-16, microsoft-surface, apple-t2, tuxedo-drivers. | `nix eval` each attribute on the omanix nixpkgs. `nix flake show github:NixOS/nixos-hardware` for module names. A missing one is packaged from omarchy-pkgs or set to `status = "deferred"`. |
| U7 | A human working copy at `~/omanix-host` fits the switch/approval design (V5/V6 doc). | Reconcile with the switch-path design. The test is VM `human-commit`: edit `home.nix` in the copy, commit with the human key, `loom switch`, card shows "human-authored", promote. |
| U8 | omarchy's NvPCR drop-ins (`systemd-pcrlogin@`, `pcrproduct`, `tpm2-setup-early`) conflict or not with loom's PCR 7 policy (D4). | VM with swtpm + Secure Boot: enroll TPM2 per §e.9 with and without the drop-ins, reboot 3×, unlock must be hands-free in both. Adopt only if neutral. |
| U9 | Menu guards that used `omarchy-pkg-present` give correct ✓/disabled states from the generation manifest (P6). | `test/shell.d/menu-guards-test.sh` logic ported to a VM test: install Steam via a fixture host, open menu, `install.gaming.steam` is disabled+✓. |
| U10 | `omarchy-input-method` (KEEP-AS-GUI) still works when the HM-owned fontconfig file is read-only (it writes `fontconfig/conf.d/`, which is not HM-owned). | DESIGN §f.3.9 `writers-respect-hm` test, extended with `omarchy-input-method configure --defaults`. |

---

## Appendix A. bin/ mapping (558 scripts, `omarchy-` prefix omitted)

Classes: **GUI** = KEEP-AS-GUI, **INTENT** = AGENT-INTENT, **ASSET**, **NIX** = RE-EXPRESS-IN-NIX, **DROP**. The rules are listed in match order, and each script matches the first rule that applies. `classify.toml` is the machine form.

| # | Class | Scripts | Mechanism / intent text |
|---|---|---|---|
| 1 | ASSET | omarchy | CLI router; `omarchy commands --json` feeds `catalog/commands.json` |
| 2 | ASSET | agent, agent-prompt | launch the human's own coding harness (not the resident); agent keys rebound to chat (P9) |
| 3 | INTENT | agent-crash | diagnose: "Diagnose why {program} crashed." |
| 4 | GUI | agent-account-add, agent-account-mode, agent-account-remove, agent-account-rename, agent-account-use | sign-in / account choice for the human's harnesses (agents panel); app-owned dirs |
| 5 | ASSET | agent-account-exec, agent-account-home, agent-account-list, agent-account-state | read/exec helpers for the above |
| 6 | DROP | agent-account-copy, agent-account-transfer | moves assistant credentials between machines; out of scope (spec) |
| 7 | ASSET | agent-usage-agy, agent-usage-claude, agent-usage-codex, agent-usage-copilot, agent-usage-cursor, agent-usage-deepseek, agent-usage-devin, agent-usage-fireworks, agent-usage-grok, agent-usage-grokbot, agent-usage-hermes, agent-usage-kimchi, agent-usage-kimi, agent-usage-local, agent-usage-minimax, agent-usage-muse, agent-usage-ollama, agent-usage-opencode, agent-usage-openrouter, agent-usage-qwen, agent-usage-synthetic, agent-usage-update, agent-usage-vibe, agent-usage-zai | usage collectors for the agents panel |
| 8 | NIX | apply-lock | `security.pam.services` for the Quickshell lock (lock module) |
| 9 | NIX | apply-hardware, apply-system | base modules + `omanix.hardware.quirks.*` (§7) |
| 10 | NIX | apply-n1x-gpu-memory | quirk `n1x` (deferred) |
| 11 | DROP | apply-pacman | pacman |
| 12 | ASSET | ascii | text art helper |
| 13 | GUI | audio-input-mute, audio-input-set-default, audio-output-set-default, audio-output-switch, audio-output-volume, audio-source-switch | continuous control; wpctl/pactl live, WirePlumber persists in `~/.local/state/wireplumber` |
| 14 | ASSET | audio-output-sink, audio-sink-availability | read helpers for the shell |
| 15 | INTENT | audio-tuning | hardware: "Turn the speaker tuning for this laptop on/off." → quirk `speaker-tuning` |
| 16 | GUI | bar | bar placement/background/widgets; runtime `shell.json` (P2) |
| 17 | ASSET | bar-text-color | color helper |
| 18 | ASSET | battery-low, battery-present, battery-status | status/notification helpers |
| 19 | GUI | bluetooth-device, bluetooth-power | reach-the-agent / frequent; bluetoothctl live |
| 20 | DROP | boot-direct | Direct Boot EFI entry; loom owns boot (D7) |
| 21 | INTENT | branding-about, branding-screensaver | look: "Change my About/screensaver branding to …" → `omanix.branding.*` HM files |
| 22 | ASSET | branding-about-animation | sourced helper |
| 23 | ASSET | brightness-keyboard-mute | mic-mute LED helper |
| 24 | GUI | brightness-display, brightness-display-apple, brightness-display-ddc, brightness-keyboard | continuous control (brightnessctl / ddcutil / asdcontrol) |
| 25 | ASSET | capture-region, capture-screenrecording-process, capture-webcam-list | helpers |
| 26 | GUI | capture-qr, capture-screenrecording, capture-screenrecording-with-webcam, capture-screenshot, capture-text, capture-webcam-resize | screenshots/recording/OCR/QR |
| 27 | INTENT | channel-set | update: "Move this machine to the omanix {channel} release line." (flake input ref) |
| 28 | DROP | channel-current | pacman channel; `omanix context` shows the input |
| 29 | NIX | chromium-add-feature | `omanix.apps.chromium.features` (HM flags file + runtime overlay) |
| 30 | ASSET | chromium-copy-url-host, chromium-ytdlp-host | native messaging hosts, registered by the chromium module |
| 31 | GUI | clipboard-open, clipboard-paste-file, clipboard-paste-text | clipboard history |
| 32 | ASSET | cmd-browser-handoff, cmd-default-browser, cmd-missing, cmd-present, cmd-terminal-cwd | command helpers |
| 33 | GUI | crash-mute | runtime per-program mute |
| 34 | ASSET | crash-watch | patched (P14): "Ask Ada" pre-fills the diagnose intent |
| 35 | ASSET | debug, debug-idle | diagnostics (read-only) |
| 36 | INTENT | default-agent, default-browser, default-dictation, default-editor, default-terminal | defaults: "Make {x} my default {kind}." → `omanix.defaults.*` |
| 37 | ASSET | dev-theme-preview | palette preview |
| 38 | DROP | dev-add-migration, dev-benchmark-cli, dev-benchmark-theme-switcher, dev-font, dev-install-ydoo, dev-link, dev-notification-demo, dev-pkg-test, dev-status, dev-ui-preview, dev-unlink | omarchy contributor tooling (migrations, dev-link, pkg tests, benchmarks, ydotool, glyph font, UI gallery) |
| 39 | INTENT | dictation-use | defaults: "Use {backend} for dictation." |
| 40 | DROP | dictation-superwhisper | superwhisper is not in nixpkgs (facts §4) |
| 41 | ASSET | dictation, dictation-voxtype | recording runtime (keybind) |
| 42 | ASSET | disk-speedtest | measurement panel |
| 43 | GUI | display-text-size | continuous scale control; runtime overlays (P3/P4) |
| 44 | INTENT | dns | network: "Use {provider} DNS." → `omanix.dns.provider` |
| 45 | GUI | dock | dock autohide/position; runtime `shell.json` |
| 46 | ASSET | done | setup-task markers |
| 47 | ASSET | drive-info, drive-select | read helpers |
| 48 | NIX | drive-password | `loom unlock passphrase` (human-only, polkit auth_self; LUKS is loom's) |
| 49 | ASSET | file-select | file chooser |
| 50 | GUI | font-set | visual browsing (menu fonts provider); runtime overlay |
| 51 | ASSET | font-current, font-list | read helpers |
| 52 | INTENT | font-cjk | locale: "Use {variant} glyph forms for CJK text." → `omanix.fonts.cjk` |
| 53 | ASSET | games-retro-cores | list helper |
| 54 | INTENT | games-retro-install | apps: "Add a launcher for the RetroArch game {rom}." → HM `xdg.desktopEntries` |
| 55 | ASSET | git-url-check | validator |
| 56 | ASSET | hibernation-available | probe |
| 57 | INTENT | hibernation-remove, hibernation-setup | boot: "Set up / remove hibernation." → `loom.disk.swap.hibernate` |
| 58 | ASSET | hook | runs user hooks (user-data) |
| 59 | INTENT | hook-install | look: "Run {command} on {hook}." → `omanix.hooks.<name>` HM files |
| 60 | ASSET | hw-aarch64, hw-clamshell, hw-display, hw-external-monitors, hw-fingerprint, hw-hybrid-gpu, hw-intel, hw-laptop, hw-laptop-closed, hw-match, hw-match-device-tree, hw-nvidia, hw-nvidia-display, hw-platform, hw-recover-internal-monitor, hw-touchpad, hw-touchscreen, hw-vm, hw-vulkan, hw-webcam, hw-x86 | runtime predicates called by kept scripts/QML |
| 61 | ASSET | hw-aarch64-apple, hw-aarch64-gb10, hw-aarch64-n1x, hw-aarch64-qualcomm, hw-apple-silicon, hw-asus-expertbook-b9406, hw-asus-rog, hw-asus-zenbook-ux5406aa, hw-dell-xps-haptic-touchpad, hw-dell-xps-oled, hw-dell-xps13-dx13260-ptl, hw-dell-xps13-sidecar-amps, hw-elgato-camlink-4k, hw-framework16, hw-intel-ptl, hw-intel-sof, hw-n1x, hw-nvidia-gsp, hw-nvidia-without-gsp, hw-surface | read-only model probes, kept for their shipped callers (e.g. `theme-set-keyboard-asus-rog`); their predicates are **also** transcribed into `fork/hw-quirks.toml` for `loom-detect` (§7) |
| 62 | ASSET | hyprland-focus-app, hyprland-monitor-clamshell, hyprland-monitor-external-active, hyprland-monitor-focused, hyprland-monitor-focused-apple, hyprland-monitor-laptop, hyprland-monitor-modeless, hyprland-monitor-watch, hyprland-session-lock-stranded, hyprland-session-locked, hyprland-toggle-disabled, hyprland-toggle-enabled, hyprland-workspace-layout-current | helpers/watchers (`monitor-clamshell` patched to read the overlay, P4) |
| 63 | DROP | hyprland-reload-guard | pacman transaction hook |
| 64 | GUI | hyprland-corners, hyprland-monitor-internal, hyprland-monitor-internal-mirror, hyprland-monitor-scaling, hyprland-toggle, hyprland-window-close-all, hyprland-window-gaps-toggle, hyprland-window-minimize, hyprland-window-pop, hyprland-window-single-square-aspect-toggle, hyprland-window-tiled-fullscreen-toggle, hyprland-window-transparency, hyprland-window-transparency-toggle, hyprland-window-width, hyprland-workspace-layout-default, hyprland-workspace-layout-toggle | window/workspace/monitor controls and look toggles; `hyprctl` live, state in `~/.local/state/omarchy` |
| 65 | ASSET | i18n | string lookup |
| 66 | GUI | input-method | IM switching (frequent); `configure` writes app-owned fcitx5 |
| 67 | ASSET | installed-service-dropbox, installed-service-tailscale | presence checks (patched to the generation manifest, P6) |
| 68 | DROP | install-and-launch, install-app | generic pacman install UI |
| 69 | NIX | install-camera, install-video-decode | quirk `qualcomm-*` (deferred) |
| 70 | NIX | install-gaming-gpu-lib32 | `hardware.graphics.enable32Bit` from the steam module |
| 71 | INTENT | install-ai-chatgpt, install-ai-claude, install-ai-hermes, install-ai-openclaw, install-ai-t3-code, install-browser, install-chromium-claude, install-chromium-copy-url, install-chromium-google-account, install-chromium-ytdlp, install-dev-env, install-dictation-superwhisper, install-dictation-voxtype, install-docker-dbs, install-editor-emacs, install-editor-helix, install-editor-vscode, install-editor-zed, install-font, install-gaming-battlenet, install-gaming-geforce-now, install-gaming-heroic, install-gaming-lutris, install-gaming-retroarch, install-gaming-steam, install-gaming-xbox-cloud, install-gaming-xbox-controllers, install-hermes-cli, install-openclaw-cli, install-preinstalls, install-service-1password, install-service-dropbox, install-service-microsoft, install-service-nordvpn, install-service-once, install-service-signal, install-service-spotify, install-service-sunshine, install-service-tailscale, install-t3code-app, install-terminal | apps: "Install {thing}." → NixOS/HM module in the host repo |
| 72 | INTENT | kernel | boot: "Boot the {kernel} kernel by default." → `boot.kernelPackages` (picker-then-intent) |
| 73 | INTENT | language | locale: "Switch my language to {lang}." → `omanix.language` (picker-then-intent) |
| 74 | ASSET | launch-config-editor | patched (P14): HM-owned path → host-repo module / look intent |
| 75 | ASSET | launch-1password, launch-about, launch-battlenet, launch-browser, launch-discord-community, launch-docker-tui, launch-editor, launch-floating-terminal-with-presentation, launch-nautilus, launch-nautilus-cwd, launch-openclaw, launch-or-focus, launch-or-focus-tui, launch-or-focus-webapp, launch-screensaver, launch-shell, launch-signal, launch-spotify, launch-terminal, launch-terminal-herdr, launch-terminal-tmux, launch-tui, launch-webapp | launchers (`1password`/`signal`/`spotify` patched: missing → apps intent) |
| 76 | DROP | lifecycle-dispatch | platform package lifecycle |
| 77 | NIX | locale-generate | `i18n.supportedLocales` (an `add/` stub prints the option) |
| 78 | INTENT | menu-timezone | locale: "Set my timezone to {tz}." → `time.timeZone` (picker-then-intent) |
| 79 | GUI | menu-clipboard, menu-emoji, menu-emoji-insert, menu-plugin, menu-share | clipboard, emoji, LocalSend, plugin enable/disable |
| 80 | ASSET | menu, menu-file, menu-herdr-keybindings, menu-images, menu-input, menu-keybindings, menu-select, menu-tmux-keybindings | menu IPC wrapper and pickers |
| 81 | DROP | migrate, migrate-notify | migrations |
| 82 | INTENT | mise-default-tools | apps: "Turn the default mise tools on/off." |
| 83 | DROP | mise-install | runtime-fetched wrapper shims; nix packages instead |
| 84 | ASSET | monitor-state | panel state reader |
| 85 | NIX | n1x-probe | quirk `n1x` (deferred) |
| 86 | GUI | network-band, network-captive-portal | reach-the-agent |
| 87 | ASSET | network-password, network-qr, network-speedtest, network-status, network-wifi-connected | status/QR/password/speedtest readers |
| 88 | ASSET | notification-battery, notification-dismiss, notification-send, notification-time, notification-wait, notification-weather | notification helpers |
| 89 | ASSET | openclaw-onboard | interactive wizard for an installed app |
| 90 | ASSET | osd | OSD IPC |
| 91 | INTENT | pkg-aur-install, pkg-install, pkg-remove | apps: "Install / remove the package {name}." → `environment.systemPackages` / `home.packages` |
| 92 | NIX | pkg-defaults, pkg-missing, pkg-present | `add/` reimplementation over the generation package manifest (P6) |
| 93 | DROP | pkg-add, pkg-aur-accessible, pkg-aur-add, pkg-drop | pacman/AUR |
| 94 | GUI | plugin-disable, plugin-enable | runtime `shell.json` |
| 95 | ASSET | plugin-catalog, plugin-list, plugin-validate | read helpers |
| 96 | INTENT | plugin-add, plugin-clone, plugin-remove, plugin-update | shell-plugins: "Add the shell plugin from {url}" / "Update my shell plugins" / "Remove {plugin}" → `omanix.shell.plugins.<n>` |
| 97 | ASSET | plymouth-current, plymouth-list, plymouth-preview | read/preview |
| 98 | INTENT | plymouth-reset, plymouth-set, plymouth-set-by-theme, plymouth-switcher | themes: "Set the boot/unlock screen to {theme}." → `omanix.theme.boot` (switcher = picker-then-intent) |
| 99 | ASSET | power-present | probe |
| 100 | NIX | powerprofiles-init | `services.power-profiles-daemon` + AC/battery udev rule |
| 101 | ASSET | powerprofiles-list | reader |
| 102 | GUI | powerprofiles-set | frequent control |
| 103 | NIX | provision-first-run, provision-user | session init / first login (DESIGN §f.3.5) |
| 104 | DROP | provision-hardware, provision-owner | loom installer / firstboot |
| 105 | GUI | refresh-config, refresh-herdr, refresh-hyprland, refresh-hyprsunset, refresh-shell, refresh-tmux | undo: `add/` override → `omanix reset <area>` |
| 106 | DROP | refresh-applications, refresh-chromium, refresh-limine, refresh-pacman, refresh-plymouth, refresh-sddm | applications/chromium/limine/pacman/plymouth/sddm: generated by nix |
| 107 | GUI | reinstall, reinstall-configs | undo: `add/` override → `omanix reset --all` |
| 108 | DROP | reinstall-pkgs | packages come from the generation |
| 109 | GUI | reminder | reminders |
| 110 | INTENT | remove-ai-chatgpt, remove-ai-claude, remove-ai-grok-bot, remove-ai-hermes, remove-ai-lm-studio, remove-ai-ollama, remove-ai-openclaw, remove-ai-perplexity, remove-ai-t3-code, remove-browser, remove-dev-env, remove-dictation-superwhisper, remove-dictation-voxtype, remove-gaming-battlenet, remove-gaming-geforce-now, remove-gaming-heroic, remove-gaming-lutris, remove-gaming-minecraft, remove-gaming-retroarch, remove-gaming-steam, remove-gaming-xbox-cloud, remove-gaming-xbox-controllers, remove-launcher-entry, remove-preinstalls, remove-security-fido2, remove-security-fingerprint, remove-security-sshd, remove-security-sudoless-docker, remove-service-1password, remove-service-dropbox, remove-service-microsoft, remove-service-ssh-agent, remove-service-sunshine, remove-service-tailscale | apps/security: "Remove {thing}." |
| 111 | GUI | restart-app, restart-audio, restart-bluetooth, restart-shell, restart-trackpad, restart-wifi | repair |
| 112 | ASSET | restart-btop, restart-gum, restart-helix, restart-herdr, restart-hyprctl, restart-hyprsunset, restart-opencode, restart-terminal, restart-tmux, restart-xcompose | theme-switch reload helpers |
| 113 | ASSET | screensaver | screensaver runtime |
| 114 | DROP | security-functions | sudo helpers |
| 115 | DROP | setup-direct-boot | EFI entry; loom owns boot |
| 116 | GUI | setup-keyboard | reach-the-agent: runtime layout via `overlay/hypr/input.lua`; "make it stick" → locale intent |
| 117 | INTENT | setup-git, setup-input, setup-security-fido2, setup-security-fingerprint, setup-security-ssh-agent, setup-security-sshd, setup-security-sudoless-docker | git/locale/security: "Set my git name and email" / "Set up {method}" → `loom.user`, `omanix.input.methods`, security modules |
| 118 | ASSET | shell, shell-config | shell IPC / shell.json helpers (P2) |
| 119 | ASSET | show-done, show-logo | terminal output helpers |
| 120 | ASSET | sleep-disabled | probe |
| 121 | DROP | snapshot | snapper; generations + rollback |
| 122 | ASSET | state | state-file helper |
| 123 | DROP | sudo-docker, sudo-keepalive, sudo-passwordless | passwordless/keepalive sudo, docker sudo probe |
| 124 | GUI | system, system-lock | power / lock |
| 125 | DROP | system-factory-reset, system-factory-reset-finish | reinstall from USB (spec) |
| 126 | ASSET | system-lid-close, system-lid-inhibit, system-sleep-lock, system-sleep-monitor, system-stats, system-wake | lid/sleep/wake/stats helpers and units |
| 127 | GUI | tailscale-send | sharing |
| 128 | ASSET | tailscale-receive | Taildrop receiver unit |
| 129 | GUI | theme-bg-install, theme-bg-intro, theme-bg-next, theme-bg-set, theme-bg-switcher, theme-set, theme-switcher | visual browsing with live preview; state in `~/.local/state/omarchy/current` |
| 130 | INTENT | theme-install, theme-remove, theme-update | themes: "Install the theme from {url}" / "Remove theme {t}" / "Update my themes" → flake input + `omanix.theme.extra.<n>` |
| 131 | ASSET | theme-bg-boot-intro, theme-bg-cache, theme-bg-current, theme-color, theme-colors-from-alacritty, theme-current, theme-dir, theme-extras, theme-list, theme-osc, theme-refresh, theme-set-browser, theme-set-browser-policy, theme-set-claude, theme-set-fcitx5, theme-set-foot, theme-set-glass, theme-set-gnome, theme-set-herdr-machines, theme-set-hermes, theme-set-hunk, theme-set-keyboard, theme-set-keyboard-asus-rog, theme-set-keyboard-f16, theme-set-obsidian, theme-set-pi, theme-set-t3code, theme-set-templates, theme-set-tmux, theme-set-vscode | theme appliers/readers called by `theme-set` (browser-policy uses the spool, DESIGN §f.4) |
| 132 | ASSET | toggle-enabled | probe |
| 133 | GUI | toggle-hybrid-gpu | supergfxd mode switch (runtime) |
| 134 | GUI | toggle, toggle-animations, toggle-bar, toggle-crash-capture, toggle-fullscreen-desktop, toggle-idle, toggle-input-device, toggle-nightlight, toggle-notification-silencing, toggle-screensaver, toggle-suspend, toggle-theme-sync, toggle-touchpad, toggle-touchscreen | instant runtime toggles; `~/.local/state/omarchy/toggles` |
| 135 | ASSET | transcode, transcode-ascii | file tools |
| 136 | INTENT | tui-install, tui-remove, tui-remove-all | apps: "Add / remove a launcher for the TUI {cmd}." → `omanix.apps.tuis.<n>` |
| 137 | INTENT | webapp-install, webapp-remove, webapp-remove-all | apps: "Add / remove the web app {name} ({url})." → `omanix.apps.webapps.<n>` |
| 138 | ASSET | webapp-handler-hey, webapp-handler-zoom, webapp-window-class | handlers / window class |
| 139 | INTENT | update | update: "Check for updates and prepare an update card." |
| 140 | INTENT | update-firmware | update: "Check for and install firmware updates." (fwupd) |
| 141 | GUI | update-time | repair: restart time sync |
| 142 | NIX | update-available, update-restart, update-status | `add/` reimplementation over loom update / switch state |
| 143 | DROP | update-analyze-logs, update-aur-pkgs, update-boot, update-confirm, update-dev, update-keyring, update-lock, update-mise, update-orphan-pkgs, update-pacman, update-pacman-guard, update-pkg-prune, update-requires-free-space, update-stay-awake, update-system-pkgs, update-system-pkgs-when-conflicted, update-user-notify | pacman/AUR/keyring/mise update flow |
| 144 | DROP | upgrade-to-quattro, upload-log | legacy upgrade; uploads to logs.omarchy.org |
| 145 | NIX | version, version-pkgs | `add/` reimplementation: fork point + host commit + lock date |
| 146 | DROP | version-branch, version-channel | dev-link branch / pacman channel |
| 147 | INTENT | voxtype-config, voxtype-model | defaults: "Change Voxtype settings / model to …" → `omanix.apps.voxtype.*` |
| 148 | GUI | weather-location | panel setting (runtime state) |
| 149 | ASSET | weather-icon, weather-status | readers |
| 150 | INTENT | windows-vm | apps: "Set up / remove a Windows VM." |
| 151 | ASSET | windows-key | reader |

Per-class totals: KEEP-AS-GUI 101, AGENT-INTENT 128, ASSET 241, RE-EXPRESS-IN-NIX 22, DROP 66.

## Appendix B. Menu mapping (`omarchy-menu.jsonc`, 422 entries)

`NAV` = a submenu or link (structure, kept as is). Intent text is the template rendered with each row's label. Rows that differ only in label are grouped.

| Class | Entries (id → label) | Intent text / mechanism |
|---|---|---|
| GUI | `appearance.font` Font | font picker (provider `fonts`), runtime |
| INTENT | `setup.language` Language | "Switch my language to {label}." (provider rows) |
| INTENT | `update.kernel` Kernel | "Boot the {label} kernel by default." (provider rows) |
| NAV | 69 submenus and links: `learn`, `appearance`, `trigger`, `setup`, `install`, `remove`, `update`, `system`, `appearance.top-bar`, `appearance.top-bar.position`, `appearance.top-bar.background`, `appearance.top-bar.indicators`, `appearance.top-bar.indicators.clock`, `appearance.windows`, `appearance.windows.corners`, `appearance.windows.transparency`, `appearance.branding`, `appearance.branding.screensaver`, `appearance.branding.about`, `appearance.dock`, `appearance.dock.position`, `appearance.workspace-layout`, `trigger.toggle`, `trigger.reminder`, `trigger.capture`, `trigger.capture.screenrecord`, `trigger.share`, `trigger.hardware`, `trigger.tests`, `trigger.hardware.touchpad-haptics`, `setup.typing`, `setup.network`, `setup.network.dns`, `setup.default`, `setup.default.agent`, `setup.default.browser`, `setup.default.dictation`, `setup.default.terminal`, `setup.default.editor`, `setup.plugin`, `setup.security`, `setup.config`, `install.ai`, `install.service`, `install.development`, `install.editor`, `install.style`, `install.style.font`, `install.gaming`, `install.browser`, `install.terminal`, `install.development.javascript`, `install.development.php`, `install.development.elixir`, `remove.ai`, `remove.dictation`, `remove.service`, `remove.development`, `remove.gaming`, `remove.browser`, `remove.security`, `remove.development.javascript`, `remove.development.php`, `remove.development.elixir`, `update.channel`, `update.config`, `update.process`, `update.hardware`, `update.password` | kept as is |
| GUI | `apps` Apps, `about` About | launcher / About |
| DROP | `learn.community` Community | omarchy Discord |
| GUI | `learn.arch` Arch | replaced by `learn.nixos` (NixOS manual) |
| GUI | `learn.keybindings` Keybindings, `learn.omarchy` Omarchy, `learn.hyprland` Hyprland, `learn.neovim` Neovim, `learn.bash` Bash, `learn.tmux-keybindings` Tmux, `learn.herdr-keybindings` Herdr | docs launchers |
| GUI | `system.screensaver` Screensaver, `system.lock` Lock, `system.suspend` Suspend, `system.hibernate` Hibernate, `system.logout` Logout, `system.reboot` Reboot, `system.shutdown` Shutdown | power / lock |
| INTENT | `appearance.top-bar.indicators.clock.sunday-24h` Sunday 14:30, `appearance.top-bar.indicators.clock.sunday-12h` Sunday 2:30 PM, `appearance.top-bar.indicators.clock.sunday-seconds-24h` Sunday 14:30:05, `appearance.top-bar.indicators.clock.sunday-seconds-12h` Sunday 2:30:05 PM, `appearance.top-bar.indicators.clock.time-24h` 14:30, `appearance.top-bar.indicators.clock.time-12h` 2:30 PM, `appearance.top-bar.indicators.clock.date-24h` Sun 3 May 14:30, `appearance.top-bar.indicators.clock.date-12h` Sun 3 May 2:30 PM, `appearance.top-bar.indicators.clock.week` 3 May W18 2026, `appearance.top-bar.indicators.clock.iso` 2026-05-03 14:30, `appearance.top-bar.indicators.clock.stacked-24h` 14 — 30, `appearance.top-bar.indicators.clock.stacked-12h` 2 — 30 PM, `appearance.top-bar.indicators.clock.stacked-date` 03 May W18 '26, `appearance.top-bar.indicators.clock.stacked-time` 14 30 | "Show the clock as {label}." |
| INTENT | `appearance.branding.about.text` Edit Text, `appearance.branding.about.image` Set From Image, `appearance.branding.about.default` Restore Default, `appearance.branding.screensaver.text` Edit Text, `appearance.branding.screensaver.image` Set From Image, `appearance.branding.screensaver.default` Restore Default | "Change my {parent} branding: {label}." |
| INTENT | `appearance.unlock` Unlock | "Set the unlock screen to {selection}." (picker-then-intent) |
| GUI | `appearance.theme` Theme, `appearance.background` Background, `appearance.top-bar.hide` Hide Bar, `appearance.top-bar.show` Show Bar, `appearance.top-bar.background.opaque` Opaque Bar, `appearance.top-bar.background.glassy` Glassy Bar, `appearance.top-bar.background.clear` Clear Bar, `appearance.top-bar.indicators.battery-percentage-on` Show Battery %, `appearance.top-bar.indicators.battery-percentage-off` Hide Battery %, `appearance.top-bar.position.top` Top Bar, `appearance.top-bar.position.bottom` Bottom Bar, `appearance.top-bar.position.left` Left Bar, `appearance.top-bar.position.right` Right Bar, `appearance.windows.gaps-on` Window Gaps On, `appearance.windows.gaps-off` Window Gaps Off, `appearance.windows.corners.theme` Theme Corners, `appearance.windows.corners.sharp` Sharp Corners, `appearance.windows.corners.rounded` Rounded Corners, `appearance.windows.transparency.opaque` Opaque Windows, `appearance.windows.transparency.transparent` Transparent Windows, `appearance.windows.transparency.glassy` Glassy Windows, `appearance.windows.one-window-ratio-on` 1-Window Ratio On, `appearance.windows.one-window-ratio-off` 1-Window Ratio Off, `appearance.dock.autohide` Auto-hide Dock, `appearance.dock.always-on` Always-on Dock, `appearance.dock.position.top` Top Dock, `appearance.dock.position.bottom` Bottom Dock, `appearance.dock.position.left` Left Dock, `appearance.dock.position.right` Right Dock, `appearance.workspace-layout.dwindle` Tiling, `appearance.workspace-layout.scrolling` Scrolling, `appearance.workspace-layout.floating` Floating, `appearance.animations-on` Animations On, `appearance.animations-off` Animations Off | live look controls (theme, background, bar, windows, dock, layout, animations) |
| GUI | `trigger.toggle.idle-lock-on` Stay Awake, `trigger.toggle.idle-lock-off` Allow Sleep, `trigger.toggle.notifications-on` Notifications On, `trigger.toggle.notifications-off` Silence Notifications, `trigger.toggle.nightlight-on` Nightlight On, `trigger.toggle.nightlight-off` Nightlight Off, `trigger.toggle.screensaver-on` Screensaver On, `trigger.toggle.screensaver-off` Screensaver Off, `trigger.toggle.crash-capture-on` Crash Capture On, `trigger.toggle.crash-capture-off` Crash Capture Off, `trigger.emoji` Emoji, `trigger.clipboard-history` Clipboard History, `trigger.capture.screenshot` Screenshot, `trigger.capture.screenrecord.stop` Stop Screenrecording, `trigger.capture.text` Text, `trigger.capture.qr` QR Code, `trigger.capture.color` Color, `trigger.capture.screenrecord.no-audio` With no audio, `trigger.capture.screenrecord.desktop-audio` With desktop audio, `trigger.capture.screenrecord.microphone` With desktop + microphone audio, `trigger.capture.screenrecord.webcam` With desktop + microphone audio + webcam, `trigger.transcode` Transcode, `trigger.hardware.laptop-display-on` Laptop Display On, `trigger.hardware.laptop-display-off` Laptop Display Off, `trigger.hardware.mirror-display-on` Display Mirroring On, `trigger.hardware.mirror-display-off` Display Mirroring Off, `trigger.hardware.hybrid-gpu-on` Switch to Hybrid GPU, `trigger.hardware.hybrid-gpu-off` Switch to Integrated GPU, `trigger.hardware.touchpad-on` Enable Touchpad, `trigger.hardware.touchpad-off` Disable Touchpad, `trigger.hardware.touchpad-haptics.low` low, `trigger.hardware.touchpad-haptics.mid` mid, `trigger.hardware.touchpad-haptics.high` high, `trigger.hardware.touchscreen-on` Enable Touchscreen, `trigger.hardware.touchscreen-off` Disable Touchscreen, `trigger.reminder.set` Set one, `trigger.reminder.show` Show all, `trigger.reminder.clear` Clear all, `trigger.share.clipboard` Clipboard, `trigger.share.file` File, `trigger.share.folder` Folder, `trigger.share.receive` Receive, `trigger.tests.network-speedtest` Network Speed Test, `trigger.tests.disk-speedtest` Disk Speed Test | toggles, capture, share, reminders, hardware toggles, tests |
| GUI | `setup.monitors` Monitors | summons the monitor panel (arrangement/scale) |
| INTENT | `setup.keybindings` Keybindings | "Change a keybinding: " (open-ended) |
| INTENT | `setup.input` Input | "Change my mouse/touchpad settings: " (open-ended) |
| GUI | `setup.typing.keyboard` Keyboard Layouts | keyboard layouts (reach-the-agent) |
| INTENT | `setup.typing.input` Input Methods | "Set up input methods for {selection}." |
| GUI | `setup.network.qr` QR Code | Wi-Fi QR |
| INTENT | `setup.network.dns.dhcp` DHCP, `setup.network.dns.cloudflare` Cloudflare, `setup.network.dns.google` Google, `setup.network.dns.custom` Custom | "Use {label} DNS." |
| INTENT | `setup.default.agent.amp` Amp, `setup.default.agent.agy` Antigravity, `setup.default.agent.claude` Claude, `setup.default.agent.codex` Codex, `setup.default.agent.commandcode` Command Code, `setup.default.agent.copilot` Copilot, `setup.default.agent.crush` Crush, `setup.default.agent.cursor-agent` Cursor CLI, `setup.default.agent.dsh` DeepSeek Harness, `setup.default.agent.devin` Devin CLI, `setup.default.agent.freebuff` Freebuff, `setup.default.agent.grok` Grok, `setup.default.agent.hermes` Hermes, `setup.default.agent.kilo` Kilo, `setup.default.agent.kimi` Kimi, `setup.default.agent.kiro-cli` Kiro CLI, `setup.default.agent.mcode` MiniMax Code, `setup.default.agent.muse` Muse Code, `setup.default.agent.omp` omp, `setup.default.agent.openclaw` OpenClaw, `setup.default.agent.opencode` OpenCode, `setup.default.agent.ori` Ori, `setup.default.agent.pi` Pi, `setup.default.agent.qwen` Qwen Code, `setup.default.browser.chromium` Chromium, `setup.default.browser.chrome` Chrome, `setup.default.browser.brave` Brave, `setup.default.browser.brave-origin` Brave Origin, `setup.default.browser.edge` Edge, `setup.default.browser.firefox` Firefox, `setup.default.browser.zen` Zen, `setup.default.dictation.superwhisper` Superwhisper, `setup.default.dictation.voxtype` Voxtype, `setup.default.terminal.alacritty` Alacritty, `setup.default.terminal.foot` Foot, `setup.default.terminal.ghostty` Ghostty, `setup.default.terminal.kitty` Kitty, `setup.default.editor.neovim` Neovim, `setup.default.editor.vscode` VSCode, `setup.default.editor.cursor` Cursor, `setup.default.editor.zed` Zed, `setup.default.editor.sublime` Sublime Text, `setup.default.editor.helix` Helix, `setup.default.editor.vim` Vim, `setup.default.editor.emacs` Emacs | "Make {label} my default {kind}." |
| GUI | `setup.plugin.enable` Enable Plugin, `setup.plugin.disable` Disable Plugin | runtime shell.json |
| INTENT | `setup.plugin.add` Add Plugin, `setup.plugin.clone` Clone Plugin, `setup.plugin.remove` Remove Plugin | "Add / clone / remove a shell plugin: " |
| DROP | `setup.security.passwordless-sudo` Passwordless Sudo | no passwordless sudo (D8) |
| INTENT | `setup.security.fingerprint` Fingerprint, `setup.security.fido2` Fido2, `setup.security.sshd` SSHD, `setup.security.ssh-agent` SSH Agent, `setup.security.sudoless-docker` Sudoless Docker | "Set up {label}." (protected-option facts on the card) |
| INTENT | `setup.config.git` Git, `setup.config.hyprland` Hyprland, `setup.config.hyprsunset` Hyprsunset, `setup.config.xcompose` XCompose | "Change my {label} configuration: " (git: "Set my git name and email.") |
| DROP | `setup.direct-boot` Direct Boot, `setup.reset` Reset Computer | EFI direct boot / factory reset |
| DROP | `install.aur` AUR | AUR |
| GUI | `install.style.background` Background | opens the user backgrounds folder |
| INTENT | `install.package` Package, `install.style.theme` Theme, `install.style.font.cascadia` Cascadia Mono, `install.style.font.meslo` Meslo LG Mono, `install.style.font.fira` Fira Code, `install.style.font.victor` Victor Code, `install.style.font.bitstream` Bitstream Vera Mono, `install.style.font.iosevka` Iosevka, `install.webapp` Web App, `install.tui` TUI, `install.windows` Windows, `install.preinstalls` Preinstalls, `install.browser.chrome` Chrome, `install.browser.edge` Edge, `install.browser.brave` Brave, `install.browser.brave-origin` Brave Origin, `install.browser.firefox` Firefox, `install.browser.zen` Zen, `install.service.1password` 1Password, `install.service.dropbox` Dropbox, `install.service.spotify` Spotify, `install.service.signal` Signal, `install.service.slack` Slack, `install.service.tailscale` Tailscale, `install.service.nordvpn` NordVPN, `install.service.once` ONCE, `install.service.bitwarden` Bitwarden, `install.service.microsoft` Microsoft, `install.service.chromium-account` Chromium Account, `install.editor.vscode` VSCode, `install.editor.cursor` Cursor, `install.editor.zed` Zed, `install.editor.sublime` Sublime Text, `install.editor.helix` Helix, `install.editor.vim` Vim, `install.editor.emacs` Emacs, `install.terminal.alacritty` Alacritty, `install.terminal.foot` Foot, `install.terminal.ghostty` Ghostty, `install.terminal.kitty` Kitty, `install.ai.chatgpt` ChatGPT Desktop, `install.ai.claude` Claude Desktop, `install.ai.grok-bot` Grok Bot, `install.ai.hermes` Hermes Desktop, `install.ai.lm-studio` LM Studio, `install.ai.ollama` Ollama, `install.ai.openclaw` OpenClaw, `install.ai.perplexity` Perplexity, `install.ai.t3-code` T3 Code, `install.gaming.steam` Steam, `install.gaming.retroarch` RetroArch, `install.gaming.minecraft` Minecraft, `install.gaming.geforce-now` NVIDIA GeForce NOW, `install.gaming.xbox-cloud` Xbox Cloud Gaming, `install.gaming.xbox-controllers` Xbox Controllers, `install.gaming.battlenet` Battle.net, `install.gaming.lutris` Lutris, `install.gaming.heroic` Heroic (Epic Games), `install.gaming.retro-launcher` RetroArch Game Launcher, `install.development.rails` Ruby on Rails, `install.development.docker-dbs` Docker DB, `install.development.go` Go, `install.development.python` Python, `install.development.zig` Zig, `install.development.rust` Rust, `install.development.java` Java, `install.development.dotnet` .NET, `install.development.ocaml` OCaml, `install.development.clojure` Clojure, `install.development.scala` Scala, `install.development.javascript.node` Node.js, `install.development.javascript.bun` Bun, `install.development.javascript.deno` Deno, `install.development.php.php` PHP, `install.development.php.laravel` Laravel, `install.development.php.symfony` Symfony, `install.development.elixir.elixir` Elixir, `install.development.elixir.phoenix` Phoenix | "Install {label}." |
| INTENT | `remove.package` Package, `remove.theme` Theme, `remove.webapp` Web App, `remove.tui` TUI, `remove.windows` Windows, `remove.preinstalls` Preinstalls, `remove.security.fingerprint` Fingerprint, `remove.security.fido2` Fido2, `remove.security.sshd` SSHD, `remove.security.sudoless-docker` Sudoless Docker, `remove.ai.hermes` Hermes Desktop, `remove.browser.chrome` Chrome, `remove.browser.edge` Edge, `remove.browser.brave` Brave, `remove.browser.brave-origin` Brave Origin, `remove.browser.firefox` Firefox, `remove.browser.zen` Zen, `remove.service.1password` 1Password, `remove.service.dropbox` Dropbox, `remove.service.tailscale` Tailscale, `remove.service.microsoft` Microsoft, `remove.service.ssh-agent` SSH Agent, `remove.ai.chatgpt` ChatGPT Desktop, `remove.ai.claude` Claude Desktop, `remove.dictation.superwhisper` Superwhisper, `remove.dictation.voxtype` Voxtype, `remove.ai.grok-bot` Grok Bot, `remove.ai.lm-studio` LM Studio, `remove.ai.ollama` Ollama, `remove.ai.openclaw` OpenClaw, `remove.ai.perplexity` Perplexity, `remove.ai.t3-code` T3 Code, `remove.gaming.steam` Steam, `remove.gaming.retroarch` RetroArch, `remove.gaming.minecraft` Minecraft, `remove.gaming.geforce-now` NVIDIA GeForce NOW, `remove.gaming.xbox-cloud` Xbox Cloud Gaming, `remove.gaming.xbox-controllers` Xbox Controllers (󰂯), `remove.gaming.battlenet` Battle.net, `remove.gaming.lutris` Lutris, `remove.gaming.heroic` Heroic (Epic Games), `remove.development.rails` Ruby on Rails, `remove.development.go` Go, `remove.development.python` Python, `remove.development.zig` Zig, `remove.development.rust` Rust, `remove.development.java` Java, `remove.development.dotnet` .NET, `remove.development.ocaml` OCaml, `remove.development.clojure` Clojure, `remove.development.scala` Scala, `remove.development.javascript.node` Node.js, `remove.development.javascript.bun` Bun, `remove.development.javascript.deno` Deno, `remove.development.php.php` PHP, `remove.development.php.laravel` Laravel, `remove.development.php.symfony` Symfony, `remove.development.elixir.elixir` Elixir, `remove.development.elixir.phoenix` Phoenix | "Remove {label}." |
| DROP | `update.config.plymouth` Plymouth | generated by nix |
| GUI | `update.config.hyprland` Hyprland, `update.config.hyprsunset` Hyprsunset, `update.config.tmux` Tmux, `update.config.shell` Shell | undo: `omanix reset <area>` |
| GUI | `update.process.hyprsunset` Hyprsunset, `update.process.shell` Shell, `update.hardware.audio` Audio, `update.hardware.wifi` Wi-Fi, `update.hardware.bluetooth` Bluetooth, `update.hardware.trackpad` Trackpad | repair: restart shell/hyprsunset/audio/wifi/bluetooth/trackpad |
| GUI | `update.time` Time | repair: time sync |
| GUI | `update.password.drive` Drive Encryption, `update.password.user` User | human-only secret tools: `loom unlock passphrase`, `loom user passwd` |
| INTENT | `update.channel.stable` Stable, `update.channel.rc` RC, `update.channel.edge` Edge, `update.channel.dev` Dev | "Move this machine to the omanix {label} release line." |
| INTENT | `update.omarchy` Omarchy | "Check for updates and prepare an update card." |
| INTENT | `update.themes` Extra Themes, `update.firmware` Firmware, `update.timezone` Timezone | "Update my themes." / "Update firmware." / "Set my timezone to {selection}." |

Per-class totals: KEEP-AS-GUI 115, AGENT-INTENT 232, ASSET 0, RE-EXPRESS-IN-NIX 0, DROP 6, NAV 69.

## Appendix C. Tree mapping (every file outside bin/, grouped)

| Class | Rule (path) | Files | Mechanism |
|---|---|---|---|
| DROP | `migrations/.*` | 211 files | migrations |
| ASSET | `themes/.*` | 274 files | themes (renderer unchanged) |
| DROP | `shell/plugins/dev-gallery/.*` | `shell/plugins/dev-gallery/manifest.json`, `shell/plugins/dev-gallery/GalleryPanel.qml` | contributor UI gallery |
| ASSET | `shell/.*` | 276 files | Quickshell shell (patches P1–P3, P5–P8, P10–P13) |
| ASSET | `applications/.*` | 33 files | web app catalog + icons → `omanix.apps.webapps` |
| DROP | `config/autostart/limine-snapper-notify\.desktop` | `config/autostart/limine-snapper-notify.desktop` | limine/snapper |
| ASSET | `config/.*` | 47 files | HM read-only dotfiles / app-owned seeds (D9) |
| INTENT | `default/agents/.*` | `default/agents/skills/omarchy/theming.md`, `default/agents/skills/omarchy/plugins.md`, `default/agents/skills/omarchy/hyprland.md`, `default/agents/skills/omarchy/hooks.md`, `default/agents/skills/omarchy/contributing.md`, `default/agents/skills/omarchy/capture.md`, `default/agents/skills/omarchy/SKILL.md`, `default/agents/skills/omarchy-app/templates.md`, `default/agents/skills/omarchy-app/SKILL.md`, `default/agents/skills/diagnose-crash/reporting.md`, `default/agents/skills/diagnose-crash/SKILL.md` | folded into resident skills (§4.5) |
| DROP | `default/(pacman\|libalpm\|limine\|snapper\|regions)/.*` | 28 files | Arch boot/packaging |
| DROP | `default/systemd/user/omarchy-migrate-notify\.service` | `default/systemd/user/omarchy-migrate-notify.service` | migrations |
| DROP | `default/systemd/system/systemd-(pcrlogin@\|pcrproduct\|tpm2-setup-early)\.service\.d/.*` | `default/systemd/system/systemd-tpm2-setup-early.service.d/10-omarchy-nvpcr.conf`, `default/systemd/system/systemd-pcrproduct.service.d/10-omarchy-nvpcr.conf`, `default/systemd/system/systemd-pcrlogin@.service.d/10-omarchy-nvpcr.conf` | NvPCR drop-ins (pending U8) |
| NIX | `default/(systemd\|udev\|v4l2-relayd\|audio\|alsa\|uwsm\|environment\.d\|firefox\|chromium)/.*` | 61 files | units, quirk data, session env, browser policies |
| DROP | `default/omarchy/sudo-no-update/.*` | `default/omarchy/sudo-no-update/sudo` | pacman update guard for sudo |
| ASSET | `default/.*` | 354 files | Lua, menu data, templates, shell configs, fonts, i18n, plymouth/sddm themes, input methods |
| DROP | `etc/(sudoers\.d\|mkinitcpio\.conf\.d\|limine-entry-tool\.d)/.*` | `etc/sudoers.d/omarchy-tzupdate`, `etc/sudoers.d/omarchy-theme-browser`, `etc/sudoers.d/omarchy-passwd-tries`, `etc/sudoers.d/omarchy-locale-generate`, `etc/sudoers.d/omarchy-dns`, `etc/mkinitcpio.conf.d/thunderbolt_module.conf`, `etc/mkinitcpio.conf.d/omarchy_vconsole.conf`, `etc/mkinitcpio.conf.d/omarchy_hooks.conf`, `etc/mkinitcpio.conf.d/i2c_hid_of_module.conf`, `etc/mkinitcpio.conf.d/00-omarchy-hooks.conf`, `etc/limine-entry-tool.d/omarchy-uki.conf`, `etc/limine-entry-tool.d/omarchy-defaults.conf` | sudoers/initramfs/limine |
| DROP | `etc/tmpfiles\.d/omarchy-nopasswd-sudo\.conf` | `etc/tmpfiles.d/omarchy-nopasswd-sudo.conf` | passwordless sudo |
| DROP | `etc/mise/conf\.d/omarchy-(tools\|agent-accounts)\.toml` | `etc/mise/conf.d/omarchy-tools.toml`, `etc/mise/conf.d/omarchy-agent-accounts.toml` | runtime-fetched agent CLIs (nix packages instead) |
| ASSET | `etc/(fastfetch\|mpv\|xdg)/.*` | `etc/xdg/kitty/kitty.conf`, `etc/mpv/mpv.conf`, `etc/fastfetch/config.jsonc` | app configs (environment.etc) |
| NIX | `etc/.*` | 38 files | sysctl, NM, logind, resolved, oomd, faillock, cups, docker, xkb, profile.d, mise base |
| DROP | `install/hardware/(all\|pacman\|platform-setup)\.sh` | `install/hardware/platform-setup.sh`, `install/hardware/pacman.sh`, `install/hardware/all.sh` | dispatchers / pacman |
| DROP | `install/hardware/fix-yt6801-ethernet-adapter\.sh` | `install/hardware/fix-yt6801-ethernet-adapter.sh` | empty |
| NIX | `install/(hardware\|user/hardware)/.*` | 57 files | quirk modules (§7) |
| DROP | `install/user/(xcompose\|language\|all)\.sh\|install/user/first-run/setup-agent\.hook` | `install/user/xcompose.sh`, `install/user/language.sh`, `install/user/all.sh`, `install/user/first-run/setup-agent.hook` | HM-owned / resident onboarding / dispatcher |
| NIX | `install/user/.*` | 15 files | session init / first login |
| NIX | `install/.*\.packages` | `install/omarchy-x86_64-only.packages`, `install/omarchy-other.packages`, `install/omarchy-base.packages`, `install/omarchy-aarch64.packages`, `install/omarchy-aarch64-qualcomm.packages`, `install/omarchy-aarch64-n1x.packages`, `install/omarchy-aarch64-gb10.packages`, `install/omarchy-aarch64-apple.packages` | `omanix.packages.base` (aarch64 lists deferred) |
| DROP | `install/config/(snapper\|all)\.sh` | `install/config/snapper.sh`, `install/config/all.sh` | snapper / dispatcher |
| NIX | `install/(config\|login)/.*` | 13 files | base modules, SDDM |
| DROP | `install/.*` | 14 files | helpers, post-install, provisioning (loom installer) |
| ASSET | `manual/.*` | 2594 files | end-user manual (resident reference) |
| ASSET | `LICENSE` | `LICENSE` | MIT notice, shipped unmodified (§10) |
| DROP | `(logo\.svg\|logo\.txt\|icon\.png\|icon\.txt\|version)` | `version`, `logo.txt`, `logo.svg`, `icon.txt`, `icon.png` | branding / meaningless version |
| DROP | `.*` | 552 files | contributor docs, plans, tests, scripts, agents/skills, CI, editor configs |
