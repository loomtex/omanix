---
name: boot
description: Kernel choice, hibernation, Plymouth boot screen.
---
# Boot

- Kernel: `boot.kernelPackages = pkgs.linuxPackages_latest;` (or `_zen`, LTS) in a module.
- Hibernation needs swap on disk: `loom.disk.swap = "zram+file"` with `swap.hibernate = true`
  and a size; that changes `machine.nix`, which the card flags.
- Boot screen theme: `omanix.theme.boot.theme`.
- Secure Boot and TPM unlock are the human's (`loom unlock`, `rotate-keys`): explain, don't run.
