#!/usr/bin/env bash
# scripts/setup-remotes.sh: origin fetches from silo; pushes go to silo and GitHub ("github+silo", §a.1). Safe to re-run.
# ---- omanix preamble: identical in every scripts/*.sh (checks.script-preamble-identical, §e.10) ----
set -euo pipefail
OMANIX_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
OMANIX_SIGNERS=${XDG_CONFIG_HOME:-$HOME/.config}/omanix/allowed_signers
OMANIX_PUBLISHED="https://silo.loom.farm/omanix.git, https://github.com/loomtex/omanix and the omanix README"

omanix_die() { printf '\033[1;31momanix: %s\033[0m\n' "$*" >&2; exit 1; }

# The key lines of an allowed_signers file (no comments, no blank lines).
omanix_keys() { grep -Ev '^[[:space:]]*(#|$)' "$1" 2>/dev/null || true; }

# The SHA256 fingerprint of an allowed_signers line (principals [options] type key).
omanix_fp() {
  awk '{ for (i = 1; i < NF; i++) if ($i ~ /^(ssh-|sk-|ecdsa-)/) { print $i, $(i + 1); exit } }' <<<"$1" \
    | ssh-keygen -lf - 2>/dev/null | awk '{ print $2 }'
}

# 1. The user-pinned signers. If there are none, show the fingerprints of the
#    keys published in this tree and pin one only after the user types
#    `trust <fingerprint>` on the terminal (an agent can't answer for them).
omanix_pin() {
  [[ -n $(omanix_keys "$OMANIX_SIGNERS") ]] && return 0
  local published=$OMANIX_ROOT/release/allowed_signers line answer
  [[ -n $(omanix_keys "$published") ]] || omanix_die "no release signer is published in release/allowed_signers yet"
  printf '%s\n' "No pinned omanix release key ($OMANIX_SIGNERS)." \
    "Compare a fingerprint below with the one published at $OMANIX_PUBLISHED:" >&2
  while IFS= read -r line; do printf '  %s\n' "$(omanix_fp "$line")" >&2; done < <(omanix_keys "$published")
  { : < /dev/tty; } 2>/dev/null \
    || omanix_die "no terminal: run this once yourself and type 'trust <fingerprint>', or put the line in $OMANIX_SIGNERS"
  printf 'Type "trust <fingerprint>" to pin it: ' >&2
  read -r answer < /dev/tty
  [[ $answer == "trust SHA256:"* ]] || omanix_die "not pinned"
  while IFS= read -r line; do
    if [[ $(omanix_fp "$line") == "${answer#trust }" ]]; then
      mkdir -p "$(dirname "$OMANIX_SIGNERS")"
      printf '%s\n' "$line" >> "$OMANIX_SIGNERS"
      return 0
    fi
  done < <(omanix_keys "$published")
  omanix_die "${answer#trust } is not a published release key"
}

# 2-3. A clean checkout at a tag signed by a pinned key; or, without git, the
#      signed scripts/SHA256SUMS over the whole tree. OMANIX_DEV=1 skips the
#      check with a red banner.
omanix_verify() {
  if [[ ${OMANIX_DEV:-} == 1 ]]; then
    printf '\033[1;37;41m %s \033[0m\n' "OMANIX_DEV=1: running an UNVERIFIED checkout ($OMANIX_ROOT)" >&2
    return 0
  fi
  omanix_pin
  local tag sums=$OMANIX_ROOT/scripts/SHA256SUMS principal f
  if git -C "$OMANIX_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    [[ -z $(git -C "$OMANIX_ROOT" status --porcelain --untracked-files=normal) ]] \
      || omanix_die "this checkout has uncommitted changes; check out a release tag (or OMANIX_DEV=1)"
    tag=$(git -C "$OMANIX_ROOT" describe --exact-match --tags HEAD 2>/dev/null) \
      || omanix_die "HEAD is not a release tag; check one out, e.g. git checkout v0.1.0 (or OMANIX_DEV=1)"
    git -C "$OMANIX_ROOT" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$OMANIX_SIGNERS" verify-tag "$tag" >/dev/null 2>&1 \
      || omanix_die "tag $tag is not signed by a key in $OMANIX_SIGNERS"
  elif [[ -e $sums.sig ]]; then
    principal=$(ssh-keygen -Y find-principals -f "$OMANIX_SIGNERS" -s "$sums.sig" 2>/dev/null | head -n1) \
      || omanix_die "scripts/SHA256SUMS.sig is not by a key in $OMANIX_SIGNERS"
    ssh-keygen -Y verify -f "$OMANIX_SIGNERS" -I "$principal" -n omanix-release -s "$sums.sig" < "$sums" >/dev/null 2>&1 \
      || omanix_die "scripts/SHA256SUMS.sig doesn't verify"
    (cd "$OMANIX_ROOT" && sha256sum --quiet --strict -c scripts/SHA256SUMS) >/dev/null 2>&1 \
      || omanix_die "files differ from the signed scripts/SHA256SUMS"
    while IFS= read -r -d '' f; do
      f=${f#./}
      [[ $f == scripts/SHA256SUMS || $f == scripts/SHA256SUMS.sig ]] && continue
      grep -qF "  $f" "$sums" || omanix_die "$f is not in the signed scripts/SHA256SUMS"
    done < <(cd "$OMANIX_ROOT" && find . -type f -not -path './.git/*' -not -path '*/__pycache__/*' -print0)
  else
    omanix_die "neither a git checkout at a signed tag nor a signed scripts/SHA256SUMS"
  fi
}

# 4. Hand over to the tool from this (now verified) tree.
omanix_run() {
  omanix_verify
  exec nix --extra-experimental-features 'nix-command flakes' run "$OMANIX_ROOT#$1" -- "${@:2}"
}
# ---- end of omanix preamble ----

omanix_verify
silo=ssh://git@silo.loom.farm/omanix.git
github=git@github.com:loomtex/omanix.git
git -C "$OMANIX_ROOT" remote get-url origin >/dev/null 2>&1 || git -C "$OMANIX_ROOT" remote add origin "$silo"
git -C "$OMANIX_ROOT" remote set-url origin "$silo"
git -C "$OMANIX_ROOT" config --unset-all remote.origin.pushurl || true
git -C "$OMANIX_ROOT" remote set-url --add --push origin "$silo"
git -C "$OMANIX_ROOT" remote set-url --add --push origin "$github"
git -C "$OMANIX_ROOT" remote -v
