---
name: build-installer
description: Get a verified omanix USB installer image and write it, with a configure sidecar, to a USB stick safely. Use when someone wants to make or flash an omanix installer stick, or after the configure skill wrote a sidecar.
---

# Build and flash the installer (DESIGN §e.1, §e.4, §e.10)

The installer is a **USB image only**. It never carries credentials or an
AI-assistant login; the sidecar holds only the closed answers set, the
host bundle, the single-use enrollment key and an optional signed install
cache.

## 1. Get the image

**Normal path: the signed release.** Download the release directory
(`omanix-installer-<v>.raw`, `omanix-installer-net-<v>.raw`,
`stick-index.txt`, `cache-key.pub`, `release.json`, `SHA256SUMS`,
`SHA256SUMS.sig`) and verify it:

```
scripts/verify-release.sh <dir> --json
```

`ok: true` and the signer must be a pinned release key. Anything else:
stop and tell the human; don't work around it.

- `omanix-installer-<v>.raw` (offline): carries the reference closures in
  a CACHE partition signed with `omanix-cache-1`; installs without network
  when `configure check` reported `cacheMiss: []`.
- `omanix-installer-net-<v>.raw`: no CACHE; needs network to install.

**Developer path (unsigned, never for someone else's machine).**
`nix build .#installer-net` builds the net image from the checkout.
`.#installer-offline`'s CACHE is unsigned until a release signs it, so it
can't install offline (require-sigs stays on); `.#installer-test` is the
test image (serial console, `silo.test`, red banner) and can't reach the
real silo. Images build one at a time; each is several GiB.

## 2. Flash (two phases; the guards are in code)

```
scripts/flash-usb.sh plan --image <dir>/omanix-installer-<v>.raw --sidecar ./cfg --json
```

Show the human every candidate (vendor, model, serial, size, partitions)
and ask which stick. Never pick for them, never offer a disk that isn't in
`candidates`, never pass `--allow-large` on your own.

```
scripts/flash-usb.sh write --device /dev/disk/by-id/usb-… --confirm <token> --image … --sidecar ./cfg --json
```

On a terminal the human also types the last 4 characters of the serial.
Exit codes: 2 token (re-run `plan`), 3 not a candidate, 4 busy (mounted or
in use), 5 too small, 6 too large, 7 signature, 8 readback, 9 sidecar,
10 serial. Report the code and meaning; never retry `write` with a token
from a different `plan`.

To replace only the sidecar on an already-flashed stick:
`scripts/flash-usb.sh sidecar --device … --confirm <token> --sidecar ./cfg`.

## 3. Hand-off

Tell the human: boot the new computer from the stick (Secure Boot off or in
Setup Mode, which also enables TPM2 unlock), follow the installer, and write
the system encryption key on paper when it is shown. If the stick is lost
before the install finishes: `configure revoke-enroll` (configure skill).
