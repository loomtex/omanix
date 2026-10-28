# omanix toolchain facts (verified 2026-10-27)

Checked with `git ls-remote`, `nix eval` against fresh `nixos-26.05` and `nixos-unstable` tarballs, `nix flake metadata`, and by reading sources. Nothing from the omarchy reference tree was executed. Where something could not be confirmed, it is marked **UNVERIFIED** with the test that would settle it.
Scope follows spec rev 16: USB installer image only, whole-disk install, and credentials that are never copied by the installer.

## 1. Channels and pins

| Thing | Value |
|---|---|
| nixpkgs `nixos-26.05` | `718f670e84`, `.version` 26.05 (stable) |
| nixpkgs `nixos-unstable` | `3ec636362e`, `.version` 26.11 |
| nixpkgs `nixos-25.11` | `b6018f87da` (**loom and nuketown still pin 25.11** and HM release-25.11; mynix is already on 26.05) |
| nix on signi | 2.34.9 |
| Hyprland latest release | **v0.56.2** (tags v0.56.0/.1/.2), flake rev `efb5099378` |
| omarchy upstream | `github:omacom/omarchy`, default branch **`quattro`** (HEAD `83f040099f`). Tags: v4.0.0 (2026-08-14) … **v4.0.6** (2026-10-19), **v4.5.0-rc2** (2026-10-27). The `version` file still reads `4.0.0.alpha` on every tag, so don't trust it and pin by tag or rev. The reference checkout `bc220e7` is on `quattro` and has diverged from v4.5.0-rc2 (5 ahead, 6 behind). License: MIT (DHH). |
| sops-nix | HEAD `60182817ee` (2026-10-26) |
| disko | v1.13.0 (HEAD `cedd626e11`) |
| impermanence | HEAD `fa627f4c8b` (2026-10-23), no tags |
| lanzaboote | v1.2.0 |
| nixos-generators | **archived** upstream (last tag 1.8.0). Its functionality lives in nixpkgs now (§6). Do not use it. |

## 2. Hyprland: Lua config

- Lua config landed in **v0.55.0** (`src/config/lua/*`, `example/hyprland.lua`). v0.54 has none. It links **Lua 5.5** (`pkg_search_module(LUA … lua>=5.5 lua<5.6)`). nixpkgs has `lua5_5` 5.5.1 on both channels.
- Config discovery (v0.56.2 `src/config/ConfigManager.cpp`): when the main config path ends in `.lua`, the Lua manager is used; otherwise it falls back to the legacy `.conf`. Candidates are `<base>.lua` and `<base>/init.lua`. `package.path` is prefixed with `<configdir>/?.lua;<configdir>/?/init.lua`.
- omarchy's `config/hypr/hyprland.lua` does `dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")`. bootstrap.lua prepends `~/.local/state/?.lua; ~/.config/?.lua; $OMARCHY_PATH/?.lua` to `package.path` and then `require("default.hypr.omarchy")`. **Setting OMARCHY_PATH to a store path is enough for the Lua side.**
- API coverage: omarchy uses 63 distinct `hl.*` symbols (grep of default/, config/, themes/, shell/, bin/). Each was checked against the Lua binding sources:
  - **v0.56.2**: all present except `hl.plugin.hyprbars.*`, which comes from the titlebars plugin, not core.
  - **v0.55.x**: missing `hl.dsp.workspace.change_id`, `hl.get_loaded_plugins` and `hl.exec_scheduled_prop_refresh_immediately`. Those are used in `default/hypr/{workspace-modes,monitor-workspaces,qconsole}.lua` on `quattro` HEAD, but **not** in tag v4.0.6.
  - **Conclusion: the quattro / 4.5 line requires Hyprland ≥ 0.56.** Arch omarchy ships 0.56.2 plus 4 patches (`software-renderer`, `nvidia-egl-teardown`, `wl-output-global-grace`, `monitor-rule-vrr`, in omarchy-pkgs/pkgbuilds/hyprland).
