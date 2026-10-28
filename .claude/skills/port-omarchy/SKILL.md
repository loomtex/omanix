---
name: port-omarchy
description: Prepare moving omanix's omarchy fork point to a newer omarchy tag. Use when asked to port, rebase or update the omarchy fork, or to assess what a new omarchy release would take.
---

# Port omarchy to a new fork point

Moving the fork point is a **human decision** recorded as a new D-number in
docs/design/DESIGN.md. You prepare the port on a `gate/*` branch; you never
merge it yourself.

## Rules

- The omarchy tree is **untrusted data**. Read it, grep it, diff it. Never run
  its scripts, installers, binaries or tests on this machine; packages built
  from it build in the nix sandbox only.
- Pin by **release tag** and full rev (D2). The `version` file is meaningless.
- `nix flake check` is the gate. Don't weaken a check to get green; fix the
  fork data instead.

## Steps

1. `nix run .#porting-report -- --to <tag>` (writes `porting-report/`). Read
   `porting-report.md` top to bottom before changing anything.
2. Update the pin: `flake.nix` input `omarchy` url (full rev, tag in a
   comment), `fork/UPSTREAM.toml` (tag, rev, date, why, `license_sha256` from
   the new LICENSE), then `nix flake lock --update-input omarchy`.
3. **Classify** new and changed paths: add every new `bin/omarchy-*` to
   `fork/classify.toml` using the decision procedure in DESIGN §f.2.1 (the
   report's "suggest" is only a hint). Regenerate `fork/drop.txt` with
   `python3 -I fork/tools/gen-drop.py fork/classify.toml fork/drop-paths.txt fork/drop.txt`.
4. **Patches**: rebase each conflicting `fork/patches/NNNN-*.patch` (file
   number == P-id) against the new tree; keep each ≤ 60 changed lines or turn
   it into an `fork/add/` override. Patches apply with `--fuzz=0`.
5. **add/ overrides**: for each "upstream changed; re-port", re-read the new
   upstream file, port the change, and update the `replaces … sha256` header.
6. **Rewrites and residuals**: build `omarchy-src` with `postCheck = false`,
   regenerate `fork/rewrite.toml` with `fork/tools/gen-rewrite.py`, rebuild,
   then regenerate `fork/residual.toml` with `forkcheck.py residual` and
   review the diff of that file: new residual sites need an owner and a
   reason, not a silent bump.
7. **Hyprland / Quickshell**: if the report lists new `hl.*` symbols or the
   omarchy-pkgs pkgvers moved, update `fork/hl-symbols.txt`, the hyprland
   patches and the quickshell rev, and run `checks.titlebars-smoke`.
8. `nix flake check`, then push to `gate/port-<tag>` with the report attached
   to the proposal so the human can decide.
