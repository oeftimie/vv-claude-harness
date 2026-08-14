<!-- Shipped with the vv-harness plugin. There is no auto-loading: the SessionStart
orientation injects this file's absolute path, and /harness-continue instructs the lead
to read it before planning parallel work. -->

# Parallel Work

Rules for parallelizing work through workflow mode — the lead orchestrating
worktree-isolated agents via the plugin's Workflow scripts (`/harness-continue`
Step 5b), or via plain worktree-isolated subagents when the Workflow tool is
unavailable. These activate when a `.harness/` directory exists.

## When to parallelize

Parallelize when:
- Two or more independent, spec-verified features are ready (empty `depends_on` AND
  non-overlapping `scope`)
- A single feature has independent components (e.g., backend API + frontend UI + test suite)
- Research and implementation can proceed in parallel
- Code review or security audit benefits from multiple perspectives

Do NOT parallelize when:
- Only one feature is ready
- Work is sequential (step B depends on step A's output with no other work available)
- The orchestration overhead exceeds the parallelism benefit

When in doubt, start with a single session. Escalate to workflow mode if the task
naturally decomposes.

## Feature Schema

Every feature in `.harness/features.json` uses this shape:

```json
{
  "id": "F001",
  "description": "FEATURE_DESCRIPTION",
  "priority": 1,
  "status": "pending",
  "scope": ["src/auth/", "tests/auth/"],
  "depends_on": [],
  "assigned_to": null,
  "test_file": null,
  "coverage": null,
  "notes": null,
  "correction_cycles": 0,
  "scope_expansions": [],
  "approaches_tried": [],
  "failure_reason": null,
  "discovered_via": null,
  "spec": null
}
```

This is the one worked example; `${CLAUDE_PLUGIN_ROOT}/schemas/feature.schema.json` is the
authoritative field-by-field definition (types, patterns, required vs. optional) that this
example illustrates. The prose below only covers semantics the schema can't express (who
writes a field, when).

**Status values** (exhaustive enum):
- `pending`: ready for work, no one has claimed it
- `in-progress`: a workflow agent or single-session agent is actively working on it
- `blocked`: waiting on another feature or external dependency
- `passing`: complete, tests passing, coverage met
- `failed`: attempted and failed; needs re-assessment

**`scope`**: directories and files this feature owns. Passed to the workflow as
`featureSpecs[ID].scope` to define each agent's boundary.

**`depends_on`**: array of feature IDs (e.g., `["F001"]`). Maps to `TaskUpdate`
`addBlockedBy` calls on the lead's mirrored tasks.

**`assigned_to`**: the workflow run or agent working the feature, `"single-session"`
otherwise. Helps the lead reconstruct state if the session dies and restarts.

**Operational metrics** (who updates what):
- `correction_cycles` — incremented automatically by `verify-task-quality.sh` on each TaskCompleted rejection. **Never manually set.**
- `scope_expansions` — array of files/dirs added to scope after initial assignment. Lead appends here when a feature's scope had to grow mid-work.
- `approaches_tried` — brief notes on approaches attempted before the passing implementation. The implement agent's structured `notes` field carries this; lead populates the field at integration.
- `failure_reason` — lead sets this when moving a feature to `status: "failed"`. Must explain why, not just that it failed.
- `discovered_via` — lead sets this when adding a feature that emerged from another feature's implementation. Value is the source feature's ID (e.g., `"F002"`). Different from `depends_on` (technical dependency) — this is discovery lineage.

**Spec verification** (optional): when a feature's spec has passed the verification gate
(`/harness-init` Step 5.1 or the `harness-issue-prep` skill), it carries a `spec` object:
`{"hash", "verdict", "sv_version", "verified_at", "source"}`. `hash` is sha256 over the
`description` string exactly as stored (see `${CLAUDE_PLUGIN_ROOT}/schemas/readiness-stamp.md` for the canonical
recipe); editing the description invalidates it, and the SessionStart orientation warns on
that drift. Absent or `null` means unverified. Hooks and the lead must tolerate all three
states. A stamp-sourced `risk: "elevated"` maps to `require_plan_approval: true` plus an
elevated review pass (see Dynamic overrides).

