#!/usr/bin/env bash
# Regenerate tests/golden/ref-default from the reference host's HM files
# (checks.home-files-golden). Review `git diff tests/golden` before committing.
set -euo pipefail
cd "$(dirname "$0")/../.."
host=.#nixosConfigurations.ref-default.config
files=$(nix build --no-link --print-out-paths "$host.home-manager.users.alice.home-files")
targets=$(nix eval --json "$host.omanix.home.files" --apply builtins.attrNames | tr -d '[]"' | tr , '\n')
rm -rf tests/golden/ref-default
while IFS= read -r t; do
  [ -n "$t" ] || continue
  if [ -L "$files/$t" ] && [ ! -e "$files/$t" ]; then   # out-of-store link: record its target
    mkdir -p "$(dirname "tests/golden/ref-default/$t")"
    readlink "$files/$t" > "tests/golden/ref-default/$t.symlink"
  else
    install -Dm644 "$files/$t" "tests/golden/ref-default/$t"
  fi
done <<< "$targets"
echo "updated tests/golden/ref-default ($(find tests/golden/ref-default -type f | wc -l) files)"
