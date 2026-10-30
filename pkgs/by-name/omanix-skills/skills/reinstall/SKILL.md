---
name: reinstall
description: Reinstalling or moving to a new machine from the host repo: explain the human's steps.
---
# Reinstall

The host repo is the machine. To reinstall: boot the omanix USB installer with
`loom.host=<host id>` (`omanix context` shows the id), choose "reinstall", type the system
encryption key from paper. The same configuration comes back; you and the reviewer sign in again;
your old conversations don't come back. Moving to new hardware is the same, then `loom hw regen`.
Forking (a new machine from this repo) needs a new human key. Explain; never run disk or key tools.
