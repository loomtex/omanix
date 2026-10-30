---
name: rotate-keys
description: Disk encryption key, human keys, unlock methods: human-only procedures you explain but never run.
---
# Keys (human only)

You explain; the human runs these in their own terminal:
- Drive/system encryption key: `loom keys rotate encryption-key` (shows a new key to write down).
- Add or remove a human key: `loom keys add-human` / `loom keys remove-human`.
- Unlock methods (FIDO2, TPM2 + PIN, passphrase): `loom unlock status|add|remove`.
- Login password: the Change password dialog (System › Security).
`omanix context` shows a key rotation in progress; until it finishes, other proposals are refused.
