---
name: diagnose-crash
description: An app crashed: read the coredump summary and the journal, explain, propose a fix.
---
# A program crashed

The crash toast pre-fills a request with the program, pid, executable and signal.
1. `coredumpctl info <pid>` and `journalctl -b _PID=<pid>` for context (read-only).
2. Typical causes on omanix: a GPU driver quirk (`hardware` skill: `omanix hw probe`), a stale
   per-user config in the app's own directory, an app that needs a newer package.
3. Explain; propose a change only for what is declared (a package, a quirk, an option). Never
   delete the human's files; tell them which to move if it's their app's state.