- nixpkgs `hyprland`: **26.05 = 0.55.4 (too old for quattro HEAD)**, unstable = 0.56.2.
- hyprwm flake `github:hyprwm/Hyprland/v0.56.2`:
  - outputs: `packages.<sys>.{default,hyprland,hyprland-unwrapped,hyprland-debug,hyprland-with-tests,xdg-desktop-portal-hyprland,…-cross}`, `nixosModules.default`, `homeManagerModules.default`, `overlays.{default,hyprland-packages,hyprland-extras,…}`, checks, devShells.
  - Its own `nixpkgs` input is unstable `e72e4f2994`. It locks `hyprland-guiutils` v0.2.2 (`a16ad89`), aquamarine, hyprlang, hyprutils, hyprwire, hyprtoolkit and xdph.
- `hyprland-guiutils` (omarchy dep) is **not in nixpkgs** under that name; nixpkgs only has the predecessor `hyprland-qtutils` 0.1.5. Get it from `github:hyprwm/hyprland-guiutils` (v0.2.2) or through the Hyprland flake's overlays.
- Titlebars: omarchy loads `/usr/lib/omarchy-hyprland-titlebars/titlebars.so` (hard-coded constant in `default/hypr/workspace-modes.lua:26`) through `hl.plugin.load`.
  - Source: `github:omacom/omarchy-hyprland-titlebars` v0.2.2 (BSD-3 + MIT, cmake, deps hyprlang and hyprutils). It is a hyprbars-API plugin.
  - Plugins only load into **the exact Hyprland build they were compiled against**, so build it with `hyprlandPlugins.mkHyprlandPlugin` against the same `hyprland` derivation and substitute the path.
  - nixpkgs `hyprlandPlugins.hyprbars` = 0.56.0 on unstable and 0.55.0 on 26.05.
- `programs.hyprland.withUWSM` exists in nixpkgs, and uwsm is 0.26.4 on 26.05 and 0.27.1 on unstable. omarchy relies on uwsm: 57 files, and the shell reads OMARCHY_PATH from the uwsm env.

## 3. Quickshell

- omarchy (Arch) builds **quickshell `0.3.2.r7.g2b4501a`**, which is v0.3.2 plus 7 commits, with `load_qtquick_611.patch` (Qt 6.11 QML scanner/intercept fix).
  - The 7 commits: hyprland/ipc follows workspace-id changes (pairs with `hl.dsp.workspace.change_id`), wayland/lock `lockStateChanged`, screencopy null-screen crash, desktop-entry trim, scriptmodel identity updates, MOC namespaces, light-dep metatypes.
- nixpkgs: **26.05 = 0.3.0 (Qt 6.11.2)**, **unstable = 0.3.2 (Qt 6.12.0)**, with no extra patches.
- A flake exists: `github:quickshell-mirror/quickshell` → `packages.<sys>.{default,quickshell}`, `overlays`, `devShells`. Pin it to `2b4501a2826…` (or later; HEAD is `9b0f339`) and review and vendor the 611 patch if building against Qt 6.11. omarchy also has a `fix-qt612-color` branch, a hint that Qt 6.12 regressions exist. **UNVERIFIED**: whether the omarchy shell runs on Qt 6.12 unpatched. Test: VM smoke test, `qs -p $OMARCHY_PATH/shell` with no QML errors.
- Quattro replaced the older components: walker, elephant, mako, hyprlock, hypridle, waybar and swayosd now appear only in `bin/omarchy-upgrade-to-quattro` (removal) and incidental QML strings. **Do not package them.** The shell is also the polkit agent, the lock screen, the notifier and the OSD.

**Channel implication**: Hyprland ≥0.56, guiutils and quickshell ≥0.3.2 are all unstable-era.
- Option A: run the desktop on `nixos-unstable`.
- Option B: stay on 26.05 and take hyprland, quickshell and guiutils from their flakes (or from a nixpkgs-unstable overlay), with all three following one nixpkgs so Qt, Mesa and wayland libraries match.
  - B **UNVERIFIED** risk: the Hyprland wiki warns about a Mesa mismatch when the flake's Hyprland runs on a different nixpkgs. Test: VM test that runs Hyprland and the shell on virtio-gpu.

