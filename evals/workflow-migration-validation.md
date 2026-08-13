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

## AC1 — end-to-end workflow-mode run (2026-08-14)

- **Mechanism**: detached headless Opus lead in toy-fresh
  (`VV_HARNESS_DASHBOARD=1`, `--plugin-dir` checkout) running the
  `harness-continue` Step 5b flow: mirror tasks → `implement-features` workflow
  (`maxReviewRounds: 3`) → per-feature integration in the pinned order.
- **Expected**: 3 features implemented/reviewed/merged/passing; four gates
  observed; dashboard renders the run.
- **Observed**: F001 APPROVE round 1 (18 tests), F002 APPROVE round 1 (21),
  F003 REVISE→APPROVE round 2 of 3 (14 + 15 author-blind conformance). Final
  suite 69/69 — re-verified independently outside the toy session. Elevated
  handling on F003: high-effort Opus review + conformance pass both ran.
  Integration commits show the pinned order (merge → status flip → separate
  add/commit). Gates: SessionStart (incl. a real SESSION_INCOMPLETE catch),
  TaskCompleted ×3 (coverage stage self-skipped: no `coverage.py` — see
  findings), commit gate, enforce-scope, git-identity, dashboard hooks (538+
  events, 8 SubagentStart/Stop pairs).
- **Dashboard**: served by this branch's `serve.py`; only console entry the
  pre-existing favicon-404 resource line. Terminal-state screenshot at
  `.harness/evidence/ovi-147/ac1-dashboard-render.png`; per-agent spokes
  evidenced by the 8 SubagentStart/Stop pairs in
  `.harness/evidence/ovi-147/ac1-session.jsonl` (replay of a completed session
  animates faster than a capture round-trip — same disclosed limitation as
  F116). Full lead report: `.harness/evidence/ovi-147/ac1-lead-report.txt`.
- **Verdict**: PASS.
- **Findings routed to backlog**: (1) `implement-features.js` hardcodes the
  implementer to Sonnet — the elevated-risk lane's "upgrade implementer to
  Opus" heuristic has no per-feature override hook; (2) following
  `harness-continue` Step 3.5 (conformance proof on elevated features)
  guarantees a `qa_binding`/`proof.evidence_type` mismatch warning from
  `verify-task-quality.sh` — the two shipped rules contradict; (3) the
  coverage stage self-skips silently when no coverage tool exists for the
  stack; (4) deliberately batching dependent same-scope features (drill
  design, disclosed) reproduced exactly the failures `parallel-work.md`
  predicts — duplicated helpers, wholesale reimplementation, every
  post-first merge conflicting — independently caught by both reviewers; a
  strong negative result validating the rule's independence definition.

## AC2(a) — failing-tests REVISE drill (2026-08-14, organic)

- **Mechanism**: not injected — F003's round-1 implementation carried two
  mutation-verified test gaps (local-time timestamp with literal `Z`;
  tombstone written on the `KeyError` branch); the Opus reviewer returned
  REVISE.
- **Expected**: REVISE loop engages and terminates at ≤ 3 rounds.
- **Observed**: REVISE at round 1 → fixes applied and mutation-re-verified
  (including a reviewer-caught `TZ=UTC` mutant the first fix missed) →
  APPROVE at round 2 of 3. Loop bounded, no override needed.
- **Snippet**: `F003 delete | Sonnet, worktree 3 | 2 of 3 | REVISE → APPROVE`.
- **Verdict**: PASS (organic occurrence disclosed in place of an injected
  failure; the loop's engagement and bound are the assertion, and both were
  exercised for real).

## AC2(b) — blocked-feature drill (2026-08-14)

- **Mechanism**: toy-blocked clone (pre-implementation state) given an F004
  whose spec requires an API credential in an uncommitted `.env.notescloud`
  and forbids stubbing it — genuinely unbuildable by design; Sonnet lead ran
  the workflow for F004 alone.
- **Expected**: the workflow returns `status: blocked` with structured
  findings; the lead surfaces it, never merges; `features.json` unchanged for
  F004.
- **Observed**: `outcome: "blocked"` with a precise blocker naming the missing
  credential and the spec clause forbidding fakes; `review: null` (a blocked
  implementer short-circuits its review stage); pre-existing 69-test suite
  confirmed green before the block; no merge commit on the integration branch
  (verified independently: `F004 status: pending`, worktree branch unmerged);
  no credential fabricated, no stub written.
- **Snippet**: `"status": "blocked", "blocker": "Spec AC/edge case requires
  reading a real NotesCloud API key from .env.notescloud …"`.
- **Verdict**: PASS.
- Fixture artifact (not a defect): the worktree branch based itself on the
  clone's `origin/main` (toy-fresh, which already has F001–F003 merged) rather
  than the local drill branch — a divergence created by the clone-based drill
  setup, disclosed by the toy lead unprompted.

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
