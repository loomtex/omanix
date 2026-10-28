# omanix fork: agent-first UX (V2, V3, V5)

Status: design, 2026-10-27. Scope follows spec rev 16 (USB installer image only; credentials never copied by the installer; the agent signs in on the new machine through its own normal login flow). This file covers what the human sees and touches. It replaces DESIGN.md's tiers, `settings.json` and `omanix keep`/`set` gates wherever they touch UX (V4). Install image, disk, LUKS, unlock, Secure Boot, enrollment, SEK, impermanence and read-only HM dotfiles stay as DESIGN.md has them.

Sources read: loom `prompt.nix` and history (`6780813` "hyprctl live-tuning", `250f71f` QR auth server, `bab41d5` three-phase kiosk); nuketown `approval-daemon.nix`, `module.nix` broker, `daemon/` socket and XMPP approval; omarchy `shell/plugins/*` (manifest contract, `omarchy.polkit`, `omarchy.agents`, `omarchy.image-picker`), `default/omarchy/omarchy-menu.jsonc`, `default/hypr/bindings/*`; survey reports in `understand/`.

---

## 0. Ten rules

| # | Rule |
|---|---|
| U1 | **The agent is the front door for change, not for control.** Anything continuous, instant or visual stays a GUI control. Anything that changes what the machine *is* (packages, services, defaults, hardware setup, keybinds) is a sentence to the agent. |
| U2 | **GUI changes are runtime state.** Every kept GUI tool changes the running session only, and offers **Make it stick**. Sticking is a request to the agent. |
| U3 | **Every switch is a card, and every card needs the human's key.** Touch (FIDO2) or passphrase (software key). No unattended switches, no exceptions except the watchdog's automatic rollback and a human-initiated Undo (§3.8). |
| U4 | **Routine cards are one line.** Escalation is decided by code (facts) or by the reviewer. The reviewer can escalate but can never de-escalate a fact. |
| U5 | **Facts are code, never AI.** They are computed by loom from the evaluated configs and build results, shown in their own frame, and hashed into the approval commit. |
| U6 | **Provenance is held by root, not by the agent.** What the human typed is recorded by `loom-askd` (SO_PEERCRED) before the resident sees it. The reviewer reads the ask from askd, never from the agent. |
| U7 | **The resident is another user.** It can't see the human's screen, files or Wayland socket. The human hands it context explicitly (attachments), with a preview. |
| U8 | **Nothing the agent writes can look like system UI.** Chat renders plain text plus a safe Markdown subset. Cards are drawn by a separate plugin in a separate layer-shell surface. |
| U9 | **The system is whole without the agent.** It's NixOS: edit the host repo, `loom switch`, same card, same key. |
| U10 | **One keystroke to the agent from anywhere**: `SUPER + SHIFT + A` opens the chat panel; typing in the `SUPER + SPACE` menu falls through to "Ask <agent>: …". |

---

## 1. Components and where they live

```
human session (uid 1000)                         root                                   residents
──────────────────────────                       ────                                   ─────────
Quickshell omarchy-shell (forked)                loom-askd       /run/loom/ask.sock     ada     (uid 1100)  UI agent
  plugins/omanix.chat      ── record ask ──────▶   (SO_PEERCRED: human only)              loom-agent-bridge@ada
  plugins/omanix.chat      ── chat ────────────────────────────────────────────────────▶   /run/loom/agent/ada/chat.sock
  plugins/omanix.approval  ◀─ card (IPC) ── nuketown broker (human user svc)              harness: claude-code (stream-json)
  plugins/omanix.welcome                          ▲ SIGN                                 review  (uid 1101)  reviewer
  plugins/omanix.undo  ── rollback ──────────▶  loom-switchd   /run/loom/switchd.sock      no general network, no tools,
                                                  loom-facts (inside loom-eval)             writes nothing outside its creds
                                                  loom-reviewd ─ systemd-run --uid=review ▶ reads bundle, prints review JSON
```

| Component | Repo | Runs as | Job |
|---|---|---|---|
| `loom-askd` | loom | root (`DynamicUser=no`, `ProtectSystem=strict`) | Records human asks, rejections and make-it-stick requests with ids. Append-only store `/persist/var/lib/loom/asks/YYYY-MM.jsonl`. |
| `loom-agent-bridge@<agent>` | loom | `<agent>` (system unit, socket-activated) | Hosts the harness in streaming mode; translates harness events to `loom.chat/v1`; receives attachments. **Untrusted**: it is the agent's own process. |
| `loom-facts` | loom | inside `loom-eval` (DynamicUser) | Deterministic facts (§3.3). |
| `loom-reviewd` | loom | root, spawns reviewer as `review` | Assembles the review bundle, runs the reviewer, validates its JSON, assembles the card. |
| `loom-switchd` | loom | root | Unchanged pipeline (DESIGN §g.4) with classify replaced by facts + review + SIGN for every commit. |
| nuketown broker (+`SIGN`) | nuketown | human user service | Relays the card to the prompter, runs `loom-approve-sign`, returns the approval commit. Prompter = `qs ipc call omanix.approval show <card.json>`; zenity fallback. |
| `omanix.chat` | omanix (shell fork) | human | Panel, composer, transcript, activity rail, bar widget, attachments. |
| `omanix.approval` | omanix | human | Card surface (routine banner, escalated card, diff view), pending-cards badge. Replaces zenity. |
| `omanix.welcome` | omanix | human | First-boot checklist and tour driver. |
| `omanix.undo` | omanix | human | "Undo last change" in the bar menu and in post-switch toasts. |
| `loom-card-tty` | loom | caller | Same card rendered in a terminal for `loom switch` without a session and for the no-agent path. |

Schemas (JSON Schema, in loom, checked in `nix flake check` by `checks.ux-schemas`):

```
loom/schemas/
  ask.v1.json          { id, at, uid, origin, text, context[], attachments[{name,kind,sha256,bytes}] }
  chat-event.v1.json   bridge → surface events (§2.3)
  chat-input.v1.json   surface → bridge messages
  facts.v1.json        §3.3
  review.v1.json       §3.4
  card.v1.json         { id, sha, deployed, kind: change|update|rollback, ask, facts, factsSha256,
                         review|null, presentation: routine|escalated, reasons[], diffstat, expires }
```

