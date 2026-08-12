---
name: harness-doctor
description: Report-first, idempotent instance health check for a harness-managed project. Verifies python3/git presence, the hook set and its executability, .claude/settings.json wiring, .gitignore rules, .harness/ file validity, version drift against the current plugin, whether a passing/in-progress feature's test_file actually exists, and the mld non-injection guarantee. Offers a --fix upgrade mode, but never writes without explicit approval. Use when a smoke test fails unexpectedly, after a manual edit to .claude/ or .harness/, or when upgrading a project initialized under an older harness version.
---

# Harness Doctor

Structural, idempotent health check for a single harness project. It is report-first:
running it never changes anything on disk. It only writes when re-run with `--fix`,
and `--fix` applies exactly the six mechanical steps in INSTALL.md's "Upgrading an
existing harness project" section — nothing broader, and never without you having
first seen the report and asked for the fix.

## Running it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/harness-doctor/doctor.py" .
```

A clean project prints a single line:

```
healthy
```

A project with problems prints one `FINDING:`/`fix:` pair per problem and exits
non-zero:

```
FINDING: hook 'enforce-scope.sh' is not executable
  fix: chmod +x .claude/hooks/enforce-scope.sh
```

A directory with no `.harness/` at all is not a harness project — the doctor exits 2
and points to `/harness-init` instead of running any checks.

## What it checks

1. **Dependencies**: `python3` and `git` resolve on `PATH` — every hook depends on
   `python3`, and nothing else in this project checks for it.
2. **Hook set**, each entry classified so a missing artifact is reported at the right
   severity:
   - **Hard-required** (missing or non-executable = error): `verify-task-quality.sh`,
     `enforce-scope.sh`, `verify-git-identity.sh`, `statusline.sh`.
   - **Optional-v5** (missing = "upgrade available", not an error): `harness_state.py`
     (post-OVI-50) — `verify-task-quality.sh` works identically with or without it,
     so its absence is a suggestion, not a defect.
   - **Not-yet-applicable**: a commit-content gate (post-S4/OVI-64). The doctor only
     checks for this once the running plugin version actually ships a commit-gate
     template; until then, a missing per-project copy produces no finding of any kind.
3. **`.claude/settings.json`**: parses; carries `statusLine`, a non-empty
   `permissions.allow`, and hook wiring for `PreToolUse` (enforce-scope.sh,
   verify-git-identity.sh, commit-gate.sh) and `TaskCompleted`
   (verify-task-quality.sh). The check is structural — it accepts either the
   `"$CLAUDE_PROJECT_DIR"/...` form or a simpler relative path, since both are
   functionally equivalent; it does not enforce one string form over the other. A
   stale `PostCompact` hook block (superseded by the plugin's SessionStart `compact`
   handling) is flagged for removal.
4. **`.gitignore`**: does not exclude `.claude/` without the `!.claude/hooks/` and
   `!.claude/settings.json` exceptions, and does include `.harness/SESSION_INCOMPLETE`.
5. **`.harness/` state**: `harness.json` and `features.json` parse; `features.json`
   additionally validates against `scripts/validate-features.py` when the running
   plugin ships one; `context_summary.md` carries the section headings that always
   appear per its canonical template (`rules/context-summary.md`): `## Active
   Context`, `## Cross-Cutting Concerns`, at least one `## Domain: ` section, and
   `## Meta-Patterns`. Repeatable dated `## Meta-Session [DATE]` entries and the
   optional `## Closed Work Streams` section are not checked for bare presence — a
   project's first session legitimately has neither yet.
6. **v5 upgrade staleness**: a stale `PostCompact` block (see check 3) and missing v5
   artifacts (`statusline.sh`, the settings wiring, the `.gitignore` entry,
   `harness_state.py`) are the staleness surface for a per-project doctor. The global
   v3.6-era stale-file manifest in `CHANGELOG.md` is explicitly scoped to `~/.claude/`
   only and does not apply here.
7. **Feature test_file existence** (F066): every feature with status `passing` or
   `in-progress` and a non-null `test_file` must have that path actually resolve in
   the working tree — `features.json` recording a test file is a claim, not a fact,
   and nothing else in the harness validates it. `pending` features and features with
   no `test_file` set are not checked (nothing to verify yet).
8. **Plugin version drift** (F068): `.harness/harness.json`'s `plugin_version` field
   is compared against the currently running plugin's own `.claude-plugin/plugin.json`
   version. `scripts/stamp.sh` writes it at project creation (mechanical, not
   decision-shaped, so the stamp emits it directly rather than deferring it to a
   `/harness-init` follow-up step like `git_identity`/`worker`). A mismatch is
   reported (not an error) — hooks and skills may have legitimately changed between
   the two versions, and the reader decides whether that matters here. A project with
   no `plugin_version` recorded at all — one stamped before F068 shipped, most likely
   — gets an "upgrade available" finding, same class as the missing-`harness_state.py`
   case (check 2): fixable, not a hard error, and `--fix` bootstraps it. This is the
   only path by which such a project can ever acquire the field, so unlike the
   `worker` block, absence here is not silently valid.
9. **mld non-injection**: if `.harness/mld/` exists, the currently running plugin's
   `hooks/session-start.sh` must not reference it anywhere — that directory is
   telemetry, never something read into the model's context. This checks the
   plugin's own copy rather than anything under the project's `.claude/hooks/`,
   since `session-start.sh` is invoked directly from `CLAUDE_PLUGIN_ROOT` and is
   never copied per-project. If `.harness/mld/` doesn't exist, or the plugin root
   can't be determined, there is nothing to guard and no finding is produced.