## 4. omarchy runtime deps vs nixpkgs (unstable unless noted)

**Present** (version on unstable; 26.05 differs where noted):
- herdr 0.9.5 (absent on 26.05; upstream `herdrdev/herdr`; omarchy's README links `omacom-io/herdr`)
- hyprland-preview-share-picker 0.2.1 (absent on 26.05; `WhySoBad/hyprland-preview-share-picker`)
- cliamp 2.3.0 (bjarneo/cliamp), disktree 0.10.1 (tobi/disktree), usage 7.0.1 (jdx), mise, xdg-terminal-exec, gum, localsend, obsidian, pinta, moonlight-qt, voxtype 1.1.1, tzupdate, starship, plocate, foot, imv, mpv, nautilus-python, sushi, evince, yaru-theme, font-awesome 7.2.0, nerd-fonts.jetbrains-mono 3.5.0 (omarchy uses 3.5.1), noto-fonts / -cjk-sans / -color-emoji, cantarell-fonts (Plymouth), ia-writer-mono, bluez-tools, ddcutil, qrencode, zbar, cups-pk-helper, bolt, gpu-screen-recorder (5.13.8 on 26.05, 6.1.4 on unstable; omarchy has a `minimum-version` fix branch), satty, hyprpicker, hyprsunset, xdg-desktop-portal-hyprland, lua5_1 + luarocks, tree-sitter, fcitx5, tesseract, sbctl 0.18, tpm2-totp, zram-generator, snapper, wiremix, bluetui, impala
- elephant and walker exist but are not needed (see §3)

**Name collision**: nixpkgs `try` is `binpash/try`, **not** `tobi/try`, which omarchy uses (95 references). Package tobi/try under another attribute name.

**Missing from nixpkgs; must be packaged.** Sources are taken from `omacom-io/omarchy-pkgs/pkgbuilds/*/PKGBUILD`, and upstream tags were confirmed with ls-remote.

| pkg | ver | source | build | license |
|---|---|---|---|---|
| owe (+ owe-lockfeed) | 0.2.12 | github:omacom/owe | meson; mpv ffmpeg wayland libglvnd libepoxy socat. Video wallpaper, feeds lock-screen frames | MIT |
| ttfx | 0.5.1 | github:omacom/ttfx | cargo. Terminal text FX for the screensaver (replaced `tte`) | MIT |
| omacalc | 0.3.1 | github:omacom-io/omacalc | make + qt6 base/declarative | MIT, OFL |
| aether | 4.32.0 | github:omacom/aether | webkit2gtk-4.1 + gtk3 | MIT |
| omarchy-hyprland-titlebars | 0.2.2 | github:omacom/omarchy-hyprland-titlebars | cmake; mkHyprlandPlugin | BSD-3, MIT |
| omarchy-nvim | 2026.9.21 | LazyVim/starter main tarball + omarchy theme import | no real build (needs neovim, git); better as an omanix nvim module | MIT |
| omasnap | 1.24.0 | github:omacom/omasnap | cmake; layer-shell-qt qt6 tesseract wl-clipboard | MIT, OFL |
| omacut | 0.7.2 | github:omacom/omacut | make + qt6 (multimedia) ffmpeg | MIT |
| omawrite | 0.7.2 | github:omacom/omawrite | make + qt6 | MIT, OFL |
| hype | 0.6.0 | github:omacom/hype | make + qt6 ≥6.9, source-highlight, libwebp | MIT |
| signed | 0.3.1 | github:omacom/signed | make + qt6, poppler-qt6, qpdf | MIT |
| monologue | 0.3.1 | github:omacom/monologue | make | MIT |
| gliff | 0.4.1 | github:omacom/gliff | cargo | MIT, BSD-2 |
| asdcontrol | 0.6.0 | github:omakasui/asdcontrol | make, plus a sudoers drop-in | GPL-2 |
| hyprland-guiutils | 0.2.2 | github:hyprwm/hyprland-guiutils (flake) | — | BSD-3 |

**Not needed or out of scope**:
- `omarchy-power-profiles-daemon` (stock PPD 0.30 plus ARM cppc patches). x86 uses stock `services.power-profiles-daemon`.
- `linux-omarchy`. Use nixpkgs kernels.
- `superwhisper-bin`, `ufw` / `ufw-docker`. Use the NixOS firewall.
- `kernel-modules-hook`, `limine-mkinitcpio-hook`, `limine-snapper-sync`, yay, pacman.

## 5. How omarchy locates its files (for store-path substitution)

Counts cover 1876 files and exclude manual/, test/, migrations/, docs/ and plans/:

| pattern | lines / files | notes |
|---|---|---|
| `OMARCHY_PATH` | 378 / 177 | bin 119, shell 19, default 19, install 14, agents 3. Default is `${OMARCHY_PATH:-/usr/share/omarchy}` (bash), `env_or("OMARCHY_PATH","/usr/share/omarchy")` (Lua `default/hypr/paths.lua`) and `Quickshell.env("OMARCHY_PATH")` (shell.qml, no fallback). `default/bash/env-bootstrap` **force-resets** it to `/usr/share/omarchy` when a stale value is found, so patch that file. |
| `/usr/share/omarchy` literal | 106 / 47 | mostly fallback defaults; subdirs default 20, install 11, bin 6, themes 5 |
| `~/.local/share/omarchy` | 14 / 1 | only `omarchy-upgrade-to-quattro` (legacy) |
| `/usr/lib/omarchy*` | 4 / 3 | `titlebars.so`, `/usr/lib/omarchy/{mac,mac-boot,speedtest}` |
| `~/.local/state/omarchy` | 173 / 98 | mutable state (current theme symlinks, toggles); stays in $HOME and must be persisted |
| `~/.config/omarchy` | 139 / 61 | user overrides and branding; persist |
| `/etc/omarchy` | 40 / 14 | system drop-ins; generate with `environment.etc` |
| `/usr/share/{plymouth,sddm}` | 5/4, 4/3 | theme dirs; map to NixOS plymouth/sddm theme packages |
| `/usr/(local/)?bin/X` | 254 / 107 | top: `/usr/bin/omarchy-locale-generate` 51, `python3` 37, `sudo` 20, coreutils |
| `pacman` / `yay` | 320 / 66 | these scripts need replacing or dropping |
| `systemctl` | 176 / 61 | |
| bash shebangs | 554 files | need `patchShebangs` |

**Plan**: package upstream as `omarchy-src` (store path).
- Set `OMARCHY_PATH` in the uwsm/session env, systemd user env and `/etc/profile`.
- `substituteInPlace` `/usr/share/omarchy` → `$out` and the titlebars path. Rewrite `/usr/bin/<tool>` to bare names or store paths.
- Run `patchShebangs`. Generate the Lua path/state files from nix.
- Add an eval-time check (build check) that greps the output for any surviving `/usr/(share|lib|bin)/` and fails.

## 6. Installer image building (nixpkgs-native, no nixos-generators)

- nixpkgs `nixos/modules/image/images.nix` provides `system.build.images.<variant>`, also usable as `nixos-rebuild build-image --image-variant <v>`. Variants: `iso`, `iso-installer`, `raw-efi`, `raw`, `qemu-efi`, `qemu`, `kexec`, `sd-card`, cloud formats. Do not use `kexec`; it is out of scope.
- ISO: `isoImage.squashfsCompression` defaults to `"zstd -Xcompression-level 19"`. Also available: `isoImage.storeContents`, `includeSystemBuildDependencies`, `makeEfiBootable`, `makeUsbBootable`.
  - ISO9660 is read-only. A writable config partition would have to be appended to the stick after `dd`, which the hybrid ISO allows but which is fiddly.
- **Better for USB: `image.repart`** (`nixos/modules/image/repart.nix`, systemd-repart).
  - Options: `image.repart.{name,version,compression.{algorithm,level},seed,split,sectorSize,imageSize,partitions.<n>.{storePaths,stripNixStorePrefix,nixStorePrefix,contents,repartConfig},mkfsOptions}`.
  - Supports `Format` of vfat, ext4, squashfs, erofs, btrfs, xfs or swap, and Type esp, root or other.
  - The tests `appliance-repart-image.nix` and `appliance-repart-image-verity-store.nix` are templates.
  - This allows one raw GPT image with three partitions: ESP (UKI or Limine), a read-only store/root (erofs or squashfs, which can hold the `file://` cache as plain files), and a small **vfat config partition (e.g. label `OMANIX-CFG`)** for the sidecar. The vfat partition is writable from any OS and can be rewritten without rebuilding the image.
- Profiles available: `minimal.nix`, `perlless.nix`, `bashless.nix`, `installation-device.nix`, `all-hardware.nix`.
  - `system.forbiddenDependenciesRegexes` exists in top-level.nix, so it can serve as the CI size and deps guard.
- The `nixos/tests/installer*` and `installer/` tests exist as patterns for a whole-disk install VM test.

## 7. Disk: disko, LUKS, btrfs, impermanence

- disko v1.13.0 CLI modes: `destroy`, `format`, `mount`, `unmount`, `format,mount`, `destroy,format,mount`. An `install-cli.nix` exists.
  - Examples: `luks-btrfs-subvolumes.nix`, `luks-interactive-login.nix`, `btrfs-subvolumes.nix`, `tmpfs.nix`, `hybrid-tmpfs-on-root.nix`.
  - The `luks` type has `name, keyFile, passwordFile, askPassword, settings (→ boot.initrd.luks.devices.<n>.*), additionalKeyFiles, initrdUnlock, extraFormatArgs, extraOpenArgs`.
  - There is **no built-in TPM2/FIDO2 enroll**, so run `systemd-cryptenroll` after format in the installer script.
- impermanence: `environment.persistence."/persist"` module (HEAD 2026-10-23). btrfs layout: blank-root snapshot rollback in initrd, or tmpfs `/`, plus a `@nix` subvol with `compress=zstd` and a `@persist` subvol.
- NixOS LUKS unlock in systemd stage 1 (`boot.initrd.systemd.enable = true`):
  - `boot.initrd.luks.devices.<n>.crypttabExtraOpts = [ "tpm2-device=auto" ]` or `[ "fido2-device=auto" ]`.
  - `boot.initrd.systemd.tpm2.enable` (defaults on with systemd initrd) pulls `libcryptsetup-token-systemd-tpm2.so`. FIDO2 support is in luksroot.nix.
  - Enrollment: `systemd-cryptenroll --tpm2-device=auto [--tpm2-pcrs=…]` or `--fido2-device=auto`.
  - systemd: 260.5 on 26.05, 262 on unstable. cryptsetup: 2.8.6 / 2.8.8.
  - nixpkgs VM tests that are ready-made templates for `nix flake check`: `systemd-initrd-luks-{tpm2,fido2,password,keyfile,unl0kr}.nix`, `initrd-luks-empty-passphrase.nix`, `systemd-credentials-tpm2.nix`, `tpm2`, `tpm-ek`. TPM tests use `virtualisation.tpm.enable`. FIDO2 tests use `qemu_test.override { canokeySupport = true; }` and `-device canokey`, which gives an emulated FIDO2 key in a VM.
  - `plymouth-tpm2-totp` module exists for anti-evil-maid display.

## 8. Bootloader

- `boot.loader.limine` exists on both channels (limine 12.5.2 on 26.05, 12.9.4 on unstable).
  - Options: maxGenerations, extraConfig, extraEntries, additionalFiles, biosDevice, partitionIndex, extraInstallCommands, style (wallpapers, branding, palette …), `validateChecksums`, `panicOnChecksumMismatch`, `enrollConfig` (defaults to panicOnChecksumMismatch), and `secureBoot.{enable,autoGenerateKeys,autoEnrollKeys.{enable,extraArgs}}` (sbctl-signed).
  - Tests: `nixos/tests/limine/{uefi,bios,secure-boot,checksum,specialisations,additional-files,distroName}.nix`.
- omarchy itself uses Limine plus snapper. Alternatives are systemd-boot, or lanzaboote v1.2.0 for Secure Boot with UKIs, which gives stable PCR 7 for TPM sealing.

## 9. sops-nix with host-generated keys

- sops-nix options: `sops.age.{keyFile, sshKeyPaths, generateKey, plugins}`.
  - `sops.age.plugins` (list of packages) is put on PATH for both the activation script and the systemd `sops-install-secrets` service, and for secrets-for-users.
  - `useSystemdActivation` auto-enables with sysusers or userborn.
- `age-plugin-tpm` **1.0.1** (Foxboron) is in nixpkgs on both channels, and there is a nixpkgs test `nixos/tests/age-plugin-tpm-decrypt.nix` (maintainers include `josh`).
  - `age-plugin-tpm --generate -o identity.txt` creates a TPM-wrapped identity file. The file is not secret, is useless off-chip, and must be persisted.
  - Its recipient is a **native `age1tag1…` (p256tag) recipient**, and the identity supports an optional `--pin` / `AGE_TPM_PIN`.
  - The README lists **no PCR-policy binding**, so the key is bound to the TPM chip only, not to boot state. This bears on the open question about PCR policy.
- **sops 3.13.3** (age lib 1.3.1) handles `age1pq1` natively, but treats any other `age1…1…` recipient (including `age1tag1`) as a **plugin recipient**. Encrypting to a host TPM key therefore needs `age-plugin-tag` on PATH, which age 1.3.2 ships (`age-plugin-{tag,tagpq,pq,batchpass}`). Decrypting needs `age-plugin-tpm` (put it in `sops.age.plugins`).
  - **UNVERIFIED** end-to-end: sops encrypt to `age1tag1` with `age-plugin-tag`, then decrypt via sops-nix with `age-plugin-tpm` in a VM. Add a VM test modeled on age-plugin-tpm-decrypt.
- Fallback for hosts without a TPM: plain age key generated at install (`sops.age.generateKey` or the installer) under `/persist`, or ssh-host-key-derived (`sshKeyPaths`).
- Human key: `age-plugin-yubikey` 0.5.1 (in nixpkgs) can be a second recipient. rage 0.12.1 is also available.

## 10. Host repo id

`systemd-id128 machine-id --app-specific=<APP_UUID>` (also `-a`) works on signi (systemd 26x). It gives an HMAC-derived id that does not reveal the machine-id, which suits the `omanix/<id>.git` path.
- Note: on a fresh install the machine-id is new. Reinstalls must take the existing id from cmdline or prompt, per fixed decision 2.
- `systemd-id128 new` gives a random id if one is preferred at mint time.

## 11. Sibling-repo pins (read-only observation)

- loom: nixpkgs 25.11, disko `latest` (de570873), impermanence 7b1d382f, sops-nix, HM 25.11, nuketown input.
- nuketown: 25.11, HM 25.11.
- mynix: **26.05** + unstable, HM 26.05, nuketown branch `portal-multi-session`, seed via `ssh://silo.loom.farm/seed.git`.
- seed: 25.11.
- Integrating omanix on loom means a channel bump of loom (and nuketown) to 26.05, or to unstable for the desktop parts. signi (mynix) is already on 26.05.

## 12. Open items / risks

1. Channel choice for the desktop (§3), A vs B. Must be decided before modules are written.
2. Pin omarchy to `v4.5.0-rc2` / `quattro` (needs Hyprland 0.56) or `v4.0.6` (likely fine on 0.55). The fixed decision is Quattro + Hyprland 0.56+, so pin the 4.5 line.
3. Port omarchy's 4 Hyprland patches only if hardware needs them (nvidia-egl-teardown, software-renderer for VMs).
4. Qt 6.12 versus quickshell patches (§3).
5. TPM age key has no PCR policy (§9). If boot-state binding is wanted, seal with systemd-creds (`systemd-credentials-tpm2`) or LUKS TPM2 PCRs instead.
6. age1tag + sops round trip is **UNVERIFIED** (§9).
