# DESIGN.md archive (revisions 3, 4, 5)

The current design is `../DESIGN.md` (rev 5.1 and later). These are earlier
revisions, kept verbatim so the deferred security and hardening material can
be mined later. Section references inside them (`§g.14`,
`scratchpad/DESIGN.rev3.md`, and so on) are to the revision itself, not to the
current design. Authors: Ada, with Joshua Perry.

| File | Revision | Lines | Completeness |
|---|---|---|---|
| `DESIGN.rev3.md` | Rev 3, 2026-10-27: the fork and agent-first redesign, before the v1 cut. It holds the full hardening design: request ledger, human-signed approval merges, nonces, the deterministic facts engine and highlight list, the preflight VM, reviewer isolation and egress, and nuketown deltas N1–N15. | 2,786 (2,787 counting the empty line after the final newline) | Complete. No gaps. |
| `DESIGN.rev4.md` | Rev 4, 2026-10-28: the v1 scope cut (`../v1-cut-changelog.md`). nuketown is unchanged and most hardening moves to Appendix H, which points back to rev 3's sections. | 2,491 | Complete. No gaps. |
| `DESIGN.rev5.md` | Rev 5, 2026-10-28: reviewed sudo and no switch daemon (V8), before the 5.1 change that added the approval service user. | 2,586 | Complete. Byte-identical to `docs/design/DESIGN.md` at commit `3119f2a`. |

Change logs between revisions: `../reconcile-changelog.md` (rev 1 to 2),
`../fork-changelog.md` (rev 2 to 3) and `../v1-cut-changelog.md` (rev 3 to 4,
4 to 5 and 5 to 5.1).

## How they were recovered (2026-10-29)

Rev 3 and rev 4 were never committed. Their only copies were session
scratchpad backups, and those are now gone. All three files were rebuilt from
the Claude Code session transcripts under
`~/.claude/projects/-agents-ada-projects-omanix/`.

- **Rev 3.** The base is the verification agent's full read of DESIGN.md just
  before its fixes, at 2026-10-28 04:25Z (fork-redesign workflow
  `wf_84a0e494`, agent `a77df47`). That read covers all 2,698 lines. On top of
  it we re-ran that agent's own fix scripts, in their original order:
  `vfix1.py`, `vfix2.py`, `vfix3.py` and one inline edit. They reported 50, 69
  and 41 replacements, the same counts as the original run, and the result had
  the original line count. The rebuilt file was then checked against the v1-cut
  agent's snapshots of rev 3 from 07:22–07:25Z, the moment `DESIGN.rev3.md`
  was copied. Those snapshots are `sed` outputs saved in `tool-results/` and
  Read results, and they cover lines 1–1132, 1495–1512 and 1577–2787. All of
  them match exactly. The remaining lines (1133–1494 and 1513–1576) come from
  the 04:25Z read plus the replayed fixes. They also agree with every
  `grep -n` and line probe taken at 07:21–07:34Z, including all 157 headings.
- **Rev 4.** We re-ran the v1-cut agent's assembly against the rebuilt rev 3:
  its section files (`rev4/*.md`, with their later in-place edits),
  `rev4/assemble.py` and its follow-up edit. Every exact-count substitution in
  `assemble.py` hit its target, which is also a check on rev 3, and the output
  had 2,491 lines, as in the original run. Every `sed`, `grep` and Read the
  rev 5 agent ran on rev 4 (2026-10-28 21:28–21:35Z) gives the same output on
  the rebuilt file.
- **Rev 5.** We re-ran the rev 5 agent's `rev5.py`, with its two in-place
  fixes and three follow-up edits, on the rebuilt rev 4. The result is
  byte-identical to commit `3119f2a`. So the whole chain, rev 3 to rev 4 to
  rev 5, reproduces the committed file exactly.
