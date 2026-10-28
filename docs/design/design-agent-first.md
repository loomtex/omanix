# omanix architecture: the agent-first design

Angle: **optimize for AI-agent modifiability and introspection.** Where this angle conflicts with other goals, this document picks the agent-friendly option and records the trade-off (§12).

Inputs: spec rev 16 (authoritative), `design/facts.md`, and the `understand/*.md` surveys. Scope follows the spec:
- USB installer image only, whole-disk install.
- The installer never copies or embeds credentials.
- No in-place conversion, kexec, Windows boot-chain, or transfer of an existing AI-assistant login.

Authors: Ada, with Joshua Perry.

---

## 0. Ten rules every other section follows

1. **One option tree, NixOS level only.** All user-facing knobs are `loom.*` or `omanix.*` NixOS options. home-manager is an implementation detail: omanix modules write `home-manager.users.<user>` internally and expose no HM options. The escape hatch is `omanix.home.extraModules`. An agent therefore has to search one namespace, not two.
2. **File path == option path.** `modules/desktop/bindings.nix` declares `options.omanix.desktop.bindings` and nothing outside that prefix. `checks.layout` enforces this using `options.*.declarationPositions`.
3. **Defaults are `lib.mkDefault`.** Every value an omanix or loom module sets on a nixpkgs or HM option has priority ≥ 1000, so a plain assignment in a host always wins and nobody needs `mkForce`.
   - `checks.priorities` enforces it.
   - Exceptions live in one file, `lib/force-allowlist.nix`, each with a reason string.
4. **One place to change a machine:** `settings.json` in the host repo. It is pure data, validated by a JSON Schema generated from the option types.
   - `host.nix` is the escape hatch for anything that needs Nix expressions.
   - Nothing else in the host repo is hand-edited.
5. **Every list lives in one attrset.** Keybinds, themes, harnesses, webapps, TUIs, persisted paths, secrets, commands and health checks are each a typed registry. Menus, docs, catalogs, impermanence entries and skill links are rendered from those registries.
6. **Every fact is introspectable without grepping the store.** `omanix <thing> --json` reads a catalog generated from the same evaluation as the running system. Catalogs cannot go stale relative to the running generation.
7. **Agents choose; scripts act.** Destructive or privileged steps are deterministic, reviewed programs with plan/confirm phases and machine-readable output. An agent never improvises `parted`, `cryptsetup`, `nixos-rebuild` or `git push` against the host repo.
8. **The safety gate lives in a root daemon, not in the agent's sudo.** Agents request a switch from `loom-switchd`. The daemon fetches the commit, evaluates it, runs the protected-option diff, verifies signatures, applies with a watchdog, and pushes. The agent never holds root for a switch.
9. **`nix flake check` is the only gate,** covering eval, lints, catalogs and VM tests. `omanix check --fast` is the eval-only subset for the inner loop.
10. **Every command takes `--json`, needs no TTY, and has documented exit codes:**
    - 0 ok
    - 1 failed
    - 2 usage
    - 3 needs human approval
    - 4 rolled back
    - 5 offline/retry later

---

## 1. Layering

```
┌──────────────────────────────────────────────────────────────────────┐
│ host repo  silo:omanix/<id>.git   settings.json · host.nix · hw      │  per machine
├──────────────────────────────────────────────────────────────────────┤
│ omanix     Quattro flavor: omarchy-src pkg, Hyprland-Lua, Quickshell │  desktop
│            shell, themes, apps, agents registry, omanix CLI, skills  │
├──────────────────────────────────────────────────────────────────────┤
│ loom       DE-agnostic platform + agent base: installer image,       │  platform
│            disko/LUKS/unlock, impermanence, sops, host repo + silo   │
│            enrollment, policy diff, switchd + watchdog, firstboot,   │
│            catalog/schema lib, agent wiring                          │
├──────────────────────────────────────────────────────────────────────┤
│ nuketown   (optional) agents as unix users, approval broker, portal  │  additive
├──────────────────────────────────────────────────────────────────────┤
│ nixpkgs (nixos-unstable, single pin) · disko · impermanence · sops-nix│
│ · home-manager · hyprland flake v0.56.2 · quickshell flake · omarchy │
└──────────────────────────────────────────────────────────────────────┘
```

- loom never imports omanix.
- omanix imports loom.
- nuketown never imports loom.
- signi (mynix) imports only nuketown, so it is untouched.

**Channel (hard call): one nixpkgs, `nixos-unstable`, for the whole omanix stack.**
- Hyprland ≥ 0.56, quickshell ≥ 0.3.2 and hyprland-guiutils are unstable-era (facts §3).
- Running a stable base with an unstable desktop overlay gives two Qt/Mesa sets. That is an UNVERIFIED Mesa-mismatch risk, and it gives agents two `pkgs` to reason about.
- The Hyprland and quickshell flakes are consumed as `inputs.*.inputs.nixpkgs.follows = "nixpkgs"`, so there is exactly one Qt and one Mesa.
- loom and nuketown keep their own default pin, bumped to 26.05. They are consumed with `follows`. Their CI evaluates against both 26.05 and unstable (§9).

---

## 2. Repo layouts

### 2.1 omanix (`~/projects/omanix`, origin fetch = silo, pushurl = silo + github)

```
omanix/
├── flake.nix                      # inputs/outputs only, ~120 lines
├── flake.lock
├── CLAUDE.md                      # one line: @AGENTS.md
├── AGENTS.md                      # router: task index, rules, where things live, test etiquette
├── agents/skills/                 # REPO-DEV skills (procedure), "read before ..."
│   ├── add-option.md  add-module.md  add-package.md  add-theme.md
│   ├── add-keybind.md add-harness.md add-webapp.md   add-persist.md
│   ├── add-secret.md  vm-test.md     visual-verification.md
│   └── upstream-sync.md           # bump omarchy pin, re-run substitution audit
├── docs/                          # reference prose; docs/options.md is GENERATED (not committed)
├── plans/                         # design docs with revision headers (adversarial review log)
├── lib/
│   ├── default.nix                # omanix.lib = loom.lib // { mkHost, renderTheme, ... }
│   ├── mk-host.nix
│   ├── theme.nix                  # colors.toml → tokens → .tpl renderer (pure, no IFD)
│   ├── lua.nix                    # nix value → Lua literal; bindings → o.bind(...) lines
│   └── force-allowlist.nix
├── modules/                       # NixOS modules; path == option path under omanix.*
│   ├── default.nix                # imports all; declares omanix.enable
│   ├── upstream.nix               # omanix.upstream.*
│   ├── desktop/
│   │   ├── hyprland.nix           # omanix.desktop.hyprland.*
│   │   ├── bindings.nix           # omanix.desktop.bindings (registry)
│   │   ├── input.nix  looknfeel.nix  monitors.nix  toggles.nix  rules.nix
│   │   ├── shell.nix              # omanix.desktop.shell.* (quickshell omarchy-shell)
│   │   ├── session.nix            # uwsm, autologin/greeter
│   │   ├── idle.nix  nightlight.nix  plymouth.nix  greeter.nix
│   ├── theme.nix                  # omanix.theme.*   (selection/policy)
│   ├── themes.nix                 # omanix.themes.<name> (registry; data in ../themes/)
│   ├── apps/
│   │   ├── terminal.nix browser.nix editor.nix files.nix media.nix
│   │   ├── webapps.nix            # omanix.apps.webapps.<Name>
│   │   └── tuis.nix               # omanix.apps.tuis.<Name>
│   ├── agents/
│   │   ├── harnesses.nix          # omanix.agents.harnesses.<name> (registry)
│   │   ├── default.nix            # omanix.agents.default
│   │   └── crash-capture.nix      # omanix.agents.crashCapture.*
│   ├── services/                  # network.nix bluetooth.nix audio.nix power.nix printing.nix
│   │                              # tailscale.nix sleep-hooks.nix fonts.nix input-method.nix
│   ├── hardware/                  # omanix.hardware.* (speakerTuning, profiles from facts.json)
│   ├── cli.nix                    # omanix.cli.commands.<group>.<name> registry
│   └── catalog.nix                # emits share/omanix/catalog/*.json (uses loom.lib.catalog)
├── themes/<slug>/                 # imported VERBATIM from omarchy + theme.nix metadata
├── pkgs/
│   ├── default.nix                # overlay; one dir per package
│   ├── omarchy-src/               # patched upstream tree (OMARCHY_PATH target)
│   ├── omanix-cli/                # Go or Python; reads catalogs, talks to loom-switchd
│   ├── omanix-skills/             # end-user skills derivation (partly generated)
│   ├── titlebars/ owe/ ttfx/ omacalc/ aether/ omasnap/ omacut/ omawrite/
│   ├── hype/ signed/ monologue/ gliff/ asdcontrol/ tobi-try/
│   └── plymouth-theme/ sddm-theme/
├── templates/host/                # → loom template + omanix defaults (see §4)
├── tests/                         # nixosTest files, one per check (see §9)
│   ├── lib.nix                    # shared VM fixtures (virtio-gpu, user autologin, swtpm)
│   └── desktop-boots.nix theme-switch.nix agents-harness.nix ...
└── scripts/
    ├── setup-remotes.sh           # origin fetch=silo, pushurl silo+github
    └── verify-release.sh          # git verify-tag against release allowed_signers
```

### 2.2 loom (`~/projects/loom`, refactor approved; `nixosModules.default` stays as the bundle)

