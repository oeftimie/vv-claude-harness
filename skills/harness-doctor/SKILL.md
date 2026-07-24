---
name: harness-doctor
description: Report-first, idempotent instance health check for a harness-managed project. Verifies python3/git presence, the hook set and its executability, .claude/settings.json wiring, .gitignore rules, .harness/ file validity, version drift against the current plugin, and the mld non-injection guarantee. Offers a --fix upgrade mode, but never writes without explicit approval. Use when a smoke test fails unexpectedly, after a manual edit to .claude/ or .harness/, or when upgrading a project initialized under an older harness version.
---

# Harness Doctor

Structural, idempotent health check for a single harness project. It is report-first:
running it never changes anything on disk. It only writes when re-run with `--fix`,
and `--fix` applies exactly the five mechanical steps in INSTALL.md's "Upgrading an
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
     `check-remaining-tasks.sh`, `enforce-scope.sh`, `verify-git-identity.sh`,
     `statusline.sh`.
   - **Optional-v5** (missing = "upgrade available", not an error): `harness_state.py`
     (post-OVI-50) — `verify-task-quality.sh` and `check-remaining-tasks.sh` work
     identically with or without it, so its absence is a suggestion, not a defect.
   - **Not-yet-applicable**: a commit-content gate (post-S4/OVI-64). The doctor only
     checks for this once the running plugin version actually ships a commit-gate
     template; until then, a missing per-project copy produces no finding of any kind.
3. **`.claude/settings.json`**: parses; carries `statusLine`, the
   `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var, a non-empty `permissions.allow`, and
   hook wiring for `PreToolUse` (enforce-scope.sh, verify-git-identity.sh),
   `TaskCompleted` (verify-task-quality.sh), and `TeammateIdle`
   (check-remaining-tasks.sh). The check is structural — it accepts either the
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
6. **Version drift**: a stale `PostCompact` block (see check 3) and missing v5
   artifacts (`statusline.sh`, the settings wiring, the `.gitignore` entry,
   `harness_state.py`) are the drift surface for a per-project doctor. The global
   v3.6-era stale-file manifest in `CHANGELOG.md` is explicitly scoped to `~/.claude/`
   only and does not apply here.
7. **mld non-injection**: if `.harness/mld/` exists, the currently running plugin's
   `hooks/session-start.sh` must not reference it anywhere — that directory is
   telemetry, never something read into the model's context. This checks the
   plugin's own copy rather than anything under the project's `.claude/hooks/`,
   since `session-start.sh` is invoked directly from `CLAUDE_PLUGIN_ROOT` and is
   never copied per-project. If `.harness/mld/` doesn't exist, or the plugin root
   can't be determined, there is nothing to guard and no finding is produced.

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
`statusLine`/`env`/`permissions`/hook wiring to `.claude/settings.json`; append
`.harness/SESSION_INCOMPLETE` to `.gitignore`; copy `harness_state.py.template` (and
re-copy `verify-task-quality.sh`/`check-remaining-tasks.sh`, since older per-project
copies may carry pre-OVI-50 inline logic). Anything it cannot mechanically resolve —
missing `python3`/`git`, a hard-required hook that was deleted outright, a JSON parse
error, a `features.json` validation failure, a `context_summary.md` missing a required
section — is reported unchanged after the fix pass, because that is a judgment call,
not a copy step.

**Report-first is the whole point: the doctor never writes anything without explicit
approval.** Run it plain first, read the findings, and only re-run with `--fix` once
you've decided you want those specific mechanical fixes applied. It is idempotent —
running it (with or without `--fix`) twice in a row produces the same result the
second time.

## When to reach for it

- `harness-continue`'s Step 2.5 smoke test fails unexpectedly.
- After manually editing anything under `.claude/` or `.harness/`.
- Before or after upgrading a project that was initialized under an older harness
  version — this replaces the five manual steps INSTALL.md used to require.
