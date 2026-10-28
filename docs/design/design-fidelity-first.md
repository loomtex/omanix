# omanix architecture: fidelity-first design

Rev 1, 2026-10-27. Authors: Ada, Joshua Perry.
Inputs: spec.md rev 16 (authoritative), design/facts.md, understand/*.md.
Angle: **faithful omarchy 4 "Quattro" UX and cheap upstream tracking.** omarchy is consumed as a pinned flake input, patched as little as possible, and nix owns only the *default layer* that omarchy already exposes for distribution packagers.

Out of scope, per spec rev 16, and not designed here:
- converting a running OS in place
- kexec or other infect-style install vectors
- Windows boot-chain vectors
- carrying an AI-assistant login or token over to the new machine

Loom's old QR credential server (`loom-auth-server`) is **removed**, not ported. On the installed machine the user signs in to their agent through that agent's own normal login flow.

---

## 0. The hard calls (read first)

| # | Call | Why it favors fidelity / tracking | What it costs |
|---|---|---|---|
| H1 | **Run omarchy's own runtime code unchanged**: the `bin/` scripts, `shell/` QML, `default/hypr/*.lua`, and the theme pipeline (`omarchy-theme-set` and its awk renderer). Nix packages them as a store tree reached through `OMARCHY_PATH`. | UX is byte-for-byte upstream. An upstream bump is a lock bump plus a drift report. | Less "idiomatic nix" inside the desktop. Most scripts are not hermetic: their deps sit on the system PATH, as on Arch. |
| H2 | **Nix owns only the default layer** (`$OMARCHY_PATH`). User files under `~/.config` are **seeded like `/etc/skel`** and then belong to the user. The human desktop gets **no home-manager**. | omarchy's runtime writers (`sed -i monitors.lua`, `shell.json` editors, theme-set, toggles) keep working. The upstream layering (defaults → theme → user → toggles) is preserved. | Agents can't express every setting as a read-only HM file. Nix settings sit *below* user files; `omanix doctor` reports shadowing. |
| H3 | **`OMARCHY_PATH = /run/current-system/sw/share/omarchy`**, a stable profile path, and the literal `/usr/share/omarchy` is rewritten to it. | Matches Arch semantics: a pacman upgrade replaces `/usr/share/omarchy` in place, and here a switch replaces the profile in place. No re-login is needed and `hyprctl reload` picks up new defaults. | The tree is per-host (it contains generated host files). The text tree (≈10–20 MB) is copied per host; big media is symlinked. |
| H4 | **Whole desktop on `nixos-unstable`** (Option A in facts §3), pinned in omanix's `flake.lock` and moved in lockstep with omarchy tags. | Quattro needs Hyprland ≥0.56, quickshell ≥0.3.2 and current Qt, which matches Arch's rolling base. One Mesa, one Qt, no overlay mismatch. | A less conservative base. Mitigations: the switch watchdog with auto-rollback, VM gates before an omanix tag, and loom/nuketown CI kept green on 26.05 for signi. |
| H5 | **The Hyprland package matches omarchy's build**: 0.56.2 with omarchy's 4 patches taken from pinned `omarchy-pkgs`, the titlebars plugin built against that exact derivation, and quickshell at omarchy's rev (`2b4501a`, +7 commits). | Same compositor and shell behavior as Arch omarchy, including `hl.dsp.workspace.change_id` IPC and VM software rendering. | We carry 4 patches and an override. A drift check fails on any patch that no longer applies. |
| H6 | **Persist all of `/home`** on its own subvolume, and wipe only `/`. | omarchy writes state all over `$HOME` (chromium, mise, `~/.local/state/omarchy`, agent homes). Per-path home persistence would silently break on each upstream bump. | Less "erase your darlings" purity for the human. Agents under nuketown keep ephemeral homes. |
| H7 | **Typed nix options *overlay* upstream data instead of replacing it.** Keybinds, menu, `shell.json` defaults, window rules and monitors are emitted as one generated Lua module plus merged JSON, on top of the unmodified upstream files. | Upstream's 8 binding files, the 453-line menu and the shell defaults stay the source of truth. New upstream binds and menu rows show up for free. | The full keybind and menu catalog is not a nix attrset. It is extracted at build time by running upstream Lua under a recording stub (§6.4), so introspection still exists. |
| H8 | **Every deviation from upstream is a declared, hash-pinned artifact** in `upstream/` (rewrites, patches, whole-file overrides, drops, package map, install map, quirk map, hl-symbol allowlist). `nix flake check` fails on any unclassified upstream change. | An upstream bump is mechanical. The bump skill reads the drift report and fixes exactly the files it names. | Some up-front classification work (the manifest covers 558 bin scripts, 166 packages and about 50 hardware leaves). |
| H9 | **Limine** is the bootloader (omarchy parity, themed from the palette), with SDDM plus omarchy's `Main.qml` greeter running on Hyprland. **Autologin follows the unlock method**: on only when unlock needs a human factor. | Same boot, unlock and greeter visuals as Quattro. | The TPM2 PCR story is weaker without UKIs. The unlock matrix (§5.6) states this, and Secure Boot via `limine.secureBoot` gives PCR 7. |

---

## 1. Layering (confirmed decision 6)

```
┌──────────────────────────────────────────────────────────────────────┐
│ host flake  (silo: omanix/<id>.git)  host.json · host.nix · hardware.* │
├──────────────────────────────────────────────────────────────────────┤
│ omanix  = Quattro flavor: omarchy-src(pinned)+patch pipeline,          │
│           OMARCHY_PATH overlay, desktop/session/theme/menu/keybinds,   │
│           hardware quirks, omarchy packages, upstream drift checks     │
├──────────────────────────────────────────────────────────────────────┤
│ loom    = DE-agnostic platform + agent base: mkHost, host.json loader, │
│           installer image, disko/LUKS/unlock, impermanence, sops,      │
│           silo host repo + enrollment, policy diff, switch watchdog,   │
│           update, first boot / onboarding                             │
├──────────────────────────────────────────────────────────────────────┤
│ nuketown (optional) = agents as unix users, approval sudo, portal      │
└──────────────────────────────────────────────────────────────────────┘
seed/silo: git hosting (deltas: owner handoff, protected paths, standalone test module)
```

Rules:
- omanix may set `loom.*` options with `mkDefault` and may contribute `loom.switch.healthChecks`, `loom.persist.*` and `loom.policy.protected` *additions*. It never redefines loom internals.
- loom never mentions Hyprland or omarchy.
- nuketown changes are additive options whose defaults equal today's behavior, so signi (mynix, 26.05) keeps evaluating.

---

## a) Repository layouts

### a.1 omanix (new; `~/projects/omanix`)

Origin: fetch from silo, push to both silo and github (decision 5).

```
omanix/
├── flake.nix  flake.lock
├── AGENTS.md                      # router: where things live, rules, apply workflow, test etiquette
├── CLAUDE.md                      # "@AGENTS.md"
├── .claude/skills/
│   ├── configure/SKILL.md         # conversation -> host repo (host.json) + sidecar  (spec)
│   ├── build-installer/SKILL.md   # build image, flash USB, verify                  (spec)
│   ├── bump-omarchy/SKILL.md      # upstream tracking procedure (drift report -> fixes)
│   ├── override-upstream/SKILL.md # how to add a rewrite / patch / override / drop
│   ├── add-option/SKILL.md        # file path == option path, mkDefault, docs, check
│   ├── add-keybind/  add-menu-item/  add-theme/  add-quirk/  add-package/
│   ├── vm-test/SKILL.md           # run / debug nixosTests, screenshots
│   └── diagnose-build/SKILL.md
├── scripts/                       # deterministic, reviewed, signed (spec)
│   ├── flash-usb.sh               # guarded writer (§e.4)
│   ├── mint-host.sh               # answers.json -> host repo + sidecar + enrollment key
│   ├── stage-cache.sh             # host delta closure -> file:// cache dir
│   ├── verify-self.sh             # ssh-keygen -Y verify of the calling script
│   ├── allowed_signers            # release signing keys (namespace omanix-release)
│   └── *.sig                      # detached signatures, regenerated at release tag
├── lib/
│   ├── default.nix                # exports mkHost, lua, jsonc, menu, upstream helpers
│   ├── mkHost.nix                 # = loom.lib.mkHost with flavor = omanix module
│   ├── lua.nix                    # toLua + o.bind/o.window/hl.monitor emitters
│   ├── jsonc.nix                  # ORDER-PRESERVING JSONC parser (list of {id, value, order})
│   ├── menu.nix                   # merge upstream menu + omanix.menu.items -> ordered JSON
│   └── upstream.nix               # the patch pipeline (§b.4)
├── upstream/                      # EVERY deviation from omarchy lives here (H8)
│   ├── pin.toml                   # tag, rev, date, hyprland/quickshell expectations
│   ├── manifest.toml              # path globs -> keep|rewrite|patch|override|drop (+sha256)
│   ├── rewrites.toml              # literal substitutions applied tree-wide
│   ├── patches/*.patch            # surgical, minimal; one concern per patch
│   ├── overrides/<upstream path>  # whole-file replacements, header pins upstream sha256
│   ├── packages.toml              # install/*.packages entry -> nixpkgs attr | omanix pkg | option | drop
│   ├── install-map.toml           # omarchy-install-*/remove-* -> omanix option path
│   ├── hw-quirks.toml             # install/hardware/** leaf -> quirk module | drop
│   ├── hl-symbols.txt             # hl.* API allowed for the pinned Hyprland
│   └── mutable-paths.txt          # files upstream writes at runtime (nix must never own)
├── pkgs/by-name/
│   ├── omarchy-src/               # pinned upstream + pipeline output (the "base tree")
│   ├── omanix-data/               # per-host OMARCHY_PATH tree (base + generated files)
│   ├── hyprland-omarchy/          # nixpkgs hyprland 0.56.2 + omarchy-pkgs patches
│   ├── omarchy-hyprland-titlebars/ quickshell-omarchy/  hyprland-guiutils/
│   ├── owe/ ttfx/ omacalc/ aether/ omasnap/ omacut/ omawrite/ hype/ signed/
│   ├── monologue/ gliff/ asdcontrol/ try-tobi/
│   ├── omanix-plymouth/  omanix-sddm-theme/   # built from upstream default/{plymouth,sddm}
│   ├── omanix-cli/                # `omanix` introspection/apply CLI
│   └── omanix-catalog/            # options/commands/keybinds/menu/themes JSON
├── modules/omanix/                # FILE PATH == OPTION PATH
│   ├── default.nix                # imports all; omanix.enable
│   ├── upstream.nix               # omanix.upstream.*
│   ├── path.nix                   # omanix.path (readOnly), /etc/omarchy.conf (dev link)
│   ├── session.nix                # omanix.session.*  (uwsm, Hyprland, env.d, user units)
│   ├── login.nix                  # omanix.login.*    (sddm greeter, autologin rule)
│   ├── seed.nix                   # omanix.seed.*     (skel-equivalent first-login seeding)
│   ├── theme/default.nix          # omanix.theme.*
│   ├── theme/boot.nix             # omanix.theme.boot.* (plymouth, sddm, limine style)
│   ├── hyprland/default.nix       # omanix.hyprland.{package,settings,extraLua,toggles,...}
│   ├── hyprland/monitors.nix      # omanix.hyprland.monitors
│   ├── hyprland/window-rules.nix  # omanix.hyprland.windowRules
│   ├── keybinds.nix               # omanix.keybinds.*
│   ├── menu.nix                   # omanix.menu.*
│   ├── shell.nix                  # omanix.shell.*   (shell.json defaults, plugins)
│   ├── defaults.nix               # omanix.defaults.{terminal,browser,editor,agent,dictation}
│   ├── apps/{default,webapps,tuis,preinstalls}.nix
│   ├── packages.nix               # omanix.packages.* (base list from packages.toml)
│   ├── input.nix fonts.nix audio.nix network.nix dns.nix power.nix printing.nix
│   ├── dev.nix gaming.nix region.nix agents.nix security.nix
│   ├── hardware/default.nix       # omanix.hardware.* (reads hardware.json facts)
│   ├── hardware/quirks/<leaf>.nix # one file per upstream install/hardware leaf
│   ├── persist.nix                # omanix's contributions to loom.persist
│   ├── health.nix                 # compositor/shell health checks for loom.switch
│   └── catalog.nix                # /run/current-system/sw/share/omanix/*.json
├── templates/host/                # silo host flake template (§d)
├── checks/                        # pure/cheap checks (§h.1)
├── tests/                         # nixosTests (§h.2)
└── docs/{architecture,upstream-tracking,options}.md   # options.md generated
```

### a.2 loom (refactor; `~/projects/loom`)

The old kiosk lives on as `loom.firstboot.mode = "kiosk"` for DE-agnostic hosts, **without** the auth server.

```
loom/
├── flake.nix  flake.lock          # nixpkgs NOT forced on consumers (they pass/follow)
├── AGENTS.md CLAUDE.md  .claude/skills/{installer-dev,policy,vm-test}/SKILL.md
├── lib/
│   ├── mkHost.nix                 # mkHost { hostDir; flavor; system; extraModules }
│   ├── hostJson.nix               # schema-derived loader for host.json (fixed schema)
│   ├── schema.nix                 # options marked settable -> JSON Schema + validator
│   ├── mkInstallerImage.nix       # image.repart: ESP + INSTALLER + CACHE + OMANIX-CFG
│   ├── protectedView.nix          # config -> JSON of protected option set
│   └── appId.nix                  # app UUID constants (host id derivation)
├── modules/loom/                  # file path == option path
│   ├── default.nix host.nix user.nix locale.nix
│   ├── disk.nix                   # loom.disk.*   (disko layout)
│   ├── unlock.nix                 # loom.unlock.* (crypttab opts, initrd, recovery)
│   ├── boot.nix                   # loom.boot.*   (limine | systemd-boot, secure boot, splash hook)
│   ├── persist.nix                # loom.persist.* (impermanence + btrfs root rollback)
│   ├── sops.nix                   # loom.sops.*   (tpm/age host key, recipients)
│   ├── policy.nix                 # loom.policy.* (protected diff, signers)
│   ├── switch.nix                 # loom.switch.* (loom-switch, watchdog, health checks)
│   ├── update.nix                 # loom.update.*
│   ├── enroll.nix                 # loom.enroll.* (first-boot retry of silo enrollment)
│   ├── firstboot.nix              # loom.firstboot.* (onboarding: kiosk | desktop)
│   ├── agents.nix                 # loom.agents.* -> nuketown (optional)
│   ├── hardware/firmware.nix      # loom.hardware.firmware.* (filtered linux-firmware)
│   └── installer/{image,tui,detect}.nix
├── pkgs/{loom-installer,loom-detect,loom-switch,loom-enroll,loom-host,silo-stub-keys}/
├── templates/host-generic/
└── tests/{fde-passphrase,fde-tpm2,fde-tpm2-pin,fde-fido2,impermanence,sops-tpm,
          switch-watchdog,policy,installer,reinstall,enroll-offline}.nix
