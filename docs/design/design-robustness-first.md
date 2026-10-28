# omanix architecture: robustness-first design

Angle: **security and recoverability first.** Where a convenience feature fights with "the machine can't be talked into
granting itself power" or "you can always get your data and your repo back", security and recoverability win, and the
trade-off is written down (marked **TRADE-OFF**). Scope follows spec rev 16: USB installer image only, whole-disk, no
in-place conversion, no credential copying. Nothing in this design moves an existing AI-assistant login or token to the new
machine. The agent logs in on the installed machine through its own normal login flow, or not at all.

Authors: Ada, with Joshua Perry. Date 2026-10-27. Inputs: spec.md (rev 16), design/facts.md, understand/*.md.

---

## 0. Hard calls (summary)

| # | Decision | Why (security/recoverability) | Trade-off |
|---|---|---|---|
| H1 | omanix pins **nixos-unstable** now and moves to **nixos-26.11** at branch-off. loom/nuketown CI-test both 26.05 and unstable. | One nixpkgs means one Mesa, one Qt and one systemd. Facts §3 flags Mesa mismatch as the main risk of mixing channels. | Unstable churn. It is contained because only release tags that passed the full `nix flake check` are consumable (H6). |
| H2 | Root is **tmpfs**. `/home` and `/persist` are **persistent** btrfs subvolumes, and `/agents` is wiped every boot by the nuketown rollback. | "Forgot to persist it" is the #1 impermanence data-loss bug, and it is fatal for user files. A tmpfs root needs no rollback script that could fail. | `$HOME` dotfile drift is possible. It is detected by `omanix doctor` rather than wiped. |
| H3 | **Every disk has a recovery key slot** (`systemd-cryptenroll --recovery-key`), shown once. The user must type a group back to continue. | It is the only unlock path that survives losing a TPM, a FIDO2 key or a passphrase. | One more secret for the user to keep. |
| H4 | **TPM2-only (no PIN) is offered only when Secure Boot is on with our keys.** With SB off, TPM2 is offered only as TPM2+PIN. | With SB off, PCR 7 does not change when an attacker boots their own OS, so TPM-only would unlock for any USB stick. | Machines that can't enter Setup Mode lose pure auto-unlock. |
| H5 | **The host sops key defaults to a file** under `/persist`, protected at rest by LUKS. The TPM-wrapped key (age-plugin-tpm) is opt-in. | A BIOS update can clear an AMD fTPM, and a moved disk loses its TPM. Either would destroy a TPM-only host key. | Root on the running host could copy the key. Root can already read every secret, so the loss is small. |
| H6 | **Trust anchors always come from the running system**, never from the proposed commit. That covers allowed_signers, the protected-path list and release signers. | An agent cannot edit the rules that judge its own commit. | Changing a trust anchor takes two steps: a human-signed commit, then a switch. |
| H7 | **Three-tier policy.** Tier A (agent-writable settings, empty protected diff) needs only the agent's signature. Tier B (lock bump to a verified release tag) needs only the agent's signature. Tier C (everything else) needs the **human** signature. | The spec's "diff evaluated options" plus a structural rule, because arbitrary Nix can always run code as root. | The agent can't hand-write NixOS modules without a human click. |
| H8 | **The agent never switches through generic sudo.** It calls `loom switch`, which talks to a root `loom-switchd` over polkit. The policy check, build, test and watchdog all run inside the daemon. | The policy can't be bypassed by an approved-but-misread sudo prompt. | One more daemon. nuketown's generic approval sudo still exists for other tasks. |
| H9 | **Silo ownership is handed to the human key at enrollment** (new silo push option). The enrollment key ends with no power at all. | Today `.owner_key` is immutable, so the enrollment key would keep push rights forever. | Needs a small seed/silo change (S1). |
| H10 | The installer is a **deterministic TUI with no agent and no sshd**. Agents work before install (the configure skill) and after first boot. | No network credential and no remote shell exist on the medium that does the destructive work. | Remote or unattended installs exist only in the separate test image. |
| H11 | The installer media's store partition is **dm-verity protected**. Release images and `SHA256SUMS` are SSH-signed. | Bad USB sticks are common, and verity turns silent corruption into a clear error. It also catches tampering. | Slightly more complex image build (nixpkgs has a template). |
| H12 | Boot loader is **Limine** (matches omarchy, `secureBoot` in nixpkgs, `enrollConfig` + checksums). Fallback is lanzaboote. | Signed config plus hash-checked kernel and initrd under SB. The nixpkgs `limine/secure-boot` test exists. | Limine has no boot counting, so recovery relies on "promote only after health" (§6.5) plus the generation menu. |

---

## 1. Layering and repos

```
                 ┌────────────────────────────── host flake (silo: omanix/<id>.git) ─┐
                 │ flake.nix → omanix.lib.mkHost { … }   host.json  settings/  system/ │
                 └───────────────▲───────────────────────────────────────────────────┘
                                 │ inputs.omanix (the only direct input; everything else follows)
┌────────────── omanix (Quattro flavor) ───────────────┐
│ desktop: hyprland(lua) quickshell omarchy-src themes │
│ apps, menus, keybinds, agents registry, omanix CLI   │
└──────────────────────▲───────────────────────────────┘
                       │ inputs.loom
┌────────────── loom (DE-agnostic platform + agent base) ───────────────────────────────┐
│ installer image, disko/FDE/unlock, secure boot, impermanence, sops lifecycle,          │
│ silo host repo + enrollment, policy diff, loom-switchd + watchdog, firstboot/onboarding │
└──────────────────────▲─────────────────────────────────────────────▲─────────────────┘
                       │ inputs.nuketown (optional, additive)         │ seed (silo server; test module)
               nuketown: agents as unix users                     seed/silo
```

Remotes for omanix, loom and nuketown: `origin` fetches `silo.loom.farm:<repo>.git`, and pushurl is set to both silo and
github (fixed decision 5). Host flakes live on silo only.

### 1.1 omanix repo

```
omanix/
  flake.nix  flake.lock
  CLAUDE.md               # @AGENTS.md
  AGENTS.md               # router: where things live, rules, apply workflow, test etiquette
  .claude/skills/
    configure/SKILL.md          # conversation → host repo on silo + sidecar (spec)
    build-installer/SKILL.md    # build/verify image, flash USB with sidecar (spec)
    add-option/SKILL.md  add-theme/SKILL.md  add-app/SKILL.md  add-keybind/SKILL.md
    vm-test/SKILL.md     release/SKILL.md
  scripts/                      # thin, signed, self-verifying entry points (§5.9)
    flash-usb.sh  configure.sh  verify-release.sh
    SHA256SUMS  SHA256SUMS.sig
  release/allowed_signers       # omanix release signers (copy; the trust anchor is pinned out of band)
  lib/
    default.nix                 # re-exports loom.lib + mkHost with omanix flavor
    render-template.nix         # .tpl renderer (pure nix, no IFD)
  pkgs/
    omarchy-src/default.nix     # upstream omarchy (MIT) pinned input → patched store tree
    omanix-cli/                 # `omanix` CLI (python, stdlib): options/where/get/theme/apps/doctor
    titlebars/ owe/ ttfx/ omacalc/ omasnap/ omacut/ omawrite/ hype/ signed/ monologue/ gliff/
    aether/ asdcontrol/ tobi-try/ quickshell/ (pinned flake + vendored 611 patch if needed)
    plymouth-theme/ sddm-theme/ # pure functions of theme colors + logo
  modules/
    nixos/
      default.nix               # imports all; nothing enabled unless omanix.enable
      desktop/{hyprland,session,sddm,plymouth,portals,fonts,input,audio,power,network,bluetooth,printing}.nix
      hardware/{gpu,laptop,apple,asus,framework,dell,intel,quirks}.nix
      apps/{chromium,firefox,docker,localsend,…}.nix
      agents/{registry,launcher,crash-capture}.nix
      theme/{registry,boot}.nix
    home/
      default.nix
      hyprland/{default,bindings,looknfeel,monitors,autostart,toggles}.nix
      shell/{quickshell,menu,bar}.nix
      theme/{default,state,retint}.nix
      terminals/{foot,alacritty,ghostty,kitty}.nix
      apps/{webapps,tuis,nvim,btop,git,mise}.nix
      agents/{skills,harnesses}.nix
  themes/<name>/default.nix     # registry entries generated from upstream colors.toml (+ overrides)
  templates/host/               # omanix host template (extends loom's)
  tests/
    desktop-boots.nix  theme-switch.nix  keybind-dupes.nix  no-usr-paths.nix  closure-budget.nix
  docs/  (generated options.md, commands.md; architecture prose)
```

File path equals option path: `omanix.desktop.hyprland` lives in `modules/nixos/desktop/hyprland.nix`, and
`omanix.theme.*` (home) lives in `modules/home/theme/default.nix`. `omanix where <opt>` confirms it from
`definitionsWithLocations`.

### 1.2 loom repo (refactor; the existing MVP is replaced)

```
loom/
  flake.nix  flake.lock  CLAUDE.md  AGENTS.md  README.md  LICENSE
  lib/
    default.nix
    mk-host.nix              # mkHost: host flake → nixosConfiguration (+ policy view, + test VM)
    mk-installer.nix         # mkInstallerImage: repart raw image (ESP + verity store + OMANIX-CFG)
    sidecar.nix              # sidecar JSON schema (generated from option types) + validator
    settings-guard.nix       # loads settings/*.nix as DATA, rejects paths outside agentWritable
    policy-view.nix          # projection of protected options → canonical JSON
    persist-audit.nix        # StateDirectory coverage assertions
  modules/
    default.nix              # bundle: imports all + nuketown(optional) + HM + impermanence + sops + disko
    host/identity.nix        # loom.host.{id,name,user,humanKeys,…}
    disk/{layout,unlock,recovery}.nix
    boot/{loader,secure-boot,initrd}.nix
    impermanence/{default,persist-list,audit,snapshots}.nix
    secrets/{default,host-key,recipients,prompted}.nix
    silo/{default,remote,enroll,sync}.nix
    trust/{signers,releases}.nix
    policy/{default,view,tiers}.nix
    switch/{daemon,watchdog,health}.nix
    agent/{default,nuketown}.nix
    firstboot/{default,unlock-finalize,secureboot-enroll,secrets-prompt,onboarding}.nix
    installer/{image,tui,payload,test-mode}.nix
    nix/{settings,cache}.nix
  pkgs/
    loom-cli/           # python stdlib: loom status|switch|policy|keys|unlock|enroll|repo (all --json)
    loom-switchd/       # root daemon (python), polkit-activated D-Bus/varlink socket
    loom-watchdog/      # tiny static binary or python; run from OLD generation's store path
    loom-installer/     # TUI (python + gum), disk guard, capability probe, enroll
    flash-usb/          # python; removable-only guards
  templates/host/       # generic loom host template
  tests/                # nixosTests (§8)
    lib/silo-standin.nix
  docs/
```

Removed: `installer.nix` (dead), the inline Python auth/credential server, the `MOCK_APPROVED` tmpfile path, and the
`wheelNeedsPassword=false` default. The credential QR handoff from the MVP is dropped and is not replaced by anything that
moves tokens.

### 1.3 nuketown deltas (all additive; signi defaults unchanged)

```
nuketown/
  module.nix            # + persistRoot, sops.ageKey.{encryptedFile,keyFile}, gate impermanence on options ?,
                        #   extraHomeConfig → deferredModule, promptFragments, agents.<n>.sudo.switchPolicy
  approval-daemon.nix   # + prompter, display=null|":0", target, SIGN request kind
  broker/               # NEW python broker with SO_PEERCRED (replaces socat handler; same socket path)
  checks.nix            # + checks for new options, bypass regression test
```
Security fixes that are **prerequisites** for omanix:
- **N1** `sudoex-run` NOPASSWD bypass. sudoex-run must itself obtain a broker approval token as root, so a direct
  `sudo sudoex-run` without approval fails.
- **N2** Broker verifies the peer uid via `SO_PEERCRED`, so the user string can't be spoofed.
- **N3** Mock mode lives only in test builds (`nuketown.testing.mockApproval`), never as a runtime file.
- **N4** `nuketown-switch` removes the decrypted key on failure (trap).

### 1.4 seed/silo deltas

- **S1 owner handoff** (required). `git push -o silo.owner=<type> <blob>` is accepted only when the pusher's key equals
  the current `.owner_key`. post-receive atomically rewrites `.owner_key`. Also `-o silo.owner-reset` is accepted from any
  key currently in CODEOWNERS on master, with an audit line in `.owner_log`.
- **S2 path hardening** (C2): no `.`-prefixed components, no repo inside a repo, and depth ≤ 3.
- **S3 test module**: `seed.nixosModules.silo-standalone` (shell.nix + hooks.nix + git-http without the controller
  webhook) for use as the local silo stand-in in nixosTests.
- **S4 sk-key auth check**: confirm `sk-ssh-ed25519@openssh.com` blobs pass `AuthorizedKeysCommand` and the
  `.authorized_keys` grep. Add a test. Today this is **UNVERIFIED**.
- No private repos, no branch rename (host repos use `master`), and no HTTP push (we push over SSH only).

---

## 2. Flake interfaces

### 2.1 Inputs

| repo | inputs |
|---|---|
| loom | nixpkgs (nixos-unstable; CI matrix also 26.05), home-manager, disko v1.13, impermanence, sops-nix, nuketown (optional at module level), seed (tests only: `flake = true`, used only in `checks`) |
| omanix | loom (and `follows` for all of loom's inputs), omarchy (`github:omacom/omarchy?ref=v4.5.x`, `flake = false`), hyprland `v0.56.2` (`inputs.nixpkgs.follows`), quickshell (pinned rev `2b4501a…`, follows), hyprland-guiutils (follows) |
| host flake | **only** `omanix` (pinned to a release tag rev). Everything else is reached through omanix (`omanix.inputs.*`). |

The host lock is therefore a single trust decision: which omanix release tag. That is what makes Tier B possible.

### 2.2 Outputs

loom:
```nix
{
  lib = { mkHost; mkInstallerImage; sidecar = { schema; validate; toHostJson; };
          policy = { view; classify; }; settingsGuard; persistAudit; };
  nixosModules = { default; disk; boot; impermanence; secrets; silo; policy; switch; agent; firstboot; installer; };
  packages.<sys> = { loom-cli; loom-switchd; loom-watchdog; loom-installer; flash-usb;
                     installer-image;        # generic loom (no DE) image
                     installer-image-test; };# test-mode variant (sshd + scripted answers); NEVER released
  checks.<sys> = { … §8 … };
  templates.host = { path = ./templates/host; };
}
```
omanix:
```nix
{
  lib = loom.lib // { mkHost = args: loom.lib.mkHost (args // { flavor = self.nixosModules.default;
                                                               homeFlavor = self.homeModules.default; }); };
  nixosModules.default; homeModules.default; overlays.default;
  packages.<sys> = { omanix-cli; omarchy-src; installer-image; flash-usb; …custom pkgs… };
  apps.<sys> = { flash-usb; configure; verify-release; };
  catalogs.<sys> = { options-json; commands-json; keybinds-json; };   # generated, also in system closure
  checks.<sys> = { … };
  templates.host;
  nixosConfigurations.reference-desktop;   # CI-only reference host (precomputed cache base)
}
```

### 2.3 `mkHost`

```nix
# loom/lib/mk-host.nix
mkHost = {
  self,                    # the host flake
  flavor ? null,           # e.g. omanix.nixosModules.default
  homeFlavor ? null,
  system ? "x86_64-linux",
}:
let
  host     = lib.importJSON (self + "/host.json");          # schema-validated (lib.sidecar.validate)
  settings = loom.lib.settingsGuard {                        # data-only, prefix-checked
    dir = self + "/settings"; allowed = agentWritablePrefixes; };
  system'  = lib.optional (builtins.pathExists (self + "/system")) (self + "/system");  # free nix, Tier C
in {
  nixosConfigurations.${host.id} = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ loom.nixosModules.default flavor
                (loom.lib.hostJsonModule host)              # fixed mapping JSON → loom.*/omanix.* options
                settings.module
                (self + "/hardware.nix") ] ++ system';
    specialArgs = { loomHost = host; };
  };
  checks.${system} = { eval = …toplevel…; policy-view = …; };
};
```
Evaluation is pure: no IFD and no reads from `/etc`. The host id is a literal in `host.json`.

**settingsGuard** reads each `settings/*.nix` with `import`. The file must evaluate to an attrset, or to a function of
`{ lib, pkgs }` that returns one. It must not be a NixOS module function, so it has no `config`, `options` or `imports`.
The guard walks the leaf paths and throws `settings/apps.nix sets 'services.openssh' which is outside agent-writable
prefixes (omanix.theme, omanix.apps, …); move it to system/ (needs human signature)` for anything off the allowlist.
Values may be `mkDefault`/`mkForce` wrappers and packages.

---

## 3. Option tree (important options)

Conventions: every flavor default uses `mkDefault`. Every option has a `description`, and an `example` when its type is
non-trivial (enforced by a check). Enums are preferred over strings.

### 3.1 loom.*

```nix
loom.enable                          bool   false
loom.host.id                         strMatching "[0-9a-f]{32}"      # app-specific id; literal from host.json
loom.host.name                       hostname str
loom.host.user.name                  str
loom.host.user.fullName              str
loom.host.user.hashedPasswordSecret  str  "user/password-hash"       # sops key; neededForUsers
loom.host.humanKeys                  listOf (submodule { type = enum ["sk-ssh-ed25519" "ssh-ed25519" …]; key = str; hardware = bool; })
                                      # ≥1 asserted (decision 3)
loom.host.agentKeys.<name>           { ssh = str; }                    # public halves, written by installer

loom.disk.device                     str   # /dev/disk/by-id/…  (never /dev/sdX; asserted)
loom.disk.layoutVersion              int 1
loom.disk.swap                       enum ["zram" "zram+file"] "zram";  swapFileSize nullOr str
loom.disk.root.tmpfsSize             str "25%"
loom.disk.unlock.methods             listOf (enum ["passphrase" "fido2" "tpm2" "tpm2-pin" "recovery" "tang"])
                                      # "recovery" always present (asserted)
loom.disk.unlock.tpm2.pcrs           listOf int [ 7 ]
loom.disk.unlock.tpm2.requireSecureBoot  bool true   # tpm2 (no pin) ⇒ loom.boot.secureBoot.enable (asserted)
loom.disk.unlock.fido2.{clientPin,userPresence,userVerification} bool true true false
loom.disk.unlock.tang.urls           listOf str []   # advanced; servers only
loom.disk.unlock.finalizeOnFirstBoot bool  # set by installer when tpm2* chosen

loom.boot.loader                     enum ["limine" "lanzaboote"] "limine"
loom.boot.secureBoot.enable          bool false      # installer sets true when keys enrolled
loom.boot.secureBoot.includeMicrosoftKeys bool true  # option ROMs; never brick GPUs
loom.boot.maxGenerations             int 10

loom.persist.root                    str "/persist"
loom.persist.system.{directories,files}   listOf …   # each feature module appends its own
loom.persist.ephemeralOk             listOf str      # StateDirectories deliberately not persisted
loom.persist.snapshots.enable        bool true       # btrbk hourly/daily on @home and @persist (local)

loom.secrets.hostKey.backend         enum ["file" "tpm"] "file"           # H5
loom.secrets.hostKey.path            str "/persist/var/lib/loom/sops/host.age"
loom.secrets.recipients.host         str  # age1… or age1tag1… (installer-written literal)
loom.secrets.recipients.human        listOf str   # age-plugin-yubikey or age keys (optional)
loom.secrets.recipients.recovery     str  # offline recovery age recipient (installer)
loom.secrets.recipients.agents.<n>   str
loom.secrets.prompted.<name>         { description; target = secretName; validate = enum ["nonempty" "psk" "hash"]; }
                                      # first-boot prompts for secrets not available at install

loom.silo.enable                     bool true
loom.silo.host                       str "silo.loom.farm"
loom.silo.hostKey                    str "<pinned ed25519>"
loom.silo.path                       str "omanix/${loom.host.id}.git"
loom.silo.fetchUrl / pushUrl         derived
loom.silo.workingCopy                str "/persist/var/lib/loom/host"  # root-owned bare+worktree; agent clones it
loom.silo.gateBranchPrefix           str "gate/"

loom.trust.signers.human             derived from humanKeys → allowed_signers (namespace "git")
loom.trust.signers.agents.<n>        ssh pubkey (namespace "git")
loom.trust.signers.host              host ssh pubkey
loom.trust.releases.<input>          { signers = listOf str; refPattern = str "refs/tags/v*"; }
                                      # omanix/loom/nuketown release keys; baked into /etc/loom/release-signers

loom.policy.enable                   bool true
loom.policy.agentWritable            listOf str  # option-path prefixes Tier A may touch (flavor extends; protected)
loom.policy.extraProtected           listOf str  # option paths; can only grow without human sig
loom.policy.protectedRepoPaths       listOf str [".sops.yaml" ".authorized_keys" "CODEOWNERS" ".loom/" "system/" "hardware.nix" "flake.nix" "flake.lock"]
loom.policy.humanKeyKind             enum ["hardware" "software"] (derived)
                                      # software ⇒ human-session code paths become protected (§6.4)

loom.switch.watchdog.timeout         int 120
loom.switch.watchdog.checks          attrsOf (submodule { command; critical = bool; baselineOnly = bool true; })
loom.switch.confirmProtected         bool true    # Tier C needs a "Keep changes" click within timeout
loom.switch.autoUpdate               enum ["off" "notify" "stage"] "notify"   # never auto-switch desktops

loom.agent.enable                    bool true
loom.agent.name                      str "ada";  uid int 1100
loom.agent.harness                   str "claude-code"
loom.firstboot.enable                bool true
loom.installer.testMode              bool false   # only in installer-image-test; asserted false in release image
```

### 3.2 omanix.*

```nix
omanix.enable                         bool false   # mkHost with flavor sets true
omanix.release                        str          # read-only: the omanix tag this build is from
omanix.profile                        enum ["desktop" "server"] "desktop"
omanix.session.autologin              bool true    # asserted only if an unlock method has a human factor
omanix.session.displayManager         enum ["sddm" "greetd"] "sddm"
omanix.desktop.hyprland.package       package      # hyprland v0.56.2 from flake
omanix.desktop.hyprland.extraLua      lines ""     # appended user Lua (agent-writable iff humanKeyKind=hardware)
omanix.desktop.titlebars.enable       bool true
omanix.shell.package                  package      # quickshell pinned
omanix.shell.settings                 attrs {}     # → shell.json overrides
omanix.keybinds                       listOf (submodule { mods; key; description; action; }) # dup = assertion
omanix.keybinds.defaults.enable       bool true
omanix.theme.default                  enum <registry names> "tokyo-night"
omanix.theme.policy                   enum ["mutable" "pinned"] "mutable"
omanix.theme.available                listOf str (all)
omanix.theme.intros                   bool true
omanix.themes.<name>                  submodule { colors = attrsOf (strMatching "#[0-9a-fA-F]{6}"); backgrounds; overrides; trusted; unlock; }
omanix.boot.splash.theme              str config.omanix.theme.default   # plymouth/sddm rebuilt, not runtime
omanix.apps.<name>.enable             bool (defaults per omarchy base list)
omanix.webapps.<Name>                 { url; icon; bind ? null; mimeTypes ? []; }
omanix.tuis.<Name>                    { command; style = enum ["float" "tile"]; bind ? null; }
omanix.terminal                       enum ["foot" "alacritty" "ghostty" "kitty"] "foot"
omanix.fonts.monospace                str "JetBrainsMono Nerd Font"; fonts.cjkVariant enum [...]
omanix.input.{layout,variant,options,compose}   # initrd keymap derived; non-Latin → us at LUKS prompt
omanix.hardware.{gpu = enum ["intel" "amd" "nvidia" "nvidia-legacy" "none"]; isVM; laptop; profiles = listOf str;}
omanix.agents.default                 str "claude"
omanix.agents.harnesses.<n>           { enable; package; command; skillDirs; persist; theme.template; }
omanix.agents.isolation               enum ["user" "resident"] "resident"  # resident = nuketown user (safer)
omanix.region                         enum ["global" "cn"] "global"         # substituter mirrors only, never new trust
```

Agent-writable prefixes contributed by omanix: `omanix.theme`, `omanix.keybinds`, `omanix.apps`, `omanix.webapps`,
`omanix.tuis`, `omanix.terminal`, `omanix.fonts`, `omanix.input`, `omanix.shell.settings`, `omanix.desktop.hyprland.extraLua`*,
`omanix.agents.default`, `omanix.hardware.profiles`, `omanix.region`. Items marked * are code in the human session and
drop out of the list when `humanKeyKind = "software"` (§6.4).

---

## 4. Host flake template and sidecar schema

### 4.1 Host repo (`silo:omanix/<id>.git`, branch `master`)

```
flake.nix               # 10 lines: inputs.omanix.url = "git+https://silo.loom.farm/omanix.git?ref=refs/tags/v0.4.2";
                        #           outputs = { self, omanix }: omanix.lib.mkHost { inherit self; };
flake.lock              # omanix pinned to tag's rev (Tier B moves it)
host.json               # pure values (schema v1), machine-written; agent may edit the allowlisted keys
hardware.nix            # nixos-generate-config --show-hardware-config (protected: boot.*)
settings/               # agent-writable data files (Tier A)
  theme.nix  apps.nix  keybinds.nix  webapps.nix  input.nix  shell.nix
system/                 # optional free NixOS modules (Tier C, human-signed)
  default.nix
secrets/
  host.yaml             # recipients: host, human*, recovery
  user.yaml             # password hash, wifi PSKs; recipients: host, human*, recovery
  agents/<name>.yaml    # agent ssh key, agent API keys if user adds them; recipients: host, agent, human*, recovery
.sops.yaml              # protected
.authorized_keys        # silo push ACL: human key(s), host key, agent key   (protected)
CODEOWNERS              # human key(s), host key — NOT the agent key       (protected)
.loom/allowed_signers   # informational copy; the enforced copy is in the running system (H6)
CLAUDE.md               # generated: "this is <hostname>; edit settings/*; run `loom switch`; never edit system/ …"
```

The agent pushes only to `gate/*`. silo always accepts gate refs, and CODEOWNERS keeps the agent off `master`. The host's
`loom-switchd` fast-forwards `master` with the host key after a successful, policy-approved switch.

### 4.2 host.json (schema v1, generated from option types as JSON Schema)

```json
{
  "schema": 1,
  "id": "3f9c0a…32hex",
  "hostName": "kestrel",
  "user": { "name": "josh", "fullName": "Joshua Perry", "email": "josh@6bit.com" },
  "humanKeys": [ { "type": "sk-ssh-ed25519@openssh.com", "key": "AAAA…", "hardware": true } ],
  "locale": { "timeZone": "America/Denver", "lang": "en_US.UTF-8", "keymap": "us", "xkbVariant": "" },
  "theme": "tokyo-night",
  "disk": { "device": "/dev/disk/by-id/nvme-Samsung_…_S6ABC", "layoutVersion": 1, "swap": "zram" },
  "unlock": { "methods": ["fido2","passphrase","recovery"], "tpm2": null, "fido2": { "clientPin": true } },
  "secureBoot": { "enable": false },
  "secrets": { "hostRecipient": "age1…", "recoveryRecipient": "age1…", "humanRecipients": [] },
  "agents": { "ada": { "ssh": "ssh-ed25519 AAAA…", "age": "age1…" } },
  "hardware": { "gpu": "intel", "isVM": false, "profiles": ["framework-13-amd"] }
}
```
The `id` is minted at configure time with `systemd-id128 new` (128-bit random). It is not derived from a machine-id,
because the target doesn't exist yet. It is never a raw machine-id.

### 4.3 Sidecar (vfat partition `OMANIX-CFG`, written by flash-usb)

```
OMANIX-CFG/
  sidecar.json          # { schema:1, repo:{host,path,commit}, host: <host.json subset>, payload:{extraCache:bool} }
  host.bundle           # git bundle of the host repo at `commit` (offline install)
  enroll.key            # per-repo enrollment private key (ed25519). ONE purpose: first enrollment push.
  cache/                # optional extra nar.zst + narinfo for long-tail closures built by configure
  SHA256SUMS            # over all files above
```
**What the sidecar must never contain:** plaintext passwords, a user's personal SSH or GPG private keys, API keys, agent
logins or OAuth tokens. The validator rejects files matching known secret patterns (`-----BEGIN`, `sk-ant-`, `ghp_`,
`AKIA`, …) except `enroll.key`.

The password hash is not in the sidecar by default. The installer TUI prompts for the password locally and writes the
hash only into sops-encrypted `secrets/user.yaml`. The spec allows a pre-supplied hash, but the configure skill doesn't
offer it, because the hash would then exist on a second machine. **TRADE-OFF:** one more installer prompt.

The enrollment key is the only secret on the stick. It can push to exactly one repo that holds only public config. It is
spent at enrollment (S1 owner handoff, then removed from `.authorized_keys`) and shredded from the stick and from
`/persist`.

**Reinstall/test path:** no sidecar is needed. The kernel cmdline `omanix.repo=<id>` or a TUI prompt names the repo. The
installer clones it over public HTTPS, or from a local silo stand-in in tests. Pure values come from the repo's `host.json`.
Only the disk device and unlock are re-asked.

---

## 5. USB installer flow, end to end

### 5.1 Image build (`loom.lib.mkInstallerImage`)

`image.repart` raw GPT image, three partitions:

| # | Part | Format | Contents |
|---|---|---|---|
| 1 | ESP | vfat | Limine + kernel/initrd of the live system (UKI later) |
| 2 | store | erofs (zstd) + **dm-verity**; root hash on kernel cmdline | live system closure **+** `file://` binary cache (`nar/*.nar.zst`, `*.narinfo`, `nix-cache-info`) signed with `omanix-cache-1` |
| 3 | OMANIX-CFG | vfat, 256 MiB (grown by flash-usb to fill stick when `--extra-cache`) | sidecar |

- Live system: `minimal.nix` + `perlless` where possible, `all-hardware.nix`, broad `linux-firmware`, `gum`, `disko`,
  `sbctl`, `cryptsetup`, `systemd-cryptenroll`, `age`, `sops`, `ssh-keygen`, `git`, `nix`. No sshd. No network secrets.
- Cache content: `nixosConfigurations.reference-desktop` toplevel closure plus the **flake input sources** of the release
  (so `nix eval` of a host flake works offline), plus common GPU variants (nvidia open/legacy, intel media).
  Hardware-filtered firmware is staged at install. The full set stays substitutable.
- Size budget: a CI check runs `nix path-info -S` on the cache and fails above budget. `system.forbiddenDependenciesRegexes`
  blocks known bloat (duplicate LLVM, a second Mesa).
- Two variants: `installer-image` (offline, full closure) and `installer-image-net` (bootstrap of about 150 MB that
  substitutes over the network). Same code, different cache root.
- Release: `SHA256SUMS` of image files, signed with `ssh-keygen -Y sign -n omanix-release` by Josh's hardware key. Tag
  `vX.Y.Z` signed (`gpg.format=ssh`).

### 5.2 Configure skill (on the user's existing computer; agent holds the conversation)

1. Verify the omanix checkout: `scripts/verify-release.sh` (§5.9). Refuse on an unverified tree.
2. Gather pure values in conversation: hostname, user name and full name, timezone, keymap, theme, apps, GPU guess,
   and the **human key**. The skill offers in order:
   - an existing FIDO2 key: `ssh-keygen -t ed25519-sk -O resident -O verify-required`, recommended;
   - an existing ssh key pubkey;
   - generating `~/.ssh/omanix_<host>` (software key, passphrase required) and warning that it lowers the policy tier
     (§6.4).
3. `omanix configure --json` (script, not the agent) does the rest:
   - `systemd-id128 new` → id;
   - `ssh-keygen -t ed25519 -f enroll.key -N ''`;
   - render the template, `host.json` and `settings/*`;
   - `.authorized_keys = [human, enroll]`, `CODEOWNERS = [human]`;
   - commit signed with the human key if it can sign here (otherwise unsigned: the first commit is attested by the
     enrollment push);
   - `git push silo:omanix/<id>.git master` **with enroll.key**. silo auto-creates the repo, and `.owner_key = enroll`.
4. Optional local build: `nix build .#nixosConfigurations.<id>.config.system.build.toplevel`, then `nix copy --to file://…`
   only the paths missing from the release cache (`nix path-info` diff), giving `cache/`.
5. Write `sidecar.json` + `host.bundle`, then hand off to the build-installer skill.

### 5.3 flash-usb (script guards in code, not prompt)

`flash-usb --image <img> --sidecar <dir> [--device /dev/disk/by-id/usb-…]`
- Verify `SHA256SUMS.sig` against the pinned release signers (`~/.config/omanix/allowed_signers`, §5.9), then verify the
  image hash. Refuse on mismatch.
- Candidate devices: `TRAN=usb` **or** `/sys/block/X/removable == 1`, **and** not mounted, **and** no holders (`/sys/block/X/holders`
  empty: no dm/LVM/md/LUKS), **and** not swap, **and** not backing `/`, `/boot` or `/nix`, **and** size ≥ image size and
  ≤ 512 GiB (above that needs `--allow-large`, which still requires removable).
- Show vendor, model, serial, size and current partitions/labels. Confirmation needs **typing the last 4 characters of
  the serial**. `--yes` exists only together with `--device <by-id>` and `--expect-serial <serial>`, so an agent must
  have the exact serial from a human-visible listing.
- Write with `dd oflag=direct conv=fsync`, then **read back and hash** the written range.
- Grow and populate OMANIX-CFG, write `SHA256SUMS`, `sync`, eject.
- Exit codes are documented. `--json` progress output for agents.

### 5.4 Installer boot and TUI (deterministic, no agent)

```
boot → verity check (fail: "This USB stick is damaged or modified. Re-flash.") → loom-installer.service on tty1
 1. Welcome; keyboard layout (applies to console + becomes initrd keymap)
 2. Source:   [sidecar found on OMANIX-CFG]  or  [omanix.repo=<id> on cmdline]  or  prompt "Existing host id"
              → verify sidecar SHA256SUMS; verify bundle commit == sidecar.repo.commit
              → for reinstall: clone over network (git+https; TOFU-free: silo host key pinned in image)
 3. Network (optional for offline image; required for -net image or reinstall without bundle)
 4. Disk:     list non-removable disks ≥ 64 GiB, excluding the boot medium (by verity root device's parent);
              if sidecar names by-id and it exists → preselect; show model/serial/size/existing OS signatures
              (BitLocker, NTFS, other LUKS, ext4 with /etc/os-release → "Contains: Windows 11" etc.)
              confirm = type the hostname (and, if an OS signature was found, also the word ERASE)
 5. Capability probe (§5.5) → unlock choice screen with pros/cons → enroll factors
 6. Password: user login password (pwquality score shown); "use same for disk passphrase" offered when passphrase chosen
 7. Recovery kit: show LUKS recovery key + sops recovery identity (text + QR); require re-typing group 3 of each
 8. Summary → final confirm → install (progress, log to /mnt/persist/var/log/loom-install.log)
```

`loom.installer.testMode = true` (test image only) reads answers from `/dev/disk/by-label/OMANIX-TEST/answers.json`
and enables an sshd for the test driver. The release image asserts it is false, and the test image has a red banner and
a different `system.nixos.label`.

### 5.5 Unlock capability detection and choices

Probe (all non-destructive):
- **TPM2:** `systemd-analyze has-tpm2` (firmware + driver + sha256 bank); `/sys/class/tpm/tpm0/tpm_version_major`;
  fTPM vendor heuristic (`/sys/class/tpm/tpm0/device/description`, `tpm2_getcap properties-fixed` manufacturer `AMD`).
- **Secure Boot state:** `SecureBoot` and `SetupMode` efivars (`bootctl status`). Possible states are `off`,
  `on (vendor keys)` and `setup mode`.
- **FIDO2:** prompt "insert your security key now (optional)", then `systemd-cryptenroll --fido2-device=list`, and check
  the `hmac-secret` extension (`fido2-token -I`). Offer to enroll a second (backup) key.
- **Keyboard:** if the first XKB layout is non-Latin, show a warning that the LUKS prompt uses `us`.
- **Tang:** only when the sidecar provides URLs (advanced, servers).

Matrix and the text shown to the user (every method added is an *alternative*, so the disk is only as strong as the
weakest enrolled method, and this sentence is shown on the screen):

| Method | Available when | Pros (shown) | Cons (shown) | Default |
|---|---|---|---|---|
| **Recovery key** | always | Works if every other method is lost: dead TPM, lost key, forgotten passphrase, disk moved to a new machine. 256-bit random, so it can't be guessed. | You must store it offline (paper or password manager). Anyone holding it can unlock the disk. | **mandatory** |
| **Passphrase** | always | Works on any hardware and after moving the disk. Nothing to lose but your memory. | Can be watched or guessed. It's as strong as you make it (we require score ≥3). You type it every boot. | on, unless FIDO2 is chosen and the user removes it |
| **FIDO2 security key** (PIN + touch) | key with hmac-secret detected | The key can't be copied, and the PIN locks after a few tries. Theft of the laptop alone doesn't unlock it. Strongest everyday choice. | Lose the key and you need a backup key, passphrase or recovery key. Must be plugged in at boot. | **recommended** when detected; also prompts for a backup key |
| **TPM2 + PIN** | TPM2 detected | Short PIN, protected by the TPM's anti-hammering. The disk only unlocks in this machine. | A BIOS update or TPM clear (common on AMD fTPM) disables it, so you fall back to passphrase or recovery. The PIN can be shoulder-surfed. | offered |
| **TPM2 automatic** (no PIN) | TPM2 **and** Secure Boot can be enabled with our keys (Setup Mode) | No typing. Boots straight to the login screen, and the disk is unreadable outside this machine. | Anyone holding the laptop gets to the login screen, so your login password is the only barrier. A firmware change may require recovery. **Not offered without Secure Boot.** Autologin is disabled. | offered only in setup mode |
| **Tang (network)** | sidecar provides URLs | Unattended unlock on a trusted network. | Needs the Tang server reachable. For servers, not laptops. | hidden unless configured |

Rules enforced in code and in assertions:
- `recovery ∈ methods`.
- `tpm2 ∈ methods ⇒ loom.boot.secureBoot.enable`.
- `omanix.session.autologin ⇒ methods ∩ {passphrase, fido2, tpm2-pin} ≠ ∅`. TPM2 automatic is not a human factor.
- Any `tpm2*` choice also requires a passphrase or FIDO2 slot for the first boot (§5.7). The user may delete that slot
  later with `loom unlock remove passphrase`, which refuses if it would leave only TPM plus recovery while the TPM is
  fTPM-AMD, and warns otherwise.

### 5.6 Partitioning, FDE, install

1. **Generate disko config** from `host.json` (layout v1) via `loom.lib.diskoLayout`, a pure function with by-id device:
   ```
   GPT: ESP 1 GiB vfat /boot
        LUKS2 "cryptroot" (argon2id, allowDiscards, header ≥ 16 MiB for tokens)
          btrfs -L omanix:
            @nix         /nix          compress=zstd,noatime
            @persist     /persist      compress=zstd,noatime   neededForBoot
            @home        /home         compress=zstd,noatime
            @agents      /agents       noatime   (+ @agents-blank, read-only snapshot, via postCreateHook)
            @snapshots   /.snapshots   (btrbk targets)
            @swap        /swap         (only if zram+file)
   /  = tmpfs (size = loom.disk.root.tmpfsSize, mode 755)
   ```
2. LUKS is formatted with a **random 64-byte bootstrap keyfile** in `/run/loom/bootstrap.key` (tmpfs, 0400).
3. `systemd-cryptenroll` adds the chosen slots: `--recovery-key` (always), `--password`, `--fido2-device=auto
   --fido2-with-client-pin=yes` (×N keys). TPM2 is **not** enrolled here (§5.7).
4. **Wipe the bootstrap slot** (`systemd-cryptenroll --wipe-slot=<n>`), then verify with `cryptsetup luksDump` that
   only the expected token types remain. Abort with a clear message if not.
5. Secure Boot (only if SetupMode and the user opted in): `sbctl create-keys` into `/mnt/persist/var/lib/sbctl`, then
   `sbctl enroll-keys --microsoft`. Set `host.json.secureBoot.enable = true`. Failure is non-fatal: continue with SB off and
   downgrade `tpm2` to `tpm2-pin` with notice.
6. `nixos-generate-config --root /mnt --show-hardware-config > hardware.nix`, stripped of `fileSystems` (disko owns them).
7. **Keys generated on the target** (into `/mnt/persist`, never shown, never leave the machine):
   - host SSH ed25519: `/persist/etc/ssh/ssh_host_ed25519_key` (silo transport and host commit signing);
   - host sops age key (`file` backend) at `/persist/var/lib/loom/sops/host.age`, or `age-plugin-tpm --generate` for the
     `tpm` backend;
   - agent ssh ed25519 and agent age key. These are encrypted into `secrets/agents/<name>.yaml` (the agent home is
     ephemeral, so nuketown delivers them each boot) and also give the agent's sops identity;
   - **recovery age identity**: displayed in the recovery kit, recipient recorded, private half **never written to disk**.
8. **Secrets:** write `.sops.yaml`, then `sops -e` for `secrets/user.yaml` (password hash) and `secrets/agents/<n>.yaml`.
   Recipients are host + human* + recovery (+ agent for its own file).
9. Write `host.json` (device, unlock, recipients, agents, hardware), commit **signed with the host key**: "install:
   enroll host <name>".
10. Build: `nixos-install --flake /mnt/persist/var/lib/loom/host#<id> --option substituters "file:///run/loom/media/cache
    https://cache.nixos.org https://cache.omanix…" --option require-sigs true --no-root-passwd`. The order puts the file
    cache first, with network as fallback (spec), and signature checks stay **on**.
11. **Enrollment** (§5.8). Failure is non-fatal: it is queued for first boot.
12. Install Limine, sign with sbctl when SB is on, set the final boot order (`efibootmgr`: omanix first, USB removed from
    BootNext).
13. `shred -u` `enroll.key` on OMANIX-CFG (if enrollment completed), and also `host.bundle`/`sidecar.json` by default (the
    spec says "shred the sidecar"). Then `sync`, show the recovery reminder, and reboot.

### 5.7 First boot (loom.firstboot)

Ordered oneshots (each idempotent, with state in `/persist/var/lib/loom/firstboot/*.done`):
1. **unlock-finalize** (if `tpm2*`): the user unlocked with passphrase or FIDO2. With Secure Boot now in its final state,
   it runs `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 [--tpm2-with-pin=yes]`, verifies a test unseal, and
   records the slot in `/persist/var/lib/loom/unlock.json`. From the next boot on, unlock is automatic or PIN-based.
2. **enroll-retry** (if pending): network-online → §5.8 with `/persist/var/lib/loom/enroll.key` (0400 root). Shred on
   success.
3. **secrets-prompt**: for each `loom.secrets.prompted.<n>` missing from sops (for example Wi-Fi PSK, restic password),
   ask once on a themed TTY or graphical prompt, then sops-encrypt to the recipients and commit (Tier A for data-only
   secret files, §6.4).
4. **onboarding**: start the desktop and open a terminal with the agent (`omanix agent`). The agent harness asks the user
   to log in with its normal login flow on this machine. Nothing is pre-provisioned. The agent's first task is the
   `onboarding` skill: tour, check `loom status --json`, and confirm that the recovery kit is stored.

### 5.8 Enrollment (key separation)

```
installer/host (root)                       silo
  git push --push-option=silo.owner="<human key>" \
      ssh -i enroll.key  omanix/<id>.git master   ───►  pre-receive: pusher == .owner_key (enroll) ✓
      commit: .authorized_keys = [human…, host, agent]                       post-receive: copy .authorized_keys
              CODEOWNERS       = [human…, host]                               S1: .owner_key := human key
              (enroll key removed)
  verify: git ls-remote with host key ✓ ; push with enroll.key now fails ✓ (asserted, else warn + retry)
```
Who can do what afterwards:

| Key | Lives | silo master | silo gate/* | sops decrypt | git signature tier |
|---|---|---|---|---|---|
| human (YubiKey preferred) | with the human | yes (owner + CODEOWNERS) | yes | if age-plugin-yubikey recipient | A, B, C |
| host ssh | `/persist/etc/ssh` (root) | yes (CODEOWNERS) | yes | no (separate key, H5) | records switches; never authorizes C |
| host age | `/persist/var/lib/loom/sops` (root) | — | — | host/user/agents files | — |
| agent ssh/age | sops → `/agents/<n>/.ssh` | **no** | yes | own file only | A, B |
| recovery age | paper | — | — | all files | — |
| enroll | spent | no | no | — | — |

Nothing off the machine holds write access except the human (spec point 4: the human is the intended exception).

### 5.9 Signed release tags and script self-verification

- Release signers: Josh's hardware-key SSH signing key(s), published on silo (`omanix/release/allowed_signers`), on
  github and in the README, with the fingerprint printed in docs.
- `scripts/*.sh` start with a fixed 30-line preamble (identical in every script, checked by CI):
  1. locate the repo root;
  2. require `~/.config/omanix/allowed_signers` (the **user-pinned** anchor). If it is missing, print the fingerprint of
     `release/allowed_signers` and the URLs where it's published, and require the human to type `trust <fingerprint>`.
     This is a TOFU pin, and it is stored outside the repo;
  3. `git verify-tag $(git describe --exact-match)` with `gpg.ssh.allowedSignersFile` = pinned file, **or** verify
     `scripts/SHA256SUMS.sig` (namespace `omanix-release`) and `sha256sum -c` over `scripts/` and `pkgs/`;
  4. refuse to run on a dirty tree or on an untagged commit unless `OMANIX_DEV=1` is set, which prints a red banner on
     every run;
  5. `exec nix run .#<tool> -- "$@"`. The real logic is a Nix-built package, so the shell wrapper stays tiny.
- **Honest limit:** self-verification catches tampered or accidentally modified checkouts and stale forks. It can't
  protect a user who pins an attacker's key. The pin step shows the published fingerprints to make that unlikely.
- On installed hosts, `loom.trust.releases.omanix.signers` is baked into `/etc/loom/release-signers` and used by
  `omanix update` (§6.6).

---

## 6. Runtime

### 6.1 Impermanence layout

`/` is tmpfs. `/nix`, `/persist`, `/home` and `/.snapshots` are btrfs subvolumes. `/agents` is reset from `@agents-blank`
in initrd (nuketown rollback, extended to delete nested subvolumes recursively and keep `@agents-prev` for one boot of
forensics). `/tmp` is tmpfs. Nix build TMPDIR is `/var/cache/nix` (persisted, signi pattern).

**Persist list** (each feature module contributes its own entries; `loom.persist.system`):
```
files:  /etc/machine-id
        /etc/ssh/ssh_host_ed25519_key{,.pub}
dirs:   /var/lib/nixos               (uid/gid stability)
        /var/lib/loom                (host repo working copy, sops host key, firstboot state, unlock.json, policy log)
        /var/lib/sbctl               (secure boot keys; if enabled)
        /var/lib/systemd/{coredump,timers,backlight,rfkill}
        /var/log
        /var/cache/nix
        /etc/NetworkManager/system-connections   /var/lib/NetworkManager
        /var/lib/bluetooth  /var/lib/fprint  /var/lib/cups  /var/lib/upower
        /var/lib/docker (if docker)  /var/lib/tailscale (if)  /var/lib/alsa
        /root
agents: nuketown per-agent persist (projects, .claude, .claude.json)   (user-level, under /persist/agents/<n>)
home:   whole /home on @home (H2)
```
**Correctness machinery:**
- **Eval-time StateDirectory audit** (`loom.lib.persistAudit`): for every enabled `systemd.services.*` with
  `serviceConfig.StateDirectory`, assert that `/var/lib/<dir>` is persisted or listed in `loom.persist.ephemeralOk`. The
  message names the option to set. This catches the classic "enabled a service, lost its state" bug before any boot.
- **`/persist` neededForBoot**, and impermanence `hideMounts`.
- **machine-id**: the VM test asserts that it is stable across reboots and that `/var/log/journal/<id>` continues.
- **VM test `impermanence-survives-reboot`** (§8) writes sentinel files in persisted and non-persisted locations, reboots,
  and asserts which survive. It also runs a "what was written outside persist" diff after a desktop session against an
  allowlist and fails on any unknown path under `/var/lib` or `/etc`.
- **Snapshots** (`loom.persist.snapshots`): btrbk hourly snapshots of `@home` and `@persist` into `@snapshots`, kept as
  `24h 7d 4w`. This is the local undo for user data. Off-machine backup (restic plus sops creds) is a separate optional
  module.

### 6.2 Mutable vs declarative state

| State | Where | Owner |
|---|---|---|
| System config | host repo → generation | declarative (policy-gated) |
| Dotfiles (`~/.config/hypr/*`, shell.json defaults, terminals) | HM read-only links | declarative |
| User overrides that omarchy supports (`~/.config/omarchy/*` user stubs, `shell.json` user layer) | `/home` | mutable, persisted, reported by `omanix doctor --drift` |
| Current theme, background, toggles, workspace layouts | `~/.local/state/omarchy/` (path kept for upstream compatibility) | mutable, persisted |
| Secrets | sops in repo → `/run/secrets` | declarative (encrypted) |
| LUKS slots, TPM seal | disk header | imperative via `loom unlock …`, recorded in `/persist/var/lib/loom/unlock.json` and mirrored into `host.json.unlock` via a Tier C commit |
| Agent home | `/agents/<n>` (wiped) + persisted subdirs | nuketown |

### 6.3 Desktop (Quattro) in brief

- `omarchy-src`: upstream tree pinned (4.5 line). `substituteInPlace` rewrites `/usr/share/omarchy` → `$out`, the
  titlebars `.so` path, and `/usr/bin/<tool>` → bare names. Also `patchShebangs`, and patch `default/bash/env-bootstrap`
  so it doesn't reset `OMARCHY_PATH`. pacman/yay scripts are replaced or dropped by an explicit table. A **build check**
  greps `$out` for surviving `/usr/(share|lib|bin)/` and fails.
- `OMARCHY_PATH` is set in the uwsm env, the systemd user env and `/etc/profile`. Hyprland v0.56.2 is built from its flake,
  and titlebars use `mkHyprlandPlugin` against **the same** hyprland derivation. quickshell is pinned. uwsm session, SDDM
  (or greetd) with autologin gated by the unlock assertion.
- Config: HM writes `~/.config/hypr/hyprland.lua` (stub) plus `hypr/{bindings,input,looknfeel,monitors,autostart}.lua`
  generated from `omanix.keybinds` and related options. `misc.disable_autoreload = true` and a single `hyprctl reload`
  after HM `linkGeneration` (omarchy's alpm pause/resume equivalent).
- Quickshell is the polkit agent, lock, notifier and OSD. No polkit-gnome, mako or waybar. D-Bus services are enabled:
  NetworkManager, bluez, upower, power-profiles-daemon, pipewire.
- **Theme switching**: the registry builds one derivation per theme with omarchy's `current/theme` layout (pure
  `.tpl` render). `~/.local/state/omarchy/current/theme` is a **symlink through the per-user profile path** (GC-safe), and
  the switch is atomic (`ln -sfn tmp && mv -T`). HM activation reconciles: if the link is dangling or names an unknown
  theme, it resets to `omanix.theme.default`. With `pinned`, it always resets. Retint hooks are data-driven
  (`omanix.theme.reloadHooks.<app>`). Plymouth/SDDM/Limine colors are **declarative only**, so they change on rebuild. The
  browser theme color uses a root path unit from a user spool **or** stays theme-independent (default:
  theme-independent, no runtime root writes). **TRADE-OFF:** the browser toolbar color doesn't follow the theme live.
- Approval UI: nuketown approvalDaemon with `display = null`, `target = graphical-session.target`, and a prompter that is
  a Quickshell IPC card (zenity fallback). Hyprland rules float, pin and focus the dialog.

### 6.4 Protected-option policy diff

**Projection** (`loom.lib.policy.view`, in loom, pinned by a release tag): `system.build.policyView` is a canonical JSON
file inside the toplevel. It contains:
```
users.users.<n>.{uid,group,extraGroups,isNormalUser,shell,hashedPasswordFile,openssh.authorizedKeys,linger}
users.groups.{wheel,…}.members ; users.mutableUsers ; users.users.root.*
security.{sudo,sudo-rs,doas}.* (extraRules, extraConfig sha, wheelNeedsPassword) ; security.polkit.extraConfig sha
security.pam.services.<n>.text sha ; security.wrappers (names, owner, setuid, source) ; security.tpm2.*
nix.settings.{trusted-users,allowed-users,substituters,trusted-substituters,trusted-public-keys,require-sigs,sandbox}
services.openssh.{enable,ports,settings,listenAddresses} ; networking.firewall.* (enable, ports, ranges, interfaces, extraCommands sha, trustedInterfaces)
boot.{loader.*, kernelParams, initrd.luks.devices, initrd.systemd.services (names + ExecStart sha), kernelModules, blacklistedKernelModules, initrd.network.*}
systemd.services.<n> where User∈{root,null} : {name, wantedBy}  (adding/removing a root unit is protected; content changes of upstream-pinned units are not)
loom.{host.humanKeys, host.agentKeys, trust.*, policy.*, secrets.recipients.*, disk.unlock.*, boot.secureBoot.*, silo.*, switch.*}
nuketown.{humanUser, agents.<n>.{uid, sudo, devices, extraGroups}}
virtualisation.docker.enable + docker group members ; hardware.*.extraGroups-like grants (i2c, video, input)
```
**Classification** (`loom policy classify <old-gen> <new-commit>` inside loom-switchd):
1. Build the new toplevel (in the daemon's sandbox, as root via nix-daemon).
2. `paths_changed = git diff --name-only <deployed-commit>..<new-commit>`.
3. `view_diff = jsondiff(old_gen/policy-view.json, new/policy-view.json)`. The **path list comes from the old view**:
   a path present in old and missing in new counts as changed (H6).
4. Tier:
   - **A**: `paths_changed ⊆ {settings/**, secrets/user.yaml (data keys only), host.json allowlisted keys}` and
     `view_diff = ∅`.
   - **B**: `paths_changed = {flake.lock}`, and the only lock node changed is `omanix`, whose new rev is a commit pointed
     to by a tag matching `loom.trust.releases.omanix.refPattern` that verifies against
     `/etc/loom/release-signers` (old system), and `view_diff` ⊆ "upstream default changes".
     Upstream default changes are view paths whose definitions all come from omanix/loom store files. That is checked
     via a `definitionsWithLocations` summary emitted into the view: `{path: [files]}`, where file prefixes are
     upstream input store paths.
   - **C**: everything else, including any `system/**`, `hardware.nix`, `.sops.yaml`, `.authorized_keys`, `CODEOWNERS`,
     `flake.nix`, any `view_diff` entry defined by a host file, and any new lock node.
5. Signature requirement: the commit range must be signed. Every commit by an agent, human or host key works for A and B.
   For **C**, the tip commit must carry a signature by a **human** key from the old system's allowed_signers. The
   human's signature covers the whole range.
6. **humanKeyKind = software** (no hardware human key): options that execute code in the human session
   (`omanix.desktop.hyprland.extraLua`, `omanix.tuis.*.command`, `omanix.webapps.*.exec`, `home-manager.users.<human>.*`)
   are removed from `agentWritable`, so they become Tier C. A software human key in the human's ssh-agent could
   otherwise be driven by code the agent planted in the human session. **TRADE-OFF:** without a YubiKey, the agent needs a
   click for more things.

**Human signing gesture:** for Tier C, loom-switchd sends a `SIGN` request to the nuketown broker (new request kind). The
dialog shows the commit summary and the protected view diff (rendered human-readable, for example "adds user `ada` to
group `docker` — grants root-equivalent"). On Approve, the broker (running as the human) runs `git commit --amend -S` or
`ssh-keygen -Y sign` with the human key. A YubiKey asks for touch, and that touch is the approval. If there's no broker
(server profile), `loom switch` prints the commit id and the human signs from anywhere and pushes to `gate/`.

Explain command: `loom policy explain [<commit>] --json` gives the tier, reasons, view diff and the required signer.
Agents run it before asking for approval.

### 6.5 Switch, watchdog, rollback

```
loom switch [--commit <sha>|--gate <branch>] [--dry]
  (client, any allowed user; polkit action org.loom.switch: agent + human allowed without password)
loom-switchd (root):
  1 lock /run/loom/switch.lock ; fetch commit into /persist/var/lib/loom/host (from agent's working copy or silo gate/*)
  2 verify signatures + classify (§6.4); C ⇒ SIGN request ⇒ wait (timeout = reject)
  3 build toplevel; nvd diff → stored in /persist/var/lib/loom/switches/<n>/
  4 baseline health snapshot (run checks NOW; record which pass)
  5 spawn watchdog as transient unit FROM THE OLD GENERATION's store path:
      systemd-run --unit=loom-watchdog-<n> --property=… <old>/bin/loom-watchdog --deadline 120 --prev <old> --new <new>
  6 <new>/bin/switch-to-configuration test        # NOT boot: bootloader default untouched
  7 watchdog loop (every 5 s until deadline):
      checks (default): system reached multi-user/graphical; no new failed units vs baseline;
                        NM connectivity ≥ baseline; human session: Hyprland + omarchy-shell alive (desktop);
                        silo reachable with host key (if it was at baseline); loom-switchd responsive
      Tier C (confirmProtected): plus "Keep these changes?" shell dialog — needs a human click
  8a pass  → nix-env -p /nix/var/nix/profiles/system --set <new>; <new>/bin/switch-to-configuration boot;
             git update-ref master <sha>; push master with host key (queued if offline); log
  8b fail/timeout/crash of switchd → watchdog runs <old>/bin/switch-to-configuration switch;
             records failure + journal excerpt; pushes refs/heads/gate/rejected/<sha>; notifies human + agent
```
Properties:
- **Rollback by default.** Nothing reaches the boot default until health passes. A crash or power loss mid-test boots the
  previous generation.
- The watchdog code comes from the **old** generation, so a broken new config can't disable its own rollback.
- Baseline-relative checks: failures that were already present don't cause rollbacks. This avoids flapping on hosts with
  a pre-existing failed unit.
- `loom.switch.autoUpdate`: `notify` (default) or `stage` (build ahead, switch on user click). There is no auto-switch on
  push for desktops (spec).
- `loom rollback` = switch to the previous generation through the same pipeline (Tier A: rollback to a previously
  deployed and recorded commit is always allowed) + `git revert` commit.

### 6.6 Update

`omanix update` (also the Update menu item and the agent's `update` skill):
1. `git ls-remote --tags git+https://silo…/omanix.git 'v*'` → newest tag ≥ current on the same channel (stable or rc).
2. Fetch the tag object and `git verify-tag` with `/etc/loom/release-signers` (the old system's trust).
3. `nix flake lock --override-input omanix git+https://…?ref=refs/tags/vX&rev=<rev>`, then commit (agent-signed),
   giving Tier B. Then `loom switch`.
4. A tag that fails verification aborts with an explanation and a pointer to `release` docs. It never falls back to an
   unsigned rev.

### 6.7 Script guards (general rules for every loom/omanix tool)

- Destructive tools (`loom-disk-apply`, `flash-usb`, `loom unlock remove`, `loom keys rotate`, `omanix reset`) take
  `--dry-run`, print a plan as JSON, and require an **out-of-band confirmation**: a TTY-typed token (serial, hostname or
  `ERASE`), or a broker approval for host tools. No `--force` bypasses device-class checks.
- They only act on `/dev/disk/by-id/*` paths resolved once and re-checked (major:minor, serial) right before the write
  (TOCTOU).
- Every write is logged to `/persist/var/log/loom/<tool>.log` (or `~/.local/state/omanix/log/` on the configuring
  computer).
- `writeShellApplication` + shellcheck for any shell. Python tools have pytest in `checks`.

### 6.8 Reinstall and key rotation

**Reinstall (same repo id; decision 3):**
1. Boot the USB with `omanix.repo=<id>` (or the prompt). The installer clones the repo publicly and shows hostname, user
   and last commit for confirmation.
2. Disk and unlock flow as for a new install, with new LUKS. New host ssh, host age and agent keys are generated.
3. **Re-encrypt secrets:** the installer needs a current recipient's identity. In order:
   - human YubiKey (`age-plugin-yubikey`, prompted);
   - typed **recovery identity** from the recovery kit;
   - neither available: secrets are **dropped** and listed for the first-boot `secrets-prompt`. The user password is
     re-prompted in the TUI anyway.

   Then `sops updatekeys` swaps the old host and agent recipients for the new ones and keeps human + recovery.
4. **Authorize the new keys on silo:** commit with `.authorized_keys`/CODEOWNERS replacing the old host and agent keys,
   signed **and pushed with a surviving human key** (YubiKey `ed25519-sk` works through ssh in the installer), giving the
   human-authorized in-place update.
5. **No surviving human key** gives a fork: mint a new id, push the tree as a new repo with an ephemeral enrollment key,
   hand ownership (S1) to a **new** human key that the user creates at that point (FIDO2 recommended). Set
   `host.json.forkedFrom = <old id>`. The old repo stays as an orphan. A human can later `-o silo.owner-reset` it if
   they regain a CODEOWNERS key.
6. The new recovery kit is shown. The old recovery identity stays a recipient until the user runs
   `loom keys rotate recovery`.

**Rotation commands** (all produce Tier C commits, human-signed; all `--json`):
- `loom keys list` shows every key with location, fingerprint, powers and last-used time.
- `loom keys rotate host`: new ssh + age keys, `sops updatekeys`, `.authorized_keys` swap, push, then shred the old ones
  after a successful switch.
- `loom keys rotate agent <n>`: same, for the agent. It also re-runs the nuketown secret delivery.
- `loom keys rotate recovery`: new recovery identity shown once, `sops updatekeys` removes the old one, and LUKS
  `--wipe-slot=recovery` + `--recovery-key` in the same transaction (old slot wiped only after the new one is verified).
- `loom keys add-human <pubkey>` / `remove-human <fp>`. Removing the last hardware key asks for confirmation and
  downgrades `humanKeyKind`.
- `loom unlock {status,add,remove,reseal}`: LUKS slot management with a "never leave fewer than 2 independent methods
  incl. recovery" guard. `reseal` re-enrolls TPM2 after a firmware update (needs another factor).

---

## 7. Agent surfaces

- **Host repo `CLAUDE.md`** (generated, Tier C to change by hand):
  - what the host is (id, silo URL, release);
  - "edit `settings/*` only; run `loom policy explain` then `loom switch`";
  - "never edit `system/`, `.sops.yaml`, `.authorized_keys`, `CODEOWNERS`, `hardware.nix` without asking the human";
  - "never run disk tools";
  - pointers to the catalogs.
- **omanix repo `AGENTS.md`**: router covering the layering, file==option rule, mkDefault rule, how to add a
  module/theme/app/keybind, `nix flake check` as the single gate, test etiquette, and the release process.
- **Skills** (shipped in the system closure, linked into every harness `skillDirs` by HM):
  - `omanix` (customize: settings files and options, generated table of agent-writable options);
  - `onboarding`, `update`, `add-secret` (sops into `secrets/user.yaml` with existing recipients), `diagnose-crash`,
    `diagnose-unit`, `diagnose-build`;
  - `recover` (unlock and secret recovery procedures), `rotate-keys`, `reinstall` (USB with repo id).
  - Pre-install: `configure` and `build-installer` in the omanix repo (spec).
- **Catalogs (generated, in closure, `--json`):**
  - `/run/current-system/sw/share/omanix/options.json` (nixosOptionsDoc of `loom.*` and `omanix.*` with declaring file
    and an `agentWritable: bool` flag);
  - `commands.json` (every `omanix`/`loom` subcommand: args, exit codes, `destructive`, `needsHuman`);
  - `keybinds.json`, `themes.json`, `persist.json`, `policy-view.json` (current).
- **Introspection commands:**
  - `omanix options [q]`, `omanix where <opt>`, `omanix get <opt>` (pre-dumped `config.omanix` JSON);
  - `omanix doctor [--drift]`;
  - `loom status` (generation, deployed commit, ahead/behind silo, pending enrollment, unlock methods, SB state, persist
    gaps, sops decryptability);
  - `loom policy explain`, `loom keys list`, `loom unlock status`.
  - All support `--json`, need no TTY and return stable exit codes.
- **Agent isolation:** `omanix.agents.isolation = "resident"` (default) runs the agent as the nuketown user `ada`. It
  edits a clone of the host repo in `~/projects/host`, pushes to `gate/*`, and calls `loom switch`. It has no
  password-less sudo.

---

## 8. Testing (`nix flake check` = single gate)

Pure checks (fast):
- `eval-*`: reference hosts (desktop intel, desktop nvidia, server, VM).
- `options-documented` (description + example).
- `keybind-dupes`.
- `no-usr-paths` (omarchy-src grep).
- `persist-audit` (StateDirectory coverage).
- `policy-view-golden`: projection of the reference host matches the checked-in golden. Diffs need review.
- `policy-classify-cases`: table-driven unit tests. Theme change → A. Lock bump to a signed tag → B. Unsigned rev → C.
  Removing a protected path from the view → C. `settings/` setting `services.openssh` → eval error.
- `settings-guard` negative fixtures.
- `sidecar-schema` + secret-pattern rejection.
- `closure-budget` (installer cache size, forbidden deps).
- `script-preamble-identical`.
- `shellcheck`/`pytest` (loom-cli, switchd, installer, flash-usb with a fake sysfs tree: refuses non-removable, mounted,
  holder-backed, and oversize devices).

nixosTests (VM):

| Test | Asserts |
|---|---|
| `desktop-boots` | SDDM autologin → uwsm → Hyprland 0.56 + omarchy-shell up on virtio-gpu; `hyprctl configerrors` empty; screenshot. This also settles the UNVERIFIED Qt 6.12/quickshell and Mesa questions. |
| `theme-switch` | `omanix theme set catppuccin`, symlink target, reboot, still set; `pinned` policy resets. |
| `impermanence-survives-reboot` | persisted sentinel survives, tmpfs sentinel gone, machine-id stable, `/agents` reset, `@agents-prev` exists, unexpected-write audit. |
| `fde-passphrase` / `fde-fido2` (canokey) / `fde-tpm2-pin` (swtpm) / `fde-recovery` | systemd-initrd unlock per method. Recovery key unlock works after the TPM is cleared (swtpm state wiped). |
| `fde-tpm2-requires-sb` | eval assertion fires without SB. With limine SB (test keys), TPM2 auto-unlock works. |
| `sops-host-key` | file backend decrypt at boot. **`sops-tpm-age1tag`** settles the UNVERIFIED age1tag round trip. If it fails, the `tpm` backend is marked experimental. |
| `installer-e2e` | 3 nodes: `silo` (seed `silo-standalone`, S3), `target` (empty disk, swtpm, OVMF), `installer-image-test` attached as a USB disk + OMANIX-TEST answers. Flow: configure script on a driver node creates repo `omanix/<fixed test id>` **on the local stand-in** → install → reboot target → unlock → desktop up → `git ls-remote` shows enrollment commit → push with enroll key **fails** → `.owner_key` == human test key. |
| `installer-reinstall` | same silo repo; `omanix.repo=<id>` on cmdline; human test key (software, in answers) authorizes the in-place key swap; old host key no longer in `.authorized_keys`; secrets re-encrypted via the recovery identity. |
| `installer-fork` | no human key → new id minted, `forkedFrom` set. |
| `switch-watchdog` | agent commits a settings change (A) → switched + promoted. Commit that breaks Hyprland → watchdog rolls back, boot default unchanged, `gate/rejected/<sha>` exists. Kill switchd mid-test → rolled back. |
| `policy-enforcement` | agent commit adding `ada` to wheel via `system/` → switchd demands SIGN. Mocked broker denies → not applied. Approves (human test key) → applied. Agent attempts `sudo switch-to-configuration` → broker prompt shows the "bypasses policy" banner. |
| `nuketown-sudoex-bypass` | direct `sudo sudoex-run id` as agent fails (N1). |
| `flash-usb-guards` | VM with a virtio "non-removable" disk + a usb-storage disk: only the usb one is offered; mounted usb is refused; readback verify catches an injected bit flip. |
| `verity-corruption` | flip a byte in the store partition → installer refuses with the "damaged" message. |

**Tests never touch silo.loom.farm.** The `loom.silo.host` default is overridden in all test hosts, and an assertion in
`installer-image-test` fails if any `*.loom.farm` host appears in its config.

---

## 9. Work breakdown (ordered; each package builds and tests on its own)

| # | Package | Repo(s) | Scope / files | Deps | Acceptance |
|---|---|---|---|---|---|
| P1 | **nuketown security + additive options** | nuketown | N1–N4; `persistRoot`, `sops.ageKey.*`, impermanence gating, deferredModule `extraHomeConfig`, approvalDaemon `prompter/display/target`, python broker with SO_PEERCRED and `SIGN` kind | — | existing checks + new bypass/peercred/SIGN tests pass; mynix signi `nix build` unchanged (nvd diff empty except broker pkg) |
| P2 | **silo deltas** | seed | S1 owner handoff, S2 path hardening, S3 `silo-standalone` module, S4 sk-key test | — | nixosTest: create → handoff → enroll key rejected; sk key push works |
| P3 | **loom skeleton + identity + nix settings** | loom | new flake layout, `lib/mk-host.nix`, `settings-guard`, `host.json` schema → options, templates/host, channel matrix | P1 (lock bump) | `nix flake check` evals template host on unstable and 26.05; guard negative fixtures |
| P4 | **disk + unlock + boot** | loom | `modules/disk/*`, `boot/*` (limine, SB via sbctl), `diskoLayout` fn, unlock assertions, recovery | P3 | `fde-*` tests, `fde-tpm2-requires-sb` |
| P5 | **impermanence + persist audit + snapshots** | loom | `modules/impermanence/*`, `lib/persist-audit.nix`, nuketown `@agents` rollback w/ nested delete (upstream to nuketown as option) | P3, P1 | `impermanence-survives-reboot`, audit assertion fixtures |
| P6 | **secrets lifecycle** | loom | host key backends, recipients, `.sops.yaml` render, prompted secrets, `loom keys` CLI (list/rotate/add-human) | P3, P5 | `sops-host-key`, `sops-tpm-age1tag`, rotation unit tests |
| P7 | **policy view + classify + trust** | loom | `lib/policy-view.nix`, `modules/policy/*`, `trust/*`, `loom policy explain` | P3 | golden + classify case tables |
| P8 | **switchd + watchdog** | loom | `pkgs/loom-switchd`, `pkgs/loom-watchdog`, polkit action, broker SIGN integration, silo push of master | P7, P1 | `switch-watchdog`, `policy-enforcement` |
| P9 | **installer image + TUI + enrollment** | loom | `mkInstallerImage` (repart + verity + cache), `loom-installer` (probe, matrix UI, disko apply, cryptenroll, keys, sops, enroll), firstboot units, test-mode variant | P2, P4, P5, P6 | `verity-corruption`, `installer-e2e`, `installer-reinstall`, `installer-fork` (with generic loom host) |
| P10 | **omarchy-src + custom packages** | omanix | `pkgs/omarchy-src`, titlebars (mkHyprlandPlugin), quickshell pin, owe/ttfx/oma* apps, hyprland-guiutils | — | `no-usr-paths`; each pkg builds; titlebars loads in VM |
| P11 | **omanix desktop modules (system + HM)** | omanix | `modules/nixos/desktop/*`, `modules/home/{hyprland,shell,terminals}`, keybinds typed, session/autologin assertion, approval UI wiring | P10, P3 | `desktop-boots`, `keybind-dupes` |
| P12 | **themes + boot visuals** | omanix | registry from upstream `colors.toml`, `.tpl` renderer, state symlink + reconcile, retint hooks, plymouth/sddm/limine theme derivations | P11 | `theme-switch`; golden renders for 3 themes |
| P13 | **agent surfaces + CLI + catalogs** | omanix, loom | `omanix` CLI (options/where/get/doctor/theme/update), catalogs, skills, generated CLAUDE.md/AGENTS.md, agent registry + resident isolation | P8, P11 | catalogs validate against JSON Schema; `omanix update` test with a locally signed tag (B) vs unsigned (refused) |
| P14 | **configure + build-installer skills, flash-usb, release** | omanix, loom | `scripts/*` preamble, `flash-usb` guards, configure script (id mint, enroll key, push), release signing, reference-desktop cache, closure budget | P9, P13 | `flash-usb-guards`, `installer-e2e` re-run with the **omanix** flavor image, `closure-budget`, `script-preamble-identical` |

Parallelism: P1, P2, P3 and P10 start immediately. P4–P7 start after P3. P11 follows P10. P8 needs P7. P9 needs P2 and
P4–P6. P12 follows P11. P13 and P14 come last.

---

## 10. Trade-offs and open items

- **Agent speed vs safety:** Tier C for any free-form Nix and, without a hardware human key, for human-session code.
  Expect the agent to ask more often. The mitigation is to grow `agentWritable` typed options so common requests stay
  Tier A.
- **Root code execution is inherent:** the policy diff protects authority grants (users, sudo, trust, network exposure,
  boot), plus structure such as new root units and free-form Nix via Tier C. A Tier A change can't add root code because
  settings are data-only under agent-writable prefixes. That holds only as long as no agent-writable option feeds a root
  context. **Every new agent-writable option needs a review flag in its declaration** (`loom.policy.agentWritable` changes
  are protected, and the omanix check `agent-writable-review` lists them with justification strings).
- **Unstable channel** until 26.11, accepted for one Mesa/Qt stack (H1).
- **Secure Boot** depends on the firmware entering Setup Mode. Many users will run SB off with FIDO2 or a passphrase,
  which is fine. TPM-automatic is unavailable to them (H4).
- **PCR policy (spec open question):** LUKS TPM uses PCR 7 only, with SB on our keys. pcrlock and signed PCR 11 policies
  are future hardening (they need UKIs, so lanzaboote). The host age key has no PCR policy (chip-bound only, and opt-in).
- **Protected list location (spec open question):** upstream in loom, pinned by the release tag. Hosts can only add
  (`extraProtected`), and both adding and removing are themselves protected.
- **Seed-side builder (spec open question):** not in v1. Local Nix, or WSL2 on Windows, does the build. The design keeps
  the "commit X of repo Y" contract, so a builder can be added later without changing the installer.
- **UNVERIFIED, gated by tests:**
  - age1tag sops round trip (`sops-tpm-age1tag`);
  - sk-key auth on silo (P2);
  - quickshell on Qt 6.12 (`desktop-boots`);
  - Limine SB plus TPM PCR 7 stability across generations (`fde-tpm2-requires-sb`);
  - `@agents` nested-subvolume delete.
