<!-- Shipped with the vv-harness plugin. There is no auto-loading: harness-continue's
Session End step instructs the lead to write .harness/mld/ entries and points here for
the review cadence and disposition. -->

# MLD Review

`.harness/mld/` accumulates one file per session (`YYYY-MM-DD-<session-id>.md`), each
with `## Mistakes`, `## Learnings`, and `## Desires` sections written by the lead at
session end (see harness-continue's Session End step). It is raw per-session telemetry,
not an audit trail read back into model context: session-start.sh has a hard guarantee
never to read `.harness/mld/` (enforced by `/harness-doctor`'s non-injection check and a
regression test in `test/run-tests.sh`). Confusing MLD with the cumulative
`context_summary.md` Retrospective defeats the point of both — the Retrospective is
digested analysis for future sessions to read; MLD is undigested raw material for
periodic human/lead review only.

## Review cadence

Review accumulated entries on a fixed cadence rather than every session — MLD is a
trailing signal, not a per-session gate. Weekly is a reasonable default for an actively
worked project; a dormant project can review whenever work resumes. A single session's
MLD entry is rarely actionable on its own; the value is in patterns that recur across
several.

## Disposition

On review, give each recurring theme one of four dispositions:

- **Promote**: a Learning that recurs across 2+ sessions becomes a rule — a global
  `~/.claude/CLAUDE.md` line for a cross-project mistake, a project `CLAUDE.md` line or
  `rules/*.md` addition for a project-specific one. Mirrors the global CLAUDE.md's
  "Learning From Corrections" convention: propose the exact wording and get it approved
  before editing, don't infer approval from repetition alone.
- **Escalate**: a Mistake that recurs becomes a tracked task or a `features.json` entry
  with `discovered_via` pointing at the review, the same as any other internally
  discovered feature (see F022's precedent).
- **Action**: a Desire that is still wanted on reflection becomes a `features.json`
  entry, same mechanism as Escalate.
- **Discard**: a one-off entry with no recurring pattern is left as historical record.
  Do not delete `.harness/mld/` files during review — disposition decides what to build
  next, not what to prune; the files themselves are the record that the review happened.

## Committing

`.harness/mld/` is committed by default, the same as the rest of `.harness/` (only
`.harness/SESSION_INCOMPLETE` is gitignored). Commit MLD files with the session's other
harness-metadata changes (a `docs:` prefixed commit), not bundled into a code commit.
