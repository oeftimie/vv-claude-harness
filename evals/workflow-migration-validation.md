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

## Release review round (2026-08-14)

The `review-branch` workflow over the release branch (13 raw findings → 13
deduped → adversarial verify; 2 verifiers lost to API 529s, their findings
treated as unverified-but-actioned): 7 confirmed (3 major). All fixed or
dispositioned in one commit: stale "Agent Teams coordination" in both release
manifests (+ a manifest vocabulary-sweep assertion); the runbook delist note's
MAINTENANCE_LOG.md pointer dangling against a log that said "NOT retired"
(retirement record appended, assertion now follows the pointer); doctor
check 10's marker conjunct unpinned (marker-less/no-fake-green fixture added);
the workaround retirement-condition assertion counted file-wide (now
per-entry); unrecorded scope expansions on F117 (recorded); the resume
resend-`args` fix unpinned (asserted in both passages). One minor accepted as
the documented trade-off: dropping the `run_focused` requirement stops
detecting a runner-invoking `init.sh` missing only the remap. Suite
2036/2036 after the round.

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

## AC2(c) — kill/resume drill, attempt 1 (2026-08-14): kill-side PASS, resume leg confounded

- **Mechanism**: toy-resume clone; Sonnet lead launched the workflow; monitor
  on the dashboard log's first `SubagentStop`; `kill -9` on the lead process
  at that point (21:51 UTC). First kill hit the shell wrapper, not the CLI —
  the surviving `claude` child was identified by cwd and killed separately
  (drill note: kill the CLI pid, not its wrapper).
- **Kill-side observations (all hold)**: `.harness/features.json` sha256
  byte-identical to the pre-launch baseline (`a6a7ddc5…`); no integration on
  the branch; one in-flight worktree branch left behind. The corruption
  invariant is proven.
- **Resume-leg confound (drill-design error, disclosed)**: toy-resume was
  cloned from toy-fresh AFTER AC1 completed, so the clone's `origin/main`
  already contained implemented F001–F003. The resumed session consulted the
  run's `journal.jsonl`, discovered the finished work, verified it
  independently (ancestor check, `spec.hash` match, its own 69/69 suite run,
  source read), and integrated by fast-forward instead of exercising
  `resumeFromRunId` — explicitly disclosing that it had not run the pipeline
  itself. The cache-replay observable was therefore NOT demonstrated in this
  attempt.
- **Conduct finding (positive)**: the resumed session treated the operator
  prompt's "machine crash" framing as an unverified narrative, declined to
  parrot the prescribed report claims, and grounded itself in the journal —
  exactly the injected-instruction skepticism the integrity rules ask for.
- **Verdict**: kill-side PASS; resume leg re-run in attempt 2 (below) on an
  uncontaminated fixture (no origin remote, `main` at the pre-implementation
  commit).

## AC2(c) — kill/resume drill, attempt 2 (2026-08-14): PASS

- **Mechanism**: uncontaminated fixture (toy-resume2: no origin remote, `main`
  at the pre-implementation commit); fully scripted drill — Sonnet lead
  launched the 3-feature batch, a shell watchdog polled the dashboard log and
  `kill -9`'d the CLI process at `SubagentStop count=1` (05:32 UTC), recorded
  the state, then launched `claude --resume <session>` with the resume
  instruction.
- **Expected**: resume via `resumeFromRunId` replays the completed agent from
  cache and re-runs in-flight agents live; `features.json` untouched by the
  workflow; batch completes.
- **Observed**: post-kill `features.json` diff contained ONLY the lead's own
  pre-launch bookkeeping (`status: in-progress`, `assigned_to`) — zero
  workflow-written fields, so the corruption invariant holds in its intended
  sense. The resumed session relaunched the run and completed it: 3/3 passing,
  71/71 green (verified independently), REVISE verdicts on all three
  implementers handled by the lead with mutation-verified fixes and no
  auto-merge of a REVISE.
- **Snippet**: `KILLED lead 604 at 05:32:18Z after SubagentStop count=1` →
  resumed session: `Batch complete: 3/3 features passing, 71/71 tests green`.
- **Verdict**: PASS.
- **Load-bearing finding (fixed in-branch)**: `Workflow({scriptPath,
  resumeFromRunId})` alone fails fast — the ORIGINAL `args` must be resent
  with the resume call. The shipped `harness-continue` text documented the
  two-parameter form; both passages now name the `args` requirement.
- Drill-procedure note: kill the CLI pid, not its shell wrapper (attempt 1's
  first kill hit the wrapper and left the CLI running).

## AC2(d) + AC3 — unavailability degradation and fallback parity (2026-08-14): PASS

- **Mechanism**: toy-fallback (clone at pre-implementation state) with
  `permissions.deny: ["Workflow"]` committed as drill scaffold; two sessions
  (the first killed by the account usage limit mid-F001; the second recovered
  and completed — itself an unplanned exercise of interrupted-session
  recovery).
- **Expected**: availability probe detects the denied tool; documented plain
  worktree-subagent path engages; same 3 features end passing with outcome
  parity; same gates fire.
- **Observed**: probe ran `claude --version` (2.1.231 ≥ 2.1.154) and detected
  the deny via settings + a ToolSearch miss; fallback engaged explicitly. All
  3 features passing (verified independently), 72/72 green, pinned
  integration order with separate add/commit per feature, `TaskCompleted` and
  commit gates fired on all 4 commits, F003 carried mutation-tested review +
  author-blind conformance (`proof.evidence_type: "conformance"`), worktree
  removed post-merge. Outcome parity with the workflow run holds on every
  required axis (same features passing, acceptance tests green, equivalent
  `features.json`, same gates); test counts differ (69 vs 71 vs 72) as
  review-round-shaped extras, explicitly exempt from parity.
- **Integrity catch (backlog candidate)**: the interrupted session's
  surviving worktree carried an unauthorized edit REMOVING the `Workflow`
  deny from `.claude/settings.json` — out of scope for any feature. The
  recovering lead excluded it from the merge and verified the real settings
  byte-identical to the scaffold commit (re-verified independently:
  `deny: ["Workflow"]` intact). Proposed mechanical check: diff every
  worktree-touched file against the feature's declared scope at recovery.
- **Verdict**: PASS (both AC2d and AC3).

## Observed failure class — account usage limit mid-run (2026-08-14)

Not a drill: the first AC3 fallback run (~85 min in, F001 still unintegrated)
and the first attempt-2 AC2(c) launch were both killed by the account session
limit ("resets 2:40am"). Recovery used the same machinery the drills
validate: state re-read from `features.json`/`claude-progress.txt`, runs
relaunched after the reset window. Recorded for the OVI-140 exit review as a
real failure class the workflow-era harness must absorb (and did).

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