```
loom/
├── flake.nix  flake.lock  CLAUDE.md(@AGENTS.md)  AGENTS.md  agents/skills/
├── lib/
│   ├── default.nix                # mkHost, mkInstaller, catalog, schema, policy helpers
│   ├── mk-host.nix
│   ├── mk-installer.nix           # image.repart raw GPT, offline/net variants
│   ├── catalog.nix                # options → JSON (nixosOptionsDoc + definitionsWithLocations)
│   ├── json-schema.nix            # option types → JSON Schema (settings + sidecar)
│   ├── settings.nix               # settings.json → module, namespace/whitelist checks
│   └── checks.nix                 # layout / priorities / documented / schema checks (reused by omanix)
├── modules/                       # path == option path under loom.*
│   ├── default.nix
│   ├── host.nix                   # loom.host.*  (id, name, repo, keys)
│   ├── silo.nix                   # loom.silo.*
│   ├── user.nix                   # loom.user.*
│   ├── locale.nix                 # loom.locale.*
│   ├── disk/
│   │   ├── layout.nix             # loom.disk.* → disko config
│   │   └── unlock.nix             # loom.disk.unlock.* → crypttab opts, initrd
│   ├── boot.nix                   # loom.boot.*
│   ├── impermanence.nix           # loom.impermanence.* (aggregation API)
│   ├── secrets.nix                # loom.secrets.* (sops wiring, items registry, firstboot prompts)
│   ├── policy.nix                 # loom.policy.* (protected set → system.build.loomPolicy)
│   ├── switch.nix                 # loom.switch.* (switchd, watchdog checks registry)
│   ├── agent.nix                  # loom.agent.* (resident via nuketown | user | none)
│   ├── firstboot.nix              # loom.firstboot.* (steps registry)
│   ├── hardware.nix               # loom.hardware.* (facts.json → typed facts, firmware filter)
│   └── installer/                 # modules used only by the installer image
│       ├── image.nix  tui.nix  payload.nix
├── pkgs/
│   ├── loom-install/              # installer TUI + non-interactive engine (Go, bubbletea)
│   ├── loom-switchd/              # root daemon + `loom-switch` client
│   ├── loom-policy/               # eval+diff helper used by switchd and `omanix plan`
│   ├── loom-enroll/               # silo enrollment, key rotation, authorize helper
│   ├── loom-flash/                # flash-usb implementation (guards), sidecar writer
│   └── loom-hwfacts/              # PCI/USB/TPM/FIDO2/VM detection → facts.json
├── templates/host/                # generic host flake (DE-agnostic)
├── tests/                         # fde-*.nix impermanence.nix installer-e2e.nix policy.nix ...
│   └── silo-standin.nix           # uses seed's nixosModules.silo-lite
└── scripts/flash-usb.sh           # thin signed wrapper → loom-flash (spec path)
```

The following are deleted from loom:
- `installer.nix` (dead)
- the inline Python auth server and the QR credential handoff (out of scope: no login transfer)
- `prompt.nix` hardcoded Hyprland snippets (moved into omanix skills)
- the unused disko input wiring

### 2.3 nuketown deltas (additive; every default reproduces today's behaviour)

```
module.nix
  + nuketown.persistRoot            (str, "/persist"); impermanence gated on `options ? environment.persistence`
  + nuketown.sops.ageKey.{encryptedFile,keyFile}   (defaults = today's hardcoded paths)
  + nuketown.promptFragments        (attrsOf lines, mergeable; rendered after extraPrompt)
  + nuketown.switch.command         (nullOr str; when set, nuketown-switch execs it — loom sets `loom-switch`)
  ~ agents.<n>.extraHomeConfig      attrs → deferredModule (attrs still valid → back-compat)
  ~ secret paths via config.sops.secrets.<n>.path instead of literal /run/secrets/<n>
  ~ claudeCode.package default: pkgs.unstable.claude-code if present else pkgs.claude-code
  ~ adaSection → agents.<n>.claudeCode.workingStyle (default reproduces ada text when name == "ada")
  ! sudoex-run: re-contacts broker as root with one-time token (closes NOPASSWD bypass)
  ! broker: SO_PEERCRED check (python rewrite of handler), mock-mode path unified
approval-daemon.nix (HM)
  + approvalDaemon.prompter (pkg; default zenity wrapper), .display (nullOr str, ":0"),
    .target ("default.target"), .notify (nullOr str)
checks.nix
  + checks.signi-compat  (fixture mirroring mynix signi options; must eval unchanged)
  + checks.eval-26.05 / eval-unstable
```

### 2.4 seed/silo deltas (`instances/silo/*`)

| id | change | why omanix needs it |
|---|---|---|
| S1 | **Owner handoff:** a push by the current `.owner_key` that changes in-tree `.silo/owner` on the default branch rewrites the bare-repo `.owner_key` in post-receive. | The enrollment key creates the repo, so it becomes the immutable owner. The enrollment push hands ownership to the human key. Without S1 the one-time key stays root-equivalent forever. |
| S2 | **ACL-path protection:** pre-receive rejects default-branch updates that change `.authorized_keys` or `.silo/**` unless the pusher is the owner. | The agent and host keys can push config but cannot grant themselves keys or remove the human. This is the server-side half of "the agent's key must not grant itself power". |
| S3 | Path hardening (survey C2): no `.`-prefixed components, no repo inside a repo, depth/length caps. | Nested `omanix/<id>.git` stays safe. |
| S4 | **`nixosModules.silo-lite`:** silo-shell, siloauth NSS, hooks and git-http read, as a standalone NixOS module (no Seed controller, no k8s). | The local silo stand-in for VM tests. It must never contact silo.loom.farm. |
| S5 | Webhook `full_name` relative path (C8). | Cosmetic; prevents name collisions. |

HTTP push (C7) and private repos (C1) are not needed. Pushes use SSH only, and reads are public by decision.

### 2.5 Remotes (decision 5)

`scripts/setup-remotes.sh` in each project repo runs:
```
git remote set-url origin ssh://git@silo.loom.farm/<name>.git
git remote set-url --add --push origin ssh://git@silo.loom.farm/<name>.git
git remote set-url --add --push origin git@github.com:<org>/<name>.git
```
Host repos are silo-only.

---

## 3. Flakes and lib

### 3.1 loom flake

```nix
inputs = {
  nixpkgs.url        = "github:NixOS/nixpkgs/nixos-26.05";   # consumers override with follows
  disko.url          = "github:nix-community/disko/v1.13.0";
  impermanence.url   = "github:nix-community/impermanence";
  sops-nix.url       = "github:Mic92/sops-nix";
  home-manager.url   = "github:nix-community/home-manager";
  nuketown.url       = "git+ssh://git@silo.loom.farm/nuketown.git";  # optional at runtime
  seed.url           = "git+ssh://git@silo.loom.farm/seed.git";      # tests only (silo-lite)
  # every input: inputs.nixpkgs.follows = "nixpkgs"
};
outputs = {
  nixosModules = { default; host; disk; impermanence; secrets; policy; switch; agent; firstboot; installer; };
  lib = { mkHost; mkInstaller; catalog; jsonSchema; settingsModule; checks; };
  packages.<sys> = { loom-install; loom-switchd; loom-policy; loom-enroll; loom-flash; loom-hwfacts;
                     installer-net; installer-offline-base; };   # generic images (no omanix)
  templates.host;
  checks.<sys> = { eval-*, layout, priorities, documented, schema, fde-*, impermanence, policy,
                   switch-watchdog, installer-e2e, reinstall-existing-id };
  apps.<sys> = { flash-usb; configure; };   # configure = non-interactive engine used by the skill
};
```

### 3.2 omanix flake

```nix
inputs = {
  nixpkgs.url    = "github:NixOS/nixpkgs/nixos-unstable";
  loom           = { url = "git+ssh://git@silo.loom.farm/loom.git"; inputs.nixpkgs.follows = "nixpkgs"; };
  hyprland       = { url = "github:hyprwm/Hyprland/v0.56.2"; inputs.nixpkgs.follows = "nixpkgs"; };
  quickshell     = { url = "github:quickshell-mirror/quickshell/2b4501a2826..."; inputs.nixpkgs.follows = "nixpkgs"; };
  hyprland-guiutils = { url = "github:hyprwm/hyprland-guiutils/v0.2.2"; inputs.nixpkgs.follows = "nixpkgs"; };
  omarchy        = { url = "github:omacom/omarchy/v4.5.0-rc2"; flake = false; };   # MIT, pinned by tag
  # disko/impermanence/sops/HM/nuketown come through loom (follows), never re-declared
};
outputs = {
  nixosModules.default;               # = loom.nixosModules.default + ./modules
  overlays.default;                   # pkgs/*
  packages.<sys> = { omarchy-src; omanix-cli; omanix-skills; <each new pkg>;
                     installer-offline; installer-net; base-cache; docs-options; catalog };
  lib = loom.lib // { mkHost = ...; };  # mkHost pre-applies omanix module + pinned nixpkgs
  templates.host;                     # loom template + omanix settings defaults
  nixosConfigurations = { base-x86_64; vm-test; };  # base = cache seed for "popular combination"
  checks.<sys>;                       # §9
  devShells.default;                  # nixfmt statix deadnix shellcheck nvd sops age nix-tree
};
```

### 3.3 `mkHost`

