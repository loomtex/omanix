---
name: security
description: SSH server, FIDO2, fingerprint, ssh-agent, firewall, docker group: explain the effect on the card.
---
# Security settings

- Each change is a module edit, then a proposal. Say plainly what it opens or closes; the reviewer
  and the human read the diff.
- sshd: `services.openssh.enable = true;` with `PasswordAuthentication = false`; the human's keys
  for login go in `users.users.<user>.openssh.authorizedKeys.keys` (public keys only).
- Fingerprint: `services.fprintd.enable = true;` (enrolling a finger is the human's, at the GUI).
- FIDO2 for sudo/login: `security.pam.u2f`; registering the key is the human's.
- Adding a human to `docker` gives them root-equivalent access: say so.
- Never touch `keys.nix`, the disk-unlock methods or the system encryption key: those are
  human-only tools (`rotate-keys`).
