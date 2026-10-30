---
name: configure
description: Prepare an omanix install for someone's new computer from their existing one - collect their choices, mint the host repo on silo with their key, check what the USB stick covers offline, stage a per-host cache if needed, and write the stick's sidecar. Use when someone wants to install omanix, set up a new machine, or "configure" an installer.
---

# Configure an omanix install (DESIGN §e.2)

You converse; `scripts/configure.sh` acts. Every step is a subcommand with
`--json`; read its JSON, never scrape text. The script verifies its own
checkout first (§e.10) and then runs `nix run .#configure`.

## Never

- Never ask for, type, store or echo a **password, passphrase, PIN, token,
  API key or AI-assistant login**. The answers schema has no field for them
  and `loom-hostgen` refuses unknown keys. The login password, the disk
  passphrase and the system encryption key are asked by the installer, on
  the new computer, from the human.
- Never generate or handle the **system encryption key** (the installer
  does) or copy credentials onto the stick.
- Never answer the trust prompt (`trust <fingerprint>`) or a passphrase or
  FIDO2 prompt for the human: those read `/dev/tty` on purpose.
- Never point anything at `silo.loom.farm` in a test; tests use the silo
  stand-in.

## 0. Before anything

- The human pins the release key once, themselves:
  `scripts/verify-release.sh <downloaded release dir>` or any script
  prints the published fingerprints; they compare one with silo, GitHub and
  the README and type `trust SHA256:…`. Explain why; don't do it for them.
- The checkout must be a clean, signed release tag (`git checkout v0.1.0`).
  `OMANIX_DEV=1` is for omanix developers only (red banner); say so if
  someone wants it.

## 1. Collect the answers

Ask conversationally and fill `answers.json` (schema `loom.answers/v1`,
`flavor = "omanix"`):

- `host.name` (lowercase, digits, dashes), `user.name`, `user.fullName`,
  `user.email`;
- `locale.timeZone`, `locale.keyMap`, `locale.language`;
- `theme`, `defaults.{terminal,browser,editor}`, extra `apps`: only values
  from the release's hostgen catalog (`nix eval .#nixosConfigurations.ref-default.config.omanix.catalog.hostgen --json`);
  offer the list, don't invent;
- a GPU guess only as a hint for the human; the installer's probes decide;
- `agent.name`, `agent.harness`, and **agent sudo** (D8), asked exactly:
  "Should <agent> be able to ask you for any administrator (sudo) command,
  beyond its short list (applying changes, logs, services, firmware,
  cleaning the nix store)? Each request shows a card with an AI explanation
  and runs only if you approve." → `"listed"` (default) or `"any"`;
- optional human age recipient (YubiKey) for data secrets;
- the **owner SSH key** (`humans.<name> = { key; owner = true; }`). It
  makes the first push and becomes silo's owner, so it must work **here**:
  - recommended: FIDO2, `ssh-keygen -t ed25519-sk -O resident -O verify-required -O application=ssh:omanix`;
  - an existing key: dry-run sign it (`ssh-keygen -Y sign -n loom-probe -f <key> < /dev/null`);
    if `ssh-keygen -y -P "" -f <key>` succeeds it has **no passphrase**:
    refuse it and offer `ssh-keygen -p -f <key>` or a new key (D10);
  - a new software key `ssh-keygen -t ed25519 -a 100` with a passphrase
    the human types (refuse empty). FIDO2 is recommended; don't say a
    software key lowers anything (D10).
- optional additional human public keys (`ssh-ed25519` or
  `sk-ssh-ed25519@openssh.com` only): not owners.

Show the human the finished `answers.json` before minting.

## 2. Mint (`configure mint`)

```
scripts/configure.sh mint --answers answers.json --owner-key ~/.ssh/<key> --work ~/omanix-hosts/<name> --json
```

The human may be asked for a touch or a passphrase (twice: sign, push).
On a network error after the repo was created: `scripts/configure.sh mint --resume --id <id> --owner-key … --json`.
Result: `state.json` under `~/.local/state/omanix/hosts/<id>/` (keep it:
`revoke-enroll` needs it), `enroll.key` next to it.

## 3. Check (`configure check`)

```
scripts/configure.sh check --repo ~/omanix-hosts/<name> --index <release>/stick-index.txt --json
```

`cacheMiss` lists source downloads an offline install would need that the
stick lacks. Empty: the stick installs this host offline. `toBuild` is
what the installer rebuilds locally (normal: the per-host parts).

## 4. Stage a cache (only if `cacheMiss` is not empty and Nix runs here)

```
scripts/configure.sh stage-cache --repo … --index … --state <state.json> --owner-key … --out ./install-cache --answers answers.json --json
```

It builds the misses, signs them with a fresh per-host key, commits
`.loom/install-cache.pub` (owner-signed, pushed) and deletes the secret
key. Without local Nix: tell the human the install needs network for those.
On Windows this runs in WSL2 (FIDO2 needs `usbipd`, else a passphrase key).

## 5. Sidecar (`configure sidecar`)

```
scripts/configure.sh sidecar --state <state.json> --answers answers.json --out ./cfg [--install-cache ./install-cache] [--hint-unlock fido2,passphrase] --json
```

Then hand over to the **build-installer** skill to flash it.

## 6. Lost stick / abandoned install

```
scripts/configure.sh revoke-enroll --state <state.json> --owner-key … --json
```

If silo's `master` moved since the sidecar commit it stops and recommends a
re-mint; `--reuse-anyway` restores the human-only key set and shows the
diff for the owner to review. Explain the trade-off; let the human choose.