10. **focused_test skip contract** (F108): `.harness/init.sh` is a per-project copy
    made at init time, so v5.5.0's focused_test exit-code contract (F106 — exit 3
    reserved for a skip, a runner's own exit 3 remapped to 1, a missing test file
    skipped rather than faked green) never reaches a project that adopted
    `focused_test` before F106 shipped. If `init.sh` mentions `focused_test` outside
    a comment (the same support-detection heuristic `verify-task-quality.sh` uses)
    but is missing the `skipped (exit 3)` marker or the `run_focused` exit-3 remap
    — or still carries a pre-F106 `treating as pass` fake-green arm, which catches a
    partially hand-applied repair — the doctor reports it as upgrade-available. All
    of these are checked against non-comment lines only, so a comment quoting the
    markers (a TODO note, or the finding text pasted as a reminder) neither
    satisfies nor triggers the check. An `init.sh` with no `focused_test` support
    at all, or none present, produces no finding — there is nothing to check yet.
11. **Agent Teams migration** (OVI-144): Agent Teams was retired in v5.7.0, when
    worktree-isolated workflows replaced it. A project initialized under v5.x still
    carries four artifacts of it, each reported as a migration step with a fixer:
    a `TeammateIdle` route to `check-remaining-tasks.sh`, the
    `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var, the orphaned
    `.claude/hooks/check-remaining-tasks.sh` itself, and a leftover
    `.claude/teammate-scope.txt`. The last one is the only remnant that still has an
    effect — while it exists, `enforce-scope.sh` gates edits against a scope no
    running teammate owns.

## Workflow-support notices

Workflow mode needs the `claude` CLI at 2.1.154 or newer and the `Workflow` tool
enabled. Neither is a health defect: without them the single-session fallback applies
and the project is fine. So these are printed as notice lines beside the report and
never change its exit code:

```
WARN: claude CLI 2.1.100 < 2.1.154 -- workflow mode unavailable, single-session fallback applies
WARN: Workflow tool disabled in settings -- workflow mode unavailable
INFO: claude CLI version undetectable -- skipping workflow-support check
```

The version probe is defensive in the same way `harness-continue`'s worker-epoch check
is: an absent CLI, a non-zero exit, or output this can't parse all produce the `INFO`
line and skip the check rather than failing anything. "Disabled in settings" means the
settings explicitly turn the tool off — a `permissions.deny` entry naming `Workflow`,
or the org-level `disableWorkflows` switch. Anything subtler than those two literal
forms is left to the skill, which detects unavailability at runtime by the tool simply
being absent.

## Finding classification

Before recommending a fix for `.claude/settings.json` or `.gitignore` findings, the
doctor diffs the artifact against git history to note whether the problem is
committed drift or a local, uncommitted edit — the two call for different follow-up
(fix it here vs. fix it upstream). If the artifact is untracked, or the repository has
no commit history for it at all, the doctor defaults to "uncommitted local edit" and
says so explicitly. It never assumes committed drift without a diffable baseline.

## `--fix`

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/harness-doctor/doctor.py" --fix .
```

This applies only the mechanical actions from INSTALL.md's upgrade section: remove a
stale `PostCompact` block; copy `statusline.sh` from the plugin; add the missing
`statusLine`/`permissions`/hook wiring to `.claude/settings.json`; append
`.harness/SESSION_INCOMPLETE` to `.gitignore`; copy `harness_state.py.template` (and
re-copy `verify-task-quality.sh`, since older per-project copies may carry pre-OVI-50
inline logic); write or update `.harness/harness.json`'s `plugin_version` to the
currently installed plugin's version (F068) — this is how a project that predates
F068, or has simply drifted, ever acquires or refreshes the field; nothing else does.

It also applies the Agent Teams migration (check 11): it deletes the orphaned
`check-remaining-tasks.sh` and the stale `teammate-scope.txt`, and strips both
settings.json remnants under a single `.claude/settings.json.bak` written immediately
before the edit (overwriting any older `.bak`, so the backup always describes the
state this run is about to change). Only the harness's own hook entry leaves the
`TeammateIdle` array — a user-authored hook sitting alongside it is preserved, and the
event key itself is removed only when nothing is left to run.
Anything it cannot mechanically resolve —
missing `python3`/`git`, a hard-required hook that was deleted outright, a JSON parse
error, a `features.json` validation failure, a `context_summary.md` missing a required
section, a stale focused_test skip contract in `.harness/init.sh` (check 10) — is
reported unchanged after the fix pass, because that is a judgment call, not a copy
step. `init.sh` in particular is never rewritten by `--fix` at all: it is the one
genuinely decision-shaped per-project file (it mixes in project-specific stack logic),
so its finding always carries a hand-apply repair instead of a fix.

**Report-first is the whole point: the doctor never writes anything without explicit
approval.** Run it plain first, read the findings, and only re-run with `--fix` once
you've decided you want those specific mechanical fixes applied. It is idempotent —
running it (with or without `--fix`) twice in a row produces the same result the
second time.

## When to reach for it

- `harness-continue`'s Step 2.5 smoke test fails unexpectedly.
- After manually editing anything under `.claude/` or `.harness/`.
- Before or after upgrading a project that was initialized under an older harness
  version — this replaces the six manual steps INSTALL.md used to require.