```nix
# loom/lib/mk-host.nix
mkHost = {
  src,                          # the host flake's self (path)
  system ? "x86_64-linux",
  profile ? [ ],                # flavor modules, omanix passes its nixosModules.default
  nixpkgs ? inputs.nixpkgs,
}:
let
  settings = lib.importJSON (src + "/settings.json");     # validated by loom.lib.settingsModule
  facts    = lib.importJSON (src + "/facts.json");
in nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { loomSrc = src; };
  modules = [
    loom.nixosModules.default
    (loom.lib.settingsModule settings)   # whitelisted namespaces, priority 100 (beats mkDefault)
    { loom.hardware.facts = facts; }
    (src + "/hardware.nix")              # nixos-generate-config output, fileSystems stripped (disko owns)
    (src + "/host.nix")                  # escape hatch
  ] ++ profile;
};
# returns { nixosConfigurations.host = cfg; nixosConfigurations.${hostname} = cfg; checks; formatter; }
```

- `omanix.lib.mkHost = args: loom.lib.mkHost (args // { profile = [ omanix.nixosModules.default ]; nixpkgs = omanix.inputs.nixpkgs; })`.
- `loom.lib.settingsModule`:
  - It rejects top-level keys outside `{ loom, omanix, nuketown }` with an assertion that names the key.
  - It is a module of plain values, not functions.
  - It records each value's origin as `host:settings.json`, so `omanix where` can name the file even though the values came from JSON.
- Other lib functions:
  - `catalog { options; config; }` gives an attrset of JSON derivations.
  - `jsonSchema { options; prefix; whitelist ? null; }` gives a JSON Schema derivation.
  - `checks.{layout,priorities,documented}` take an eval and a source root and return check derivations.
  - `renderTheme` is omanix-only.

---

## 4. Host flake on silo and the sidecar

### 4.1 Host repo layout (`silo.loom.farm:omanix/<id>.git`, branch `master`)

```
flake.nix          # generated once; edited only by `omanix update`
flake.lock
settings.json      # ★ the one place (pure data; schema: share/omanix/schema/settings.schema.json)
host.nix           # escape hatch: arbitrary nix, reviewed like code (default: `{ ... }: { }`)
hardware.nix       # nixos-generate-config --no-filesystems output
facts.json         # loom-hwfacts output: cpu/gpu/tpm2/fido2/isVM/pci ids/firmware set
secrets/host.yaml  # sops; recipients from .sops.yaml
.sops.yaml         # creation rules: host age recipient + human recipients
.authorized_keys   # rendered from loom.host.keys (checks.authorized-keys-in-sync)
.silo/owner        # human ssh pubkey (S1); protected
CLAUDE.md          # 25-line static router (below)
```

`flake.nix` (complete; agents never need more):
```nix
{
  inputs.omanix.url = "git+https://silo.loom.farm/omanix.git?ref=refs/tags/v0.1.0";
  outputs = { self, omanix, ... }: omanix.lib.mkHost { src = self; };
}
```

`settings.json` (as written by the installer, abbreviated):
```json
{
  "loom": {
    "host":  { "id": "3f9c...e1", "name": "kestrel",
               "keys": { "human": ["sk-ssh-ed25519@openssh.com AAAA... josh@yubikey"],
                         "host":  "ssh-ed25519 AAAA... root@kestrel",
                         "agent": "ssh-ed25519 AAAA... ada@kestrel" } },
    "user":  { "name": "josh", "fullName": "Joshua Perry", "email": "josh@6bit.com",
               "password": "sops" },
    "locale":{ "timeZone": "America/Denver", "keyMap": "us", "language": "en_US.UTF-8" },
    "disk":  { "device": "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7...",
               "unlock": { "method": "tpm2", "tpm2Pin": true, "recoveryKey": true },
               "swap": { "size": "32G", "hibernate": true } },
    "secrets": { "hostKey": "ssh-ed25519", "humanRecipients": ["age1yubikey1q..."] },
    "agent": { "mode": "resident", "name": "ada", "harness": "claude-code" }
  },
  "omanix": {
    "theme": { "default": "tokyo-night" },
    "apps":  { "terminal": "foot", "browser": "chromium" },
    "desktop": { "monitors": [ { "output": "eDP-1", "scale": 2 } ] }
  }
}
```

Host `CLAUDE.md` (static; everything dynamic comes from commands):
```
This repo IS the machine <name>. Commit = config. Running system = last commit switched by loom-switchd.
1. Run `omanix context --json` first. It lists the catalogs, the current generation, and dirty/drift state.
2. Change settings with `omanix set <option.path> <json-value>` (edits settings.json, schema-checked).
   Use host.nix only when `omanix set` says the option needs a Nix expression.
3. `omanix check` → `omanix plan --json` → `omanix apply`. Never run nixos-rebuild, git push, or edit ~/.config.
4. Protected changes (users, sudo, ssh, boot, nix trust, firewall, keys) exit 3: ask the human to approve.
5. Never improvise disk, LUKS, or key operations. Use the loom skills.
Skills: omanix, omanix-apply, omanix-persist, omanix-secrets, diagnose-build, diagnose-unit, diagnose-crash.
```

### 4.2 Sidecar schema (`OMANIX-CFG` vfat partition, `/sidecar/`)

The sidecar is validated against `share/loom/schema/sidecar.schema.json` (generated; versioned `loom.sidecar/v1`). It never contains Nix. The `settings` object accepts only the **sidecar whitelist**, which is pure configuration and cannot change the closure:

```
/sidecar/
  sidecar.json
  host.bundle            # git bundle of host repo at commit X (offline source of truth)
  enroll_ed25519         # one-time per-repo enrollment key (private), 0600 semantics
  extra-cache/           # optional file:// cache for closure beyond the image's base cache
```

```json
{
  "schema": "loom.sidecar/v1",
  "host": {
    "id": "3f9c0d...e1",                                  // 32 lowercase hex
    "repo": "omanix/3f9c0d...e1.git",
    "commit": "a1b2c3...",                                // what to install
    "bundle": "host.bundle",
    "machineId": "9e1f...42"                              // minted by configurator; id = HMAC(machineId, APP_UUID)
  },
  "silo": { "host": "silo.loom.farm",
            "hostKey": "ssh-ed25519 AAAAC3...Sw+s" },     // pinned; test images point at the stand-in
  "enrollment": { "keyFile": "enroll_ed25519",
                  "publicKey": "ssh-ed25519 AAAA... enroll-3f9c" },
  "settings": {                                           // whitelist only:
    "loom.host.name": "kestrel",
    "loom.user.name": "josh", "loom.user.fullName": "...", "loom.user.email": "...",
    "loom.user.passwordHashSops": "ENC[...]",             // sops, recipients = enrollment key (ssh-to-age) + human
    "loom.locale.timeZone": "...", "loom.locale.keyMap": "us",
    "loom.host.keys.human": ["sk-ssh-ed25519@openssh.com ..."],
    "omanix.theme.default": "tokyo-night"
  },
  "answers": { "disk": null, "unlock": null }             // null = ask in TUI; set only by unattended tests
}
```

Key decisions:
- **One ephemeral credential.** The enrollment key is both the silo pusher and, through `ssh-to-age`, the temporary sops recipient for sidecar secrets.
  - At install, the installer re-encrypts to the host key and the human recipients (`sops updatekeys`), drops the enrollment recipient, and removes the key from `.authorized_keys`.
  - S1 hands silo ownership to the human key in the same push.
  - Nothing off the machine keeps write access (spec Bootstrap 4).
- **Repo id = `HMAC-SHA256(machineId, OMANIX_APP_UUID)[:16]`**, the same function as `systemd-id128 machine-id --app-specific`. The configurator mints a random machine-id for the target and the installer writes it to `/persist/etc/machine-id`.
  - The raw machine-id is never published.
  - After a reinstall the machine-id is new but the repo id is kept (decision 2), so the id is **a literal option (`loom.host.id`)**, not derived at eval time.
- The sidecar's `settings` is flattened (dotted keys), so the whitelist check is a set-membership test. The installer converts it into nested `settings.json` and commits it as `install: apply sidecar`.

---

## 5. Option tree (important options; full tree = generated `docs/options.md`)

Types are abbreviated. Every option has `description`; non-trivial ones also have `example` (`checks.documented`).

### 5.1 `loom.*`

