# Omanix USB Installer & Agent-Config Recommendations (rev 16, 2026-10-27, authoritative)

## Summary
Omanix ships as a standard bootable USB installer image. It consumes one artifact: a shared, cacheable base closure plus a small per-host sidecar, built from a per-host flake on Silo. Any machine boots the generic image from a USB stick; the installer then partitions the disk, sets up full-disk encryption, fetches the host's config, and installs. Write access to a host's repo is root on that machine, so every security decision follows from guarding that.

Design principles:
- One image, personal sidecar. The base payload is identical across users and CDN-cacheable; only the per-host sidecar differs.
- Nothing secret in git. sops for anything sensitive; credentials never touch Loomtex infrastructure.
- Agents choose, scripts act. The agent holds the conversation and picks a script; reviewed, signed scripts do every destructive step.
- Every risky step is recoverable. `nixos-rebuild test` plus watchdog, rollback by default.
- Human gates live in code, not just prompts. Scripts enforce safety checks even if a permission prompt is clicked through.

## Install image
The installer is a generic NixOS live image: flash it to a USB stick and boot from the firmware menu. It carries a broad firmware set, and the per-host sidecar rides on a small writable config partition, so it can be injected without rebuilding the image. It installs "the build of commit X of host repo Y" from a local binary cache.

Installer sequence:
1. Read sidecar and git bundle of the host repo.
2. Partition the target disk (whole-disk; Omanix does not dual-boot) and set up full-disk encryption with the unlock method the user picked (TPM2, FIDO2, or passphrase).
3. `nixos-generate-config` for hardware, merged into the host flake.
4. `nixos-install` from the local `file://` binary cache; substitute from network only as fallback.
5. Generate host and agent keys, re-encrypt secrets to the host key, enroll keys on Silo (see Configuration model).
6. Shred the sidecar; set the final boot order.

## Payload size and delivery
Bar to beat: Omarchy's offline ISO, ~6 GB in 4.x, much of it hardware packages a given machine doesn't use. A trimmed Nix closure with hardware-filtered firmware should come in well under that.
- Measure with `nix path-info -rsSh`, `nix why-depends`, nix-tree.
- Trim with minimal and perlless profiles, `documentation.enable = false`, `environment.defaultPackages = []`, split outputs; watch for duplicate Mesa/LLVM/Python.
- Enforce a size budget in CI (closure-size check plus `system.forbiddenDependenciesRegexes`).
Compression and delivery:
- Binary cache as the payload format: stage `.nar.zst` + narinfo from your own cache into a `file://` cache on the install medium.
- Installed system: btrfs subvolume for /nix with compress=zstd, plus auto-optimise-store.
- ISO store: zstd squashfs.
- Firmware filtering: the installer can enumerate PCI/USB IDs and stage only needed linux-firmware blobs; keep the full set substitutable.
Offline vs online: support both. Full-offline image ships the whole closure; a small bootstrap (~100-200 MB) substitutes the rest over the network.

## Configuration model
Each host has a per-host flake in its own GUID repo on Silo. The installer builds a host from that flake plus a small sidecar, minting a new repo from answers given at install time, or taking an existing host repo id (kernel cmdline or interactive prompt) for reinstalls and VM testing.

Repo layout: CLAUDE.md and .claude/skills/ (procedures), not README instructions:
```
omanix/
  CLAUDE.md                  # what this is, house rules, never improvise disk ops
  .claude/skills/
    configure/SKILL.md       # conversation -> host flake + sidecar
    build-installer/SKILL.md # build the image, flash USB, verify
  scripts/                   # deterministic, reviewed, signed
    flash-usb.sh
```
Base + sidecar split:
- Closure-affecting choices (apps, toolchains) go in the host flake. Precompute popular combinations in the cache; build the long tail on demand.
- Pure configuration (username, password hash, hostname, timezone, keymap, SSH keys, theme) goes in a small sidecar the installer turns into config. Secrets in it are sops-encrypted or first-boot prompts.
- Expose a fixed options schema, never arbitrary Nix from untrusted input. Pure eval, no IFD.

Building without local Nix (optional): agent pushes host flake to Silo; a Seed-side builder builds into the binary cache; local scripts download .nar.zst over HTTPS. Gate like `plant` (invite or rate limit). Otherwise local Nix on Linux, WSL2 on Windows.

Bootstrap ownership on Silo (key that creates a repo owns it):
1. Configurator creates the host repo with a per-repo enrollment key, shipped in the sidecar.
2. On install, the host generates its host key and agent key.
3. Using the enrollment key once, it pushes a commit adding host key, agent key and user's human key to `.authorized_keys`, and removing the enrollment key.
4. Nothing off the machine holds write access afterward.

Post-install: host flake imports Omanix upstream modules. Updates = agent (or Update menu item) bumping that input in flake.lock; rollback free. An "export my flake" path lets users graduate to owning their config.

Trust anchor: this repo drives an agent with a path to root, so a malicious fork is an attack. Point users at signed release tags on Silo; scripts verify their own signature before running.

## Agent security
The host repo's `.authorized_keys` is effectively the machine's sudoers file. Prompt injection is the realistic threat; the agent's key must not be able to grant itself power.
- Separate keys, separate powers: human key and agent key distinct, individually revocable.
- Diff evaluated options, not text. Before any switch, evaluate old and new configs and compare a protected set: users.users.*, sudo and security.*; nix.settings.trusted-users, substituters, trusted-public-keys; openssh settings, boot.*, firewall rules; the repo's own .authorized_keys. If anything protected changed, require the commit signed by the human key (git SSH signing, allowed_signers); otherwise the agent's signature suffices.
- One approval gesture: the existing GUI sudo dialog (later XMPP approval) produces the human signature for protected commits.
- Run the policy check on the host, not on whoever pushed. Prefer agent-initiated switches over auto-switch-on-push for desktops.
- Switch watchdog: 1) nixos-rebuild test; 2) health check on timer (network, compositor/session alive, agent reaches Silo); 3) pass → promote to boot default; fail/timeout → automatic rollback (deploy-rs magic-rollback pattern).
- Script-level guards: flash-usb: removable devices only; refuse mounted or root-holding devices; show model and size before confirming.

## Open questions
- Read-gated repos on Silo: not planned; host configs public-read (reveal usernames, hostnames, software; secrets covered by sops).
- Seed-side builder for users without local Nix: v1 or local/WSL2 Nix only?
- TPM sealing policy for the host age key with Secure Boot off: which PCRs.
- Exact protected-option list for the policy diff; upstream or per host.