```

### a.3 nuketown deltas (additive only; all defaults equal today's behavior)

```
nuketown/
├── module.nix          + nuketown.persistRoot (str, "/persist")
│                       + gate impermanence on (options ? environment.persistence)
│                       + nuketown.sops.ageKey.{encryptedFile,keyFile} (defaults = today)
│                       + agents.<n>.extraHomeConfig : deferredModule (attrs still valid)
│                       + nuketown.switch.{backend = "nixos-rebuild" | "command", command, postSwitchHooks}
│                       + agents.<n>.keys.generateAtInstall (bool, false): publish expected
│                         secret names so loom's installer can mint them
│                       + pkgs.unstable fallback -> pkgs.claude-code when absent
├── approval-daemon.nix + approvalDaemon.{prompter, display (null|":0"), target, notify}
├── checks.nix          + eval matrix: nixos-26.05 AND nixos-unstable
└── (fix regardless) close sudoex-run NOPASSWD bypass; broker peer-cred check
```

### a.4 seed/silo deltas (`instances/silo/*`)

| id | change | needed for |
|---|---|---|
| S1 | **Owner handoff.** In post-receive on the default branch: if the tree has `.silo/owner` (one pubkey) and the push was accepted, rewrite the bare repo's `.owner_key` to it. | Spec step 3: nothing off the machine keeps write access, even though the enrollment key created the repo. |
| S2 | **Protected paths.** In pre-receive: a push that changes `.authorized_keys`, `.allowed_signers` or `.silo/**` must come from a key listed in `.silo/admins` (the human plus host keys). The owner key always passes. | "The agent's key must not be able to grant itself power", enforced at the server as well as on the host. |
| S3 | Path hardening (C2): reject `.`-prefixed components, nested `*.git` ancestors, and paths deeper than 4 levels or longer than 200 chars. | Safety of nested `omanix/<id>.git`. |
| S4 | `nixosModules.silo-standalone`: sshd catch-all plus `silo-shell` plus hooks plus smart-HTTP read, without the controller, webhook or k8s. | The local silo stand-in for VM tests (decision 2). |
| S5 | (optional) Webhook `full_name` relative to `reposDir` (C8). | Hygiene. |

Host repos keep silo's `master` default branch, so no C6 dependency.

### a.5 mynix

No change is required. signi keeps nuketown on 26.05 because the new nuketown options default to today's values, and nuketown CI evaluates signi-shaped fixtures on 26.05.

---

## b) Flake inputs, outputs, lib

### b.1 omanix `flake.nix`

```nix
{
  inputs = {
    nixpkgs.url        = "github:NixOS/nixpkgs/nixos-unstable";       # H4
    loom.url           = "git+https://silo.loom.farm/loom.git";
    loom.inputs.nixpkgs.follows = "nixpkgs";
    # loom re-exports: home-manager, disko, impermanence, sops-nix, nuketown (all follow nixpkgs)

    omarchy = { url = "github:omacom/omarchy/v4.5.0-rc2"; flake = false; };   # pin by tag; rev in lock
    omarchy-pkgs = { url = "github:omacom-io/omarchy-pkgs"; flake = false; };   # hyprland patches + PKGBUILD versions
    quickshell-src = { url = "github:quickshell-mirror/quickshell/2b4501a2826"; flake = false; };
    hyprland-guiutils = { url = "github:hyprwm/hyprland-guiutils/v0.2.2"; inputs.nixpkgs.follows = "nixpkgs"; };
    # Leaf sources (owe, ttfx, oma*, ...) are fetchFromGitHub inside pkgs/by-name with hashes,
    # NOT flake inputs. That keeps `nix flake update` from moving them; the bump skill moves them
    # deliberately, checked against omarchy-pkgs PKGBUILD pkgver.
  };

  outputs = { self, nixpkgs, loom, ... }@inputs: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
  in {
    overlays.default = import ./pkgs/overlay.nix inputs;      # pkgs.omanix.<name>
    nixosModules = {
      omanix  = import ./modules/omanix inputs;               # flavor only
      default = { imports = [ loom.nixosModules.default self.nixosModules.omanix ]; };
    };
    lib = import ./lib { inherit inputs; };                    # lib.mkHost, lib.lua, lib.jsonc, ...
    templates.host = { path = ./templates/host; description = "omanix host flake (silo)"; };
    packages = forAll systems (pkgs: {
      inherit (pkgs.omanix) omarchy-src hyprland-omarchy omarchy-hyprland-titlebars
        quickshell-omarchy owe ttfx omacalc aether omasnap omacut omawrite hype signed
        monologue gliff asdcontrol try-tobi omanix-cli;
      omanix-data-reference = refHost.config.omanix.dataPackage;
      catalog               = refHost.config.omanix.catalog.package;
      installer-offline     = loom.lib.mkInstallerImage { flavor = self.nixosModules.omanix; mode = "offline"; referenceHosts = refHosts; };
      installer-net         = loom.lib.mkInstallerImage { flavor = self.nixosModules.omanix; mode = "net"; };
    });
    nixosConfigurations = refHosts;            # ref-default, ref-nvidia, ref-amd-laptop (cache precompute)
    checks = forAll systems (pkgs: import ./checks { inherit self pkgs inputs; } // import ./tests { ... });
    apps = forAll systems (pkgs: { flash-usb = ...; mint-host = ...; omanix = ...; });
    devShells = ...;                            # nvd, nix-tree, sops, age, age-plugin-tag, lua5_5
  };
}
```

### b.2 loom lib

```nix
loom.lib.mkHost = {
  hostDir,                 # path to host flake root (host.json, hardware.nix, ...)
  flavor ? null,           # e.g. omanix.nixosModules.omanix
  nixpkgs,                 # passed by flavor; loom does not choose
  system ? (importJSON (hostDir + "/hardware.json")).system,
  extraModules ? [],
}: nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    loom.nixosModules.default
    (loom.lib.hostJson.module (hostDir + "/host.json"))     # validated, normal priority
    (hostDir + "/hardware.nix")
    (loom.lib.hardwareFacts (hostDir + "/hardware.json"))    # -> loom.hardware.facts (readOnly)
  ] ++ optional (flavor != null) flavor
    ++ optional (pathExists (hostDir + "/host.nix")) (hostDir + "/host.nix")
    ++ extraModules;
  specialArgs.hostDir = hostDir;
};

loom.lib.mkInstallerImage = { flavor, mode ? "offline", referenceHosts ? {}, extraFirmware ? true }: ...;
loom.lib.protectedView    = config: { ...JSON-able projection of loom.policy.protected... };
loom.lib.hostJson.schema  = options: { JSON Schema for every option with `loom.settable = true` };
```

`omanix.lib.mkHost = args: loom.lib.mkHost (args // { flavor = omanix.nixosModules.omanix; nixpkgs = inputs.nixpkgs; });`

### b.3 host.json loader (fixed schema, pure, no IFD)

- An option becomes *settable* through `lib.mkOption { ...; } // { loom.settable = true; }`, via a small wrapper `loom.lib.mkSettable`.
  - Allowed types: bool, enum, `strMatching`, `ints.between`, `listOf` of those, and `attrsOf` of submodules built only from those.
- `hostJson.module` reads the JSON and:
  - rejects unknown keys and any key whose option is not settable. The error names the key and the allowed set.
  - applies values with `lib.setAttrByPath` at normal priority.
- Result: the configure skill, the installer and `omanix set` can only write typed, whitelisted values. No arbitrary Nix ever comes from them (spec: "fixed options schema").

### b.4 The upstream patch pipeline (`lib/upstream.nix` → `pkgs.omanix.omarchy-src`)

Given `src = inputs.omarchy`, it runs these deterministic stages in order:

1. **drop**: delete `manifest.toml` `drop` globs. These are `migrations/**`, `install/**` except the user/first-run and hardware predicates we reuse, `bin/omarchy-upgrade-to-quattro`, `bin/omarchy-update-pacman*`, `bin/omarchy-channel-*`, `bin/omarchy-dev-link`, `default/libalpm/**`, `default/limine/**`, `default/pacman/**`, `default/snapper/**`, `test/**`, `plans/**`.
2. **override**: copy `upstream/overrides/<path>` over `<path>`.
   - Each override's first lines must be `# omanix:overrides=<path>@sha256:<hash of the upstream file it replaced>`.
   - The build **fails** when the upstream file's hash differs. That is the "re-review me" signal on bump.
3. **patch**: apply `upstream/patches/*.patch` in order. A patch that no longer applies fails the build.
4. **rewrite**: apply `rewrites.toml` literals tree-wide, text files only:
   - `/usr/share/omarchy` → `/run/current-system/sw/share/omarchy`
   - `/usr/lib/omarchy-hyprland-titlebars/titlebars.so` → `${titlebars}/lib/titlebars.so`
   - `/usr/lib/omarchy/speedtest` → `${omanix.speedtest-stub}/bin/speedtest` (or drop)
   - `/usr/bin/<tool>` and `/usr/local/bin/<tool>` → `<tool>`. These are bare names on the system PATH, using an explicit list from the facts §5 scan.
   - `/usr/share/{plymouth,sddm}/...` → handled by overrides in `omanix-plymouth` and `omanix-sddm-theme`.
5. `patchShebangs --host` on `bin/**` and `default/**`, then `chmod +x bin/*`.
6. **post-check** (part of the build):
   - grep for surviving `/usr/(share|lib|bin|local)/`, `pacman`, `yay`, `paru`, `makepkg`, `mkinitcpio`, `limine-` outside `manifest.toml` `allowResidual`, and fail on any hit
   - every `bin/omarchy-*` is classified (manifest default `keep` is allowed only when it has no forbidden token)
   - `lua5_5 -p` (luac parse) on every `.lua`
   - `hl.*` symbols found ⊆ `hl-symbols.txt`

The **current patch set** is intentionally tiny. Expected size: patches ≤ 5 files, overrides ≈ 40–60 scripts, about 90% of them in the pkg/install/update/channel/boot families.

| kind | target | reason |
|---|---|---|
| patch | `default/hypr/omarchy.lua` | Two lines in one file: `require_optional.module("default.hypr.omanix-pre")` at the top (sets `omarchy_default_bindings`/`omarchy_preinstalled_bindings` globals) and `require_optional.module("default.hypr.omanix")` at the end, so the nix-generated host module loads after the theme and before user files. |
| patch | `default/bash/env-bootstrap` | None needed once the rewrite runs: the forced reset now resets *to* our stable path. Dev mode works unchanged through `/etc/omarchy.conf`. Listed here to record the decision. |
| override | `bin/omarchy-pkg-{add,drop,present,missing,install,remove,aur-*}` | `present`/`missing` read `/run/current-system/sw/share/omanix/features.json`, then fall back to `command -v`. `add`/`drop` map Arch names through `packages.toml` to options, then run `omanix set … && omanix apply` with a gum confirm. |
| override | `bin/omarchy-update` (+ `-system-pkgs`, `-keyring`, `-aur-pkgs`, `-orphan-pkgs`, `-pkg-prune`, `-boot`) | Becomes `omanix update` (§f.5). `update-available`, `-confirm`, `-lock`, `-stay-awake` and `-restart` stay upstream. |
| override | `bin/omarchy-install-*`, `bin/omarchy-remove-*` (generated) | Each one is `omanix-feature-shim <name>`, driven by `install-map.toml` (option path plus value). Rows map onto omanix options. Unmappable ones print a clear "not on omanix" message. |
| override | `bin/omarchy-theme-set-browser-policy` | Writes `/var/lib/omanix/browser-policy/color.json` (the sudoers rule targets the store path). `environment.etc` symlinks the chromium/chrome/brave policy file to it. |
| override | `bin/omarchy-plymouth-set{,-by-theme}` | Runs `omanix set omanix.theme.boot.theme <name> && omanix apply`, because boot visuals are declarative. |
| override | `bin/omarchy-snapshot*`, `bin/omarchy-kernel*`, `bin/omarchy-hibernation-setup`, `bin/omarchy-system-factory-reset*` | Become NixOS generations, `loom.disk.swap`, and "wipe /persist + reinstall from silo" with explicit guidance. |
| override | `bin/omarchy-dns`, `bin/omarchy-locale-generate`, `bin/omarchy-sudo-passwordless`, `bin/omarchy-setup-security-*` | Map to options (`omanix.dns.preset`, `omanix.region`, …) through `omanix set`. |

The override scripts keep omarchy's `# omarchy:summary=… / args / group` headers, so the upstream `omarchy` router, `omarchy commands --json` and the help text all keep working with no changes.

### b.5 Package set (`pkgs/by-name`, all `callPackage`, all `meta.omanix.upstreamPkgbuild` tagged)

- **hyprland-omarchy**: `pkgs.hyprland` (0.56.2 on unstable), with `patches` from `omarchy-pkgs/pkgbuilds/hyprland/*.patch` (`software-renderer`, `nvidia-egl-teardown`, `wl-output-global-grace`, `monitor-rule-vrr`).
  - A drift check compares `version` to the PKGBUILD's `pkgver`.
- **omarchy-hyprland-titlebars** v0.2.2: `hyprlandPlugins.mkHyprlandPlugin hyprland-omarchy { ... }`. It is always built against `config.omanix.hyprland.package`, so a mismatched ABI cannot happen.
- **quickshell-omarchy**: `pkgs.quickshell.overrideAttrs { src = inputs.quickshell-src; version = "0.3.2-r7"; }`. The vendored `load_qtquick_611.patch` is applied only when `qt6.qtbase.version` is 6.11.*, a conditional checked at eval. The Qt 6.12 risk is covered by `tests/desktop` asserting no QML errors.
- **hyprland-guiutils**: `inputs.hyprland-guiutils.packages.${system}.default`, following our nixpkgs.
- Leaf apps from the facts §4 table: owe (+ owe-lockfeed, `owed` user unit), ttfx, omacalc, aether, omasnap, omacut, omawrite, hype, signed, monologue, gliff, asdcontrol (+ sudoers drop-in), try-tobi (attr name `try-tobi`, binary `try`).
  - All are MIT/BSD/GPL-2 as listed. omarchy-nvim is **not** a package; it is `modules/omanix/apps/neovim.nix`, which seeds LazyVim starter plus the theme import into `~/.config/nvim` on first login, as omarchy's package seeds `/etc/skel`.
- Not packaged (retired in Quattro): walker, elephant, mako, hyprlock, hypridle, waybar, swayosd.

---

## c) Option tree (important options; every default `mkDefault`)

`S` = settable from host.json (fixed schema). `P` = in loom's protected set.

### c.1 loom.*

```
loom.host.id                 str /^[0-9a-f]{32}$/                       S  P  (literal from installer)
loom.host.name               str hostname regex                          S
loom.host.silo.host          str "silo.loom.farm"                        S  P
loom.host.silo.hostKey       str (pinned ed25519)                           P
loom.host.silo.namespace     str "loom" (omanix sets "omanix")              P
loom.host.silo.path          str "${namespace}/${id}.git"  (readOnly-ish)   P
loom.host.silo.fetchUrl      str "git+https://${host}/${path}"
loom.host.silo.pushUrl       str "ssh://git@${host}/${path}"
loom.host.repoPath           str "/var/lib/loom/host"   (persisted working copy, group loom-host)
loom.host.humanKeys          listOf sshPubKey                            S  P  (always in .authorized_keys)
loom.host.humanAgeRecipients listOf str (age1yubikey1…)                  S  P
loom.host.agentKeys          listOf sshPubKey (filled by installer)         P
loom.user.name / fullName    str                                         S  P(name)
loom.user.passwordSecret     str "user-password-hash" (sops key)            P
loom.locale.{timezone,keymap,locale,extraLocales}                        S
loom.disk.device             str /dev/disk/by-id/...  (from hardware.json)  P
loom.disk.layout             enum ["luks-btrfs"]                            P
loom.disk.espSize            str "2G"
loom.disk.swap.{enable,size} bool / str ("ram")                          S
loom.disk.hibernate          bool false                                  S
loom.unlock.method           enum ["passphrase" "tpm2" "tpm2-pin" "fido2"]  S  P
loom.unlock.tpm2.pcrs        listOf int  ([7] if secureBoot else [0 2 7])    P
loom.unlock.fallbackPassphrase bool (true for fido2, false otherwise)    S  P
loom.unlock.recoveryKey      bool true                                      P
loom.boot.loader             enum ["limine" "systemd-boot"] "limine"        P
loom.boot.secureBoot.enable  bool (true iff installer enrolled keys)     S  P
loom.boot.splash.{enable,themePackage,themeName}   (flavor fills)
loom.persist.root            str "/persist"                                 P
loom.persist.home.mode       enum ["subvolume" "ephemeral"] "subvolume"  S
loom.persist.{directories,files}  listOf (str | {directory,user,mode})   (modules append)
loom.sops.hostKey.type       enum ["tpm" "age"]  (installer decides)         P
loom.sops.hostKey.recipient  str                                             P
loom.sops.file               path hostDir + "/secrets/host.yaml"
loom.policy.enforce          bool true                                       P
loom.policy.protected        listOf str (option paths; §f.4 default)         P
loom.policy.humanPrincipals  listOf str ["human:${loom.user.name}"]          P
loom.switch.watchdog.timeout int 180 (s)
loom.switch.healthChecks     attrsOf { command; timeout; user ? null; }     (flavors add)
loom.switch.autoSwitchOnPush bool false                                      P
loom.update.input            str "omanix"   (which flake input `update` bumps)
loom.update.checkInterval    str "6h"
loom.firstboot.mode          enum ["desktop" "kiosk" "none"] "desktop"
loom.firstboot.prompts       attrsOf { description; secret ? true; sopsKey; }   (first-boot asks)
loom.agents.enable           bool false                                  S
loom.agents.<…>              thin mapping onto nuketown.*                     P (sudo, persist)
loom.hardware.facts          readOnly attrs from hardware.json
loom.hardware.firmware.mode  enum ["detected" "full"] "detected"         S
loom.installer.*             (image only) cacheUrl, allowNetworkFallback, siloOverride
```

### c.2 omanix.*

```
omanix.enable                       bool true (when module imported)
omanix.upstream.package             package pkgs.omanix.omarchy-src        (readOnly default)
omanix.upstream.rev                 str (readOnly; from pin.toml + lock)
omanix.upstream.devPath             nullOr str null   -> /etc/omarchy.conf (omarchy dev-link mode)
omanix.path                         str "/run/current-system/sw/share/omarchy" (readOnly)
omanix.dataPackage                  package (readOnly; base tree + generated files)

omanix.session.uwsm                 bool true
omanix.session.keepShellOnStop      bool true   (KillMode=mixed drop-in)
omanix.login.greeter                enum ["sddm-omarchy" "none"] "sddm-omarchy"
omanix.login.autologin              bool  default = loom.unlock.method != "tpm2"     S
omanix.seed.enable                  bool true   (first-login copy of $OMARCHY_PATH/config)
omanix.seed.refreshOnBump           enum ["never" "untouched"] "untouched"
                                     # re-seed files whose sha matches a previously shipped copy
                                     # (same idea as upgrade-to-quattro's sha table)

omanix.theme.default                enum <upstream + extra theme slugs> "tokyo-night"   S
omanix.theme.lock                   bool false   (true: re-apply default each login, menu hides picker)  S
omanix.theme.available              nullOr (listOf enum) null (= all)                    S
omanix.theme.intros                 bool true (false drops backgrounds/intros videos)     S
omanix.theme.extra.<slug>           { src : path; trusted : bool false; }   (untrusted -> upstream denylist)
omanix.theme.boot.theme             enum themes  default = theme.default                  S
omanix.theme.boot.{plymouth,sddm,limine}   bool true

omanix.hyprland.package             package pkgs.omanix.hyprland-omarchy
omanix.hyprland.plugins.titlebars   bool true
omanix.hyprland.defaultBindings     bool true   -> omarchy_default_bindings global           S
omanix.hyprland.preinstalledBindings bool true  -> omarchy_preinstalled_bindings global      S
omanix.hyprland.settings            attrs (Lua-able) {}  -> hl.config({...}) in omanix.lua
omanix.hyprland.env                 attrsOf str {}       -> hl.env(k, v)
omanix.hyprland.monitors            listOf { output; mode ? "preferred"; position ? "auto"; scale ? "auto"; extra ? {} }
omanix.hyprland.windowRules.<name>  { match : str|attrs; rules : attrs; }  -> o.window(...)
omanix.hyprland.toggles.<flag>      bool  (seed ~/.local/state/omarchy/toggles/hypr/<flag>.lua on first login)  S
omanix.hyprland.workspaceLayout     enum ["dwindle" "scrolling" "floating"] "dwindle"   S
omanix.hyprland.extraLua            lines ""   (escape hatch, appended last in omanix.lua)

omanix.keybinds.<name>              submodule {
    keys        : str  e.g. "SUPER SHIFT + B"          (validated grammar)
    description : str
    action      : oneOf [ str                                        # exec
                          (submodule { launch; focus ? null; })        # {launch=,focus=}
                          (submodule { webapp; focus ? false; })
                          (submodule { tui; focus ? false; })
                          (submodule { menu; }) (submodule { panel; })
                          (submodule { omarchy; }) (submodule { ipc; })
                          (submodule { audio; }) (submodule { brightness; })
                          (submodule { lua; })                         # raw dispatcher expr
                        ]
    locked, repeating, release, mouse, nonConsuming, transparent : bool false
    replaces    : nullOr str  (keys of an upstream bind to hl.unbind first)
    enable      : bool true }
omanix.keybinds.unbind              listOf str []   (upstream binds to remove)

omanix.menu.items.<dotted-id>       submodule { icon; label; action; target; provider; aliases;
                                               description; title; iconFont; when; checked; disabled;
                                               after : nullOr str; enable : bool true; }
                                     # upstream items are pre-populated at mkDefault with their order
omanix.menu.hides                   listOf str  (launcher.hides additions)
omanix.shell.settings               JSON-typed submodule merged over upstream config/omarchy/shell.json:
    idle.{screensaver,lock} int; bar.{position enum, background enum, layout.*}; dock.{position, pinned}; plugins; disabledPlugins
omanix.shell.plugins.<id>           { src : path; }  (installed to $OMARCHY_PATH/shell/plugins-extra)

omanix.defaults.terminal            enum ["foot" "alacritty" "ghostty" "kitty"] "foot"    S
omanix.defaults.browser             enum ["chromium" "chrome" "brave" "firefox" "zen"] "chromium"  S
omanix.defaults.editor              enum ["nvim" "code" "cursor" "zed" "helix" "vim" "emacs"] "nvim" S
omanix.defaults.agent               nullOr enum <harness names> null                      S
omanix.defaults.dictation           nullOr enum ["voxtype"] null                           S
omanix.apps.<name>.enable           bool (preinstalls default true: aether cliamp libreoffice pinta obsidian
                                     moonlight omacut monologue omacalc omawrite hype signed localsend ...)  S
omanix.webapps.<Name>               { url; icon : path|package; mimeTypes; exec ? null; enable; }  S(enable)
omanix.tuis.<Name>                  { command; style enum ["float" "tile"]; icon; }
omanix.packages.base                listOf package  (generated from upstream/packages.toml)
omanix.packages.extra               listOf str (attr names)                               S

omanix.input.layouts                listOf { layout; variant ? ""; }  [{layout="us";}]   S
omanix.input.composeOption          str "omarchy:shift_caps_compose"
omanix.input.fcitx5.enable          bool true
omanix.fonts.monospace              str "JetBrainsMono Nerd Font"                          S
omanix.fonts.cjkVariant             enum ["jp" "kr" "sc" "tc" "hk" "default"] "default"    S
omanix.dns.preset                   enum ["dhcp" "cloudflare" "google"] "dhcp"             S  P
omanix.region                       nullOr enum ["cn"] null  (substituter prepend, no trust change) P
omanix.power.sleepHooks.{unmountFuse,fprintdResume,kbdBacklight,forceIgpu}  bool
omanix.hardware.quirks.<leaf>.enable bool  (defaults from hardware.json detected list)    S
omanix.hardware.nvidia.mode         enum ["auto" "open" "legacy580" "off"] "auto"          S
omanix.dev.docker.enable            bool false;  omanix.dev.languages listOf enum (mise)    S
omanix.gaming.{steam,retroarch,lutris}.enable                                             S
omanix.agents.harnesses.<name>      { enable; package; command; prompt.*; skillDirs; persist; }   (omarchy agent picker)
omanix.agents.residents             bool false -> loom.agents.enable (nuketown)            S
omanix.catalog.package              package (readOnly)
```

---

## d) Host flake template (silo) and sidecar schema

### d.1 Host repo `silo:omanix/<id>.git` (branch `master`)

```
flake.nix          # 12 lines; never edited by tools
flake.lock         # pins omanix (by signed release tag), nixpkgs follows omanix
host.json          # fixed-schema settings: the ONE place tools and agents write
host.nix           # optional escape hatch (options only); empty template with comments
hardware.nix       # nixos-generate-config --no-filesystems output
hardware.json      # installer facts: system, cpu, gpu[], tpm, fido2, secureBoot, disk by-id,
                   #   pci/usb ids, detected quirks[], firmware globs[], dmi {vendor,product}
.sops.yaml         # creation_rules: host recipient (age1tag1… or age1…) + human recipients
secrets/host.yaml  # sops: user-password-hash, agent ssh/gpg private keys, first-boot answers
.authorized_keys   # silo push ACL: human key(s), host key, agent key(s)
.allowed_signers   # git ssh signing: "human:<user>" and "agent:<name>" principals
.silo/admins       # S2: keys allowed to change ACL files: human + host
.silo/owner        # S1: owner handoff target: host key
CLAUDE.md          # generated at mint; short; points to `omanix` CLI and skills
.claude/skills/host/SKILL.md   # "edit host.json via `omanix set`; host.nix only for X; apply"
```

`flake.nix`:
```nix
{
  inputs.omanix.url = "git+https://silo.loom.farm/omanix.git?ref=refs/tags/v0.1.0";
  outputs = { omanix, ... }: {
    nixosConfigurations.host = omanix.lib.mkHost { hostDir = ./.; };
  };
}
```

`host.json` example (written by the configure skill, the installer and `omanix set`):
```json
{
  "$schema": "omanix-host/v1",
  "loom": {
    "host": { "id": "4f1c…e9", "name": "tesla",
              "humanKeys": ["sk-ssh-ed25519@openssh.com AAAA… josh@yubikey"],
              "humanAgeRecipients": ["age1yubikey1q…"] },
    "user": { "name": "josh", "fullName": "Joshua Perry" },
    "locale": { "timezone": "America/Denver", "keymap": "us", "locale": "en_US.UTF-8" },
    "unlock": { "method": "fido2", "fallbackPassphrase": true },
    "boot": { "secureBoot": { "enable": true } },
    "agents": { "enable": true }
  },
  "omanix": {
    "theme": { "default": "tokyo-night" },
    "defaults": { "terminal": "foot", "browser": "chromium", "agent": "claude" },
    "apps": { "obsidian": { "enable": true }, "pinta": { "enable": false } },
    "input": { "layouts": [ { "layout": "us" } ] }
  }
}
```

### d.2 Sidecar (`OMANIX-CFG` vfat partition, schema `omanix.sidecar/v1`)

```
OMANIX-CFG/
  sidecar.json
  host.bundle            # git bundle of host repo master at <commit>
  xcache/                # optional file:// cache: host closure minus base image cache
    nix-cache-info  *.narinfo  nar/*.nar.zst
  SHA256SUMS             # integrity only; authenticity = host.commit pin + signed omanix tag in flake.lock
```

```json
{
  "schema": "omanix.sidecar/v1",
  "host": {
    "id": "4f1c…e9",
    "fetchUrl": "git+https://silo.loom.farm/omanix/4f1c…e9.git",
    "pushUrl": "ssh://git@silo.loom.farm/omanix/4f1c…e9.git",
    "siloHostKey": "ssh-ed25519 AAAAC3…Sw+s",
    "commit": "9d2e…",                       // host.bundle must contain exactly this commit
    "attr": "nixosConfigurations.host",
    "toplevel": "/nix/store/…-nixos-system-tesla-…"   // expected; installer compares after build
  },
  "machineId": "b7e0…",                      // the id was derived from this; installed to /etc/machine-id
  "enrollment": {                            // single-use, per-repo; NOT a user credential
    "privateKey": "-----BEGIN OPENSSH PRIVATE KEY-----…",
    "publicKey": "ssh-ed25519 AAAA… enroll-4f1c"
  },
  "hints": { "disk": null, "unlock": ["fido2", "tpm2-pin", "passphrase"] },
  "caches": { "xcache": true, "netFallback": ["https://cache.loom.farm", "https://cache.nixos.org"] },
  "publicKeys": { "cache": ["cache.loom.farm-1:…", "cache.nixos.org-1:…"] }
}
```

What the sidecar never contains:
- passwords or password hashes
- Wi-Fi PSKs
- API keys or AI-assistant tokens
- any private key except the single-use enrollment key

Pure configuration is in `host.json` inside the bundle. Secrets are created on the target (§e.6).

---

## e) USB installer, end to end

### e.1 Image build (`loom.lib.mkInstallerImage`, nixpkgs `image.repart`; no nixos-generators)

```
GPT raw image  omanix-installer-<ver>-<mode>-x86_64.raw(.zst)
 p1 ESP        vfat 512M   Limine (themed, omarchy branding) -> installer kernel+initrd
 p2 INSTALLER  erofs (lz4hc) or squashfs zstd-19: installer NixOS store (minimal+perlless profile,
               all-hardware firmware, nix, disko, cryptsetup, systemd-cryptenroll, sbctl, tpm2-tools,
               age, age-plugin-tpm, age-plugin-tag, sops, git, gum, loom-installer)
 p3 CACHE      erofs, NO compression (contents are .nar.zst already): file:// binary cache
               = closure of all referenceHosts (offline mode only; absent in "net")
 p4 OMANIX-CFG vfat 256M, label OMANIX-CFG, empty except README.txt
```

Size bars:
- offline: target ≤ 3.5 GiB, versus omarchy's ~6 GB
- net: ≤ 200 MB

The budgets are enforced in `checks.closure-size` (§h.1).

`referenceHosts` are the precomputed popular combinations: `ref-default` (Intel/AMD iGPU), `ref-nvidia` (open driver) and `ref-laptop` (thermald, PPD, fprintd). The long tail goes into `xcache` at flash time or substitutes online.

Trimming:
- `documentation.enable = false` (desktop keeps man pages via an option), `environment.defaultPackages = []`
- installer `perlless`, `system.forbiddenDependenciesRegexes = [ "-doc$" "texlive" "ghc-" ]`
- a duplicate Mesa/LLVM/Python check through `nix why-depends` in `checks.closure-dupes`

### e.2 Sidecar injection (no image rebuild)

`scripts/flash-usb.sh` writes the image, re-reads the partition table, mounts `OMANIX-CFG` and copies in `sidecar.json`, `host.bundle`, `xcache/` and `SHA256SUMS`.

Users without Linux can copy the same files onto the vfat partition from any OS. The configure skill emits a ZIP layout for that case.

If xcache is bigger than the free space on CFG, flash-usb creates p5 `OMANIX-XCACHE` (ext4) in the unallocated tail of the stick. CFG is never resized.

### e.3 configure skill (on the user's existing computer, which has Nix locally or through WSL2)

1. **Conversation.**
   - The agent asks about identity (hostname, user, full name, tz, keymap, locale), human SSH key(s) and age recipients (e.g. a YubiKey), theme, default terminal/browser/editor/agent, preinstalls, gaming/dev, and whether to enable residents.
   - It never asks for passwords or tokens. The skill text forbids it, and the `answers.json` schema has no field for one.
2. Writes `answers.json`. Then `scripts/mint-host.sh answers.json`, which verifies its own signature first:
   1. Validates against `omanix-host/v1` with `nix eval .#lib.hostSchema`. Unknown keys fail.
   2. `machineId = systemd-id128 new`.
   3. `id` is the app-specific id. `unshare -m` bind-mounts a temp file containing `machineId` over `/etc/machine-id`, then runs `systemd-id128 machine-id --app-specific=$LOOM_HOST_APP_ID`. That gives exact systemd semantics with no reimplemented HMAC. The raw machine-id never appears in the path.
   4. `ssh-keygen -t ed25519 -N "" -C enroll-<id8>` creates the enrollment key.
   5. `nix flake init -t omanix#host`, then writes `host.json` and a placeholder `hardware.{nix,json}` (`"system":"x86_64-linux"`, no quirks).
   6. Writes `.authorized_keys` = enrollment + human keys, `.silo/admins` = enrollment + human, and `.allowed_signers` = human. Commits (unsigned; the human may sign).
   7. `git push ssh://git@silo.loom.farm/omanix/<id>.git master` using the enrollment key. Silo auto-creates the repo with `.owner_key` = enrollment key.
   8. `nix build .#nixosConfigurations.host.config.system.build.toplevel` (optional). `scripts/stage-cache.sh` computes `toplevel − base-image closure` into `xcache/`.
   9. Emits `sidecar.json`, `host.bundle` (`git bundle create host.bundle master`) and `SHA256SUMS`.
3. **build-installer skill**: gets the signed release image, or builds `.#installer-offline`. Verifies the image signature with `ssh-keygen -Y verify -n omanix-release`. Runs `flash-usb.sh` (§e.4). Verifies by reading back.

The agent chooses and the scripts act. Every destructive step is in a signed script.

### e.4 `flash-usb.sh` guards (enforced in code, not prompts)

1. `verify-self.sh "$0"` must pass, against `scripts/allowed_signers`, and so must the image `.sig`.
2. The target must be given as `/dev/disk/by-id/usb-*` or resolve to a disk where:
   - `TRAN=usb` **or** `/sys/block/X/removable == 1`, and
   - `TYPE=disk`, not a partition.
3. Refuse if any partition of the disk:
   - is mounted
   - holds `/`, `/nix`, `/boot` or swap
   - is an LVM PV, an md member, or an open LUKS holder (`lsblk -no HOLDERS`, `/proc/swaps`, `findmnt`)
4. Refuse if the disk is smaller than the image size + CFG, or larger than 2 TiB (it is likely not a stick; override with `--i-know-this-is-large`).
5. Show vendor, model, serial, size and current partitions. Require typing the **last 4 characters of the serial**.
6. `dd bs=4M conv=fsync oflag=direct status=progress`, then `blockdev --flushbufs`, then re-read the partition table.
7. Read back and compare the sha256 of the image region.
8. Mount `OMANIX-CFG` by PARTLABEL on *this* disk only, copy the sidecar files, check `SHA256SUMS`, unmount.
9. Exit codes are distinct per refusal reason. `--dry-run` prints the plan.

### e.5 Installer runtime (`loom-installer`, gum TUI on tty1; scripts in the image are store paths)

Boot. `loom-installer.service` starts after `network-pre`; the network is optional.

**Step 0, mode selection**
- Mount `OMANIX-CFG` read-only, then verify `SHA256SUMS`.
- If `sidecar.json` exists: **preconfigured mode**. The installer verifies `host.bundle` contains `host.commit`.
- Else, if the kernel cmdline has `loom.host=<id>` or the user picks "Reinstall an existing host" and types the id: **reinstall mode**.
  - It fetches from `loom.silo=<host>` (cmdline) or the default. Over HTTPS that is public read; with no network it uses a bundle on CFG.
  - VM tests always pass `loom.silo=silo` (a local stand-in). The test harness asserts that `silo.loom.farm` is never contacted (§h).
- Else: **fresh mode**. The installer asks the same questions as the configure skill, in gum forms, and mints locally with the same `mint-host.sh` logic packaged as `loom-mint`. If there is no network, the push is deferred to first boot.

**Step 1, detect** (`loom-detect` → `hardware.json`)
- Disks: non-removable, excluding the boot stick, with model, serial and size.
- `tpm2`: `/sys/class/tpm/tpm0/tpm_version_major == 2` and `systemd-cryptenroll --tpm2-device=list`.
- `fido2`: `systemd-cryptenroll --fido2-device=list`.
- Secure Boot: `bootctl status` (enabled or setup mode).
- CPU vendor/model, GPU via lspci (NVIDIA GSP-capable or not), DMI, PCI/USB ids, RAM.
- **Hardware quirks**: run upstream omarchy `bin/omarchy-hw-*` predicates. These are read-only probes, shipped in the image from `omarchy-src`. Each `hw-quirks.toml` leaf is evaluated for a list of detected quirks.
- Firmware: `modinfo -F firmware` of modules bound to detected devices gives the firmware globs.

**Step 2, disk**: whole disk only (no dual boot). Pick from the list. Show model, serial, size and existing partitions/OS signatures (`wipefs -n`). Require typing `ERASE <last4serial>`.

**Step 3, unlock method**: the capability matrix (§e.6) shows only what step 1 detected, with pros and cons.
- If Secure Boot is in setup mode, also offer "Enroll Secure Boot keys (sbctl)". It is recommended for any TPM option.

**Step 4, local secrets, prompted on this machine and never from the sidecar**
- User login password, entered twice and hashed with `mkpasswd -m yescrypt`.
- LUKS passphrase (passphrase method, or the fallback) or the TPM PIN.
- The FIDO2 PIN is entered at enroll time by the token.
- A **recovery key** is generated by `systemd-cryptenroll --recovery-key` and shown once, with a QR code (`qrencode`, only displayed). The user confirms they recorded it by retyping 2 random groups. It is never stored anywhere.

**Step 5, partition/FDE**
- Evaluate the host's disko config with `loom.disk.device` = the chosen by-id, through a `--override-input`-free JSON arg.
- `disko --mode destroy,format,mount` with a temporary random keyfile in tmpfs.
- `systemd-cryptenroll` adds the chosen method(s) and the recovery key, then **wipes the temporary keyfile slot** (`--wipe-slot`).
- Passphrase method: `cryptsetup luksAddKey` from the prompt.

**Step 6, identity and keys** (all written under `/mnt/persist`)
- `/etc/machine-id`: from the sidecar, else `systemd-id128 new`. In reinstall mode it is new; the id stays as recorded in host.json.
- `/etc/ssh/ssh_host_ed25519_key`: the host key, which is also the silo transport identity.
- Host age key:
  - with a TPM: `age-plugin-tpm --generate -o /mnt/persist/var/lib/loom/age/host.tpm` (recipient `age1tag1…`)
  - otherwise: `age-keygen -o /mnt/persist/var/lib/sops-nix/key.txt` (0400, inside LUKS)
- Agent keys (when `loom.agents.enable`): `ssh-keygen` per nuketown agent with nuketown's expected secret names. The public halves go to `loom.host.agentKeys`.

**Step 7, hardware into the flake**
- `nixos-generate-config --root /mnt --no-filesystems --show-hardware-config` writes `hardware.nix`.
- Step 1's results are written to `hardware.json`.

**Step 8, secrets**
- `.sops.yaml` recipients = host recipient + `humanAgeRecipients`.
- `sops -e` (with `age-plugin-tag` on PATH for `age1tag1`) writes `secrets/host.yaml`: `user-password-hash`, agent private keys.

**Step 9, commit** in `/mnt/persist/var/lib/loom/host`, signed with the host key (principal `host:<id8>` in `.allowed_signers`). Message: `install: hardware, keys, secrets`.

**Step 10, install**
```
nixos-install --root /mnt --no-root-passwd --flake /mnt/persist/var/lib/loom/host#host \
  --option substituters "file:///run/loom/cache?trusted=1 file:///run/loom/xcache?trusted=1" \
  [--option extra-substituters "<netFallback>" only if online AND cache miss]
```
- The cache uses `require-sigs = true` with sidecar-pinned public keys. The `?trusted` flag is only on read-only media we verified.
- After the build, compare the toplevel with `sidecar.host.toplevel`. A mismatch is only expected for hardware deltas, so it is a warning, not an error.

**Step 11, enrollment** (spec "Bootstrap ownership")
- Online: push one commit with the enrollment key. The commit:
  - sets `.authorized_keys` = human + host + agent keys, with **no enrollment key**
  - sets `.silo/admins` = human + host
  - sets `.silo/owner` = host key, and adds the host and agent principals to `.allowed_signers`

  Silo S1 hands ownership to the host key. The installer then re-fetches and verifies the server state by attempting a no-op push with the enrollment key and **expecting a rejection**.
- Offline: the enrollment key moves to `/mnt/persist/var/lib/loom/enroll/key` (0400, inside LUKS). `loom-enroll.service` retries on `network-online` at first boot and shreds the key on success. The onboarding UI shows "enrollment pending" until then.

**Step 12, cleanup**
- Overwrite the CFG `sidecar.json` enrollment fields with zeros, then delete it. `shred` is best-effort on flash; it is safe because the key is already revoked by step 11. Tell the user to re-flash or wipe the stick.
- `efibootmgr`: make the installed Limine entry first and clear `BootNext`.
- `umount -R /mnt`, `cryptsetup close`, reboot.

**Reinstall mode differences (decision 3)**
- The installer clones the existing repo and generates new host, agent and age keys.
- Write authorization:
  - If a **human key survives** (the YubiKey `sk-ssh-ed25519` plugged in), the installer pushes, signed and transported with the human key:
    - `.authorized_keys`/`.silo/*`: new host and agent keys replace the old ones
    - `.silo/owner` = new host key
    - secrets **re-encrypted** with `sops updatekeys`. Decryption is through the human's age recipient (`age-plugin-yubikey`) if present; otherwise secrets are dropped and re-prompted (password now, others at first boot).
  - If **no authorized key survives**, it forks: mint a new id and repo (fresh enrollment key), copy the tree without secrets, and record `forkedFrom` in a commit message. The old repo is left orphaned. Its history is public anyway and holds no plaintext.

### e.6 Unlock capability matrix (installer screen text; the choice becomes `loom.unlock.*`)

| Method | Offered when | Pros (shown) | Cons (shown) | Resulting options |
|---|---|---|---|---|
| **Passphrase** | always | Works on any hardware. Nothing to lose but your memory. Disk is safe if the laptop is stolen, as long as the passphrase is strong (argon2id). | Typed at every boot. Can be shoulder-surfed. Strength is up to you. | `method="passphrase"`; autologin **on** (LUKS is the auth boundary, as in omarchy) |
| **FIDO2 key** (+PIN) | a FIDO2 token is plugged in | Hardware-backed, phishing-proof, PIN rate-limited by the token. One key can unlock several machines. No boot-chain/PCR brittleness. | The key must be present at every boot. Losing it means using the recovery key or fallback passphrase. Needs USB HID in initrd (handled). | `method="fido2"`, `fallbackPassphrase=true` (recommended); autologin **on** |
| **TPM2 + PIN** | TPM 2.0 present | Machine plus a short PIN; the TPM's anti-hammering lockout makes short PINs safe. Disk is useless outside this machine. | PIN at boot. With Secure Boot off, firmware updates can change PCRs, so you will need the recovery key after some updates. | `method="tpm2-pin"`, `pcrs=[7]` with SB or `[0 2 7]` without; autologin **on** |
| **TPM2 only** | TPM 2.0 present | Boots straight to the login screen with no typing. Disk is still encrypted against removal. | Anyone holding the whole machine gets to the login screen, so your **login password is the real lock** (autologin is turned off). Evil-maid resistance needs Secure Boot. PCR changes require the recovery key. | `method="tpm2"`, `pcrs` as above; autologin **forced off** (assertion) |

Always included:
- the recovery key, a separate LUKS keyslot
- Secure Boot enrollment offered when the firmware is in setup mode (`loom.boot.secureBoot.enable`, `boot.loader.limine.secureBoot.{enable,autoGenerateKeys,autoEnrollKeys}`)

Generated NixOS config:
- `boot.initrd.systemd.enable = true`
- `boot.initrd.luks.devices.cryptroot.crypttabExtraOpts = [ "tpm2-device=auto" ]` (or `fido2-device=auto`)
- `boot.initrd.systemd.tpm2.enable`
- Plymouth asks through `systemd-ask-password`, themed from omarchy's `omarchy.script`.

Open item carried from spec: the PCR policy. The default is `[7]` with SB, and the omarchy drop-in `SuccessExitStatus=1` for the NvPCR units is carried as a quirk.

### e.7 Offline vs online payload

| Mode | Image | Install source | Typical size |
|---|---|---|---|
| offline | p3 CACHE has all reference closures; xcache on CFG has the host delta | `file://` only; network never touched | 2.5–3.5 GiB |
| net | no p3 | `file://` xcache if present, then `https://cache.loom.farm` (signed), then `cache.nixos.org` | ~150–200 MB image |

Firmware filtering:
- The installed host gets `hardware.firmware = [ (loom.firmwareFiltered facts.firmwareGlobs) ]`, built at install from full `linux-firmware`, which is in the image cache. There is always an escape: `loom.hardware.firmware.mode = "full"`, settable, and the omarchy menu "Setup > Hardware > Full firmware" maps to it.

Installed store:
- `@nix` subvolume with `compress=zstd,noatime`
- `nix.settings.auto-optimise-store = true`

---

## f) Runtime

### f.1 Disk and impermanence layout (loom.disk / loom.persist)

```
GPT: ESP 2G vfat (/boot, Limine; room for generations) | LUKS2 "cryptroot" (rest)
cryptroot -> btrfs:
  @root        /            wiped each boot: initrd systemd unit restores from @root-blank
  @root-blank  (never mounted; empty read-only snapshot)
  @nix         /nix         compress=zstd,noatime
  @persist     /persist     neededForBoot
  @home        /home        persisted wholesale (H6)  [loom.persist.home.mode]
  @agents      /agents      nuketown btrfsDevice; @agents-blank snapshot for rollback
  @swap        /swap        only if loom.disk.swap/hibernate (nocow; resume_offset computed at install)
```

System persist list, merged from modules:

| source | paths |
|---|---|
| loom baseline (mynix pattern) | `/var/log`, `/var/lib/nixos`, `/var/lib/systemd/{coredump,timers,backlight,rfkill}`, `/var/cache/nix`, `/root`; files `/etc/machine-id`, `/etc/ssh/ssh_host_ed25519_key{,.pub}` |
| loom | `/var/lib/loom` (host repo, enroll, age), `/var/lib/sops-nix`, `/var/lib/sbctl` |
| omanix network | `/etc/NetworkManager/system-connections`, `/var/lib/NetworkManager`, `/var/lib/bluetooth`, `/var/lib/iwd` (if used) |
| omanix desktop | `/var/lib/upower`, `/var/lib/power-profiles-daemon`, `/var/lib/fprint`, `/var/lib/cups`, `/var/lib/omanix` (browser policy color, feature cache), `/var/lib/AccountsService`, `/var/lib/sddm` (last user) |
| omanix optional | `/var/lib/docker`, `/var/lib/tailscale`, `/var/lib/libvirt`, `/var/lib/flatpak` (gaming GeForce Now) |
| nuketown | `persist.users.<agent>` (projects, .claude, …) on `@persist` |

User state: all of `/home/<user>` survives, which covers `~/.local/state/omarchy`, `~/.config/omarchy`, the chromium profile, mise, the agent homes and so on.

`omanix doctor` still reports large unexpected writes under `/` that are not persisted (via `find / -xdev -newer /run/booted-system`), each with the option to add.

### f.2 Session and how upstream runs

- `programs.hyprland = { enable; package = omanix.hyprland.package; withUWSM = true; portalPackage = xdph; }`.
- SDDM: wayland, compositor = Hyprland running upstream `default/sddm/hyprland.lua`, theme = `omanix-sddm-theme` (upstream `Main.qml` recolored from the boot theme).
  - The session `.desktop` is upstream's `default/wayland-sessions/omarchy.desktop` (`uwsm start -g -1 -e -D Hyprland hyprland.desktop`), exposed via `services.displayManager.sessionPackages`.
  - Autologin follows §e.6.
- uwsm env: `share/uwsm/env.d/10-omarchy` comes from the upstream file in `omanix-data` and is on `XDG_DATA_DIRS`.
  - UNVERIFIED: uwsm searching data dirs for `env.d`. The test is `tests/desktop`, asserting `systemctl --user show-environment | grep OMARCHY_PATH=/run/current-system/sw/share/omarchy`.
  - Fallback: a `/etc/xdg/uwsm/env` drop-in.
- `/etc/profile.d/omarchy.sh` (upstream) goes through `environment.etc`. It sources the rewritten `env-bootstrap`.
- User units: upstream `default/systemd/user/*.service` are installed through `systemd.packages = [ omanix-data ]` (it has `lib/systemd/user`).
  - Enablement equals upstream first-run (`bt-agent, owed, omarchy-recover-internal-monitor, omarchy-sleep-lock, omarchy-migrate-notify→dropped, omarchy-fcitx5, omarchy-crash-watch`), via `systemd.user.services.<n>.wantedBy`.
  - Plus `wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf` (KillMode=mixed).
- **Seeding (H2)**: `omanix-seed-home.service`, a user oneshot run before `graphical-session-pre`:
  - first run: `cp -rn $OMARCHY_PATH/config/. ~/.config/` (skel semantics), plus `~/.bashrc` from `default/bashrc`, `~/.XCompose`, `applications/*.desktop` → `~/.local/share/applications`, nautilus-python extensions, branding txt, and the toggles from `omanix.hyprland.toggles`
  - then upstream `omarchy-provision-user` (patched only via overrides of its pacman steps) creates its own `done/` markers
  - `seed.refreshOnBump = "untouched"` keeps a sha manifest of what was seeded (`~/.local/state/omanix/seeded.json`) and refreshes only files the user never changed. This is the same algorithm as upstream's sha table in `omarchy-upgrade-to-quattro`.
- Upstream `omarchy-provision-first-run` runs from upstream `autostart.lua` unchanged. It is marker-gated.
- **Generated host module** `$OMARCHY_PATH/default/hypr/omanix.lua`, from `lib/lua.nix`. It is required at the end of upstream `omarchy.lua`, after the theme and before user files:
  ```lua
  -- generated by omanix; do not edit (change host.json / omanix.* options)
  hl.config({ ... omanix.hyprland.settings ... })
  hl.env("…", "…")
  hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.6 })
  hl.unbind("SUPER + RETURN")                              -- omanix.keybinds.unbind / replaces
  o.bind("SUPER SHIFT + B", "Browser (private)", { launch = "chromium --incognito" })
  o.window("^(org.gnome.Calculator)$", { float = true })
  -- extraLua
  ```
  The globals `omarchy_default_bindings` / `omarchy_preinstalled_bindings` must be set *before* the defaults load, and user files are not ours to edit. So `omanix-data` ships `default/hypr/omanix-pre.lua`, required at the **top** of upstream `omarchy.lua` (the same 2-line patch, §b.4). A user who uncomments the globals in their own `hyprland.lua` still wins, because that runs earlier and `omanix-pre.lua` only sets a global if it is nil.

### f.3 Theme switching

Runtime is upstream and unchanged:
- `omarchy-theme-set <slug>` stages `~/.local/state/omarchy/current/next-theme`, renders `default/themed/*.tpl` with upstream awk, swaps atomically, pushes to the shell over IPC, and retints terminals, tmux, btop, gnome, vscode, obsidian, claude, fcitx5 and so on.
- Picker: `SUPER+CTRL+T`, and the menu Appearance > Theme.

What nix does:
1. **Registry**: upstream `themes/*` plus `omanix.theme.extra.<slug>` are placed into `omanix-data/themes/`.
   - Untrusted extras go through the upstream denylist at build time (`*.lua`, terminal configs, `vscode.json`, symlinks removed), mirroring `INSTALLED_THEME_DENIED`.
   - `available` filters; `intros=false` strips `backgrounds/intros`.
   - Large images are symlinked into the store, not copied per host.
2. **Default and seed**: on first session, if `~/.local/state/omarchy/current/theme.name` is missing, `omanix-seed-home` runs `OMARCHY_THEME_WAIT=1 omarchy-theme-set <omanix.theme.default>`. That is exactly upstream's `install/user/theme.sh` behavior.
3. **Lock**: with `omanix.theme.lock = true`:
   - each login re-applies the default if it differs
   - the menu items `appearance.theme*` get `when = "false"` through `omanix.menu.items`
   - `omarchy-theme-set` is wrapped (an `overrides/`-free wrapper earlier on PATH: `omanix-theme-guard`) to print "theme is pinned by omanix.theme.default (run: omanix set omanix.theme.default <slug>)".
4. **Persisting a runtime choice**: `omanix theme keep` writes the current `theme.name` into `host.json` through `omanix set`. This is the "try at runtime, then commit declaratively" loop, offered by the menu as "Make default".
5. **Boot visuals are declarative** (they need a rebuild in omarchy too):
   - `omanix.theme.boot.theme` → `builtins.fromTOML (readFile themes/<slug>/colors.toml)` (pure; the flake input is source)
   - which feeds `omanix-plymouth` (upstream `omarchy.script` + assets recolored by ImageMagick in a derivation, `unlock.png` from the theme), the `omanix-sddm-theme` colors, and `boot.loader.limine.style` (palette, wallpaper)
   - Cantarell goes into the initrd.
   - The non-Latin keymap rule (facts gaps §2) is an assertion: the initrd falls back to `us` when the first layout is non-Latin.
6. **Root side effects**:
   - browser policy color: the override writes `/var/lib/omanix/browser-policy/color.json`, through a `security.sudo.extraRules` NOPASSWD rule for the store path with a hex-arg regex (upstream parity)
   - Plymouth: declarative (§5).
7. **Checks**: `checks.themes-render` runs the upstream renderer (`omarchy-theme-set-templates`) in a sandbox for **every** theme. It asserts no leftover `{{`, every template output produced, and that `colors.toml` parses with all canonical keys. This catches upstream theme regressions at bump time.

Trade-off recorded: build-time Stylix-style theming or HM specialisations would be more "nix", but they would break instant switching and fork the renderer. Rejected.

### f.4 Mutable vs declarative state

| Thing | Owner | Where | Survives rebuild | Survives reboot |
|---|---|---|---|---|
| omarchy defaults, bin, shell, themes | nix | `/run/current-system/sw/share/omarchy` | replaced (by design) | yes |
| host prefs (keybinds, monitors, settings, menu, shell defaults) | nix (host.json/host.nix) | `default/hypr/omanix.lua`, merged `omarchy-menu.jsonc`, `config/omarchy/shell.json` in omanix-data | replaced | yes |
| user overrides (`~/.config/hypr/*.lua`, `~/.config/omarchy/**`, terminal configs) | user / upstream scripts | `$HOME` (seeded once) | untouched | yes (@home) |
| runtime state (current theme, toggles, workspace layouts, monitor-workspaces, done markers) | upstream scripts | `~/.local/state/omarchy` | untouched | yes |
| system config (`/etc`) | nix | `/etc` | replaced | regenerated |
| system state | services | `/var/lib/*` listed in §f.1 | — | only if listed |
| secrets | sops | `/run/secrets` from `secrets/host.yaml` | re-decrypted | yes (via host key) |
| host repo working copy | human/agent | `/var/lib/loom/host` (group `loom-host`) | — | yes |

Precedence, low to high:
1. upstream defaults
2. theme
3. nix host module
4. user files
5. toggles

`omanix doctor` lists values where user files or toggles shadow a nix-set option, comparing `hyprctl getoption -j` against the expected values in `catalog/config.json`. It suggests either `omanix set` or deleting the user line.

**Rule enforced by check**: no nix module (and no HM module inside loom for the human) may own a path listed in `upstream/mutable-paths.txt`.

### f.5 Update, switch, watchdog, policy diff

`omanix update` (the menu "Update" and upstream's update indicator call it through the `omarchy-update` override):
1. Take the lock (`omarchy-update-lock` upstream), run `update-requires-free-space` (upstream), and start stay-awake (upstream).
2. In `/var/lib/loom/host`: `git pull --ff-only` from silo (public read).
3. `nix flake update omanix`, which moves to the newest **signed release tag**. `loom-host verify-input omanix` checks the tag signature against the pinned omanix release key in the current system. This is the spec's trust anchor.
4. Build, then `nvd diff /run/current-system result`, then show the summary with the gum confirm (upstream `update-confirm`).
5. Commit `update: omanix vX → vY`, signed by whoever runs it (human or agent key).
6. `loom-switch` (below).
7. On a promoted switch: `git push` to silo; run upstream `omarchy-update-restart` (reboot-required detection, now comparing `/run/booted-system/{kernel,initrd}` against `/run/current-system`); run the `omarchy-hook post-update` user hooks.

`loom-switch <toplevel|flake-ref>`, run as root via nuketown approval sudo or polkit for the human:
1. **Policy check** (on the host, never on the pusher):
   - Every commit in `deployed..new` must be signed by a principal in `.allowed_signers`, using the *deployed* version of that file, never the new one.
   - Evaluate `protectedView` for the deployed config (cached at `/run/current-system/loom/protected.json`) and for the new one. If they differ, a **human approval** is required:
     - either the head commit is signed by a `human:*` principal,
     - or there is an annotated tag `approve/<sha>` signed by the human.
   - The approval gesture is the nuketown GUI sudo dialog (later XMPP). It shows the protected diff, and on approve it invokes `git tag -s` with the human's `sk-ssh` key, so a YubiKey touch is the signature.
2. `switch-to-configuration test`.
3. Arm the watchdog: `systemd-run --on-active=${timeout} loom-rollback <prev-toplevel>`.
4. Health checks (`loom.switch.healthChecks`):
   - loom: `network` (NM connectivity or a route), `silo` (`git ls-remote` of the host repo)
   - omanix: `compositor` (`hyprctl -j monitors` as the session user via `machinectl shell`/`runuser` with `HYPRLAND_INSTANCE_SIGNATURE`), `shell` (the `omarchy-shell` process is up and its IPC answers), `configerrors` (`hyprctl configerrors` is empty)
5. Pass: cancel the watchdog, set the system profile, `switch-to-configuration boot`. Post-switch hooks:
   - omanix runs `hyprctl reload` for each session
   - it restarts `omarchy-shell` only if the `shell/` store path changed (`omarchy-restart-shell`)
   - nuketown `postSwitchHooks`
6. Fail or timeout: `loom-rollback` re-activates the previous toplevel with `test`, leaves the boot default unchanged, and sends a notification through upstream `omarchy-notification-send` with the failing check and the journal cursor.

Default `loom.policy.protected` (spec list, as option paths and prefixes):
```
users.users  users.mutableUsers  security  nix.settings.trusted-users  nix.settings.substituters
nix.settings.trusted-public-keys  services.openssh  boot  networking.firewall  loom.host  loom.policy
loom.unlock  loom.sops  loom.agents  nuketown.agents.*.sudo  omanix.dns  omanix.region
+ file hashes: .authorized_keys .allowed_signers .silo/* .sops.yaml
```

`protectedView` projects these into JSON with:
- functions stripped
- packages reduced to their `outPath`
- `boot` limited to `{loader, initrd.luks, kernelParams, kernelPackages.kernel.version, secureBoot}`, which avoids churn from irrelevant attrs. That restriction is a deliberate list, reviewed in `policy` skill.

Desktops never auto-switch on push (`loom.switch.autoSwitchOnPush = false`). Switches are agent- or human-initiated.

---

## g) Agent surfaces

### g.1 In the omanix repo
- `AGENTS.md` (router, ≤150 lines) covers:
  - the layer map (§1)
  - "never edit upstream copies; add to `upstream/`"
  - file path == option path
  - `mkDefault` everywhere
  - `nix flake check` is the only gate
  - test etiquette (from omarchy: log to file, don't rerun blindly, name the regression)
  - never improvise disk operations; use the scripts
- Skills: §a.1. **bump-omarchy** is the key one for this angle:
  1. `nix flake update omarchy` (or `--override-input` to a tag).
  2. `nix build .#checks.x86_64-linux.upstream-drift`. It emits `drift.json`:
     - overrides whose upstream hash changed (with the diff)
     - patches that fail
     - new or removed bin scripts
     - new forbidden tokens
     - new `hl.*` symbols
     - unmapped `*.packages` lines
     - unmapped hardware leaves
     - PKGBUILD version deltas (omarchy-pkgs vs `pkgs/by-name`)
     - menu items whose actions reference dropped scripts
  3. Fix each item, so the manifest is the to-do list.
  4. `nix flake check` (eval + VM).
  5. Commit `bump omarchy vA→vB` with drift.json summarized.
- `docs/upstream-tracking.md` explains each `upstream/` file.

### g.2 On the installed machine
- `/run/current-system/sw/share/omanix/`, produced by `omanix-catalog` at build time:
  - `options.json`: `nixosOptionsDoc` of `omanix.*` and `loom.*`, plus `declarations` and `settable`
  - `config.json`: the effective `config.omanix` and `config.loom` (functions stripped)
  - `commands.json`: upstream `omarchy commands --json`, generated in the build sandbox by running upstream's router in `--json` mode over the patched bin tree, merged with `omanix` subcommands; each entry has an `origin` of `upstream`, `override` or `omanix`
  - `keybinds.json`: from §6.4 below
  - `menu.json`: the merged, ordered menu
  - `themes.json`: slug, mode, accent, trusted
  - `features.json`: enabled apps and features for `omarchy-pkg-present`
  - `upstream.json`: tag, rev, overrides, drops, patches
- `omanix` CLI. Every subcommand takes `--json` and needs no TTY. Exit codes: 0 ok, 1 error, 2 usage, 3 policy-refused.
  - `omanix options [query]`, `omanix get <path>`
  - `omanix where <path>`: the declaring file, and the defining file from `definitionsWithLocations`, which is host.json / host.nix / module
  - `omanix where key "SUPER + RETURN"`: upstream Lua file:line or nix option
  - `omanix where menu <id>`
  - `omanix set <path> <json>`: only settable options. It validates by evaluating, writes host.json, and commits.
  - `omanix apply [--dry]` (build, nvd, loom-switch, push); `omanix update`; `omanix rollback` (previous generation + `git revert`)
  - `omanix commands` (merged catalog), `omanix status` (generation, flake rev, host id, dirty, enrollment state, pending first-boot prompts), `omanix doctor` (failed units, `hyprctl configerrors`, shadowed options, persist gaps, sops decryptability, cache reachability)
  - `omanix upstream` (pinned omarchy rev and override list), `omanix theme keep`
- Upstream agent features are kept as-is, with nix supplying binaries instead of mise:
  - the default-agent picker
  - the quake console `SUPER+grave` seeded with `omarchy-agent`
  - crash-watch (`omarchy-crash-watch` user unit, enabled) with `services.nixseparatedebuginfod.enable = true` for symbolization
  - shipped skills symlinked into `~/.claude/skills` and similar directories by upstream `omarchy-provision-user`
- omanix adds `omanix` and `omanix-host` skills (installed under `$OMARCHY_PATH/default/agents/skills/`, so upstream's linker picks them up). Their option tables are generated from `options.json`, so they can't drift.
- With nuketown residents: `nuketown.agents.<n>.claudeCode.extraPrompt` gets a generated omanix fragment (host repo path, `omanix` CLI, `loom-switch` policy). The agent's working copy is `/var/lib/loom/host` (group `loom-host`), and pushes use the agent's own key.
- Host repo `CLAUDE.md` (≤40 lines):
  - "you are in the host flake for <hostname>"
  - "change settings with `omanix set`; host.nix only for things without a settable option"
  - "never edit hardware.nix by hand"
  - "protected changes need Josh's approval tag"
  - "`omanix apply`"

### g.3 Keybind catalog without forking Lua (H7)
- `omanix-catalog` runs `lua5_5` over upstream `default/hypr/omarchy.lua` plus the generated `omanix.lua`, with a **recording stub** for `hl.*` (`hl.bind`, `hl.unbind`, `hl.config`, `hl.on`, `hl.dsp.*` return tagged tables). This is the same replay idea upstream uses in `omarchy-menu-keybindings` via `o.bind_commands`.
- Output: `keybinds.json` entries of `{keys, description, dispatcher, source: "file:line"}`.
- The stub symbol set is generated from `hl-symbols.txt`, so a new upstream symbol fails the drift check before it can break the catalog.
- `checks.keybind-conflicts` fails on two enabled binds with identical normalized keys unless one `replaces` the other. Both locations are named.

### g.4 Menu as data (order-preserving)
- `lib/jsonc.nix` parses upstream `omarchy-menu.jsonc` at eval time:
  - `readFile` of the flake input is pure
  - it strips `//` comments outside strings with a small `builtins.split` tokenizer
  - it drops trailing commas
  - it records **file order** for each id
- `checks.jsonc-equivalence` compares the result to python `json5` on the same file in a derivation.
- `omanix.menu.items` is pre-populated with `{ ...upstream fields; order = n; }` at `mkDefault`. Retargets from `install-map.toml` set `action` at normal priority. Host additions use `after = "<id>"`.
- Rendering sorts by `(order, after-chains)`, not by Nix's alphabetical attr order, so the upstream menu order is preserved exactly.
- The output is written as `default/omarchy/omarchy-menu.jsonc` in omanix-data. The user extension file `~/.config/omarchy/extensions/omarchy-menu.jsonc` remains the user layer.
- Install/Remove rows: `disabled` conditions that used `omarchy-pkg-present` keep working through the override that reads `features.json`.

---

## h) Testing

### h.1 Checks (`nix flake check` = eval everything + run all VM tests)

| check | what |
|---|---|
| `eval-ref-*`, `eval-template` | every reference host and the host template evaluate (x86_64; aarch64 eval-only) |
| `options-documented` | every `omanix.*`/`loom.*` option has a description; settable options have an example |
| `host-schema` | the JSON Schema is generated; the template's host.json validates; a fuzz case with an unknown key fails eval |
| `upstream-drift` | §g.1 report; fails on any unclassified item |
| `upstream-build` | `omarchy-src` builds (post-checks: no `/usr/`, no pacman, luac parse, hl symbols) |
| `themes-render` | the upstream renderer over every theme (§f.3) |
| `jsonc-equivalence`, `menu-render` | menu parse parity; every action's first word is on PATH in ref-default |
| `keybind-conflicts` | §g.3 |
| `mutable-paths` | no nix-owned file ∈ `upstream/mutable-paths.txt` |
| `pkgbuild-versions` | `pkgs/by-name` versions vs omarchy-pkgs PKGBUILDs (warn on minor, fail on a missing package) |
| `closure-size` | `ref-default` toplevel ≤ budget (start at 4.0 GiB NAR, ratchet down); installer-net ≤ 200 MB; forbidden deps |
| `scripts-lint` | shellcheck + `bash -n` on `scripts/*` and `upstream/overrides/**`, plus signature presence on tags |
| `nuketown-matrix` (in nuketown) | its checks on 26.05 and unstable |

### h.2 nixosTests (all in `checks`, KVM required)

1. **`desktop`** (omanix): `ref-default` without FDE. Autologin; wait for `wayland-wm@hyprland.desktop.service`.
   - Assertions:
     - `hyprctl -j version` shows 0.56.2
     - `hyprctl configerrors` is empty
     - the titlebars plugin is loaded after `SUPER+L` cycles to floating mode
     - `omarchy-shell` is alive with no `qml:` errors in its journal
     - `OMARCHY_PATH` is in the user env
     - `omarchy-menu summon root` gives a screenshot, OCR'd with tesseract for "Apps"
     - a bind added in nix fires (`wtype`/`hyprctl dispatch` sends it and its side-effect file appears)
   - The VM uses `virtio-vga` with the omarchy `software-renderer` patch (H5). This resolves the facts UNVERIFIED items for Qt 6.12 and for Mesa on virtio.
2. **`theme-switch`**:
   - `omarchy-theme-set nord`: `theme.name` = nord, the foot theme file changed, and the shell got `applyTheme`
   - with `theme.lock = true`, re-login restores the default
   - `omanix theme keep` modifies host.json in the test repo
3. **`impermanence`** (loom, plus the omanix desktop variant):
   - write `/etc/junk`, `/var/lib/bluetooth/x`, `~/.local/state/omarchy/current/theme.name`, then reboot
   - junk is gone; the other two are kept; machine-id and ssh host key are unchanged
4. **`fde-passphrase` / `fde-tpm2` / `fde-tpm2-pin` / `fde-fido2`** (loom):
   - a disko-formatted second disk with `systemd-cryptenroll`
   - boot through the systemd initrd with `virtualisation.tpm.enable` (swtpm) or `canokey`
   - the recovery key also unlocks
   - modeled on nixpkgs `systemd-initrd-luks-*`
5. **`sops-tpm`** (loom): `age-plugin-tpm` host key, `sops` encrypt to `age1tag1` with `age-plugin-tag`, decrypt via sops-nix `sops.age.plugins`. This settles facts §9 UNVERIFIED.
6. **`installer`** (loom + omanix), the end-to-end test. Nodes:
   - `silo`: seed `nixosModules.silo-standalone` (S4) with a pre-seeded host key
   - `target`: a UEFI VM with swtpm, the installer raw image attached as a USB stick (`-device usb-storage`), and an empty virtio disk

   Steps:
   1. The test driver mints a host with `mint-host.sh` against `ssh://git@silo/omanix/<fixed test id>.git` (the cmdline `loom.silo=silo` and the sidecar both point there). The fixed id is reused every run (decision 2).
   2. The driver writes CFG files with `mtools` into the raw image copy.
   3. Boot and drive the gum TUI with `send_chars`: pick the disk and type the ERASE confirm, choose "TPM2 + PIN", enter a password, confirm the recovery key.
   4. Assertions:
      - install completes offline (the target has no route to the internet; only `silo` is reachable)
      - silo `.authorized_keys` = human + host + agent and no enrollment key
      - `.owner_key` = host key (S1)
      - a push with the enrollment key is rejected
      - an agent-key push touching `.authorized_keys` is rejected (S2)
   5. Reboot with TPM PIN unlock into the desktop.
   - Guard: the test's DNS has no `silo.loom.farm`, and `checks.no-prod-silo-in-tests` greps all test sidecars and cmdlines.
7. **`reinstall`**: reuse the repo from test 6 (same id via `loom.host=<id>` cmdline). The human test key (plain ed25519 standing in for the YubiKey) authorizes. Assert in-place `.authorized_keys` rotation and re-encrypted secrets. A variant with no surviving key asserts a fork to a new id.
8. **`enroll-offline`**: silo unreachable during install. Enrollment is pending at first boot. Bring the silo link up; `loom-enroll` completes and shreds the key.
9. **`switch-watchdog` / `policy`**:
   - a host commit that breaks the compositor (`omanix.hyprland.package` = a stub that exits) auto-rolls back within the timeout, and the boot default is unchanged
   - an unsigned commit is refused
   - an agent-signed commit changing `services.openssh` is refused (exit 3)
   - adding a human `approve/<sha>` tag lets the switch proceed
10. **`flash-usb`**: in a VM with loop devices and an emulated usb-storage disk:
    - refuses a non-removable disk, a mounted partition, and the root disk
    - accepts the USB disk with the correct serial suffix
    - the read-back verification passes

---

## i) Work breakdown (independently buildable packages)

Each package builds and passes its acceptance test against stubs and fixtures from earlier packages. "Deps" means a hard dependency.

| # | Package | Repo | Scope and files | Deps | Acceptance test |
|---|---|---|---|---|---|
| P1 | **nuketown additive options** | nuketown | §a.3: `persistRoot`, `sops.ageKey`, `extraHomeConfig` as a deferredModule, `switch.{backend,command,postSwitchHooks}`, approvalDaemon `{prompter,display,target,notify}`, `pkgs.unstable` fallback, 26.05+unstable check matrix | — | existing checks green on both channels; a signi-shaped fixture evaluates byte-identical `/etc` (`nix store diff-closures` empty for the old defaults) |
| P2 | **loom core and mkHost** | loom | channel-agnostic flake, `lib/{mkHost,hostJson,schema,appId}.nix`, `modules/loom/{default,host,user,locale,agents}.nix`, the old kiosk refactored behind `firstboot.mode` (auth server deleted), removal of dead `installer.nix` | P1 | `checks.host-schema`; template host evaluates; an unknown host.json key fails with a named error |
| P3 | **loom disk/unlock/persist/sops/boot** | loom | `disk.nix` (disko layout §f.1), initrd root rollback, `unlock.nix`, `boot.nix` (limine + SB hooks), `persist.nix`, `sops.nix` (tpm/age) | P2 | VM tests `impermanence`, `fde-*` (4), `sops-tpm` |
| P4 | **omarchy desktop packages** | omanix | `pkgs/by-name/*`: hyprland-omarchy + patches, titlebars, quickshell-omarchy, guiutils, the 13 leaf apps, try-tobi | — | `nix build` of all; `checks.pkgbuild-versions`; a tiny VM loads `titlebars.so` via `hyprctl plugin load` |
| P5 | **upstream pipeline and drift** | omanix | `lib/upstream.nix`, `upstream/{pin,manifest,rewrites,packages,install-map,hw-quirks,hl-symbols,mutable-paths}.toml/txt`, the initial patches and overrides, `pkgs/by-name/omarchy-src` | P4 (titlebars path) | `checks.upstream-build`, `checks.upstream-drift` green on the pinned tag; a synthetic bump fixture (a modified upstream file) makes drift fail with the right item |
| P6 | **omanix-data, Lua gen, menu, keybinds, shell** | omanix | `lib/{lua,jsonc,menu}.nix`, `modules/omanix/{path,hyprland/*,keybinds,menu,shell,defaults,apps/*}.nix`, `pkgs/by-name/omanix-data`, `omanix-catalog` (keybind stub) | P5 | `checks.{jsonc-equivalence,menu-render,keybind-conflicts}`; golden-file test of the generated `omanix.lua` |
| P7 | **omanix session and system module** | omanix | `modules/omanix/{session,login,seed,packages,input,fonts,audio,network,dns,power,printing,security,region,persist,health}.nix` | P3, P6 | VM `desktop` |
| P8 | **themes and boot visuals** | omanix | `modules/omanix/theme/{default,boot}.nix`, `pkgs/by-name/{omanix-plymouth,omanix-sddm-theme}`, theme guard, `theme keep` | P6, P7 | `checks.themes-render`; VM `theme-switch`; a screenshot of the plymouth prompt in `fde-passphrase` with the omanix flavor |
| P9 | **hardware quirks and detection** | omanix + loom | `modules/omanix/hardware/{default,quirks/*}.nix` (one per `hw-quirks.toml` row), `loom-detect` (runs upstream `omarchy-hw-*`), `loom.hardware.firmware` filter | P5, P2 | `checks.upstream-drift` hw coverage; eval matrix over fixture `hardware.json`s (nvidia-gsp, t2, framework16, asus-ptl); firmware-filter derivation builds |
| P10 | **silo deltas** | seed | S1–S4 (+S5) in `instances/silo/{shell,hooks}.nix`, `nixosModules.silo-standalone` | — | seed checks; a VM with standalone silo covering: auto-create, owner handoff, protected-path reject, path hardening rejects |
| P11 | **installer image and TUI** | loom (+ omanix wiring) | `lib/mkInstallerImage.nix` (repart, 4 partitions, cache staging), `pkgs/loom-installer` (gum TUI, steps 0–12), `loom-mint`, `loom-enroll`, `modules/loom/{installer/*,enroll}.nix`; omanix `installer-{offline,net}` outputs | P3, P9, P10 | VM `installer`, `reinstall`, `enroll-offline`; `checks.closure-size` for the images |
| P12 | **scripts and skills (spec repo layout)** | omanix | `scripts/{flash-usb,mint-host,stage-cache,verify-self}.sh` + signatures, `.claude/skills/{configure,build-installer}`, `templates/host` | P11 (mint logic shared) | VM `flash-usb`; mint-host output validates against the schema; the skill dry-run produces a sidecar consumed by the `installer` test |
| P13 | **policy diff, switch watchdog, update** | loom (+ omanix health/update override) | `modules/loom/{policy,switch,update}.nix`, `pkgs/loom-switch`, `lib/protectedView.nix`, nuketown approval integration (approve-tag signing), omanix `overrides/bin/omarchy-update*`, `health.nix` | P2, P1, P7 | VM `switch-watchdog`, `policy`; an update e2e in the `desktop` VM (bump a local omanix tag, then `omanix update`) |
| P14 | **agent surfaces and CLI** | omanix | `pkgs/by-name/omanix-cli`, `catalog.nix` (all JSON), AGENTS.md/CLAUDE.md, skills (bump-omarchy, override-upstream, add-*, vm-test), host template CLAUDE.md, docs generation | P6, P13 | `omanix {options,get,where,set,commands,status,doctor} --json` golden tests in the `desktop` VM; `checks.options-documented`; the skill option tables regenerate with no diff |

Parallelism:
- **Wave 1** (no deps): P1, P4, P10.
- **Wave 2:** P2, P5.
- **Wave 3:** P3, P6, P9.
- **Wave 4:** P7, then P8 and P13.
- **Wave 5:** P11, then P12; P14 last.

Critical path: P4 → P5 → P6 → P7 → P11/P13.

---

## j) Trade-offs and open items (explicit)

1. **Non-hermetic upstream scripts (H1).** About 170 tools are on the system PATH, as on Arch. Mitigations: `menu-render` checks that every action's first command resolves, and `commands.json` generation fails on a missing interpreter. resholve-ing 558 scripts was rejected: the per-bump patch churn defeats the angle.
2. **Nix sits below user files (H2/H7).** An agent setting `omanix.hyprland.monitors` can be silently shadowed by `~/.config/hypr/monitors.lua`. `omanix doctor` and `omanix where` surface this. That is the price of upstream's runtime writers working.
3. **The unstable channel (H4)** brings churn risk to loom-based non-omanix hosts only if they choose it. loom itself is channel-agnostic.
4. **A per-host OMARCHY_PATH tree** costs about 15 MB per generation of text copies. Accepted for QML/symlink robustness. If the VM test proves symlinked QML fine, switch to a symlink farm.
5. **Upstream is pinned by tag, not by `quattro` HEAD**: a slower uptake of fixes, but reproducible. `omanix.upstream.devPath` and `--override-input omarchy` give a dev loop.
6. **Theme lock off by default** (omarchy UX). Fleet or agent-managed hosts set `omanix.theme.lock = true`.
7. Open, from the spec:
   - TPM PCR policy without SB
   - the exact protected list (the default in §f.5 lives in loom; flavors may only *add*, which is enforced by a check that the flavor's list ⊇ loom's)
   - the Seed-side builder (not in v1; local Nix or WSL2 only)
   - read-gated silo repos (not planned)
8. UNVERIFIED items, each owned by a test:
   - uwsm env.d discovery (`desktop`)
   - Qt 6.12 + quickshell-omarchy (`desktop`)
   - Mesa on virtio with the software-renderer patch (`desktop`)
   - `age1tag` round trip (`sops-tpm`)
   - Limine + TPM2 PCR 7 stability across generations (`fde-tpm2` reboots twice after a generation change)