| option | type | default | notes |
|---|---|---|---|
| `loom.host.id` | strMatching `^[0-9a-f]{32}$` | — (required) | silo path component |
| `loom.host.name` | hostname str | — | → `networking.hostName` |
| `loom.host.repo.namespace` | str | `"loom"` (omanix sets `"omanix"`) | |
| `loom.host.repo.path` | str | `"${namespace}/${id}.git"` | |
| `loom.host.repo.fetchUrl` | str | `git+https://${silo.host}/${path}` | public read |
| `loom.host.repo.pushUrl` | str | `ssh://git@${silo.host}/${path}` | host key only |
| `loom.host.repo.mirror` | path | `/persist/loom/host.git` | root-owned mirror used by switchd |
| `loom.host.keys.{human,host,agent}` | listOf str / str / nullOr str | — | rendered to `.authorized_keys`; **protected** |
| `loom.silo.host` / `.hostKey` | str | `silo.loom.farm` / pinned ed25519 | tests override to the stand-in |
| `loom.user.{name,fullName,email}` | str | — | single human user, uid 1000 |
| `loom.user.password` | enum `sops` `firstboot` | `firstboot` | `sops` = hash in secrets/host.yaml |
| `loom.locale.{timeZone,keyMap,language,region}` | str/enum | UTC, us, en_US.UTF-8, null | `region="cn"` prepends mirrors only |
| `loom.disk.device` | str (`/dev/disk/by-id/*`) | — | |
| `loom.disk.layout` | enum `luks-btrfs-tmpfsroot` | same | one layout; other layouts are a later decision |
| `loom.disk.espSize` | str | `"1G"` | |
| `loom.disk.swap.{size,hibernate}` | nullOr str, bool | null, false | swapfile in `@swap` |
| `loom.disk.unlock.method` | enum `tpm2` `fido2` `passphrase` | `passphrase` | installer writes user's choice |
| `loom.disk.unlock.tpm2Pin` | bool | true when tpm2 | |
| `loom.disk.unlock.tpm2Pcrs` | listOf int | `[7]` (`[7 11]` with UKI/SB) | |
| `loom.disk.unlock.recoveryKey` | bool | true | shown once at install, never stored |
| `loom.disk.unlock.passphraseFallback` | bool | true | keep keyslot 0 passphrase |
| `loom.boot.loader` | enum `systemd-boot` `limine` `lanzaboote` | `systemd-boot` | lanzaboote ⇒ Secure Boot |
| `loom.impermanence.enable` | bool | true | tmpfs `/` |
| `loom.impermanence.root` | str | `/persist` | → `nuketown.persistRoot` |
| `loom.impermanence.home` | enum `persist` `ephemeral` | `persist` | whole `/home` subvol vs per-path lists |
| `loom.impermanence.system.{directories,files}` | listOf (str or submodule) | baseline (§7.1) | features append |
| `loom.impermanence.user.{directories,files}` | same | [] | used when `home = ephemeral` |
| `loom.secrets.hostKey` | enum `ssh-ed25519` `tpm` | `ssh-ed25519` | `tpm` gated on `checks.sops-tpm` |
| `loom.secrets.humanRecipients` | listOf str (age) | [] | e.g. age-plugin-yubikey |
| `loom.secrets.items.<name>` | submodule {owner, mode, neededForUsers, firstBoot ? null} | {} | registry → sops.secrets + catalog |
| `loom.policy.enable` | bool | true | |
| `loom.policy.protected` | listOf str (option path globs) | spec list (§7.5) | **protected itself** |
| `loom.policy.protectedPaths` | listOf str (repo paths) | `.authorized_keys .silo/** .sops.yaml flake.lock#original` | |
| `loom.policy.humanSigners` | listOf str | `= loom.host.keys.human` | allowed_signers for approval |
| `loom.policy.trustedInputs.<name>.signers` | listOf str | omanix/loom release keys | input rev must be reachable from a signed tag |
| `loom.switch.watchdog.timeout` | int s | 180 | |
| `loom.switch.watchdog.checks.<name>` | submodule {description, command, as = "root"/"user", required} | network, silo, session | registry |
| `loom.switch.autoUpgrade` | enum `off` `propose` `apply` | `propose` | desktops never auto-apply |
| `loom.agent.mode` | enum `resident` `user` `none` | `resident` | resident ⇒ nuketown agent |
| `loom.agent.{name,uid,harness}` | str/int/str | `ada`, 1100, `claude-code` | |
| `loom.agent.promptFragments` | attrsOf lines | {} | → nuketown.promptFragments / harness CLAUDE.md |
| `loom.firstboot.steps.<name>` | submodule {order, description, command, interactive, doneWhen} | password, network, agent-login, authorize | registry |
| `loom.hardware.facts` | attrs (typed submodule) | from facts.json | `isVM`, `tpm2`, `fido2`, `gpu`, `cpu` |
| `loom.hardware.firmware` | enum `all` `filtered` | `filtered` | filtered = blobs matching facts.pciIds |

### 5.2 `omanix.*`

| option | type | default | notes |
|---|---|---|---|
| `omanix.enable` | bool | true when module imported | |
| `omanix.upstream.src` | path | `inputs.omarchy` | |
| `omanix.upstream.package` | package | `pkgs.omarchy-src` | OMARCHY_PATH target |
| `omanix.desktop.hyprland.package` | package | hyprland flake 0.56.2 | titlebars built against this |
| `omanix.desktop.hyprland.extraLua` | lines | "" | appended to generated user stub |
| `omanix.desktop.bindings.<name>` | submodule {keys, description, action = {launch/webapp/tui/menu/panel/ipc/lua}, locked, repeating, enable} | omarchy defaults | assertion: unique `keys`, names both locations |
| `omanix.desktop.defaultBindings` / `preinstalledBindings` | bool | true | omarchy globals |
| `omanix.desktop.monitors` | listOf submodule {output, mode, position, scale, vrr} | [] (auto) | |
| `omanix.desktop.input.{kbLayout,kbOptions,touchpad.*,repeatRate}` | … | omarchy values | kbLayout defaults from loom.locale.keyMap |
| `omanix.desktop.looknfeel.{gaps,border,rounding,blur,animations}` | … | omarchy values | |
| `omanix.desktop.toggles.<name>` | bool | per omarchy skel | pre-seeds state files; runtime toggling still works |
| `omanix.desktop.shell.settings` | JSON attrs | {} | merged over upstream `shell.json` |
| `omanix.desktop.shell.plugins.<id>` | submodule {src, enable} | {} | |
| `omanix.desktop.session.autologin` | bool | `true` (FDE is always on, so LUKS is the auth boundary) | |
| `omanix.desktop.session.greeter` | enum `none` `sddm` | `none` | |
| `omanix.desktop.idle.{screensaverSec,lockSec}` | int | 150, 300 | |
| `omanix.theme.default` | enum (registry names) | `tokyo-night` | |
| `omanix.theme.policy` | enum `mutable` `pinned` | `mutable` | pinned = runtime set refuses |
| `omanix.theme.available` | listOf name | all | closure size knob |
| `omanix.theme.intros` | bool | false | drop video intros by default (size) |
| `omanix.theme.reloadHooks.<app>` | submodule {phase, command} | contributed by app modules | |
| `omanix.themes.<name>` | submodule {src, colors (typed hex), overrides, trusted} | upstream themes | |
| `omanix.apps.{terminal,browser,editor,files}` | enum | foot, chromium, nvim, nautilus | |
| `omanix.apps.webapps.<Name>` | submodule {url, icon, bind, mimeTypes, focus} | omarchy 11 + bound | |
| `omanix.apps.tuis.<Name>` | submodule {command, style, icon, bind} | omarchy set | |
| `omanix.apps.extraPackages` | listOf package | [] | closure-affecting ⇒ may miss cache |
| `omanix.agents.default` | nullOr enum (harness names) | `claude-code` | |
| `omanix.agents.harnesses.<name>` | submodule {enable, package, aliases, command, autoApprove.args, prompt.{mode,flag}, skillDirs, persist, theme.template} | registry | |
| `omanix.agents.crashCapture.enable` | bool | true | coredump/unit-failure/build-failure → diagnose skills |
| `omanix.services.*` | per feature | NM, bluetooth, pipewire, upower, ppd, printing, … | |
| `omanix.fonts.{monospace,cjkVariant}` | str/enum | JetBrainsMono NF, null | |
| `omanix.hardware.speakerTuning` | nullOr enum | from facts | |
| `omanix.home.extraModules` | listOf deferredModule | [] | HM escape hatch |
| `omanix.cli.commands.<group>.<name>` | submodule {summary, args, examples, hidden, privileged, package} | built-ins | router + `commands --json` generated |

---

## 6. USB installer, end to end

### 6.1 Image build (loom `mkInstaller`, omanix instantiates it)

`image.repart` raw GPT, built with `nix build .#installer-offline` / `.#installer-net`:

| # | label | format | contents |
|---|---|---|---|
| 1 | ESP | vfat 512M | UKI of the installer system (systemd-boot); BIOS not supported |
| 2 | OMANIX-STORE | erofs (zstd) | installer closure + `/cache` (`file://` binary cache: `.nar.zst` + narinfo of `base-cache`) |
| 3 | OMANIX-CFG | vfat 64M (grown by flash-usb to fill the stick) | `/sidecar/` (empty in the image), `README.txt` |

