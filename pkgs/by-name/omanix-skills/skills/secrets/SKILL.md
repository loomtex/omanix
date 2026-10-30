---
name: secrets
description: Secret values (Wi-Fi PSKs, tokens, passwords): the human enters them; you never see them.
---
# Secrets

- Never ask for, read, echo or store a secret value. You hold no key that can decrypt them.
- The human runs `omanix secret set <file> <name>` in their own terminal (it reads the value
  without echoing and encrypts it into `secrets/<file>.yaml`; files: host, user, data, agents).
  Tell them exactly that command.
- You wire the secret into a module by name: `sops.secrets."<name>" = { sopsFile = ../secrets/data.yaml; };`
  and point the service at `config.sops.secrets."<name>".path`.
- The login password is the Change password dialog (System › Security); the disk encryption key
  and human keys are `rotate-keys`.