Feature is not done until: `status` is `"passing"`, `test_file` points to a test, and
`coverage` >= `coverage_target` (or 95% on touched code when `coverage_target` is
absent). That is the mechanical gate — **passing**. **Done** is passing plus a `proof`
object recorded (claim, evidence type, artifact, and what the evidence did NOT
establish). **Shipped** is done plus `delivered` (PR merged and verified), when the
project ships through PRs. All other prose restatements of this definition — including
in `skills/harness-init/SKILL.md` — link here instead of repeating it.

**Claim-matched proof** (optional, for backward compatibility): a feature may declare a
`qa_binding` at prep time (`/harness-issue-prep` Step 5's mandatory "QA binding" line) —
the `evidence_type` it promises to be proven with. At completion time the lead records
a `proof` object; `verify-task-quality.sh` warns (never blocks) when a feature accepts
with no `proof`, or with `proof.evidence_type` not matching its declared `qa_binding`.
`coverage_target` (integer 1-100) overrides the 95% default; overrides should be
justified in `notes`, advisory only, never machine-enforced. `delivered.merged_at` must
be valid ISO8601. `design_contract` optionally points at a locked design artifact
(mock, redline, screenshot set) that journey/manual proof is compared against.

## Model Selection

Roles and their cognitive-demand tiers are protocol -- they don't change with a worker
upgrade. Which model NAME currently fills each tier is a binding, not policy, and this
table is the single bindings table for that binding (F016/OVI-57's "bindings-as-data"):
when a model generation ages out, requalification (`${CLAUDE_PLUGIN_ROOT}/docs/requalification.md`)
updates a row here, never the Role/Reasoning prose around it.

| Role | Model | Reasoning |
|------|-------|-----------|
| Lead (coordinator) | Opus | Decomposition, synthesis, and quality judgment require deep reasoning |
| Feature implementer | Sonnet | Scoped TDD within a well-defined directory; doesn't need Opus |
| Layer implementer | Sonnet | Same as feature implementer |
| Researcher | Sonnet | Web search and doc reading are retrieval-heavy, not reasoning-heavy |
| Reviewer | Opus | Deep code review catches subtle bugs; worth the cost |

The four vv-harness agent definitions (`vv-harness:feature-implementer`,
`vv-harness:layer-implementer`, `vv-harness:researcher`, `vv-harness:reviewer`) carry
these per-role model, effort, and tool defaults in their frontmatter, matching the
bindings table above (the reviewer definition also sets high effort, not just a model).
The Opus-upgrade heuristics below still apply: a spawn-time or workflow-level `model`
parameter overrides the definition's frontmatter. Requalification updates the table
above AND each agent definition's frontmatter together -- both must move in the same
requalification pass, since the table alone doesn't change what actually gets spawned.

Default to Sonnet for implementers; use Opus only when justified.

## Model policy

The lead/orchestrator runs the stronger model tier — decomposition, integration, and
synthesis are the highest-leverage reasoning in a session — while implementers run the
execution tier for scoped, spec-verified TDD. The tier split is policy; which model
NAME fills each tier is a binding, held in the Model Selection table above.

## Dynamic overrides

**Static elevation criteria**: a feature is elevated risk — record `risk: "elevated"`
plus `require_plan_approval: true` on the feature — when any of these holds, regardless
of history:
- Touches 10+ files or spans multiple modules
- Cross-cutting concerns (changing a shared interface)
- Security-sensitive code (authentication, authorization, crypto)
- First feature in a new codebase (establishing patterns)

`harness-issue-prep` applies the same criteria when stamping `lane`/`risk` at prep
time. An elevated feature gets an escalated review pass in workflow mode (the
implement-features script raises the reviewer's effort when `featureSpecs[ID].risk` is
`"elevated"`) and, optionally, the author-blind conformance check (`/harness-continue`
Step 5b, step 3.5).

**Elevation escalates the review stage, not the implementer.** Executors default to
Sonnet (Model Selection above); risk buys a deeper review pass and, optionally, a
spec-derived conformance pass — both of which judge the work rather than produce it.
This is deliberate: two mechanisms describing one model policy drift apart, so the
script owns the automatic part and there is exactly one place it happens. The lead can
still override a single feature's implementer — the historical-signals table below is
the reason to — by passing `featureSpecs[ID].implementModel` at launch; absent it,
implementers run on their agent definition's model.

**Historical signals** (based on operational metrics from past sessions): before
assigning models, the lead reviews `features.json` for patterns in the same scope
directories:

| Historical signal | Action |
|-------------------|--------|
| `correction_cycles >= 3` on a past feature in the same scope | Upgrade this feature's implementer to Opus, via `featureSpecs[ID].implementModel` |
| `scope_expansions >= 3` on a past feature | Assign a broader initial scope; note it as expansion-prone in the feature's spec |
| `failure_reason` mentions "approach mismatch" or "misunderstood interface" | Set `require_plan_approval: true` |
| `discovered_via` depth > 1 (discovered features spawning discovered features) | Fold into parent scope rather than running it as a separate feature |
| Stamp or prep marked risk: "elevated" | Set require_plan_approval: true; escalation is automatic and review-side (below) — the implementer stays Sonnet |

These are judgment calls for the lead, not mechanical rules. If no historical data
exists (first session, new scope), default to Sonnet.

**Metrics hygiene**: these historical signals apply within the current worker epoch (F016/OVI-57's `.harness/harness.json` `worker` block); signals from a prior epoch are advisory only, not a mechanical trigger, since a correction-cycle count from a different model generation doesn't describe this one.

## Escalation

**When review routes to Opus**: the reviewer runs Opus by its agent definition — no
per-launch flag needed; the `reviewModel` override exists only to deliberately
downgrade (e.g. a cheap Sonnet pass). An elevated-risk feature (`featureSpecs[ID].risk:
"elevated"`) also gets a high-effort review pass, and its implementer is upgraded to
Opus per the Dynamic overrides above.

**When a feature falls back to single-session**: a feature that returns `status:
blocked`, or whose review rounds are exhausted without an APPROVE (`maxReviewRounds`
reached on REVISE/REJECT), leaves the parallel path: surfaced to the user with its
structured findings — never auto-merged — then fixed directly by the lead in
single-session mode, or re-launched with a corrected spec.

## Lead-owned state

The lead is the only writer of `.harness/features.json`, `.harness/context_summary.md`,
and `.harness/claude-progress.txt`. Workflow agents and subagents do NOT edit them —
they report changes instead: the implement agent's structured return (`notes`,
`files_changed`, `test_file`, `tests_run`) is what the lead folds into `features.json`
at integration, and any decision or gotcha an agent surfaces goes to
`context_summary.md` through the lead. The one exception in spirit: agents include
`approaches_tried` material in their returned `notes` so the lead can populate the
field.

The lead:
1. Reads project state (`.harness/features.json`, `claude-progress.txt`, `context_summary.md`, git log) and selects features using `scope`, `depends_on`, and the operational metrics above
2. Mirrors tasks (`TaskCreate` with `metadata.feature_id`, dependencies via `addBlockedBy` derived from `depends_on`) and sets `assigned_to` when launching
3. Integrates returned work in the order pinned in Task mirroring and integration order below, updating `features.json` (status, test_file, coverage, approaches_tried, scope_expansions, failure_reason as appropriate)
4. Runs the retrospective, updates `context_summary.md` (Meta-Session + Meta-Patterns), and writes the session handoff to `claude-progress.txt`

**Locking is advisory and hook-scoped, not a substitute for this rule (OVI-107).** `harness_state.py`'s `increment-correction-cycles` write path holds an `fcntl.flock` for the duration of its own read-modify-write-rename, which prevents concurrent *hook* invocations (e.g. two `TaskCompleted` callbacks) from losing each other's writes. It does NOT protect against the lead's own direct `Edit`/`Write` calls on `features.json` — those go through no lock at all, by construction, since Edit/Write aren't routed through `harness_state.py`. The lock closes a hook-vs-hook race; it does not make lead-vs-hook writes safe to interleave. The rule above (lead owns these three files; hooks only touch `correction_cycles` via the shared module) is still what prevents that class of conflict, not the lock.

## Task mirroring and integration order

Before any parallel launch, the lead mirrors the batch into tasks:
`TaskCreate` one task per feature, each carrying `metadata.feature_id`
(dependencies via `addBlockedBy` derived from `depends_on`). This arms the
`TaskCompleted` gate's focused-test and coverage stages. `verify-task-quality.sh`
has a task-subject `FXXX:` fallback, but a subject without the exact prefix, or
with a mismatched ID, silently skips those stages — set `feature_id` explicitly;
never rely on the fallback.

Integration is per feature, in this order, only for features returned approved:
**run the feature's focused test + smoke locally → merge its `worktree_branch` →
flip `features.json` status to passing → mark the mirrored task complete (gate
fires) → commit (commit gate fires; `git add` and `git commit` as SEPARATE
calls)**. Never flip status or mark a task complete before its tests pass on the
merged code.

## Worktree hygiene

Workflow scripts never merge, never commit to the integration branch, and never edit
`.harness/features.json` — the lead integrates. An implementer's committed worktree
branch is its durable deliverable: work survives a dead agent because it is committed
on that branch, not because the agent reported it. After merging a feature's branch,
remove the changed worktree before any repo-wide suite run — a leftover worktree
hands repo-wide assertions a duplicate copy of every file (verified in Phase 0).

**Scope-diff every branch you did not watch produced.** Before merging a worktree
branch recovered from an interrupted or dead run, diff the files it touched against
that feature's declared `scope` and account for every file outside it:

```bash
git diff --name-only <mergeBase>...<worktree_branch>
```

An agent that dies mid-run leaves a branch nobody reviewed, and the enforcement that
normally bounds it (the PreToolUse scope gate) reports per call, not per branch — so
an out-of-scope edit on that branch reaches the merge unannounced. In OVI-147's
fallback drill a recovered branch carried an edit removing the project's own
`permissions.deny: ["Workflow"]` — unrelated to the feature, caught only because the
recovering lead happened to read the diff. Exclude what doesn't belong; merging is
the point of no return.

## Integration failure recovery

When merging worktree branches reveals integration issues:

1. Run `git diff` to identify the conflicting changes
2. Run the full test suite to pinpoint which tests fail and which feature's changes are involved
3. If one feature's work is clearly wrong: revert its merge, set the feature's status to `failed` in features.json with a `failure_reason`, and either re-launch it with a corrected spec or fix it directly
4. If both sides are partially right: merge manually, keeping the passing tests from both sides
5. If the conflict is architectural (shared interface mismatch): revert both, document the conflict in `context_summary.md`, and re-plan with one feature owning the shared interface
6. Update features.json with accurate statuses after resolution
7. Record the conflict and resolution in `context_summary.md` so future sessions know about it

The goal is always: get back to green tests as fast as possible. A clean revert is
better than a broken merge — each feature's work sits on its own worktree branch, so
selective reverts are trivial.

## Script authoring constraints

Workflow scripts (`workflows/*.js`) run under resume/replay: a resumed run replays
completed agents from cache, so the script text must be deterministic.

- `meta` is a pure literal — name, description, phases as literal values only, never
  computed fields.
- No `Date.now()`, `Math.random()`, `new Date()`, and no dynamic `import()` — any of
  these breaks byte-for-byte replay.
- `args` arrives as a JSON-encoded STRING on the current CLI — parse it defensively
  (guarded `JSON.parse`) and fail fast with a clear error on bad input.
- Every loop whose iteration count depends on agent output is bounded: put a `budget`
  guard on unbounded loops, and an explicit round cap on fix-and-recheck cycles
  (`maxReviewRounds` bounds the implement→review loop).
- Any silently applied cap or drop emits `log()`: a capped loop, a dead agent, a
  skipped optional pass each log what was capped or dropped — never degrade silently.

## Structured-output contracts

Result shapes for workflow agents are contracts, enforced at runtime by the `schema`
option on each `agent()` call in `workflows/*.js`; this is their single canonical
statement, which `skills/harness-continue/launch-prompts.md`'s templates reference.

- **Implementer result**: `{ feature_id, status: implemented|blocked, files_changed[],
  test_file, tests_run: {passed, failed}, worktree_branch, head_sha, notes, blocker }`
  — required: `feature_id`, `status`, `files_changed`, `worktree_branch`.
- **Reviewer result**: `{ feature_id, verdict: APPROVE|REVISE|REJECT, findings[],
  rounds_used }` — each finding carries `summary` (required) plus optional `file`,
  `line`, and `severity: critical|major|minor`.
- **Conformance result**: `{ feature_id, criteria: [{ criterion, result:
  PASS|FAIL|NOT-TESTABLE, note }] }` — one entry per acceptance criterion.

## Author blindness

Successor to the F017 clause, applied to every review-shaped prompt: a reviewer or
conformance prompt never includes the implementation diff or the implementer's tests
as derivation input.

- A **reviewer** prompt carries the verified spec and the branch name only. The
  reviewer inspects the diff itself with read-only git — that is its job — but is
  never handed the implementer's notes, rationale, or completion message, so the
  review cannot be talked into agreeing.
- A **conformance** prompt carries the verified spec ALONE: never the implementation
  diff, never the implementer's test files, never any completion message — a single
  context that writes both code and tests can satisfy a bug with a test that matches
  the bug.

## Dual-Engine Review (optional, F018/OVI-66)

Source: agent-os's review doctrine (nodera-studio, MIT) -- "independent engines for
recall, one synthesizer for precision." vv's reviewer is a single Opus agent reading
the diff; a second, independently-run engine catches single-model blind spots at the
cost of configuration, not a new dependency.

**Config**: an optional `review` block in `.harness/harness.json`:
```json
{
  "review": {
    "second_engine": "codex"
  }
}
```
Absent -- the current default -- means single-engine behavior, zero change.

**When the block is present AND `command -v codex` succeeds**, the lead runs the Codex
CLI review as a background Bash step over the feature branch diff, BLIND to the Claude
reviewer's output: start the Claude review and the Codex background step
before reading either's result, so neither engine's findings can influence the
other's. The diff reviewed is the feature's worktree branch diff, not the lead's own
working tree.

Pinned invocation:
```bash
codex review --base <BASE_BRANCH>
```
`verified live 2026-08-01 on Codex CLI 0.145.0`: `codex review --help` confirms this
exact flag (`--base <BRANCH>`, "Review changes against the given base branch") exists
and matches this use case, and `codex doctor` confirmed the CLI is authenticated
(ChatGPT auth) and its endpoint reachable. A full end-to-end review run was NOT
executed as part of this verification (avoiding an unrequested spend against the
user's Codex subscription) -- the command's existence, exact flag spelling, and the
CLI's auth/reachability are what's verified live, not a completed review's output
shape. Re-verify a full run the first time this path actually triggers.

**If the CLI is absent or errors**, skip WITH an explicit line in the review summary:
`"second engine unavailable: single-engine review"` -- never silently. A silent skip
would let a config that looks like it's getting dual coverage quietly degrade to
single-engine without anyone noticing.

**Synthesis rules** (apply when both engines produced output; these govern how the
lead or the Claude reviewer combines the two lists into what actually routes to
fixes):
1. **Dedupe by defect, not by file:line.** Two engines describing the same underlying
   defect at slightly different line numbers (e.g. the function signature vs. its
   first call site) are ONE finding, not two.
2. **A single-engine CRITICAL survives synthesis.** Cross-engine agreement is a
   confidence signal, not a filter -- a CRITICAL-severity defect only one engine
   caught is never downgraded or dropped for lacking a second opinion.
3. **Cross-engine agreement raises confidence, it doesn't gate inclusion.** When both
   engines independently flag the same defect, label it higher-confidence in the
   synthesized list; a single-engine finding is still included, just not labeled with
   that boost.
4. **Provenance is verified, not guessed.** Before labeling a finding NEW vs.
   PRE-EXISTING, check `git show <merge-base>:<file>` for the flagged region rather
   than assuming from the diff alone -- a line that looks new in the diff view can be
   an unmodified line inside a larger hunk.

**Cost**: the second engine is Codex-subscription cost, not Claude tokens -- it adds
no Sonnet/Opus spend to the session's own cost accounting in `## Cost Considerations`
below.

**Honest limits**: two engines disagree often on style; only correctness and security
findings get the cross-engine consensus treatment above. A style disagreement between
engines is not evidence either engine is wrong -- don't synthesize style findings the
same way as correctness/security ones.

**Out of scope**: a third engine (CodeRabbit, Gemini, etc.); Codex as an implementer
(vv orchestrates Claude agents only, by design); automatically applying fixes from the
synthesized findings list -- synthesis produces a routed list, a human or a follow-up
agent still does the fix.

## Cost Considerations

Model mixing reduces per-implementer token cost by roughly 5x (Sonnet vs Opus). But
parallel orchestration has overhead that offsets some of that savings:

- **Lead overhead**: the lead runs on Opus for the entire session (planning, integration, synthesis). This is fixed cost regardless of how many agents a run launches.
- **Review rounds**: each implement→review round in the workflow costs tokens on both ends; `maxReviewRounds` bounds it.
- **Pre-launch planning**: reading all harness files, verifying specs, mirroring tasks: this happens before any implementation tokens are spent.

**Measure the break-even, don't estimate it:**
- With telemetry enabled (see INSTALL.md, "Optional: Cost Telemetry"), derive the
  break-even from `claude_code.token.usage` and `claude_code.cost.usage` grouped by
  `model` and `query_source` (main vs subagent): compare a workflow run's measured cost
  against single-session work on a comparable scope, and let that calibrate when
  parallelism pays off in this project. `agent.name` only distinguishes
  official-marketplace agents — personal-marketplace agent names (including vv-harness
  roles) are redacted to `"custom"`, so it cannot separate the harness roles.
- Without a collector, use the in-session `/usage` breakdown, which attributes recent
  usage to skills, subagents, plugins, and MCP servers as percentages (the plan-usage
  breakdown view requires a subscription plan — Pro/Max/Team/Enterprise; the session
  token/cost stats are universal).
- The retrospective should cite measured token counts per model and per query source
  in the Meta-Session entry instead of estimates.
- With no telemetry at all, fall back to judgment: parallelize only when the planned
  batch clearly exceeds what one focused session would finish.

**Rules of thumb:**
- For two features that each touch fewer than 3 files, sequential single-session is cheaper
- The more independent the features, the better the parallelism payoff (no cross-feature coordination)
- Opus review is worth the cost for features touching 10+ files
- The author-blind conformance tester (F017/OVI-65) costs one Sonnet pass per elevated-risk or plan-approval-gated feature it's spawned for -- it's opt-in per feature (`/harness-continue` Step 5b, step 3.5), not a per-session fixed cost, so it doesn't change the break-even math above for batches that never trigger it.

Don't optimize for cost at the expense of quality. The point of model mixing is to put
reasoning power where it matters most (lead decisions, code review) and use efficient
models for well-scoped, well-defined implementation work.
