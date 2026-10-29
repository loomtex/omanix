#!/usr/bin/env bash
# Regenerate the approval card goldens from the fixtures (review the diff!).
set -euo pipefail
cd "$(dirname "$0")/../.."
for c in routine full root-command; do
  nix run nixpkgs#nodejs -- tests/cards/render.js fork/add/shell/plugins/omanix-approval/CardModel.js \
    tests/fixtures/approval/$c tests/golden/cards/$c
done
git diff --stat tests/golden/cards