File tree added by this design:

```
loom/
  pkgs/loom-askd/                   python, stdlib only
  pkgs/loom-agent-bridge/
    bridge.py
    adapters/claude-code.py         stream-json in/out
    adapters/replay.py              scripted transcripts for VM tests and the demo
  pkgs/loom-facts/
  pkgs/loom-reviewd/
    prompt.md                       fixed reviewer instructions (part of the release, protected)
  pkgs/loom-card-tty/
  modules/loom/agent/{resident.nix,bridge.nix,login.nix}
  modules/loom/reviewer/{default.nix,egress.nix}
  modules/loom/provenance.nix       askd
  modules/loom/switch/facts.nix
  schemas/*.json
omanix/                              (the omarchy fork)
  shell/plugins/omanix.chat/{manifest.json,Panel.qml,BarWidget.qml,Transcript.qml,Composer.qml,
                             ActivityRail.qml,Attachments.qml,Chips.qml,OptionsBrowser.qml}
  shell/plugins/omanix.approval/{manifest.json,Service.qml,Banner.qml,Card.qml,FactsBlock.qml,
                                 ReviewerBlock.qml,DiffView.qml,KeyGesture.qml}
  shell/plugins/omanix.welcome/{manifest.json,Welcome.qml,Tour.qml}
  shell/plugins/omanix.undo/{manifest.json,Undo.qml}
  data/intents/menu.jsonc           overlay on the forked omarchy-menu.jsonc (§4.1)
  data/intents/howto.json           intent → module/option/file for the no-agent path (§6)
  data/chips/rules.json             deterministic suggestion chips (§4.2)
  modules/omanix/{chat.nix,approval.nix,welcome.nix,intents.nix}
nuketown/
  approval-daemon.nix               + SIGN, prompter/display/target options (DESIGN §a.3)
```

Options (new or changed):

```
loom.agent.enable            bool, true                         install question "Use an AI agent?" yes/later/no (§6)
loom.agent.name              str, "ada"                         installer offers rename
loom.agent.harness           enum ["claude-code" "replay"], "claude-code"
loom.agent.harnessPackage    package
loom.agent.chat.attachments.maxBytes   int, 8 MiB
loom.reviewer.enable         bool, = loom.agent.enable
loom.reviewer.name           str, "review"      uid 1101
loom.reviewer.harness        enum ["claude-code" "replay"]
loom.reviewer.model          nullOr str         null = harness default
loom.reviewer.egress.allow   listOf str, [ "api.anthropic.com:443" ]   (harness adapter sets it)
loom.reviewer.timeout        int, 120 s
loom.reviewer.maxDiffBytes   int, 200 KiB
loom.switch.vmCheck          enum ["auto" "always" "never"], "auto"   auto = when /dev/kvm exists
loom.switch.cardExpiry       int, 86400 s
loom.provenance.staleAfter   int, 86400 s
omanix.chat.keybind          str, "SUPER + SHIFT + A"   (replaces omarchy's ChatGPT webapp bind)
omanix.chat.menuFallthrough  bool, true
omanix.approval.unlockDelayMs int, 800       buttons inert this long after the card appears
omanix.welcome.enable        bool, true
omanix.welcome.tour          bool, true
```

All of `loom.agent.*`, `loom.reviewer.*`, `loom.provenance.*`, `loom.switch.*` and the reviewer prompt package are on the **highlight list** (D5): a change to any of them is a fact and escalates the card.

---

## 2. Chat surface

### 2.1 Shape

- **Panel**: right-edge drawer, layer-shell `top`, 34% width (min 420 px), full height minus bar. Toggled by `SUPER + SHIFT + A`, the bar widget, or any intent. Doesn't steal focus from fullscreen apps unless opened by the human.
- **Bar widget** `omanix.chat` (replaces `omarchy.agents` at the same slot in `shell.json`): agent glyph + state dot. Idle (hollow), working (pulsing), needs you (accent, count of pending cards/questions), offline/not signed in (struck).
- **Header**: agent name, state, "New chat", conversation list (today / earlier), overflow menu: Open in terminal, Sign in again, Stop.
- **Transcript**: human bubbles (right), agent text (left), activity rail entries inline and collapsed, card references ("Approval card opened" with a link that focuses the card; the card itself is never drawn here).
- **Composer**: multiline, Enter sends, Shift+Enter newline. Buttons: Attach (§2.5), Context chips (§4.2), Stop (while working).
- **Menu fallthrough**: in the `SUPER + SPACE` menu, a query with no exact match shows a last row "Ask ada: <query>". Choosing it opens the panel with the text in the composer, not sent.

### 2.2 Transport and auth

1. `loom-agent-bridge@<agent>.socket` (system unit): `ListenStream=/run/loom/agent/<agent>/chat.sock`, `SocketUser=<agent>`, `SocketGroup=loom-chat-<agent>`, `SocketMode=0660`. The human user is the only member of `loom-chat-<agent>` (generated from `nuketown.humanUser`).
2. The bridge also checks `SO_PEERCRED` and accepts only the human uid. One client at a time; a second connection takes over and the first gets `{t:"detached"}`.
3. Framing: newline-delimited JSON (`loom.chat/v1`), same style as nuketown's daemon socket. Quickshell side uses `Quickshell.Io` `Socket` with a `SplitParser` (UNVERIFIED-1).
4. Before sending any human text, the panel calls `loom-askd record` on `/run/loom/ask.sock` and gets `{id:"ask-01J…", at}`. The message to the bridge carries `ask` = that id. askd stores the exact text, the origin and attachment hashes (not bytes).
5. askd accepts only the human uid (`SO_PEERCRED`). The resident cannot record asks. Any process running as the human can; that is the same trust as `polkit auth_self` and is stated in the threat notes (§8).

The bridge is not trusted for anything security-relevant. Asks go to askd; cards come from switchd via the broker; the bridge carries only conversation.

