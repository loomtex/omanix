# omanix fork: host and module model

Rev fork-1, 2026-10-27. Authors: Ada, with Joshua Perry.

**Scope.** This document covers V6 and V4 of the new direction: `omanix.lib.mkHost`, the host repo template, how the installer writes the repo, plugins as modules, option introspection, the agent's typed verbs, persistence conventions, and what is removed from DESIGN.md. The approval card, reviewer and switch pipeline are covered elsewhere, and this document points to them only where it needs to.

**Unchanged and still authoritative:** spec.md rev 16 and DESIGN.md §e (installer image, disk, LUKS, unlock, Secure Boot), §g.6 (enrollment on silo), §g.9 (system encryption key), §f.1 (impermanence) and §f.3.2 (the HM read-only file table). The silo facts F1–F8 in DESIGN.md §a.4 also still apply.

---

## 0. Calls

| # | Call | Reason |
|---|---|---|
| M1 | `omanix.lib.mkHost` **returns a `nixosSystem`**. The host's `flake.nix` assigns it to `nixosConfigurations.host` itself. | A host flake is an ordinary NixOS flake that can be read top to bottom. No helper builds hidden outputs. |
| M2 | mkHost adds exactly four things: loom (which bundles nuketown, home-manager, sops-nix, impermanence, disko and lanzaboote), the omanix base, `specialArgs.inputs`, and the human's HM entry point. Everything else is the host's plain modules, reached from `configuration.nix` through ordinary `imports`. | V6. You can debug the host with plain NixOS knowledge. |
| M3 | The repo has **four installer-written files** with one concern each: `machine.nix` (this disk and these keys to the machine: id, disk, unlock, Secure Boot, recipients, stateVersion), `keys.nix` (who may sign or push), `configuration.nix` (preferences) and `home.nix` (the human's HM). It also has `hardware.nix`/`hardware.json` (generated) and `modules/` (added later). | Routine agent edits touch `configuration.nix`, `home.nix` and `modules/`. Edits to `machine.nix` and `keys.nix` are rare, and a deterministic fact on the card always flags them. |
| M4 | **`keys.nix` is the single source** for human, host, agent and enroll keys. `.authorized_keys`, `CODEOWNERS`, `allowed_signers` and `.sops.yaml` are **generated** from it by `loom keys sync` and committed. `checks.keys-sync` fails when they differ, and switchd refuses such a commit. | Silo reads the files in the tree and cannot evaluate Nix (F2, F4, F5). git and sops need their own formats. A single source with generated copies keeps them consistent. |
| M5 | **Plugins are flake inputs plus `imports`.** A NixOS module is imported in `modules/plugins.nix` and an HM module in `home.nix`. There is no wrapper, registry or manifest. Every new input appears on the card as a deterministic fact. | V6, D5. |
| M6 | There is **no settings registry, schema, `settings.json`, tier or settable level**. Option metadata comes only from the option declarations (`options.json`). | V4. |
| M7 | `omanix set` stays, but only as an **editing tool for the agent or a terminal user**. It rewrites one literal definition in a host `.nix` file and then checks the evaluated value. It is not a gate and has no allowlist. | V6: typed verbs remain as tools, not gates. |
| M8 | **The installer never emits free-form Nix.** `loom-hostgen` renders a **closed, typed answer set** into fixed module lines through one escaping serializer. The sidecar can carry only those answers. | This keeps the spec's "fixed options schema, never arbitrary Nix from untrusted input" at the one place untrusted input enters, the sidecar. After install, every change is human-signed (V4). |
| M9 | GUI changes stay runtime state (V2). The resident sees them only through a **read-only runtime snapshot** that the human session publishes. "Make it stick" is an agent edit. After a promoted switch, `omanix-overlay settle` drops overlay keys that the declared value now matches. | The resident is a different uid and cannot read `~` (V3). It still needs the GUI state, and the overlays have to be emptied without a human-run `keep`. |

---

## 1. `omanix.lib.mkHost`

### 1.1 Signature

```nix
# omanix/lib/mk-host.nix   (omanix.lib.mkHost; loom.lib.mkHost is the same function without the omanix base)
mkHost =
  { self                                   # the host flake (for configurationRevision, path)
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
      omanixSelf.nixosModules.default      # omanix base (Quattro desktop, resident + reviewer residents, catalogs, CLI)
      ({ config, ... }: {
        system.configurationRevision = self.rev or self.dirtyRev or "unknown";
        loom.host.src = self;              # used by catalogs and switchd's eval of "this commit"
        home-manager.extraSpecialArgs = { inherit inputs; omanix = omanixSelf; };
        home-manager.users.${config.loom.user.name}.imports = homeModules;
      })
    ] ++ modules;
  };
```

**What each composed part provides.**

| Part | Provides | Host-visible options |
|---|---|---|
| loom | platform: disk/LUKS/unlock, boot, Secure Boot, impermanence, sops lifecycle + SEK, silo working copy, `loom-switchd` + watchdog, firstboot, `loom.keys`, card fact computation (protected HIGHLIGHT list, D5), catalogs lib | `loom.*` |
| nuketown (via loom) | agents as unix users, approval broker (`SIGN`), portal | `nuketown.*`; loom sets the two residents from `loom.agent.*` and `loom.reviewer.*` |
| home-manager (via loom) | HM NixOS module, `useGlobalPkgs`, `useUserPackages`, `backupFileExtension = null`, `home-manager-<u>.service` ordered before the display manager | `home-manager.*`; the human's tree is `home.nix` |
| omanix base | omarchy fork (v4.5.0-rc2): Quickshell shell, themes, Hyprland Lua, menu-as-intent-launcher, keybinds, apps, hardware quirks, the HM read-only dotfiles (DESIGN.md §f.3.2), runtime overlays, `omanix` CLI, catalogs, resident skills | `omanix.*` |
| host modules | everything under `configuration.nix` and `home.nix` | anything |

**Rules.**
- The output attribute is always `nixosConfigurations.host`. switchd evaluates `<commit>#nixosConfigurations.host`. The name never depends on the hostname, so renaming the machine is a one-line edit.
- Evaluation is pure, with `allow-import-from-derivation = false` in `loom-eval` and in CI. A plugin that needs IFD fails with an error that names the input (UNVERIFIED U6).
- loom and omanix set nixpkgs and HM options only with `mkDefault`, which `checks.priorities` keeps from DESIGN.md. Any host module therefore wins at normal priority, with no `mkForce` needed.
- mkHost does not read `hardware.nix`, `machine.nix`, `keys.nix` or `modules/` itself. `configuration.nix` imports them, so a reader can trace every file.

### 1.2 Returned value and companion

`mkHost` returns the `nixosSystem` attrset (`config`, `options`, `pkgs`, `extendModules`, …). The template also exports `checks.<system>.host = toplevel`, so `nix flake check` in a host clone builds the machine. omanix provides no other per-host outputs. Catalogs and docs are part of the toplevel (§5).

---

## 2. Host repo template

### 2.1 File tree (`silo:omanix/<id>.git`, branch `master`)

```
flake.nix              # inputs: omanix + follows targets + plugin inputs; outputs: nixosConfigurations.host
flake.lock
configuration.nix      # preferences; imports the rest (installer-written, then agent/human-edited)
home.nix               # the human's home-manager module (HM, plain)
machine.nix            # this machine: id, name, disk, unlock, boot, recipients, stateVersion (installer-written)
keys.nix               # loom.keys: humans / host / agents / enroll (single source, M4)
hardware.nix           # nixos-generate-config --no-filesystems (regenerable; never hand-edited)
hardware.json          # loom-detect facts (cpu/gpu/tpm2/fido2/sb/pci+usb ids/quirks/firmware globs)
modules/
  default.nix          # explicit `imports = [ ./plugins.nix ./persist.nix … ]` (no readDir)
  plugins.nix          # imports of NixOS modules from plugin inputs
  persist.nix          # host-level loom.persist.system additions (if any)
  home/                # HM modules split out of home.nix by the agent when it grows
secrets/
  host.yaml            # host-only material                    recipients: host, human-age*, recovery
  user.yaml            # login password hash (neededForUsers)   same
  data.yaml            # Wi-Fi PSKs, app tokens                 same
  agents/<n>.yaml      # resident's ssh signing key             same
.sops.yaml             # GENERATED from keys.nix + machine.nix (creation rules per file)
.authorized_keys       # GENERATED: humans + host + agents      (silo transport, F2/F5; never deleted)
CODEOWNERS             # GENERATED: humans + host; NOT agents    (silo master gate, F4; never deleted)
allowed_signers        # GENERATED: principal@role + key         (git verification; switchd uses /etc/loom/allowed_signers)
.loom/install-cache.pub  # optional per-host install cache key (DESIGN.md §e.3)
.gitignore             # result, result-*
CLAUDE.md              # host notes for the resident (§2.8); omanix guidance comes from the resident's global prompt
.claude/skills/        # host-local skills (optional; written by human or resident; ordinary reviewed files)
```

**Who writes which file.** No file is restricted. Every change reaches the machine only through a human-signed switch (V4). The "Card highlight" column lists the deterministic facts that a change to the file always raises (D5).

| File | Written by | Card highlight when changed |
|---|---|---|
| `configuration.nix`, `home.nix`, `modules/**` | resident, terminal user | only through the evaluated facts (protected options, services, ports, packages) |
| `flake.nix`, `flake.lock` | `omanix plugin add`, `omanix update`, human | **new/changed flake inputs** (url, rev, owner first seen) |
| `machine.nix` | installer, `loom unlock`, `loom keys rotate` | protected options (boot.*, LUKS, loom.secrets.*) |
| `keys.nix` + generated files | installer, `loom keys add-human/remove`, `loom keys sync` | **always: signing/push keys changed** (fact `keys`) |
| `hardware.nix`, `hardware.json` | installer, `loom hw regen` | boot.* and kernel modules via the protected diff |
| `secrets/**` | `omanix secret set` (encrypt-only), `loom keys` (re-encrypt) | file names only; values never shown |
| `CLAUDE.md`, `.claude/**` | anyone | none (no system effect); still on the card as "agent notes changed" |

### 2.2 `flake.nix`

```nix
{
  description = "kestrel — an omanix host";

  inputs = {
    omanix.url = "git+https://silo.loom.farm/omanix.git?ref=refs/tags/v0.1.0";
    # follow targets so plugins share one nixpkgs / one HM (one Mesa, one Qt)
    nixpkgs.follows = "omanix/nixpkgs";
    home-manager.follows = "omanix/home-manager";

    # plugins — added by `omanix plugin add`; each one appears on an approval card
    # hypr-dynamic-cursors = {
    #   url = "github:VirtCode/hypr-dynamic-cursors?ref=v0.3";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = inputs@{ self, omanix, ... }: {
    nixosConfigurations.host = omanix.lib.mkHost { inherit self inputs; };
    checks.x86_64-linux.host = self.nixosConfigurations.host.config.system.build.toplevel;
  };
}
```

### 2.3 `configuration.nix` (as the installer writes it)

```nix
{ lib, pkgs, ... }:
{
  imports = [ ./machine.nix ./keys.nix ./hardware.nix ./modules ];

  loom.user = { name = "josh"; fullName = "Joshua Perry"; email = "josh@6bit.com"; };
  loom.locale = { timeZone = "America/Denver"; keyMap = "us"; language = "en_US.UTF-8"; };

  loom.agent = { name = "ada"; harness = "claude-code"; sudo = "none"; };   # D8: sudo asked at install

  omanix.theme.default = "tokyo-night";
  omanix.defaults = { terminal = "alacritty"; browser = "chromium"; editor = "nvim"; };
  omanix.apps.obsidian.enable = true;

  # Below this line: changes made by the agent or by you. Each one was approved on a card.
}
```

### 2.4 `home.nix`

```nix
{ pkgs, ... }:
{
  # The human's home-manager module. Files HM writes are read-only store links (D9).
  # omanix already owns the desktop dotfiles (hypr/*.lua, terminals, fontconfig, …): change those
  # through omanix.* options in configuration.nix, not here (`omanix where <file>` tells you which).
  home.stateVersion = "26.11";

  home.packages = with pkgs; [ ];

  programs.git.settings.pull.rebase = true;
}
```

### 2.5 `machine.nix`

```nix
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

### 2.6 `keys.nix` and the generated files

```nix
{
  loom.keys = {
    humans.josh-yk = {
      key = "sk-ssh-ed25519@openssh.com AAAA… josh@yk";
      owner = true;                       # made the first push = silo .owner_key (F1); exactly one asserted
      localPath = null;                   # e.g. "~/.ssh/id_ed25519.pub" for a generated software key (D6)
      age = "age1yubikey1…";              # optional sops recipient (age-plugin-yubikey)
    };
    host = "ssh-ed25519 AAAA… root@kestrel";
    agents.ada = "ssh-ed25519 AAAA… ada@kestrel";
    enroll = null;                        # mint commit only; the installer's enrollment push sets null
  };
}
```

`loom.keys` replaces `loom.host.{humanKeys,hostKey,agentKeys}` and `loom.secrets.recipients.human`. A software human key without a passphrase is refused when added (D10). The reviewer resident has no key because it writes nothing (V5).

`loom keys sync` renders four files with a deterministic order (humans sorted by name, then host, then agents) and trailing `# loom:<role>:<name>` comments:

| File | Lines | Consumer | Effect |
|---|---|---|---|
| `.authorized_keys` | humans + host + agents (+ enroll in mint commit) | silo transport (F2), synced on master update (F5) | everyone listed can push **something** |
| `CODEOWNERS` | humans + host (+ enroll in mint commit); **never agents** | silo pre-receive on non-gate refs (F4) | agent key can push **only `gate/*`**; master moves only by humans or by switchd (host key) after a promoted switch |
| `allowed_signers` | `<name>@human namespaces="git" <key>`, `<host>@host …`, `<n>@agent …` | `git log --show-signature` in any clone; the same content is built into `/etc/loom/allowed_signers` from the **running** generation | switchd requires the approval signature from a `*@human` principal of the running generation |
| `.sops.yaml` | creation rules: host + humans' `age` + recovery, per file in `secrets/` | sops | the agent can encrypt to recipients but never decrypt (it holds no identity) |

`checks.keys-sync` re-renders the files and compares them byte for byte. switchd runs the same check on the commit and refuses on a mismatch. **Refused regardless of signer:** a commit that deletes `.authorized_keys` or `CODEOWNERS` (F5), or that leaves `loom.keys.humans` with no owner or with more than one owner.

### 2.7 `.gitignore`, secrets, install cache

These are unchanged from DESIGN.md §d.1, except for one thing: the old rule that only `data.yaml` is Tier A is gone (V4). The resident may run `omanix secret set` against any file. That command only encrypts, never reads, and every resulting switch is human-signed.

### 2.8 `CLAUDE.md` (repo) and the resident's guidance

The **resident's global prompt** carries the omanix guidance: nuketown `promptFragments` from `loom.agent.promptFragments` and omanix. Its skills come from the `omanix-skills` package, which HM links into `/agents/<n>/.claude/skills/`. Both update with the omanix release, so a host repo never carries stale copies. The repo `CLAUDE.md` holds only host-specific notes. The installer writes this starting text, which the resident or human may change:

```markdown
# kestrel

This repo is the NixOS + home-manager configuration of the machine kestrel (omanix host).
Run `omanix context --json` first.

- Preferences: configuration.nix (omanix.*, loom.user/locale/agent). Human dotfiles: home.nix
  (plain HM; desktop dotfiles are owned by omanix.* options — check `omanix where <file>`).
- Your own modules go in modules/ and must be listed in modules/default.nix.
- Plugins: `omanix plugin add <flakeref>`; never hand-edit flake.lock.
- keys.nix and the files generated from it: change only with `loom keys`.
- Every change: edit → `omanix check` → commit (signed) → `omanix propose`. The human approves
  on a card. Never run nixos-rebuild, disk, LUKS or key tools yourself.

## Notes about this machine and its human
(none yet)
```

**Resident skills** (in `omanix-skills`, linked for every enabled harness):

| Skill | Use |
|---|---|
| `omanix-host` | the edit loop, where things live (generated table from `catalog/home.json` + option roots), `set` vs hand edit |
| `make-it-stick` | read the runtime snapshot (§4.4) → module lines → propose; what settles afterwards |
| `add-plugin` | vet a flake (§3.3), `omanix plugin add`, persistence lines, propose |
| `add-app` | omarchy app vs nixpkgs package vs webapp/TUI |
| `update` | `omanix update`, reading the "Update ready" card facts |
| `persist` | §6 conventions, `omanix persist audit` |
| `secrets` | `omanix secret set`; asking the human through the chat secure field |
| `diagnose-build`, `diagnose-unit`, `diagnose-crash`, `recover` | as DESIGN.md §h.3 |
| `rotate-keys`, `reinstall` | human-driven procedures; the resident explains, never runs |

---

## 3. Plugins are modules

### 3.1 Conventions for a plugin flake

| Output | Meaning | How a host uses it |
|---|---|---|
| `nixosModules.<n>` (and `nixosModules.default`) | NixOS module | `imports` in `modules/plugins.nix` |
| `homeModules.<n>` (and `homeModules.default`) | HM module for the human | `imports` in `home.nix` |
| `homeManagerModules.<n>` | legacy alias; accepted, `omanix plugin add` prefers `homeModules` | same |
| `overlays.<n>` | optional; the host adds it via `nixpkgs.overlays` in `modules/plugins.nix` | same file |
| `packages.<sys>.<n>` | optional; referenced as `inputs.<p>.packages.${pkgs.system}.<n>` | any module |

Plugin authors should follow these rules. None of them is enforced except where a check is named.
- Declare a `nixpkgs` input so that hosts can `follows` it. `omanix plugin add` always writes `inputs.nixpkgs.follows = "nixpkgs"` and `inputs.home-manager.follows = "home-manager"` when the plugin declares those inputs.
- Use your own option namespace (`programs.<n>`, `services.<n>`, `<author>.<n>`). Never set `omanix.*` or `loom.*` with more than `mkDefault`.
- Give every option a description. The catalog flags undocumented plugin options in `omanix options --origin`.
- Persist state with the guarded pattern in §6.2 so the module still works on hosts without impermanence.
- Use no IFD.

Nothing in omanix wraps, registers or lists plugins. `omanix context` derives the "installed plugins" list from `flake.lock` and from `imports` that resolve to input store paths (`catalog/host.json`, §5).

### 3.2 `modules/plugins.nix`

```nix
{ inputs, ... }:
{
  imports = [
    inputs.hypr-dynamic-cursors.nixosModules.default
  ];
  programs.hypr-dynamic-cursors.enable = true;
}
```

`inputs` comes from `specialArgs`, not from `_module.args`, so it can be used in `imports`. HM plugins go in `home.nix` `imports`, with `inputs` from `home-manager.extraSpecialArgs`.

### 3.3 How the agent adds one (numbered flow)

1. **Vet.** `omanix plugin inspect <flakeref>` runs `nix flake metadata --json` and `nix flake show --json`, both of which are pure fetches that evaluate no module. It reports the outputs (`nixosModules`/`homeModules` names), the declared inputs, the latest tag, and whether the owner is already present in this host's lock. The resident tells the human what the plugin is and why it fits the request.
2. **Edit.** `omanix plugin add <flakeref> [--module <n>] [--home] [--name <input>]`:
   - adds the input to `flake.nix`, with follows for `nixpkgs`/`home-manager`/`omanix` when the plugin declares them. It prefers a tag ref and refuses a bare branch without `--branch` (a warning on the card);
   - runs `nix flake update <input>`, touching only that lock node;
   - appends `inputs.<input>.nixosModules.<n>` to `modules/plugins.nix` (or `homeModules.<n>` to `home.nix` with `--home`);
   - adds no option values, because enabling and configuring is a separate, ordinary edit (`omanix set` or a hand edit).
3. **Check.** `omanix check` evaluates and builds. The persist audit (§6.1) fails if the plugin's services keep state that nothing persists. The resident adds the lines to `modules/persist.nix` and checks again.
4. **Propose.** The resident commits (agent-signed), pushes `gate/<topic>` and runs `omanix propose`. Card facts always include `new flake input <url> @ <rev>`, plus every protected or service fact the module causes. A new input is never a routine one-line card (V5 escalation).
5. **Remove.** `omanix plugin remove <input>` deletes the import lines, the input and its lock node. Option values that the plugin's options defined become eval errors, which `omanix check` reports with file:line, and the resident deletes them.

### 3.4 How the omanix base and D9 dotfiles expose options

- The omanix desktop is configured **only through `omanix.*` NixOS options** (DESIGN.md §c.2, minus settable annotations). The omanix base writes `home-manager.users.<u>.xdg.configFile.*`/`home.file.*` from those options. The files are read-only store links, and the HM table in DESIGN.md §f.3.2 is unchanged.
- `home.nix` is free HM. If it defines a target that omanix already owns, HM fails evaluation with a duplicate-definition error. `checks.home-owned` turns that into `home.nix: ~/.config/hypr/bindings.lua is owned by omanix (omanix.keybinds.*); set the option, or lib.mkForce to take the file over` (UNVERIFIED U7). Taking a file over with `mkForce` is allowed, because it is just NixOS.
- **App-owned paths** (btop.conf, fcitx5, the chromium profile, mimeapps.list, dconf) remain `omanix.home.appOwned` (readOnly list). An assertion forbids any HM definition, from omanix, `home.nix` or a plugin, targeting them. The assertion names the path.
- `omanix.home.extraModules` is **deleted**. `home.nix` imports replace it.
- `omanix.hyprland.{settings,monitors,windowRules,extraLua,fileLua.<f>,gdkScale}`, `omanix.keybinds.*`, `omanix.menu.items.*`, `omanix.shell.settings`, `omanix.theme.*`, `omanix.defaults.*`, `omanix.apps.*`, `omanix.input.*`, `omanix.fonts.*` and `omanix.language` keep their types and HM landing files. These are the targets of "make it stick".
- `omanix.menu.items.<id>.action` gains the variant `{ intent = "<prefilled text>"; }`. The default menu maps omarchy's mutating entries to intents (V2). The resident can add menu entries like any other option.

---

## 4. How the installer writes the host repo

### 4.1 Renderer

`loom-hostgen` is part of `loom-installer` and `configure` (python stdlib):
- input: an **answers** object with a fixed key set, typed and validated (§4.2). Unknown keys are refused;
- output: the template files with the values substituted in place. Strings go through one serializer, `to_nix_str` (escapes `\`, `"` and `${`, rejects control characters), so no answer can produce Nix syntax;
- after rendering: `nix eval --json .#nixosConfigurations.host.config.<path>` for every answer path, and comparison with the answer. A mismatch stops the installer and writes nothing;
- `nixfmt` on the output, so the agent's later diffs stay small.

### 4.2 Answer → module line

| Answer (installer TUI / configure / sidecar) | Validation | File | Line written |
|---|---|---|---|
| host repo id | `^[0-9a-f]{32}$`, appSpecific check in fresh mode | machine.nix | `loom.host.id = "…";` |
| hostname | RFC 1123 label | machine.nix | `loom.host.name = "…";` |
| user name / full name / email | `^[a-z_][a-z0-9_-]{0,31}$` / printable / RFC 5322 simple | configuration.nix | `loom.user = { … };` |
| login password | typed twice | secrets/user.yaml | yescrypt hash; `loom.user.password` left at default `"sops"` (or `= "firstboot";`) |
| time zone / keymap / language | tzdata list / xkb list / supported locales | configuration.nix | `loom.locale = { … };` and `omanix.language` when not `en` |
| target disk | `/dev/disk/by-id/…` of a non-removable device | machine.nix | `loom.disk.device` |
| unlock methods | from the capability matrix (DESIGN.md §e.6) | machine.nix | `loom.disk.unlock.methods = [ … ];` |
| Secure Boot | probe + user choice (D4) | machine.nix | `loom.boot.secureBoot.enable` |
| loader (advanced) | `limine` \| `lanzaboote` (D7) | machine.nix | `loom.boot.loader` only when not the default |
| SEK (generated or typed) | DESIGN.md §g.9 | machine.nix | `loom.secrets.recipients.recovery`, `loom.secrets.recovery.fingerprint` |
| host age key (generated) | — | machine.nix | `loom.secrets.recipients.host` |
| human key (FIDO2 touch, existing pubkey, or generated passphrase software key, D6) | key type allowlist; software ⇒ passphrase (D10) | keys.nix | `loom.keys.humans.<n> = { key; owner; localPath; age; };` |
| host ssh / agent ssh keys (generated) | — | keys.nix; `secrets/agents/<n>.yaml` | `loom.keys.host`, `loom.keys.agents.<n>` |
| agent name / harness | `^[a-z][a-z0-9-]{0,15}$` / enum from catalog | configuration.nix | `loom.agent = { name; harness; … };` |
| approval sudo for the resident (D8) | yes/no, default no | configuration.nix | `sudo = "approval";` only on yes (written `"none"` explicitly so the line is visible) |
| theme | enum from `catalog/themes.json` | configuration.nix | `omanix.theme.default` |
| default terminal / browser / editor | enums | configuration.nix | `omanix.defaults = { … };` |
| apps picked | names in `catalog/apps.json` | configuration.nix | `omanix.apps.<n>.enable = true;` per app |
| hardware | loom-detect + `nixos-generate-config --no-filesystems` | hardware.json / hardware.nix | whole files |
| stateVersion | release nixpkgs version | machine.nix / home.nix | `system.stateVersion`, `home.stateVersion` |
| Wi-Fi used during install | — | **not in the repo** | if the user ticks "remember", the installer writes an NM keyfile to `/persist/etc/NetworkManager/system-connections/` (runtime state the user typed on this machine; no credential is copied from anywhere) |

**The sidecar** (DESIGN.md §d.4, schema bumped to `loom.sidecar/v2`) replaces `"settings"` with `"answers"`, restricted to the rows that do not touch security: hostname, user name/fullName/email, locale, theme, defaults, apps. Unlock, Secure Boot, SEK, keys, agent sudo and the disk are always asked in the TUI, or come from the human-signed mint commit, never from the sidecar. The secret-pattern validator is unchanged.

### 4.3 Commits

1. **Mint** (configure skill on the user's existing computer; signed and pushed by the owner human key; DESIGN.md §g.6): the template rendered from the configure answers; `keys.nix` with humans and `enroll`; the generated files. There is no `machine.nix` yet. `configuration.nix` imports `./machine.nix`, so mint ships a stub `machine.nix` with only `loom.host.id`, and evaluation of the mint commit is not expected to build.
2. **`install: apply answers`** (host-signed): sidecar answers re-rendered over the mint files. In fresh mode this commit carries all the answers instead.
3. **`install: <host> on <disk>`** (host-signed): `machine.nix`, `hardware.{nix,json}`, `secrets/*`, `keys.nix` (host and agents added, `enroll = null`), and `loom keys sync` output. The enrollment push follows DESIGN.md §g.6.
4. First boot deploys commit 3. **Every later switch needs a human-signed approval** (V4). Commits 2–3 are host-signed install records made by deterministic code. They are accepted only as the installed baseline and never as the approval for a switch.

### 4.4 Runtime snapshot for "make it stick" (M9)

- `omanix-session-state.service` is a user service in the human's session. On every overlay or theme change it writes `/run/omanix/session/<uid>/runtime.json` (mode 0640, group `omanix-resident`).
- The snapshot holds only typed keys: theme name, wallpaper path, monitors (output/mode/position/scale/vrr), `gdkScale`, monospace font, shell.json delta against the defaults, the key/value pairs in hypr overlays, and toggles. It holds no file contents outside the overlays.
- The chat surface attaches the snapshot's sha to a "make it stick" request, so the reviewer sees what the human was looking at.
- `omanix-overlay settle` runs in the session after every promoted switch, on the existing per-session reload hook. It removes each overlay key whose effective declared value now matches, and leaves the rest. `omanix doctor` lists the keys that remain.

---

## 5. Option catalogs and introspection

### 5.1 Catalogs (`/run/current-system/sw/share/omanix/catalog/`)

| File | Source | Shared or per host |
|---|---|---|
| `options/nixos.json` | `nixosOptionsDoc` of the base eval (nixpkgs + loom + nuketown + omanix), with `transformOptions` adding `origin` (`nixpkgs`/`home-manager`/`loom`/`nuketown`/`omanix`) | shared per release (cached) |
| `options/home.json` | `nixosOptionsDoc` of `options.home-manager.users.type.getSubOptions []` | shared per release |
| `options/host.json` | the same doc of **this host's** eval, minus the declarations already in the shared files: plugin and host-module options, each with `origin = "input:<name>"` or `"host:<file>"` | per host (small) |
| `host.json` | host summary: plugins (input → imported module names → option roots), host module files, files that `mkForce` an omanix-owned HM target, lock revs | per host |
| `home.json`, `keybinds.json`, `menu.json`, `themes.json`, `apps.json`, `persist.json`, `secrets.json` (names), `services.json`, `unlock.json`, `commands.json` | as DESIGN.md §h.2 (minus settable columns) | per host |
| `index.json` | every file with its sha256 | per host |

Deleted: `schema/settings.schema.json`, the settable level/class columns, and `definitions.json`. Definitions are now looked up live (§5.2), which avoids walking every option at build time.

### 5.2 Commands

| Command | What it does |
|---|---|
| `omanix options <query> [--origin <o>]` | full-text search over the three option files; prints path, type, default, origin and description |
| `omanix where <option\|file>` | **live eval** in the working copy: `options.<path>.definitionsWithLocations` → file:line, priority and value per definition, marking host files as editable and input files as not. For an HM target path, it reads `catalog/home.json` → owning `omanix.*` option, overlay path, and shadowing key from `runtime.json` |
| `omanix explain <option>` | `options` entry + `where` + current value + **whether the path is on the card highlight list** (loom `policy.highlight`, D5) and why |
| `omanix context` | session start: host id, deployed commit, working copy ahead/dirty, plugins, last switch and card result, runtime snapshot summary, catalog index, skills |

**Per-host docs for the resident.** `catalog/host.md` is generated at build from `host.json` and `options/host.json`. It lists the plugin and host option roots with descriptions, the files the host overrides, and the persistence additions. The resident's prompt fragment contains the top-level option index, generated from the root descriptions of `loom.*`, `omanix.*` and the plugin roots, and says "read catalog/host.md before changing a plugin".

---

## 6. Impermanence and persistence for modules

### 6.1 Rules (DESIGN.md §f.1 unchanged; restated for module authors)

| Where state lives | What a module does |
|---|---|
| system state (`/var/lib/<svc>`, `/etc/<file>`) | `loom.persist.system.directories = [ "/var/lib/<svc>" ];` in the **same module** that enables the service. Inside the host repo, use `modules/persist.nix` for third-party plugin services |
| `DynamicUser` services | persist `/var/lib/private/<svc>` (the audit maps `StateDirectory` to the right path; UNVERIFIED U5) |
| the human's home | nothing: all of `/home` is the `@home` subvolume |
| a resident's home (`/agents/<n>`, reset every boot) | `nuketown.agents.<n>.persist.{directories,files}`; omanix persists `projects` and `.claude` for the resident; the reviewer persists nothing |
| deliberately throwaway state | `loom.persist.ephemeralOk = [ "/var/lib/<svc>" ];` with a comment explaining why |

- The **eval-time audit** (`loom.lib.persistAudit`) is an **assertion**. Every enabled service's `StateDirectory` must be persisted or listed in `ephemeralOk`, and the message names the line to add. A plugin that forgets persistence therefore fails `omanix check`, not first reboot.
- `omanix persist audit` (runtime) lists writes on tmpfs `/` that no entry covers, and the option that owns each one.
- `omanix persist add <path>` is a convenience verb that appends to `modules/persist.nix`.

### 6.2 Guarded pattern for portable plugins

```nix
{ lib, options, ... }:
{
  config = lib.optionalAttrs (options ? loom.persist) {
    loom.persist.system.directories = [ "/var/lib/foo" ];
  };
}
```

`optionalAttrs` keyed on `options` (not `mkIf`) keeps the module evaluable on plain NixOS, where `loom.*` is undeclared.

---

## 7. Typed convenience verbs (agent tools, not gates)

Every verb only edits files in the working copy and checks the result by evaluating it. None of them can switch the system, and none is required, so the same change can be made by hand. All of them follow the CLI contract in DESIGN.md §h.1: `--json`, exit codes 0/1/2/3/4/5.

| Verb | Keep? | Why |
|---|---|---|
| `omanix context` | keep | one call gives the resident its bearings |
| `omanix options` / `where` / `explain` | keep | introspection is what makes "edit any module" safe for an agent |
| `omanix set <path> <json>` / `unset` | **keep, reduced** | see §7.1. It saves the agent hand-editing nested attrsets correctly and verifies the evaluated value |
| `omanix plugin inspect/add/remove` | keep | flake input + follows + lock + import touch 3 files in a fixed pattern that is easy to get subtly wrong (missing follows ⇒ second nixpkgs) |
| `omanix app add/remove <name>` | keep | resolves one name to the right edit: omarchy app → `omanix.apps.<n>.enable`; webapp/TUI → `omanix.apps.{webapps,tuis}.<N>`; otherwise a nixpkgs attr checked with `nix eval nixpkgs#<attr>.meta.mainProgram` → `home.packages` in `home.nix` |
| `omanix secret set <file> <name>` | keep | value comes from the human through the chat surface's secure field or stdin. The tool only encrypts and never echoes or decrypts |
| `omanix persist add` / `persist audit` | keep | §6 |
| `omanix check` / `plan` / `propose` | keep | eval + build + nvd. `propose` pushes `gate/<topic>` and asks switchd for a card. It replaces `apply` for the resident |
| `omanix update [<input>]` | keep | bumps `omanix` (or a named input) to the latest signed tag/rev and proposes it. The result shows as "Update ready" |
| `omanix rollback` / `status` / `why-failed` / `doctor` | keep | repair path |
| `omanix try` | keep | live preview without a commit (V2 runtime) |
| `omanix reset <path>` / `edit <path>` | keep (human side) | runtime overlay revert and the terminal user's overlay editor |
| `omanix keep` | **delete** | replaced by the "make it stick" intent (§4.4) |
| `omanix keybinds/menu/themes` listing | fold into `options` + catalogs | no separate verbs |
| `omanix theme set` | runtime only (GUI and CLI) | V2 visual browsing; sticking is via the agent |

### 7.1 What remains of `omanix set`

1. Resolve `<path>` with `omanix where`. If the option is not declared, exit 2 with the nearest matches from `options`.
2. If **exactly one** definition comes from a host file and it is a literal (string, number, bool, list or attrset of literals), rewrite it in place with an rnix-based editor (`nix-editor`, UNVERIFIED U3).
3. If there is no host definition, append `<path> = <value>;` under the marker line in `configuration.nix` (`home.nix` for HM paths given as `home.<…>`).
4. If several host definitions exist or the definition is an expression, exit 2 with file:line for each and "edit by hand". It never guesses.
5. Run `nixfmt`, then evaluate `config.<path>`. The value must equal `<json>`, otherwise revert the file and exit 1, showing the higher-priority definition that wins.
6. Report `shadowedBy` from `runtime.json` when a GUI overlay will still hide the change.

There is no allowlist, schema or level check. Whatever the change, the card and the human signature are the gate (V4).

---

## 8. Deleted from DESIGN.md

| Item | Where | Replacement |
|---|---|---|
| `settings.json` and `loom.lib.settings.module` | §b.3, §d.1 | `configuration.nix` / `machine.nix` / `keys.nix` (M3) |
| settable registry `loom.settings.settable.*` (level, class, sidecar, reason) | §c.1 | none; option declarations only |
| JSON Schema generation, `schema/settings.schema.json`, `checks.schema`, `checks.settable-review` | §h.2, §i | `checks.keys-sync`, `checks.host-template` |
| tiers A/B/C, `loom policy classify`, `confirmProtected` tied to tier C | §g.2 | every switch human-signed; highlight facts on the card |
| `loom.policy.extraProtected`, `loom.policy.protectedRepoPaths` | §c.1 | the protected list moves to `loom.lib.policy.highlight` (fixed in loom, D5), which is a fact source and not a gate |
| `loom.policy.humanKeyKind` | (already removed) | — |
| unattended Tier-B updates, `loom.switch.autoUpdate = "stage"` | §g.5 | "Update ready" cards. `autoUpdate` becomes `enum ["off" "notify"]` |
| `host.nix` escape hatch | §d.1 | the whole repo is Nix |
| `omanix.home.extraModules` | §c.2 | `home.nix` imports |
| `omanix keep` and the `keep` column of `writers.toml` | §f.3.7 | "make it stick" intent + `overlay settle` |
| `loom.host.{humanKeys,hostKey,agentKeys}`, `loom.secrets.recipients.human` | §c.1 | `loom.keys.*` |
| "settable:agent / install / sidecar" annotations on `loom.*`/`omanix.*` | §c | dropped; types and descriptions stay |
| sidecar `settings` map | §d.4 | sidecar `answers` (closed set, §4.2) |
| `omanix set` refusal "needs host.nix (Tier C)" | §h.1 | §7.1 behavior |
| host flake "**only** `omanix`" input rule | §b.1 | any inputs; `nixpkgs`/`home-manager` follow omanix |

**Kept unchanged:** the policy view's normalization (store paths → `<pname>@<origin>`), now used to compute the card's protected-option diff; the switchd commit-only rule, watchdog and rollback; silo guards (HEAD check, never delete `.authorized_keys`/`CODEOWNERS`, push only `master` and `gate/*`); repo id; SEK.

---

## 9. Checks added or changed

| Check | Asserts |
|---|---|
| `checks.host-template` | the template + sample answers render, evaluate, and build with `allow-import-from-derivation = false`; `flake.lock` contains exactly one `nixpkgs` node |
| `checks.keys-sync` | generated files equal render(`loom.keys`) for template fixtures; refusal cases (no owner, two owners, deleted CODEOWNERS) |
| `checks.hostgen-escape` | pytest: answers with `"`, `\`, `${`, newlines, unicode are rendered as data or refused |
| `checks.plugin-fixture` | a fixture plugin flake (`nixosModules.default` with a `StateDirectory` service, `homeModules.default` with a file) added by `omanix plugin add` in a VM: lock has one nixpkgs, audit fails before `persist add` and passes after |
| `checks.home-owned` | `home.nix` defining an omanix-owned target fails with the §3.4 message; `mkForce` passes; an app-owned target always fails |
| `checks.set-roundtrip` | `omanix set` fixtures: literal rewrite, append, nested attrs, `with pkgs; [ ]` list, comments preserved, multi-definition refusal |
| `checks.catalog-size` | per-host catalog files under 2 MB; shared option files under 15 MB uncompressed |
| S3 stand-in `agent-gate-only` | agent key: push to `master` rejected, `gate/x` accepted; host key: `master` accepted |

---

## 10. UNVERIFIED (each with the test that settles it)

| # | Claim | Settling test |
|---|---|---|
| U1 | A top-level `nixpkgs.follows = "omanix/nixpkgs"` in the host flake, plus a plugin's `inputs.nixpkgs.follows = "nixpkgs"`, yields one nixpkgs lock node | `checks.host-template` / `checks.plugin-fixture`: `nix flake metadata --json \| jq '.locks.nodes \| keys'` has one nixpkgs |
| U2 | `nix flake check` on a plugin flake with `homeModules` only warns (unknown output) and does not fail, on the Nix version omanix ships | run `nix flake check` on the fixture plugin in CI with omanix's `nix` package |
| U3 | `nix-editor` (rnix) rewrites nested attr paths and list literals without losing comments; otherwise switch to a tree-sitter-nix editor in `omanix-cli` | `checks.set-roundtrip` against both backends; pick the one that passes all fixtures |
| U4 | `nixosOptionsDoc` over the full eval with plugins builds without IFD, and the shared/per-host split stays within budget | `checks.catalog-size` on `ref-default` + the fixture plugin |
| U5 | `persistAudit` maps a `DynamicUser` service's `StateDirectory` to `/var/lib/private/<svc>` and the bind works under impermanence | VM test fixture service with `DynamicUser = true`; sentinel survives reboot |
| U6 | An IFD-using plugin fails in `loom-eval` with an error that names the input | fixture plugin with `import (pkgs.runCommand …)`; assert stderr contains the input name |
| U7 | The HM duplicate-definition error for an omanix-owned `xdg.configFile` names both definition files, so `checks.home-owned` can rewrite it | `checks.home-owned` negative fixture; grep the original HM error |
| U8 | `home-manager.extraSpecialArgs.inputs` is visible to modules imported via `home-manager.users.<u>.imports` and usable in their `imports` | `checks.plugin-fixture` HM half evaluates |
| U9 | Group-readable `/run/omanix/session/<uid>/runtime.json` is readable by the resident (in group `omanix-resident`) and not by the reviewer | VM test: `sudo -u ada cat` succeeds, `sudo -u omanix-review cat` fails |
| U10 | The mint commit with a stub `machine.nix` passes `checks.keys-sync` even though the configuration does not build | `checks.keys-sync` fixture on the rendered mint tree |
