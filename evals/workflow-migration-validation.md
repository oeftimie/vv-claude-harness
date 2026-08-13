# Workflow Migration Field Validation (OVI-147 / F117)

End-to-end field validation of the v6 harness (Agent Teams → dynamic workflows
migration, OVI-140 Phases 0–5) ahead of the v6.0.0 release. Every drill follows
the record shape pinned by the verified spec (AC4): date, exact inducing
mechanism, expected behavior, observed behavior, a verbatim key output snippet
or artifact path, PASS/FAIL.

Fixtures: two `noteskeep` toy projects (tiny stdlib-Python note library, 3
features, F003 elevated-risk), built 2026-08-13 in a session-scratch workspace:

- **toy-fresh** — seeded skeleton, then `/harness-init` run headless under THIS
  checkout via `--plugin-dir` (the v6 candidate), installed 5.7.0 plugin
  disabled per-project via `enabledPlugins`.
- **toy-v5** — same skeleton, `/harness-init` run headless under the INSTALLED
  v5.7.0 plugin (genuine Teams-era wiring: `TeammateIdle` route +
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`).

Standing disclosure: the v6 candidate is unreleased, so "`/plugin` update" is
stood in for by loading this checkout via `--plugin-dir` with the installed
5.7.0 disabled — functionally the post-update state, not the marketplace
update mechanics themselves.

## Fresh-init template check (2026-08-13)

- **Mechanism**: headless `claude -p --plugin-dir <checkout>` running
  `harness-init` in toy-fresh.
- **Expected**: post-migration templates install no Teams-era artifacts.
- **Observed**: `.claude/settings.json` hook events are exactly
  `PreToolUse`/`TaskCompleted`/`PostToolUse` — no `TeammateIdle`, no env flag;
  no `check-remaining-tasks.sh` in `.claude/hooks/`.
- **Snippet**: `hook events: ['PostToolUse', 'PreToolUse', 'TaskCompleted']`
  (toy-fresh) vs `['PostToolUse', 'PreToolUse', 'TaskCompleted',
  'TeammateIdle']` (toy-v5).
- **Verdict**: PASS.
- Side finding (template, not migration): the init-time `init.sh` python branch
  in the template pipes tests through `2>&1 | tail`, which masks failures under
  `set -e` without `pipefail`; the init agent detected and avoided it locally.
  Routed to `.harness/HARNESS_BACKLOG.md`.

## Spec gate on the toy features (2026-08-13)

- **Mechanism**: three sequential headless `harness-issue-prep` runs (local
  mode) in toy-fresh, operator decisions pre-delegated in the prompt.
- **Expected**: SV→(human loop)→RV converges within the 5-cycle cap; `risk` and
  `qa_binding` persisted to `features.json`.
- **Observed**: F001 SV ASK(10) → RV PASS at cycle 4; F002 SV ASK(14) → RV PASS
  at cycle 2; F003 SV ASK(13) → RV PASS at cycle 1 with `risk: elevated`
  recorded and `depends_on` corrected to `[F001, F002]` by the gate itself.
- **Snippet**: F003 `spec.hash =
  5902b727aa9028821979c424fd177a7b862b8577ae879b4b71913bad15c31764`.
- **Verdict**: PASS.

## AC6 — v5.x fixture upgrade drill (2026-08-14)

- **Mechanism**: toy-v5 at a clean git state; stand-in for `/plugin` update
  committed (checkout via `--plugin-dir`, installed 5.7.0 disabled); headless
  session ran doctor report → `--fix`; verification stages re-run mechanically
  via `skills/harness-doctor/doctor.py` after the harness's 10-minute
  background cap killed the session post-fix (disclosed deviation — the
  migration itself completed inside the one session; effects verified
  independently).
- **Expected**: doctor reports the Teams-era artifacts, `--fix` removes them
  under a settings backup, repeat `--fix` is a zero-finding no-op,
  `features.json` byte-identical, smoke green.
- **Observed, stage by stage**:
  1. Pre-fix report (recovered from a worktree at the pre-fix commit): three
     migration findings — `TeammateIdle` route (classified "committed, not
     local"), env flag, orphaned `check-remaining-tasks.sh`. No
     `teammate-scope.txt` finding (fixture never had one — correct).
  2. Fix pass: all three removed; `.claude/settings.json.bak` written;
     user-visible settings edits only.
  3. Post-fix report: `healthy`, exit 0.
  4. Repeat `--fix`: `healthy`, zero findings, zero edits (settings hash
     unchanged).
  5. `./.harness/init.sh smoke_test`: green (exit 0).
  - `features.json` sha256 identical before/after the entire drill:
    `b60d541125db8dde234131d6b44c7945b258a982a87e931545ff433fb9bfa035`.
- **Snippet**: `FINDING: .claude/settings.json still wires TeammateIdle to
  check-remaining-tasks.sh (Agent Teams, retired in v6)` → after fix:
  `healthy`.
- **Verdict**: PASS.
- **Defect found and fixed mid-drill**: doctor check 10 (F108 focused_test
  skip contract) false-positived on toy-v5's always-skip `init.sh` (marker
  present, no per-file runner, hence no `run_focused` to require). Fixed via
  TDD in this branch (red at 2028/2029 → green at 2029/2029); F117 scope
  expanded accordingly. Without the fix, AC6's "zero findings" close was
  unreachable on any stdlib-unittest project.