### 2.3 Streaming and "what the agent is doing"

The claude-code adapter runs the harness long-lived in streaming JSON mode (`--input-format stream-json --output-format stream-json`, UNVERIFIED-2) in `~/projects/host`, with nuketown's generated prompt plus loom/omanix fragments. Permissions mode inside the harness is the resident's own business: its powers are bounded by its uid, `gate/*`-only push and switchd.

Events to the panel (`chat-event.v1`):

| `t` | Fields | UI |
|---|---|---|
| `text` | `delta` | Appended to the current agent bubble. Markdown subset: paragraphs, lists, inline code, code blocks, bold/italic, links shown as `text (domain)`. No images, no HTML, no tables wider than the panel. |
| `activity` | `kind` read\|edit\|run\|search\|web\|build\|commit\|switch, `label`, `detail` | Activity rail row: "Reading modules/apps.nix", "Editing home.nix", "Running `omanix plan`", "Reading web page — github.com". `web` rows carry an "external content" marker. |
| `progress` | `phase` eval\|build\|vm\|review, `done`, `total` | One progress row that updates in place: "Checking · building 12/40 · VM smoke · review". |
| `card` | `id`, `presentation` | Reference row; focuses the card. |
| `question` | `text`, `choices[]` | Agent asks the human; choices render as buttons whose text is the reply (origin `agent-choice`, §4.2). |
| `status` | idle\|working\|blocked\|offline\|signed-out | Bar dot and header. |
| `auth` | `url` | Sign-in handoff (§2.6). |
| `rejected` | `sha`, `reason` | "You rejected <change>: <reason>" (echo of what the agent received). |
| `error` | `text` | Inline error row. |

Input messages (`chat-input.v1`): `{t:"user", ask, text, attachments[]}`, `{t:"stop"}`, `{t:"new-session"}`, `{t:"resume", session}`, `{t:"attach-begin"|"attach-chunk"|"attach-end", …}`.

The activity rail is informational. Facts on the card never come from it.

### 2.4 Conversation storage

Sessions live in the resident's harness state (`/agents/<agent>/.claude`, persisted by nuketown `persist.directories`). The panel lists them through the bridge. **Open in terminal** runs `portal-<agent>` and resumes the same session in the harness TUI when the bridge is idle (UNVERIFIED-2). Reinstall does not restore conversations (new agent home; spec: no credential transfer, and history is the agent's).

### 2.5 Attachments and context (safe by construction)

The resident has no access to the human's Wayland socket, screen, clipboard or files. Context reaches it only this way:

1. Human clicks **Attach**: Screenshot region, Window, File…, Clipboard text, Last error (most recent failed unit name + `omanix why-failed --json` summary, computed in the human session).
2. The panel shows a preview chip (thumbnail, or the first 400 characters of text, and the byte count). Nothing is sent yet.
3. On send, the panel strips image metadata (re-encode PNG via Qt), refuses files over `maxBytes` and any type other than PNG, JPEG, plain text and JSON, then streams the bytes to the bridge, which writes `/agents/<agent>/inbox/<ask-id>/<name>`.
4. askd records `{name, kind, sha256, bytes}` only.
5. The reviewer never sees attachment contents (V5: no content the agent read). The card's ask block shows "with 1 screenshot".

There is no agent tool for taking screenshots or reading the clipboard.

### 2.6 Sign-in handoff (normal provider flow, on this machine)

The resident signs in with its harness's own login command, run as the resident:

1. Panel shows "Sign in ada" (welcome step or `signed-out` status).
2. Click opens a floating terminal (`org.omanix.agent-login` app-id, window rule float/center) running `portal-<agent> login`, which execs `loom.agent.loginCommand` (claude-code: `claude` then `/login`) as `<agent>` via `machinectl shell` (nuketown portal path).
3. `BROWSER` inside that session is `loom-open-url`, which sends `{t:"auth", url}` through the bridge. The panel shows the URL's domain and an **Open in browser** button; the human's browser opens it.
4. The provider's flow completes as it normally does: either the human pastes the code back into that terminal, or the browser hits the harness's localhost callback (shared loopback; UNVERIFIED-3).
5. Tokens land only in `/agents/<agent>/.claude/`. They never pass through the human's home, the installer, silo or git.
6. The same steps sign in the reviewer (`portal-review login`), offered right after. The reviewer gets its **own** login; residents never share a token file.

---

## 3. Approval card

### 3.1 Lifecycle

```
resident: edit → commit (agent-signed, trailer "Ask: ask-…") → push gate/<topic> → `loom switch --commit <sha>`
switchd:  verify signers → unbundle → loom-eval + loom-facts → build → vmCheck (auto) → reviewd → card
          → SIGN to broker → card shown → approve: approval commit returned / reject: reason recorded
          → (approve) arm watchdog → test → health → promote → push master with host key
```

