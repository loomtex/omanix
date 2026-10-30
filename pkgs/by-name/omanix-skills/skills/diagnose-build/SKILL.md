---
name: diagnose-build
description: Read-only diagnosis of a failing `omanix check` or build.
---
# A build or evaluation fails

1. `omanix check --json`: `eval.error`, failed assertions, `build.log` (the tail).
2. An eval error names a file:line: read it; `omanix where <option>` shows every definition.
3. A build failure: the failing derivation is in the log; `nix log <drv>` for all of it.
   An unfree package needs `nixpkgs.config.allowUnfreePredicate`; a removed package has a
   replacement in the nixpkgs release notes.
4. Assertions name the option to set. The persist audit names the path to persist.
5. Fix in the working copy, check again. Nothing has changed on the machine yet.
