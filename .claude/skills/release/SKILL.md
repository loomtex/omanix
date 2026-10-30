---
name: release
description: Cut a signed omanix release (tag, signed stick cache, installer images, SHA256SUMS) per D11, or rehearse one as a dry run with throwaway keys. Use when asked to release, tag, publish installer images, or test the release procedure.
---

# Release omanix (D11, DESIGN §e.1, §e.10)

Who holds what (D11):

| Secret | Where | Used by |
|---|---|---|
| Release SSH signing key | **Josh's YubiKey** (FIDO2, `sk-ssh-ed25519`) | Josh, in his own session: the tag, `scripts/SHA256SUMS.sig`, the release `SHA256SUMS.sig` |
| `omanix-cache-1` nix signing key | signi, sops-encrypted | this skill only, step 4, through one approval (`sudoex --decrypt`) |
| CI | **nothing** | CI builds and tests; it never signs (no secrets in CI) |

You never see, request or touch the YubiKey, and you never ask Josh to
export it. You never decrypt the cache key except in step 4, through the
approval, into a root-only path that the signing command reads and that is
gone when it exits. Nothing is pushed, tagged or published without Josh.

## Real release

1. **Gate.** On `master` at the release commit: `nix flake check` green
   (closure-budget numbers recorded in the release notes), `VERSION` =
   the new version, `release/allowed_signers` lists Josh's key(s) with
   `namespaces="git,omanix-release"`.
2. **Tree sums.** `nix run .#omanix-release -- tree-sums .` writes
   `scripts/SHA256SUMS` (whole tree). Josh signs it on his machine:
   `ssh-keygen -Y sign -n omanix-release -f ~/.ssh/id_ed25519_sk scripts/SHA256SUMS`
   (touch the key). Commit both files ("release: v<version> sums").
3. **Tag (Josh).** `git -c gpg.format=ssh -c user.signingKey=~/.ssh/id_ed25519_sk.pub tag -s v<version> -m "omanix v<version>"`.
   Verify: `git -c gpg.ssh.allowedSignersFile=release/allowed_signers verify-tag v<version>`.
4. **Sign the stick cache (one approval).**
   ```
   nix build .#base-cache --print-out-paths            # from the tag's checkout
   sudoex --why "sign the omanix v<version> stick cache with omanix-cache-1 (D11)" \
     --decrypt <sops file with omanix-cache-1>:/run/omanix-release/cache-key -- \
     omanix-release sign-cache <base-cache path> /var/tmp/omanix-<version>-cache --key-file /run/omanix-release/cache-key
   ```
   `sign-cache` verifies every narinfo against the public key and writes
   `cache-key.pub`. The approval card should show exactly this command.
5. **Images.** One at a time (each is several GiB):
   ```
   omanix-release build --repo . --tag v<version> --out ./dist/v<version> \
     --signed-cache /var/tmp/omanix-<version>-cache
   ```
   It re-verifies the tag against the **tagged tree's**
   `release/allowed_signers`, builds `installer-offline` with the signed
   CACHE and `installer-net`, writes `stick-index.txt`, `cache-key.pub`,
   `release.json` and `SHA256SUMS`, and stops: no `--sign-key`.
6. **Sign SHA256SUMS (Josh).** `ssh-keygen -Y sign -n omanix-release -f ~/.ssh/id_ed25519_sk dist/v<version>/SHA256SUMS`.
7. **Verify.** `scripts/verify-release.sh dist/v<version>` must print OK and
   Josh's principal. Then Josh pushes the tag (silo and GitHub) and
   publishes `dist/v<version>`.

The first time: Josh creates the cache key
(`nix key generate-secret --key-name omanix-cache-1`), stores it with sops
on signi, publishes the public half (it goes into installed hosts'
`nix.settings`), and puts his release key in `release/allowed_signers`.

## Dry run (throwaway keys; no YubiKey, no real cache key)

In a scratch clone, never in the real repo:

```
git clone <omanix checkout> $SCRATCH/rel && cd $SCRATCH/rel
ssh-keygen -q -t ed25519 -N '' -C release@dry-run -f $SCRATCH/k/release
nix key generate-secret --key-name omanix-dryrun-cache-1 > $SCRATCH/k/cache
echo "release@dry-run namespaces=\"git,omanix-release\" $(cut -d' ' -f1,2 $SCRATCH/k/release.pub)" > release/allowed_signers
git commit -qam "dry run: throwaway release signer"
git -c gpg.format=ssh -c user.signingKey=$SCRATCH/k/release tag -s v$(cat VERSION) -m dry-run
omanix-release build --repo . --tag v$(cat VERSION) --out $SCRATCH/dist --dry-run \
  --cache-key-file $SCRATCH/k/cache --sign-key $SCRATCH/k/release
omanix-release verify $SCRATCH/dist --signers release/allowed_signers
```

`release.json` records `"dryRun": true`. Delete the clone and keys after.