- Every commit range needs a human-signed approval commit at its tip: `approve <sha> facts:<sha256 of facts.json>` (replaces DESIGN §g.2's `view:` hash and the tier table).
- `Ask:` trailers are hints. reviewd resolves them in askd; a missing, unknown or stale id is a provenance fact (§3.3).
- Build or eval failure produces no card. The failure goes back to the resident (`exit 1`, verbatim error), and the panel shows it in the activity rail.
- Pending cards survive panel close and session restart (broker keeps them; bar badge counts them). A card expires after `loom.switch.cardExpiry` and is auto-rejected with reason `expired`.
- One card per switch request. The resident skill says: batch everything for one ask into one commit.

### 3.2 Inputs to the card

| Block | Source | Who can influence it |
|---|---|---|
| Ask | askd record(s) linked by trailer; for updates `origin: system:update-timer` | Human (typed), or system |
| Facts | `loom-facts` over old/new evaluated configs, closures, lock files, VM smoke | Nobody (code over the commit) |
| Reviewer | `loom-reviewd` running the `review` resident | AI, schema-limited, can only add escalation |
| Diff | `git diff <deployed>..<sha>`, `nvd diff` text | Agent wrote it; shown verbatim on demand |
| Agent's description | commit subject/body | Agent; shown only in the expanded view, labelled |

### 3.3 Facts (`loom-facts`, `facts.v1`)

Each fact is `{id, category, text, path?, old?, new?, origin}` where `origin` is `host:<file>` or `input:<name>` (from `definitionsWithLocations`, as DESIGN §g.1).

| Category | Computed from | Example text |
|---|---|---|
| `protected` | DESIGN §g.1 view diff (users, groups, sudo/doas, `security.*`, pam, wrappers, polkit; `nix.settings` users/substituters/keys/require-sigs/sandbox; openssh; firewall; `boot.*`; tmpfiles; `loom.*` trust/keys/policy/agent/reviewer/switch; `nuketown.humanUser`, `agents.<n>.{uid,sudo,devices,extraGroups}`; docker group) | "Adds substituter https://cache.example.org and trusts its key" |
| `repo-trust` | paths changed in `.authorized_keys`, `CODEOWNERS`, `.sops.yaml`, `secrets/` recipients | "Adds a key to .authorized_keys" |
| `services` | new/changed root `systemd.{services,timers,sockets,paths}` (name, wantedBy, ExecStart normalized) | "New system service tailscaled (starts at boot)" |
| `ports` | firewall allowed ports diff; `systemd.sockets.*.ListenStream`; listening sockets in the VM smoke vs the old generation's baseline | "TCP 41641 open in the firewall" |
| `session` | new/changed `systemd.user.services`, HM `home.activation` entries, Hyprland `exec-once`/autostart, XDG autostart files, shell init lines (rc files' hash) | "New program starts with your session: syncthing" |
| `inputs` | `flake.lock` node diff (new nodes, changed `original`, non-tag revs) | "New flake input github:foo/bar (unpinned branch)" |
| `packages` | closure diff, pname/version parsed by loom (nvd text shown, not parsed) | "+3 packages, 1 upgraded, closure +412 MiB" |
| `provenance` | askd lookup | "No request from you is linked to this change" / "Linked request is 3 days old" / "Request text was suggested by the agent" / "Request came from menu item install.gaming.steam" |
| `checks` | eval, build, VM smoke result, health baseline | "VM smoke skipped (no KVM)" |

`session` is an addition to V5's list: a human-session autostart is how a non-root change persists code in the human's account, so it is shown. Packages never escalate on their own; they are counted.

### 3.4 Reviewer (`review` resident)

- Unix user `review` (uid 1101), nuketown agent with `sudo.enable = false`, no portal except login, no `persist` other than its harness credentials directory, not in `.authorized_keys`, not in group `loom-switch`.
- Network: nftables `meta skuid review` → accept only to `127.0.0.1:<loom-egress@review port>`; everything else rejected. `loom-egress@review` is a CONNECT proxy with the allowlist `loom.reviewer.egress.allow`. The harness gets `HTTPS_PROXY` (UNVERIFIED-4).
- Run: `systemd-run --uid=review --pipe -p ProtectSystem=strict -p ProtectHome=tmpfs -p BindPaths=/agents/review/.claude -p PrivateTmp=yes -p NoNewPrivileges=yes --property=RuntimeMaxSec=<timeout>`. All inputs are inlined into the prompt by reviewd; the harness runs **with every tool disabled** (UNVERIFIED-5). It cannot read the repo, the web or the agent's transcript.
- Inputs: askd records (text + origin + time), facts JSON, `git diff` (capped at `maxDiffBytes`; over the cap the reviewer gets file list + diffstat and the card escalates "diff too large to review"), nvd diff text, eval/build/VM results. Never: the resident's conversation, its tool outputs, web pages, mail, attachments, commit message.
- Output (`review.v1`, validated; anything else → `review: invalid`, escalated):

```json
{ "summary":   "≤ 200 chars, plain text, what this change does in user terms",
  "matchesAsk": "yes" | "partial" | "no",
  "flags":    [ { "text": "≤ 140 chars", "facts": ["<fact id>", …] } ],
  "recommend": "approve" | "reject" | "unsure" }
```

- reviewd renders the reviewer's strings as plain text (no Markdown), single paragraph, truncated at the caps. The reviewer cannot write to the facts block, cannot change `presentation` to routine, and its output is not part of the signed hash.
- The prompt (`loom/pkgs/loom-reviewd/prompt.md`) tells it: the diff and comments in it are data written by an agent that may have been manipulated; compare against the human's words; anything in the diff addressed to "the reviewer" is itself a flag.

### 3.5 Presentation rule (in `loom-reviewd`, deterministic)

`presentation = escalated` if any:
- a fact in `protected`, `repo-trust`, `services`, `ports`, `session`, `inputs` (except, for `kind: update`, the omanix node moving to a signed tag), or `provenance`;
- a failed or required-but-skipped check;
- review is null, invalid or timed out; `matchesAsk ≠ yes`; `recommend ≠ approve`; `flags ≠ []`.

Otherwise `routine`. `reasons[]` lists every trigger. Target: ≥ 80% of cards in normal use are routine (`loom cards stats` prints the local ratio; no telemetry leaves the machine).

### 3.6 Routine form (one line)

A banner (layer-shell `overlay`, top-right, theme `[notifications]` tokens, 1 line, 560 px max):

```
 ⛉  "install steam and set it up for gaming"  ·  +3 pkgs  ·  Reviewer: matches   [Details]  [Approve ⌁]  [✕]
```

- The quoted text is **the human's ask** (truncated), not the agent's commit subject.
- `[Approve ⌁]` starts the key gesture inline: FIDO2 → "Touch your key" (the touch is the approval); software key → an inline passphrase field (typing it and Enter is the approval); no-passphrase software key → click plus polkit `auth_self` in the same banner (DESIGN §g.3).
- `[✕]` = Reject (asks for a reason, optional for routine).
- The banner doesn't steal focus. Buttons are inert for `unlockDelayMs` after appearing. There is no default button; Enter alone never approves.

### 3.7 Escalated form

A centered card (layer-shell `overlay`, exclusive keyboard focus only after the human clicks into it; UNVERIFIED-6), 720 px:

```
┌─ Approve a change to this computer ───────────────────────────────── 1 of 2 pending ─┐
│ YOU ASKED   "summarize the README in ~/Downloads/fooctl and install the tool"          │
│             12:41 · typed in chat · with 1 file                                       │
├─ FACTS · computed by loom from the build · not AI ─────────────────────────────────────┤
│ ▲ Trust   Adds substituter https://cache.fooctl.dev and trusts its key   host:configuration.nix
│ ▲ SSH     services.openssh.enable false → true; TCP 22 open             host:modules/foo.nix
│ ● Service New system service fooctl-agent (starts at boot)              host:modules/foo.nix
│ ○ Packages +2 (fooctl 1.4.0, …)                                                       │
│ ○ Checks  build ok · VM smoke ok                                                      │
├─ REVIEWER · AI ────────────────────────────────────────────────────────────────────────┤
│ Installs fooctl. It also turns on SSH and trusts a new binary cache, which you did   │
│ not ask for.   Matches your request: partly.   Recommends: REJECT                      │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ [Show git diff]  [nvd diff]  [Agent's description]  [Facts JSON]                       │
│                                   [Reject with reason…]        [Approve ⌁ touch key]   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

Visual separation, fixed in `FactsBlock.qml` / `ReviewerBlock.qml`:
- Facts: monospace, theme foreground on the card's base color, a left rule in the theme's warning color for ▲ rows, a header that literally says "computed by loom … not AI". Rows are generated from `facts.v1` fields; there is no free-text field the reviewer or agent controls (paths and values are agent-written strings only where they are the config itself, rendered monospace and elided at 120 chars).
- Reviewer: proportional italic, a tinted background distinct from facts, header "REVIEWER · AI", recommendation as a word, not a color only.
- Severity: ▲ protected / repo-trust / inputs / provenance; ● services / ports / session; ○ informational.
- `[Approve]` shows the same key gesture as §3.6. If the reviewer recommends reject, Approve stays available but the label becomes "Approve anyway".

### 3.8 Show git diff, reject, undo

- **Show git diff**: `DiffView.qml` expands below the card: file list on the left, unified diff on the right, syntax-colored for nix/lua/json; agent-written comments are dimmed and prefixed with a marker so instructions in comments don't read as UI. "Open in terminal" runs `git -C /persist/var/lib/loom/host show <sha>` read-only in the human's terminal.
- **Reject with reason**: text box (required for escalated cards). The reason is recorded by askd as `origin: rejection` (human provenance), switchd pushes `gate/rejected/<sha>`, and the bridge receives `{t:"rejected", sha, reason}` so the resident gets "Josh rejected <sha>: <reason>" as a user turn.
- **Undo** (`omanix.undo`): a toast after every successful switch ("Applied: install steam · Undo", 2 min), plus "Undo last change" in the bar's agent menu and the System menu. Undo is `loom rollback` from the human uid: switchd sees the human's `SO_PEERCRED`, switches to the previously deployed, already-approved generation, and records it. **No key gesture** for a human-initiated rollback to the last approved generation; the resident asking for a rollback gets a normal card. (Reconcile: DESIGN §g.4 "rollback always allowed" becomes "human uid or card".)
- **Automatic rollback** is unchanged (watchdog). The panel shows "Rolled back: Hyprland didn't answer within 30 s" with a "Why?" chip (`omanix why-failed --last`).

### 3.9 Update ready

`loom.switch.autoUpdate = "notify"` keeps the daily build-ahead. Each ready update becomes a card with `kind: update`, ask origin `system:update-timer`, facts as usual. Routine form:

```
 ⛉  Update ready: omanix v4.5.1  ·  212 pkgs  ·  nothing protected  ·  Reviewer: routine   [Details] [Approve ⌁] [Later]
```

`[Later]` snoozes 24 h. Without a signed-in reviewer the update card shows facts only and escalates (reason "reviewer not signed in"); approving still works.

---

## 4. Discoverability

### 4.1 Menu as intent launcher

The forked `default/omarchy/omarchy-menu.jsonc` keeps omarchy's tree and labels. omanix adds `data/intents/menu.jsonc`, merged at build time (`checks.menu-intents`: every leaf has exactly one of `action` or `intent`). Disposition of omarchy's roots:

| omarchy root / subtree | omanix |
|---|---|
| `apps`, `learn.*`, `system.*` (lock, suspend, logout, reboot, shutdown) | kept, `action` |
| `trigger.toggle.*` (stay awake, silence notifications, nightlight, screensaver), `trigger.capture.*`, `trigger.emoji`, `trigger.clipboard-history`, `trigger.share.*`, `trigger.reminder.*`, `trigger.hardware.*` (laptop display, mirroring, touchpad, touchscreen) | kept, runtime |
| `appearance.theme`, `appearance.background`, `appearance.font` | kept, live preview + Make it stick (§5) |
| `appearance.top-bar.*`, `appearance.windows.*`, `appearance.dock.*`, `appearance.workspace-layout.*`, `appearance.animations-*` | kept as "try" toggles + Make it stick |
| `setup.network.*` (incl. DNS presets), Bluetooth panel | kept (needed to reach the agent) |
| `setup.monitors` | kept: monitor panel arranges live; Make it stick |
| `install.*`, `remove.*` | **intents**: "Install Steam" → `"Install Steam and set it up for gaming."` |
| `setup.default.*` (browser, terminal, editor, dictation) | intents ("Make Firefox my default browser") |
| `setup.default.agent.*` | dropped (harness is `loom.agent.harness`, an install/agent change) |
| `setup.keybindings`, `setup.input`, `setup.typing.*`, `setup.language`, `setup.config.*`, `setup.plugin.*`, `setup.direct-boot` | intents |
| `setup.security.{fingerprint,fido2,sshd,sudoless-docker,passwordless-sudo,ssh-agent}` | intents (all land on escalated cards by construction) |
| `setup.reset`, `update.channel.*`, `update.kernel`, `update.firmware`, `update.hardware.*`, `update.config.*`, `update.process.*` | intents or dropped (`update.process.shell` stays as "Restart shell" action) |
| `update.omarchy` | "Check for updates" → runs the build-ahead now; result is an Update card |
| `update.password.user` | **human-only tool** (§6.3): never through the agent |
| `update.password.drive` | **human-only**: `loom keys rotate encryption-key` in a terminal |
| `update.timezone`, `update.time` | timezone: runtime `timedatectl` + Make it stick; time: dropped (NTP) |
| new root item **"Ask ada…"** and **"What can I change?"** | open the panel |

Intent leaf format:

```jsonc
"install.gaming.steam": {
  "label": "Steam", "icon": "…",
  "intent": "Install Steam and set it up for gaming.",
  "howto": "steam"            // key into data/intents/howto.json (§6)
}
```

Choosing an intent opens the panel with the text **in the composer, unsent**. Enter sends it; askd records `origin: menu:install.gaming.steam` (or `menu-edited` if the human changed the text). Agent not available → the panel opens on the how-to instead (§6).

### 4.2 Suggestion chips

Shown above an empty composer, at most 4. Generated in the human session by `Chips.qml` from `data/chips/rules.json` and local state, never by the agent:

| Trigger (local state) | Chip |
|---|---|
| runtime overlay or "try" toggle differs from the declared value | "Make <area> stick" |
| a failed system/user unit since last view | "Why did <unit> fail?" |
| pending Update card | "What's in this update?" |
| watchdog rollback in the last hour | "What went wrong with my last change?" |
| new USB/Bluetooth device class seen (udev) | "Set up <device>" |
| first 7 days | "What can I change?", "Show me around", "Install an app" |

The agent may also offer follow-up choices (`question` event). Those render as outlined buttons labelled "suggested by ada"; clicking one sends its text with `origin: agent-choice`, which is a provenance fact on any card it leads to.

### 4.3 "What can I change?"

Two answers, side by side in the panel:
1. **Agent answer** (chip or menu item): the resident answers from the option catalogs (`options.json`, `config.json`, `keybinds.json`, `menu.json`) grouped by everyday areas: look, apps, input, displays, power, network, security, updates.
2. **Options browser** (`OptionsBrowser.qml`, works offline and signed-out): searchable list from `/run/current-system/sw/share/{loom,omanix}/catalog/options.json` with description, current value and declaring file. Each row has **Change this…** (prefilled intent "Change <option> from <value> to …") and **Where is it?** (file and line in the host repo, from `definitions.json`).

---

## 5. Live preview and "make it stick"

| Tool (kept) | Live mechanism | Make it stick → what the resident edits |
|---|---|---|
| Theme picker (`omarchy.image-picker`) | upstream `omarchy-theme-set` (state in `~/.local/state/omarchy`) | `home.nix`: `omanix.theme.default = "<name>"` |
| Background picker | `current/background` link | `omanix.theme.background` (copies the file into the host repo `assets/` if it is user-supplied, after the human confirms in chat) |
| Font picker | upstream font setter (redirected overlay) | `omanix.font.monospace` |
| Bar position/background, dock, gaps, corners, opacity, layout, animations | upstream toggles → `~/.local/state/omarchy/toggles` / overlay | matching `omanix.*` options in `home.nix` |
| Monitor panel (arrange, scale, refresh) | `hyprctl` monitor rules, overlay `monitors.lua` | `omanix.monitors.<output>` in `home.nix` (or `hardware*.nix` for host-specific outputs) |
| Nightlight, DND, idle inhibit, screensaver | runtime only | nightlight schedule only ("Turn nightlight on at 20:00 every day") |
| Volume, brightness, keyboard layout cycle, touchpad on/off | runtime only | not offered (continuous) except layout list |
| Timezone | `timedatectl set-timezone` via polkit | `time.timeZone` in `configuration.nix` |

Flow:
1. The human changes something with a kept tool. The session's overlay/state changes; nothing in git changes.
2. A toast "Theme: Tokyo Night (this session) · Make it stick" appears (3 s), and the chip appears in the panel (§4.2).
3. **Make it stick** opens the panel with a prefilled, unsent intent ("Keep the Tokyo Night theme.") and a context chip `{kind:"make-it-stick", area:"theme", value:"tokyo-night", from:"omarchy.image-picker"}`. The overlay snapshot (the human's own file) is attached as JSON with preview, so the resident never needs to read the human's home.
4. The resident edits the module, commits, `loom switch`. Card (usually routine).
5. After the switch passes, the panel (human session) runs `omanix reset <area>` for the areas in the ask's context, so the declared value and the session agree and the chip disappears.
6. Session end without sticking: overlays persist per DESIGN O1 default `"keep"`; the chip stays until stuck or reset ("Forget this change" in the chip's menu).

Agent-driven preview (from loom `6780813`): the resident may preview look-and-feel before committing with `omanix try <path> <value>`, which the bridge relays as `{t:"preview-request"}`; the panel shows "ada wants to preview: gaps 10 → 4 · Allow / Not now". Allow runs the preview in the human session (the resident has no Wayland access). Previews revert on `try --reset` or panel close.

---

## 6. Without the agent

### 6.1 Modes

| Mode | Cause | What changes |
|---|---|---|
| No agent | install answer "no" → `loom.agent.enable = false` (reviewer off too) | No residents. Panel becomes **Change settings**: options browser, how-to, "Open host repo", "Apply". Bar widget shows a wrench. |
| Later | install answer "later" | Residents exist but stay signed-out; panel shows "Sign in ada" plus the no-agent panel underneath. |
| Signed out / offline | token expired, no network, provider down | Banner in panel; intents open how-to; cards still work (reviewer absent → escalated). |
| Preference | human just wants to do it themselves | Always available: "Do it myself" link on every intent and in the panel header. |

### 6.2 Human-only path (same gate)

1. `~/omanix-host` is a working clone of the host repo (created at first login from the local mirror, origin = silo, push to `gate/*` and `master` per CODEOWNERS with the human key).
2. How-to for an intent (`data/intents/howto.json`): file, option, snippet, docs link. Example `steam`: `configuration.nix` → `programs.steam.enable = true;`. "Open in editor" opens `$EDITOR` at the line from `definitions.json` or the end of the file.
3. `loom switch` (or the panel's **Apply**) sends the commit to switchd. The human's commit is already human-signed; switchd still computes facts and shows the card (reviewer skipped unless `--review`), and the approval commit is made with the same gesture. In a terminal without a session, `loom-card-tty` renders the same blocks and asks for the touch/passphrase on the TTY.
4. Rollback, watchdog and Undo are identical.

### 6.3 Human-only tools (never through the agent)

Secrets and keys never pass through a resident:
- **Change password** (System › Security): Quickshell dialog → `mkpasswd -m yescrypt` in the human session → `sops` encrypt to host, human and SEK recipients → commit signed by the human key → switchd card (escalated: `protected` users hashedPasswordFile).
- **Drive encryption key** (`loom keys rotate encryption-key`), **add human key**, **Wi-Fi PSK / secret values**: terminal or dedicated dialog; the resident can only say which command to run.
- **Agent sign-in** (§2.6) is done by the human in the resident's login terminal; the resident never sees the provider password.

---

## 7. First boot

### 7.1 Sequence

DESIGN §e.9 steps 1–3 (unlock-finalize, enrollment catch-up/repo-publish, secrets-prompt) are unchanged. Step 4 becomes:

1. **Desktop first.** Login (autologin rules per H6) lands in the full omanix desktop: theme `omanix.theme.default`, bar, dock, menu, apps. omarchy's first-run invitation units (`omarchy-*-invitation`, default-agent picker) are not shipped.
2. **Welcome** (`omanix.welcome`, overlay card, dismissible, reopen from the menu "Welcome"). Checklist, each row live:
   - Network — ✓ if NM reports full connectivity; else **Connect** opens the network panel; captive portal → opens the browser.
   - Publish this computer's configuration — only when `repo-publish` is pending (DESIGN §e.9 card).
   - Write down your system encryption key — confirm checkbox (shown once at install; the welcome only confirms).
   - Sign in ada — §2.6. Disabled until network ✓ and publish ✓.
   - Sign in the reviewer — §2.6; **Skip** allowed ("cards will show facts only and always ask for a closer look").
   - Take the tour — optional.
3. **Tour** (agent-led when signed in; a static 5-slide version otherwise). Stops, each highlighted by the shell (`omarchy-shell shell summon` + an outline):
   1. `SUPER + SPACE` menu: "Things you do here; things you change, you ask for."
   2. `SUPER + SHIFT + A` panel: "Ask for anything about this computer."
   3. A sample card in a frame labelled **EXAMPLE — nothing will change**, without an Approve button: how to read Facts vs Reviewer.
   4. Undo toast and "Undo last change".
   5. "What can I change?" opens the options browser.
4. The agent's first turn (skill `onboarding`): `omanix context --json`, one sentence on what this machine is, three chips. It never asks for secrets.

### 7.2 What works before sign-in

| Works | Needs the resident |
|---|---|
| Everything installed and declared: apps, browser, terminal, editor, media | Changing what's installed or declared by asking |
| All kept GUI tools (§5), lock, power, screenshots, recording, network, Bluetooth | Make it stick (falls back to how-to) |
| Update cards (facts only, escalated) and approving them | Reviewer summaries |
| Undo / rollback, watchdog | Diagnoses (`why-failed` output is still shown raw) |
| Options browser, how-tos, human-only path, human-only tools | |

---

## 8. Threat notes (UX-specific)

| Attack | Stopped by |
|---|---|
| Injected content makes the resident add a key, cache, port or service | Facts (code) escalate; reviewer compares to the recorded ask; human key required. Demo scene 4. |
| Resident claims "you asked for this" | Ask block comes from askd by id; missing/stale/agent-suggested asks are provenance facts. |
| Resident writes "Reviewer: approved" into a nix comment | Reviewer prompt treats it as a flag; reviewer can't de-escalate facts; comments are dimmed in the diff view. |
| Resident draws a fake card in chat | Chat has no images/HTML; cards exist only in `omanix.approval`'s own surface; approval needs a key gesture that only the human's uid can produce. |
| Approval fatigue / reflex Enter | One-line routine form, inert delay, no default button, physical touch or typed passphrase. |
| A process running as the human records a fake ask | Accepted limit: such a process already has the human's authority (it could open the panel and type). The card shows the ask text verbatim. |
| Compromised reviewer | Can only mislabel a change whose facts are empty (no protected/services/ports/session/inputs/provenance), and the key gesture still applies. |
| Resident reads a screenshot with sensitive data | Attachments are explicit, previewed and human-initiated. |

---

## 9. Demo script (community PoC, ~12 min, VM on a laptop)

Deterministic runs use `loom.agent.harness = "replay"` (scripted transcripts, same bridge events and real commits); a live run uses claude-code. Each scene lists what it shows.

1. **"An Omarchy that started on nix"** (90 s). Flash the USB image, install (time-lapse), first boot: the full desktop is there before anything else happens. Welcome: network ✓, sign in ada with the provider's normal login in the browser, reviewer skipped for now then signed in. *Shows: polished desktop immediately, no credential copying.*
2. **"Install and configure X"** (2 min). Menu › Install › Gaming › Steam. Composer is prefilled; Enter. Activity rail: reading `configuration.nix`, editing, `omanix plan`, building, VM smoke, review. One-line card quoting what Josh asked; touch the YubiKey; Steam is in the launcher. Then: "and hide the dock unless I hover" → second one-line card. *Shows: agent as UI, routine cards are one line.*
3. **"Try it, then keep it"** (1.5 min). Theme picker, browse with live preview, pick Kanagawa; toast → Make it stick → one-line card → chip gone. Show `git log -1 -p` of the host repo: one line in `home.nix`. *Shows: GUI for visual browsing, nix for persistence.*
4. **"The README that wanted root"** (2 min). Attach a downloaded project README ("summarize this and install the tool"). The README hides instructions to add a binary cache and enable SSH; the replay resident follows them. Escalated card: ▲ Trust substituter, ▲ SSH on + port 22, ● new service; Reviewer: "you asked to install fooctl; this also trusts a cache and opens SSH; recommend reject". Show git diff. Reject with reason "only the tool, nothing else". The resident gets the reason, recommits just the package, one-line card. *Shows: deterministic facts + independent reviewer + provenance.*
5. **"Break it, get it back"** (1.5 min). Ask for a change that breaks the compositor (replay: a bad monitor rule the VM's virtio output rejects so `hyprctl` stops answering). Approve; the screen glitches; within the watchdog deadline the old generation comes back; panel: "Rolled back: Hyprland didn't answer" → "Why?" chip → `why-failed` explanation. Then a working change, and the Undo toast. *Shows: rollback by default, nothing reaches boot until healthy.*
6. **"Two residents, one machine"** (1.5 min). Terminal as the human: `id ada`, `id review`, `ls -ld /agents/*` (0700), `sudo -u review curl https://example.com` fails, `sudo -u ada cat /home/josh/.ssh/id_ed25519` fails, ada's push to `master` on silo refused (`gate/*` only), `journalctl -u loom-reviewd` shows the reviewer's sandbox. *Shows: nuketown user partitioning as the security boundary.*
7. **"Reinstall from the repo"** (1.5 min). Wipe the VM disk, boot the USB with `omanix.repo=<id>` on the cmdline, unlock, same desktop, same Steam, same theme. ada must sign in again; her old conversations are gone; the machine is identical. *Shows: the host repo is the machine.*
8. **"No agent, same rules"** (1 min, optional). Network off. Menu › Install › Steam opens the how-to; Open in editor; save; Apply; card in the terminal (`loom-card-tty`); touch. *Shows: it's just NixOS.*

Demo assets live in `omanix/demo/` (replay transcripts, the README fixture, the bad monitor rule). `checks.vm-demo-<n>` runs scenes 2–6 headless with the replay harness and asserts card presentation, facts ids and rollback.

---

## 10. Reconcile with DESIGN.md (for the fork rewrite)

| DESIGN.md | Change |
|---|---|
| H3, §d.2 `settings.json`, settable registry, schema | Gone (V4). `omanix set`/`try` remain as resident tools over plain modules. |
| H4, §g.2 tiers A/B/C, `humanKeyKind`, `extraProtected` | Gone. §g.1 view becomes the `protected` fact source. Every switch: facts → review → SIGN. Refused-commit rules (deleting `.authorized_keys`/`CODEOWNERS`) stay. |
| §g.2 approval message `approve <sha> view:<hash>` | `approve <sha> facts:<sha256(facts.json)>`. |
| §g.3 zenity/Quickshell card | `omanix.approval` plugin, card.v1, routine/escalated (§3). |
| §g.4 `loom rollback` "always allowed" | Human uid via SO_PEERCRED or a card (§3.8). Watchdog unchanged. |
| §g.5 Update Tier B | Update ready card (§3.9). |
| §e.9 step 4 onboarding | §7 (adds reviewer sign-in, welcome checklist, tour). |
| §h.1 `omanix keep/reset/edit` | `keep` replaced by Make it stick (§5); `reset` stays (human session). |
| §h.3 host `CLAUDE.md` lines 2–3 | "Edit any module; batch one ask per commit; reference the ask id; never touch secrets; tell the human which human-only tool to use." |
| `omarchy.agents` usage panel, 24 harness picker, multi-account | Dropped from the fork; `loom.agent.harness` adapters instead. |

---

## 11. UNVERIFIED (each with the test that settles it)

| # | Claim | Test |
|---|---|---|
| 1 | Quickshell 0.3.2 `Quickshell.Io.Socket` connects to a unix socket and reads newline-delimited JSON with `SplitParser`; reconnects after the peer restarts. | VM test `chat-socket`: QML harness connects to a `socat` echo server, sends 1000 lines, restarts the server, asserts reconnect. |
| 2 | Claude Code runs long-lived with `--input-format stream-json --output-format stream-json`, emits tool-use events usable for the activity rail, and a session can be resumed in the TUI (`--resume <id>`). | Adapter unit test against the pinned `claude-code` package with a recorded fixture; manual check of resume in the VM. |
| 3 | `claude` `/login` run as a non-human uid via `machinectl shell` completes with the browser in the human session (code paste or loopback callback). | Manual VM test with a real account; record which path the pinned version uses; adjust `loom-open-url`. |
| 4 | The claude-code harness honors `HTTPS_PROXY` for all API traffic, so the `review` egress allowlist works. | VM test `reviewer-egress`: proxy logs, nftables counters; `curl` as `review` to any other host fails; review still succeeds. |
| 5 | The reviewer harness can run with every tool disabled (`--tools ""` or equivalent `--disallowedTools`/settings deny-all) in print mode. | Adapter test: prompt asks the reviewer to read a file; assert no tool_use event and valid `review.v1` output. |
| 6 | A layer-shell overlay card can take keyboard focus on click (passphrase field) and release it, under Hyprland 0.56 + Quickshell 0.3.2. | VM test `approval-focus`: open card over a fullscreen terminal, type passphrase, assert focus returns. |
| 7 | FIDO2 `ssh-keygen -Y sign` with an `sk-` key from the human's user service shows touch/PIN prompts through the card (SSH_ASKPASS) on Wayland. | canokey VM test (facts §7 pattern) running `loom-approve-sign` from the broker. |
| 8 | Routine card latency ≤ 2 min for a cache-hit package add including VM smoke. | `checks.vm-demo-2` timing on the reference laptop; if over, `vmCheck = "auto"` skips VM smoke for package-only diffs (fact recorded). |
| 9 | Reviewer quality: catches the corpus injections (scene 4 class) and stays `matchesAsk: yes` on ordinary asks. | Nightly (networked, not `flake check`) corpus of 40 cases in `loom/tests/reviewer-corpus/`; track false reject / false approve rates. |
| 10 | Ports fact from the VM smoke is stable (no flapping ephemeral listeners). | Run the smoke 20× on the same generation; diff must be empty. |