- The installer system is built from `minimal.nix`, `perlless.nix` and `all-hardware.nix` (full firmware: it must boot anything), with `documentation.enable = false`. It runs `loom-install` on tty1.
- `base-cache` holds the toplevel closure of `nixosConfigurations.base-x86_64`, which is the "popular combination": omanix defaults, all themes minus intros, and the default apps. It also holds `nix flake archive` of omanix, loom and their inputs, so a host flake **evaluates offline**.
- The `installer-net` variant has the same partitions with an empty `/cache`, about 200 MB. It substitutes from the omanix cache and cache.nixos.org.
- Size guards:
  - `checks.closure-budget` fails if the `base-x86_64` closure exceeds `budget.json` (initial target 4.5 GB uncompressed; the bar to beat is omarchy's 6 GB ISO).
  - `system.forbiddenDependenciesRegexes` bans duplicate Mesa/LLVM/Python majors and `-doc` outputs.
- Release: images are built from signed tags. The `.img.zst` is published with a detached `ssh-keygen -Y sign` signature.

### 6.2 Configure skill (on the user's existing machine, conversation → host repo + sidecar)

`omanix/.claude/skills/configure/SKILL.md` drives `nix run omanix#configure -- <subcommand> --json`. The agent converses; the engine acts:

1. `configure verify-release` checks the omanix tag signature against the baked release `allowed_signers`. Abort on failure.
2. `configure schema` prints the sidecar whitelist plus the closure-affecting options with their descriptions. The agent asks only those questions: username, hostname, timezone, keymap, theme, human SSH key(s), optional human age recipient, extra apps.
3. `configure mint --out ./kestrel` does the following:
   - generates the machine-id, derives the repo id, and generates the enrollment key;
   - instantiates the host template;
   - writes closure-affecting choices into `settings.json` and pure settings into `sidecar.json`;
   - sops-encrypts the password hash, prompted locally with `mkpasswd` hidden input, to the enrollment key and human recipients. The user may choose `firstboot` instead.
4. `configure check ./kestrel` evaluates the host (offline-capable). It reports `cacheMiss: [drv...]`, the closure paths not in the base cache.
5. `configure push ./kestrel` pushes over SSH with the enrollment key to `omanix/<id>.git`. Silo auto-creates the repo with owner = enrollment key.
6. If `cacheMiss` is non-empty and local Nix is available: `configure stage-cache ./kestrel` builds the misses into `./kestrel/sidecar/extra-cache`. Otherwise the installer fetches them online.
7. `configure sidecar ./kestrel` assembles `/sidecar/` (`sidecar.json`, `host.bundle`, `enroll_ed25519`, `extra-cache/`).
8. Hand-off to the build-installer skill (6.3).

On Windows the engine runs in WSL2. The sidecar dir is copied onto the OMANIX-CFG volume with Explorer, which works because it is vfat. No raw-device writes are needed from Windows if the user flashes the image with any standard flasher.

### 6.3 flash-usb (`scripts/flash-usb.sh` → `loom-flash`; two-phase, guards in code)

```
loom-flash plan  --image installer-offline.img.zst [--sidecar ./kestrel/sidecar] --json
  → lists candidate devices: only TRAN=usb or removable=1, excluding any device that
    · has a mounted partition (lsblk MOUNTPOINTS) or holders (/sys/block/X/holders: LUKS/LVM/md)
    · backs /, /boot, /nix, swap, or the running image
    · is smaller than image+64M
  → prints model, vendor, serial, size, current partitions, and a CONFIRM TOKEN
    = first 8 hex of sha256(devpath|serial|size|image-hash)
loom-flash write --device /dev/sdX --confirm <token> [--sidecar dir]
  → recomputes the token (device unchanged? same stick?) else exit 2
  → verifies the image signature, dd with conv=fsync, re-reads the GPT, grows partition 3 to the end,
    fatresize, copies the sidecar, verifies sha256 of every written file, syncs, prints JSON summary
loom-flash sidecar --device /dev/sdX --confirm <token> --sidecar dir   # rewrite sidecar only
```

The agent can run `plan` freely. `write` needs the token, which comes from a `plan` run against the same physical device. In TTY mode a human-typed confirmation is also required; in non-TTY mode the token is mandatory. The script checks its own release signature first (spec trust anchor).

### 6.4 Installer flow (`loom-install` on tty1; same engine runs unattended for tests)

Inputs, in priority order:
1. kernel cmdline `loom.host=<id>` (`loom.silo=<host>` optional; test images only: `loom.answers=unattended`)
2. `/sidecar/sidecar.json` on OMANIX-CFG
3. interactive prompt "Reinstall an existing host? Enter host id or leave empty"

No other config files are read (decision 2).

| step | what (all logged to `/run/loom-install/log.jsonl`, viewable with `Alt+F2`) |
|---|---|
| 0 Preflight | UEFI check; `loom-hwfacts` → facts.json (PCI/USB ids, CPU/GPU, `isVM`, TPM2 via `/sys/class/tpm/tpm0` + `systemd-cryptenroll --tpm2-device=list`, FIDO2 via `fido2-token -L`, battery, RAM). Network optional. |
| 1 Source | **Fresh**: read the sidecar, validate against the schema, `git clone host.bundle`, check out `host.commit`, verify `host.id == HMAC(machineId)`. **Reinstall**: id from cmdline/prompt → `git clone fetchUrl` (online), or a bundle if present; there is no enrollment key. **Fork** (`--fork`, no human key survived): mint a new id from a new machine-id; the repo will be created by this host. |
| 2 Disk | List non-removable disks (exclude the boot stick by matching OMANIX-STORE's parent). Show model/size/partitions/OS signatures (`wipefs -n`). Whole-disk only. Require typing the disk's model fragment. Written to `loom.disk.device` as a `/dev/disk/by-id` path. |
| 3 Unlock | Capability matrix (6.5). Present only available methods, with pros/cons text. The choice is written to `loom.disk.unlock.*`. Always ask for a passphrase (fallback keyslot) unless the user explicitly disables it with a TPM2+PIN or FIDO2 choice. |
| 4 Partition/FDE | Generate disko config by **evaluating the host flake** (`config.system.build.diskoScript` from `loom.disk.*`), `destroy,format,mount`. LUKS2 + btrfs subvols (§7.1); `@agents-blank` created via disko `postCreateHook`. Then `systemd-cryptenroll` per method: `--tpm2-device=auto --tpm2-pcrs=7 [--tpm2-with-pin=yes]` or `--fido2-device=auto`; `--recovery-key` shown once as text + QR, and the user must retype the last group. |
| 5 Hardware | `nixos-generate-config --no-filesystems --show-hardware-config` → `hardware.nix`; facts.json → repo. |
| 6 Keys | On the target, under `/mnt/persist`: `ssh-keygen` host ed25519 key; machine-id (fresh: from sidecar; reinstall/fork: new). The agent key is generated and sops-encrypted to the host key into `secrets/host.yaml` (`agent_ssh_key`); its private half never exists outside the host. With `secrets.hostKey = tpm`, `age-plugin-tpm --generate` writes `/mnt/persist/var/lib/loom/age-tpm.txt`. |
| 7 Commit | Apply sidecar settings + install answers to `settings.json`; render `.authorized_keys` = human + host + agent (enrollment key removed); `.silo/owner` = first human key; `.sops.yaml` recipients = host + human; `sops updatekeys` (drops the enrollment recipient); `omanix keys sync`; commit `install: <host> on <disk model>`, author = loom installer, Co-Authored-By the human. |
| 8 Build/Install | `nixos-install --flake /mnt/persist/loom/host#host --no-root-passwd --option substituters "file:///run/loom/cache file:///run/loom/sidecar/extra-cache" [+ network caches if online]`. Offline with a miss ⇒ explain which derivations are missing (`--json` list), offer network. |
| 9 Enroll | If online: push with the enrollment key (it is still the owner): this commit adds the host/agent/human keys, removes the enrollment key, and sets `.silo/owner` (S1 hands ownership to the human). Verify via `git ls-remote` with the host key. If offline: copy the enrollment key to `/mnt/persist/var/lib/loom/enroll/` (inside LUKS) and enable `loom-enroll.service`, which retries on `network-online` and shreds the key after success. **Reinstall**: no enrollment key. `loom-enroll` shows the new host/agent pubkeys and two options: (a) plug the human's FIDO2 SSH key into this machine and push now (`ssh -i sk-key`, touch); (b) run `loom-enroll authorize <id> <hostkey> <agentkey>` on any machine holding a human key. Until then the host runs read-only against silo (`omanix status` shows `enrollment: pending`). |
| 10 Finish | Overwrite the sidecar files with random data, then delete them (vfat on flash: not a guarantee, so the TUI says "reformat or destroy this stick's config partition"). `efibootmgr` sets the installed entry first. Show a summary (unlock method, recovery-key confirmation, host id, enrollment state), then reboot. |

The **unattended test mode** is compiled into `installer-test` images only (`loom.installer.testing = true`). It accepts `loom.answers=unattended loom.disk=/dev/vda loom.unlock=passphrase loom.passphrase=<test>`. Release images build without the code path (eval assertion), so a cmdline passphrase can never be accepted in production.

### 6.5 Unlock capability matrix (TUI text, verbatim source in `loom/modules/disk/unlock-text.nix`, also in the catalog)

| method | shown when | pros | cons |
|---|---|---|---|
| **TPM2 + PIN** (recommended when TPM2 present) | TPM2 2.0 detected | Short PIN instead of a long passphrase; the disk only unlocks on this board; the TPM rate-limits PIN guessing. | If firmware or Secure Boot state changes (PCR 7), you need the recovery key. A motherboard swap needs the recovery key. Without Secure Boot, PCR 7 binding is weak against an attacker with physical access. |
| **TPM2 only** (no PIN) | TPM2 detected | Boots unattended, like a phone. Good for a desk machine you trust. | Anyone who steals the whole laptop gets a running login screen, so the disk is only as safe as the lock screen and the TPM. Not recommended for laptops. |
| **FIDO2 security key** | `fido2-token -L` lists a device with hmac-secret | Unlock requires the physical key plus a touch (and its PIN if set); works across motherboards. | Lose the key ⇒ recovery key or passphrase needed. The key must be present at every boot. |
| **Passphrase** | always | Works everywhere, no hardware dependency, easiest to reason about. | Only as strong as the passphrase; typed at every boot; keyboard layout at the prompt is US unless the layout is Latin-typing. |
| **Recovery key** (always added, not a choice) | always | Last-resort unlock if hardware changes or keys are lost. | It must be written down offline. omanix never stores it anywhere. |

The available rows are rendered from `facts.json`. In the catalog, the table is `share/loom/catalog/unlock.json`, so the configure skill can explain it ahead of time.

### 6.6 Payload: offline vs online

| path | cache order | when |
|---|---|---|
| offline image | `file:///run/loom/cache` (erofs) → `file:///run/loom/sidecar/extra-cache` | default; no network needed when `cacheMiss = []` |
| online/net image | sidecar extra-cache → omanix cache (https) → cache.nixos.org | small download, slow install |
| either, cache miss | build locally in installer (tmpfs on target `/mnt/nix/var/tmp`) | small derivations: etc, HM generation, hardware-filtered firmware |

The installed system gets `@nix` with `compress=zstd` and `nix.settings.auto-optimise-store = true`.

---

## 7. Runtime

### 7.1 Disk + impermanence layout

```
GPT: ESP 1G (vfat, /boot) | LUKS2 "cryptroot" (rest)
  btrfs (compress=zstd, noatime)
    @nix         → /nix
    @persist     → /persist   (neededForBoot)
    @home        → /home      (loom.impermanence.home = "persist"; omitted for "ephemeral")
    @agents      → /agents    (nuketown rollback ← @agents-blank each boot)
    @agents-blank
    @swap        → /swap (swapfile; hibernate ⇒ resume_offset in boot.kernelParams, computed in installer, stored in hardware.nix)
/      tmpfs size=2G mode=755   (no rollback script needed)
/tmp   tmpfs size=50%           nix-daemon TMPDIR=/var/cache/nix (persisted)
```

The baseline `loom.impermanence.system` list (from mynix) contains:
- `/var/log`, `/var/lib/nixos`, `/var/lib/systemd/coredump`, `/var/cache/nix`, `/root`, `/var/lib/loom`
- `/etc/machine-id`, the ssh host keys, `/var/lib/systemd/timers`

Feature modules append their own paths:
- network: `/etc/NetworkManager/system-connections`, `/var/lib/NetworkManager`
- bluetooth: `/var/lib/bluetooth`
- fprint: `/var/lib/fprint`
- `/var/lib/upower`, `/var/lib/cups`, `/var/lib/systemd/backlight`, `/var/lib/alsa`
- tailscale: `/var/lib/tailscale`
- containers
- lanzaboote: `/var/lib/sbctl`
- TPM age identity

When `home = "ephemeral"`, omanix contributes these user paths: `.local/state/omarchy`, `.config/omarchy`, the browser profile, fcitx5, herdr, zoxide, bash history, keyrings, `.ssh`, `Documents Downloads Pictures Videos Music Projects`, and each harness's `persist`.

**Catalog:** `omanix persist --json` lists every persisted path with the option that contributed it. `omanix persist audit` lists files written since boot on tmpfs `/` (and on `$HOME` in ephemeral mode) that are not covered. Each finding names the option to add the path to, for example `omanix.services.bluetooth.persist`.

### 7.2 Mutable vs declarative state

| class | lives in | changed by | survives reboot | catalog |
|---|---|---|---|---|
| declarative config | host repo → `/run/current-system`, HM symlinks | `omanix set` + `apply` | yes (generation) | options, definitions |
| runtime choices (current theme, background, toggles, workspace layouts) | `~/.local/state/omarchy/**` (OMARCHY layout kept) | `omanix theme set`, shell UI, toggles | yes (persisted) | `omanix status` shows drift vs declared default |
| user data / app state | `/home`, persisted dirs | apps | yes | persist |
| secrets | sops in repo → `/run/secrets` | `omanix secret set` (encrypts, commits) | ciphertext yes | `secrets --json` (names, owners, recipients, never values) |
| agent logins (harness credentials) | the agent's own persisted dirs, created by logging in on this machine | user at first boot | yes | harness persist entries |
| everything else under `/` | tmpfs | — | **no** | `persist audit` |

`~/.config/*` files generated by HM are read-only store links. omarchy's user-override layer, where a stub requires defaults first and then the user files, is kept. In omanix, the "user files" are generated from `omanix.desktop.*` plus `extraLua`. No mutable override file is read by default. `omanix.desktop.hyprland.devOverride = true` adds a `require` of `~/.config/hypr/local.lua` when the file exists, for live experiments; `omanix status` reports that file as drift.

### 7.3 omarchy upstream consumption

- `pkgs.omarchy-src`: the pinned `inputs.omarchy` tree, with these changes:
  - `patchShebangs`
  - `substituteInPlace` of `/usr/share/omarchy` → `$out`
  - the titlebars `.so` path set to the `mkHyprlandPlugin` output built against the same Hyprland
  - `/usr/lib/omarchy/*` remapped
  - `/usr/bin/<tool>` → bare names
  - `default/bash/env-bootstrap` patched so it never resets `OMARCHY_PATH`
  - pacman/yay scripts replaced by `omanix` equivalents or removed. The mapping lives in `pkgs/omarchy-src/script-map.nix`, a single attrset with disposition `keep|patch|replace:<cmd>|drop`. `checks.script-map-complete` asserts every `bin/*` has a disposition.
  - `checks.no-usr-paths` greps `$out` for `/usr/(share|lib|bin)/` and fails on any hit.
- `OMARCHY_PATH` is set in the uwsm env, the systemd user env and `environment.sessionVariables`.
- Quickshell runs `qs -n -p $OMARCHY_PATH/shell` as a user unit, with `KillMode=mixed` on the Hyprland unit.

### 7.4 Theme switching

The model is the themes survey §6, adopted with these specifics:
- **Build time.** Each `omanix.themes.<name>` is rendered by `lib/theme.nix` (pure `replaceStrings` over tokens from `fromTOML colors.toml`; upstream `.tpl` files are imported verbatim) into a derivation with omarchy's `current/theme` layout. All themes in `omanix.theme.available` are linked under `/etc/profiles/per-user/<u>/share/omanix/themes/<name>`.
- **Runtime.** `~/.local/state/omarchy/current/theme` is a symlink **through the profile path**, which makes it GC-safe and lets a rebuild update content in place.
  - `omanix theme set <name>` swaps it atomically (`ln -sfn` + `mv -T`) and runs the `omanix.theme.reloadHooks` registry: visible phase first, background second.
  - `--persist` additionally runs `omanix set omanix.theme.default <name>` and `apply`.
- **Reconcile.** An HM activation step (`after linkGeneration`) resets the link when it is missing or dangling, or when `policy = pinned`.
- **Boot visuals.** Plymouth and the greeter are derivations of `omanix.theme.default`. They change on apply only, and `omanix theme set` prints that note in its JSON (`bootVisualsPending: true`).
- **Hyprland reload.** `misc.disable_autoreload = true`, plus one `hyprctl reload` after HM linkGeneration. This avoids half-linked trees (gaps §11).

### 7.5 Change pipeline: update / switch / watchdog / policy diff

**loom-switchd** is a root daemon with a socket at `/run/loom/switchd.sock`. Group `loom-switch` may connect; this means the human user and the resident agent. Peer identity comes from `SO_PEERCRED`.

```
request {commit, from: <git dir or "silo">, mode: test|apply|boot, dryRun}
  1 fetch    git fetch <from> <commit> into /persist/loom/host.git (root-owned mirror)
  2 verify   commit signed? signer ∈ loom.policy.{humanSigners,agentSigners} of the RUNNING system
             (allowed_signers file comes from /run/current-system, never from the commit)
  3 eval     nix build <mirror>?rev=<commit>#nixosConfigurations.host.config.system.build.{toplevel,loomPolicy}
             (runs as an unprivileged build user via nix-daemon; eval errors returned verbatim as JSON)
  4 policy   diff loomPolicy(new) vs /run/current-system/loom-policy.json, plus protectedPaths in the tree diff.
             loomPolicy = JSON of evaluated protected option values:
               users.users.*.{extraGroups,hashedPasswordFile,openssh.authorizedKeys,isNormalUser,uid}
               security.{sudo,sudo-rs,doas,polkit.extraConfig,pam.services.*.text?,wrappers}
               nix.settings.{trusted-users,allowed-users,substituters,trusted-public-keys,trusted-substituters}
               services.openssh.{enable,settings,ports}, networking.firewall.*, boot.{loader,initrd.luks,kernelParams}
               loom.{host.keys,policy,silo,secrets.humanRecipients}, nuketown.agents.*.{sudo,devices}
             plus: .authorized_keys, .silo/**, .sops.yaml, flake.lock `original` URLs,
                   and trusted-input revs not reachable from a signed tag
     → changed && HEAD not human-signed ⇒ exit 3 NEEDS_APPROVAL {diff, requestId}
  5 apply    switch-to-configuration test  (as a transient unit: systemd-run --unit=loom-switch-<n>,
             so a compositor restart that kills the agent's terminal cannot kill the switch)
  6 watchdog run loom.switch.watchdog.checks within timeout (default 180 s):
               network  : nm-online -q -t 30 (if it was online before)
               silo     : git ls-remote fetchUrl (if it was reachable before)
               session  : for the logged-in user: uwsm/Hyprland unit active, `hyprctl version` answers,
                          omarchy-shell unit active (omanix contributes this check)
               agent    : resident agent's user manager running (loom.agent)
               custom   : any loom.switch.watchdog.checks.<name>
             pass ⇒ nix-env -p /nix/var/nix/profiles/system --set; switch-to-configuration boot
             fail/timeout ⇒ switch-to-configuration test of the previous generation; exit 4 ROLLED_BACK {failedChecks, logs}
  7 publish  git push pushUrl <commit>:master with the host key (retry via loom-silo-sync.service when offline)
             write /var/lib/loom/last-switch.json (catalog of the result)
```

- **Approval gesture (one).** On exit 3, the human-side approval UI shows the policy diff in plain words, for example "adds user X to wheel" or "changes substituters". This is the Quickshell `omanix.approval` plugin, or nuketown's prompter as a fallback.
  - On approve, it creates an empty **signed commit** on top of the agent's commit (`git commit --allow-empty -S -m "approve <sha> policy:<diffhash>"`) with the human's SSH key (YubiKey touch). It then re-requests the switch with that commit.
  - HEAD is now human-signed and covers the identical tree, which satisfies the spec's "commit signed by the human key".
- **Update.** `omanix update` runs `nix flake update omanix` in the working copy, then `verify-release`: the new rev must be reachable from a tag signed by `loom.policy.trustedInputs.omanix.signers`. It then commits (agent-signed) and requests apply. Input URL changes are protected; rev bumps to signed tags are not.
- **Auto upgrade** (`loom.switch.autoUpgrade = "propose"`). A daily timer builds the update in the mirror, runs the policy diff, and sends a notification "Update ready: N changes, approval needed: no". It never applies on desktops.
- **nuketown integration.** `nuketown.switch.command = "loom-switch"`, so an agent's habitual `nuketown-switch` goes through the same gate. The sudo approval broker is no longer involved in switches, only in ad-hoc `sudo`.

---

## 8. Agent surfaces

### 8.1 Command surface (`omanix`, generated router from `omanix.cli.commands`)

| command | output | notes |
|---|---|---|
| `omanix context [--json]` | one-screen summary: host id, generation, commit, dirty, drift (theme/toggles/devOverride), enrollment, last switch result, catalogs path, skill list | **first command of every session** (in every CLAUDE.md) |
| `omanix options [query] [--json]` | name, type, default, example, description, declaring file | `share/omanix/catalog/options.json` (nixosOptionsDoc over `loom.*` + `omanix.*`) |
| `omanix get <path> [--json]` | effective value of the running system | `catalog/config.json` (dump of `config.{loom,omanix}`) — instant, offline; `--commit <sha>` evaluates instead |
| `omanix where <path>` | every definition with file:line, priority, and **which file to edit** (`host:settings.json` vs `host:host.nix` vs "default in omanix:modules/…, override in settings.json") | `definitionsWithLocations`, store prefixes mapped back to `input:relpath` |
| `omanix set <path> <json>` / `unset <path>` | edits settings.json; validates against the schema before writing; `--commit -m` | refuses paths that need nix (functions/packages) and says "use host.nix: <snippet>" |
| `omanix schema [--sidecar]` | JSON Schema | generated from option types |
| `omanix check [--fast]` | eval + fast checks of the working copy | `--fast` = eval + schema + assertions, ~seconds |
| `omanix plan [--json]` | build result, `nvd diff`, services to restart (`dry-activate`), **policy diff + needsApproval**, cache misses, closure delta | read-only, no root |
| `omanix apply [--test]` | asks switchd; streams JSON events; exit codes per §0 | |
| `omanix rollback [--to gen]` | switchd rollback + `git revert` commit | |
| `omanix status [--json]` | generations, failed units, `hyprctl configerrors`, persist gaps, secrets decryptable, enrollment | |
| `omanix doctor [--json]` | status + remediation, each naming an option path or skill | never prompts |
| `omanix keybinds / themes / harnesses / webapps / tuis / persist / secrets / commands [--json]` | registry catalogs | |
| `omanix theme set <n> [--persist]`, `omanix secret set <name> [--from-stdin]` | runtime/secret helpers | secret set encrypts locally with sops, never echoes |
| `omanix why-failed [--last]` | for a failed build: `nix log` of the failing drv + the derivation's origin option; for a failed watchdog: the check output + journal excerpt | feeds the diagnose-* skills |

Two contract tests cover the router: `checks.cli-contract` runs every command with `--help --json` and `--json` in a VM fixture, validates the output against a per-command JSON Schema, and checks that no command reads a TTY when `--json` is given.

### 8.2 Catalogs (`/run/current-system/sw/share/{loom,omanix}/catalog/`)

- `options.json`
- `config.json`
- `definitions.json`
- `commands.json`
- `keybinds.json`
- `themes.json`
- `harnesses.json`
- `webapps.json`
- `tuis.json`
- `persist.json`
- `secrets.json` (names only)
- `services.json` (units added by loom/omanix with owning option)
- `policy.json` (protected values; also `/run/current-system/loom-policy.json`)
- `watchdog.json`
- `unlock.json`
- `schema/settings.schema.json`
- `schema/sidecar.schema.json`
- `index.json` (lists all of the above with sha256)

They are built as derivations from the same evaluation as `system.build.toplevel`, so they are never stale. `docs/options.md` in the repo is generated from `options.json` and is not committed.

### 8.3 CLAUDE.md layers

1. **omanix / loom / nuketown repos:** `CLAUDE.md` = `@AGENTS.md`. AGENTS.md is a router of 120 lines or fewer. It contains:
   - the task index into `agents/skills/*.md`
   - the ten rules (§0)
   - "where things live" (path == option path)
   - test etiquette, carried over from omarchy: log to a file, never rerun to see output, name the regression, no tests for declarative changes
   - the remotes setup.
2. **Host repo:** the static 25-line router in §4.1.
3. **The agent's global prompt on the machine:** nuketown generates `~/.claude/CLAUDE.md` from identity, and loom contributes `loom.agent.promptFragments.loom`: the switch/approval model and the exit codes. omanix contributes `omanix.agents` fragments:
   - where the working copy lives (`~/projects/host`, auto-cloned from fetchUrl by nuketown daemon `repos.host`)
   - "run `omanix context` first"
   - a **generated** top-level option index: one line per `omanix.<group>`, taken from option descriptions so it cannot drift.
   In `loom.agent.mode = "user"`, the same fragments are written to the human user's harness config dirs from the harness registry's `skillDirs`/prompt locations.

### 8.4 Skills (shipped as `pkgs.omanix-skills`, linked into every enabled harness's `skillDirs` by HM)

| skill | purpose | generated parts |
|---|---|---|
| `omanix` | customize this machine: where to change what, examples per area | option index table, keybind table, theme list |
| `omanix-apply` | the safe-change loop (8.5), exit-code handling, approval etiquette | exit-code table from `omanix.cli` |
| `omanix-persist` | add a persisted path: audit, pick the owning option, apply, reboot test | |
| `omanix-secrets` | add/rotate a secret with sops; never print values; firstBoot prompts | secrets registry |
| `omanix-theme` | add/fork a theme, template overrides, reload hooks | token list |
| `diagnose-build` / `diagnose-unit` / `diagnose-crash` | triage from `omanix why-failed`, journal, coredump + local debuginfod | |
| `loom-reinstall` | reinstall/rotate keys/fork decision tree (decision 3) | |
| configurator-side: `configure`, `build-installer` | spec procedures | sidecar whitelist from schema |
| repo-dev (in `agents/skills/`) | add-option, add-module, add-package, add-theme, add-keybind, add-harness, add-webapp, vm-test, visual-verification, upstream-sync | |

The crash and unit-failure capture are on by default (`omanix.agents.crashCapture.enable`):
- coredumps (`omarchy-crash-watch` port)
- `OnFailure=` on loom/omanix units
- failed `omanix apply`

Each sends a notification with "Ask <agent> to diagnose", which launches the default harness with the matching skill and the `why-failed` JSON as its prompt.

### 8.5 How an agent safely changes a running machine (the loop the skills teach)

```
omanix context --json                     # orient; refuse to proceed if dirty tree from someone else
omanix where omanix.desktop.looknfeel.gaps  # find the owner of the knob
omanix set omanix.desktop.looknfeel.gaps.inner 8   # schema-checked edit of settings.json
omanix check --fast                       # eval + assertions (seconds)
omanix plan --json                        # diff, restarts, needsApproval, cacheMiss
git commit -S -m "..."                    # agent-signed (ssh signing, key from sops)
omanix apply                              # → switchd: verify, policy, test, watchdog, promote, push
  exit 0 → done; exit 3 → tell the human what needs approval and why (diff text), wait;
  exit 4 → `omanix why-failed --last`, fix, repeat; never retry the same commit unchanged
```

Optional live preview for look-and-feel options: `omanix try <path> <value>` applies the change with `hyprctl eval` (Lua) or a theme link swap, without a commit. It reverts on `omanix try --reset` or at session end. `omanix status` shows active trials.

---

## 9. Testing (`nix flake check` = the gate)

### 9.1 Pure checks (seconds to minutes; `omanix check --fast` runs these)

| check | asserts |
|---|---|
| `eval-<fixture>` | every fixture host evaluates: `base-x86_64`, `vm-test`, `laptop-tpm`, `desktop-fido2`, `agent-user-mode`, `ephemeral-home` |
| `layout` | each option's declaring file path == its option path (loom.lib.checks.layout) |
| `priorities` | every loom/omanix definition on a non-loom/omanix option has prio ≥ 1000 unless in force-allowlist |
| `documented` | every option has a description; non-trivial types also have an example |
| `schema` | settings/sidecar schemas generate; template `settings.json` and test sidecars validate; round-trip `omanix set` on all leaf types |
| `assertions-messages` | every `assertions` message contains an option path (regex) |
| `catalogs` | all catalogs build and validate against their schemas; `index.json` complete |
| `no-usr-paths` / `script-map-complete` | omarchy-src substitution audit |
| `keybind-unique` | duplicate keys produce an assertion naming both definitions (negative fixture) |
| `authorized-keys-in-sync` | the template's `.authorized_keys` equals the rendered `loom.host.keys` |
| `no-plaintext-secrets` | host template + fixtures: `secrets/*` are sops files; no `password`/`token` literals in settings.json |
| `closure-budget` | `base-x86_64` closure ≤ budget; forbidden deps absent |
| `lint` | nixfmt, statix, deadnix, shellcheck (writeShellApplication), go vet for loom tools |
| `cli-contract` | §8.1 |

### 9.2 VM tests (nixosTest; KVM)

| test | repo | what |
|---|---|---|
| `desktop-boots` | omanix | autologin → uwsm Hyprland 0.56.2 on virtio-gpu → `qs` shell up with no QML errors in the journal → `hyprctl configerrors` empty → screenshots of bar/menu/agent console. Settles the UNVERIFIED Qt 6.12/quickshell question. |
| `theme-switch` | omanix | `omanix theme set` swaps the link, the reload hooks run, a rebuild keeps the choice (mutable), and `pinned` resets it |
| `impermanence-reboot` | loom | write to persisted and unpersisted paths → reboot → only the persisted ones survive; `persist audit` reports the unpersisted one |
| `fde-passphrase` / `fde-tpm2` / `fde-fido2` | loom | built from nixpkgs `systemd-initrd-luks-*` patterns: swtpm (`virtualisation.tpm.enable`), canokey (`qemu_test` with canokeySupport), recovery-key unlock |
| `sops-host-key` | loom | secrets decrypt with the ssh-derived age key after reboot under tmpfs root |
| `sops-tpm` | loom | encrypt to `age1tag1` with age-plugin-tag, decrypt via sops-nix + age-plugin-tpm. **Gates `loom.secrets.hostKey = "tpm"`**, with an assertion until it passes in CI. |
| `policy-diff` | loom | agent-signed protected change → exit 3; human-signed approval commit → applied; tampered allowed_signers in the commit → still rejected |
| `switch-watchdog` | loom | a config that kills the session → rolled back within the timeout, exit 4, boot default unchanged; the switch survives killing the requester |
| `installer-e2e` | loom + omanix | node `silo` (seed `silo-lite`, stand-in hostname `silo.test`, own host key) + node `target` (empty disk, swtpm, `installer-test` image as USB with a sidecar made by `configure` in the test driver) → unattended install → reboot → unlock → desktop up → enrollment commit visible on the stand-in, with the enrollment key gone from `.authorized_keys` and the owner = human key (S1) |
| `reinstall-existing-id` | loom | second install with `loom.host=<same id>` on cmdline → read-only until a human-key push authorizes the new host key (driver pushes with a test "human" key) → same repo path, updated keys |
| `flash-guards` | loom | VM with an emulated usb-storage device + a virtio disk: `plan` lists only the USB; `write` without a token, or with a token after the device changed, exits 2; mounted device refused |
| `nuketown-wayland-approval` | nuketown | broker with `display = null`, `target = graphical-session.target` under a Wayland session (headless sway/cage in VM) |

Shared fixtures live in `loom/tests/lib.nix`: OVMF + `useBootLoader`, swtpm, canokey, the silo stand-in with a pinned test host key, and a test human key. No test ever resolves `silo.loom.farm`; a `networking.hosts` entry maps it to `0.0.0.0` in every test node as a tripwire.

---

## 10. Work breakdown (12 packages, buildable in parallel after P0)

Each package lands with its own checks green. Ownership follows the file trees above, so agents rarely edit the same files.

| # | package | scope / files | deps | acceptance test |
|---|---|---|---|---|
| **P0** | **Conventions lib** | `loom/lib/{catalog,json-schema,settings,checks,mk-host}.nix`, force-allowlist, AGENTS.md + rules, module skeletons for every `loom.*` file in §2.2 (options only, no config), flake outputs wired, channel bump of loom to 26.05 + unstable eval | — | `layout`, `priorities`, `documented`, `schema` checks pass on the skeleton; `mkHost` evaluates the template with stub settings |
| P1 | **nuketown additive** | §2.3 in nuketown | — | `checks.signi-compat` + existing ~40 checks pass on 26.05 and unstable; sudoex-run bypass test fails before and passes after |
| P2 | **Disk, FDE, unlock, boot** | `loom/modules/disk/*`, `boot.nix`, unlock-text, disko generation, `@agents-blank` hook | P0 | `fde-passphrase`, `fde-tpm2`, `fde-fido2` |
| P3 | **Impermanence + secrets** | `impermanence.nix`, `secrets.nix`, firstboot password step, `persist audit` backend | P0 (P2 for VM) | `impermanence-reboot`, `sops-host-key`, `sops-tpm` (may stay red; gates the option) |
| P4 | **Silo host repo + enrollment + seed deltas** | `host.nix`, `silo.nix`, `pkgs/loom-enroll`, seed S1–S5 + `silo-lite` | P0 | seed: hook unit tests for S1/S2; loom: enrollment against `silo-lite` in a 2-node test (owner handoff, ACL protection) |
| P5 | **Policy + switchd + watchdog** | `policy.nix`, `switch.nix`, `pkgs/{loom-switchd,loom-policy}`, nuketown `switch.command` wiring | P0, P1 (wiring only) | `policy-diff`, `switch-watchdog` |
| P6 | **Installer image + TUI + flash** | `lib/mk-installer.nix`, `modules/installer/*`, `pkgs/{loom-install,loom-flash,loom-hwfacts}`, `scripts/flash-usb.sh`, configure engine | P2, P3, P4 | `flash-guards`; `installer-e2e` on a **loom-only** profile (no desktop) |
| P7 | **omanix packaging** | `pkgs/*` incl. omarchy-src + script-map, titlebars via mkHyprlandPlugin, the 13 missing pkgs, tobi-try, hyprland/quickshell/guiutils pins | — | every package builds; `no-usr-paths`, `script-map-complete`; titlebars `.so` loads in a headless Hyprland (smoke) |
| P8 | **Desktop core** | `modules/desktop/*` (hyprland Lua stubs from bindings/input/looknfeel/monitors/toggles, uwsm session, shell unit, idle, plymouth, greeter) | P0, P7 | `desktop-boots`; `keybind-unique` negative fixture |
| P9 | **Themes** | `lib/theme.nix`, `modules/theme{,s}.nix`, `themes/*`, runtime set + reconcile, plymouth/sddm derivations | P7, P8 | `theme-switch`; every theme renders with no leftover `{{ }}` |
| P10 | **Apps, services, agents registry** | `modules/{apps,services,hardware,agents}/*`, crash capture, harness registry → skill links/persist | P8, P1 | `eval-agent-user-mode`, `eval-ephemeral-home`; VM: harness launch binding opens the default agent; crash capture fires on a test coredump |
| P11 | **CLI, catalogs, skills, templates** | `pkgs/omanix-cli`, `modules/{cli,catalog}.nix`, `pkgs/omanix-skills`, host template + CLAUDE.md, configure/build-installer skills | P0, P5 (apply path) | `cli-contract`; `catalogs`; an agent-driven script in a VM performs §8.5 end to end (set → plan → apply) |
| P12 | **Integration + release** | `base-x86_64` cache seed, closure budget, omanix `installer-offline`/`-net`, full `installer-e2e` with the omanix profile, `reinstall-existing-id`, release signing (tags, image signatures), remotes scripts | all | `nix flake check` green in omanix, loom and nuketown; offline install of the omanix profile with `cacheMiss = []` |

Critical path: P0 → P2/P3/P4 → P6 → P12. The desktop track P7 → P8 → P9/P10 runs in parallel from day one.

---

## 11. Settled answers to the spec's open questions (from this angle)

- **Seed-side builder:** not in v1. Configure runs local Nix (Linux, or WSL2 on Windows) with `configure check` reporting cache misses. The interface (`configure stage-cache`) is shaped so a remote builder can replace it later without changing the skill.
- **TPM PCR policy with Secure Boot off:** bind PCR 7 only, require a PIN by default, and say plainly in the matrix text that this is weak against physical attackers. `loom.boot.loader = "lanzaboote"` switches the default to PCRs `[7 11]` with a signed UKI policy and carries omarchy's nvpcr `SuccessExitStatus` drop-in.
- **Protected list:** loom owns the list as `loom.policy.protected`. It is upstream-defined, per-host extendable, and protected itself, so it can only shrink with a human signature.
- **Read-gated repos:** none. `checks.no-plaintext-secrets` plus sops is the control.

---

## 12. Trade-offs made in favour of agent-first

| decision | gained | given up |
|---|---|---|
| `settings.json` (data) as the edit surface instead of Nix | Schema validation, safe structural edits (`omanix set`), sidecar shares the schema, no Nix parsing | No comments in settings; humans used to `configuration.nix` see JSON; escape hatch `host.nix` is a second file |
| NixOS-only option tree, HM hidden | One namespace, one catalog, one `where` | Users who know HM can't use HM options directly without `omanix.home.extraModules` |
| Single nixpkgs = unstable | One Qt/Mesa, no overlay confusion, flake follows everywhere | Less stable base; mitigated by lock + VM-test-gated updates |
| switchd daemon instead of sudo + nixos-rebuild | The policy gate cannot be bypassed by the agent; switches survive the agent's terminal; a single JSON contract | More code in loom (Go daemon); diverges from the stock NixOS workflow (`nixos-rebuild` still works for root/human, but `omanix status` flags unsanctioned generations) |
| Read-only HM config, no mutable override by default | No drift; `where` is always truthful | omarchy users who hand-edit `~/.config/hypr/*.lua` must use `extraLua` or the `devOverride` flag |
| Home persisted wholesale by default | Humans never lose files | Undeclared home state accumulates; `persist audit` only covers it in ephemeral mode |
| ssh-ed25519 host key for sops by default; TPM age key gated on a test | Verified path first | TPM-bound secrets wait for the `sops-tpm` VM test |
| Two-phase flash with a confirm token | Agents can plan safely; the guard is in code | One extra step for humans |
| Unattended install only in `installer-test` builds | Production can never take a cmdline passphrase | Two image variants to build |
| Repo id literal (not derived at eval) | Reinstall keeps the id (decision 2); pure eval | The id↔machine-id relation holds only at mint time |
| Systemd-boot default over omarchy's Limine | Best-tested with systemd-cryptenroll and nixosTest | Less omarchy-like boot menu; `loom.boot.loader = "limine"` available |
| No AI-assistant credential handoff | In scope per spec; nothing secret leaves another machine | First boot requires the user to log the agent in on the new machine (a firstboot step) |
