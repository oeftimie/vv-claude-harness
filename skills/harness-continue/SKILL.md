---
name: harness-continue
description: Continue working on a harness-managed project (vv-harness plugin). Orients to current state, picks single-session or workflow mode, and guides implementation with TDD, quality gate hooks, and compaction-aware context management. Use at the start of any session on a harness project.
---

# Harness Continue

## Step 1: Orient Yourself

The vv-harness plugin's SessionStart hook auto-injects orientation at session start:
feature summary, next claimable feature, last handoff, Active Context, a git identity
warning on mismatch, and any SESSION_INCOMPLETE gaps from the previous session. Use
that injected "## Harness orientation" block instead of re-reading the harness files.
Resolve any SESSION_INCOMPLETE gaps it surfaces before starting new work.

This skill covers what the hook does not: mode choice, the smoke test, and workflow
planning.

Check for untracked files and inherited task quality:

```bash
git status -s          # surface unknown untracked files
```

If you see untracked files you didn't create (e.g., `notes.md`, scratch files), surface them to the user immediately: "I see `[file]` untracked — should I delete it, gitignore it, or leave it?" This takes 5 seconds and prevents orphaned file accumulation.

If inheriting tasks from a previous session, verify they have required metadata fields (`feature_id` at minimum) via `TaskList`. Tasks without `feature_id` can't be correlated by hooks or retrospectives. Update them with `TaskUpdate` now if they're missing it.

## Step 2: Verify Git Identity

The SessionStart hook already compared `git config user.email` against
`.harness/harness.json` and warned on mismatch (non-blocking). If the orientation
block shows an identity warning, fix it before proceeding. Also verify the SSH
identity, which the hook does not check:

```bash
ssh -T git@github.com 2>&1 || true
```

Do not skip this.

## Step 2.5: Smoke Test

Run the project's build/test smoke test:

```bash
./.harness/init.sh smoke_test
```

This is a gate, not a diagnostic. Its purpose is to confirm the environment is in a known-good state BEFORE any changes. If it fails, you know the problem is pre-existing, not something you introduced. Run it within the first 5 actions of every session. No exceptions. The 15-second cost prevents 15-minute debugging sessions later. (OVI-106: `init.sh`'s own default target is `full_test`, not `smoke_test` -- pass the argument explicitly, or this step silently runs the full suite instead of the fast gate this section describes.)

If it fails unexpectedly, `/harness-doctor` can help narrow down why — it structurally
checks hook presence/executability, `.claude/settings.json` wiring, `.gitignore`
rules, and `.harness/` file validity in about 10 seconds.

## Step 2.6: Worker Epoch Check

HE fixed-worker thesis: hold the worker (model + coding agent) constant for one epoch,
record its configuration, and requalify on every material change -- "requalification
includes subtraction." This step is the mechanical trigger for that ritual, not the
ritual itself; see `${CLAUDE_PLUGIN_ROOT}/docs/requalification.md` for the checklist.

Read `.harness/harness.json`'s optional `worker` block
(`${CLAUDE_PLUGIN_ROOT}/schemas/feature.schema.json`'s `$defs/harness_worker_block`).
**Absent -> skip silently**: an old project, or one that has never run this check, has
nothing to compare against yet, and this is not a reason to block the session.

If present, probe the live CLI version defensively -- its output format may change
across releases, and this check must never block a session over a parse failure:

```bash
claude --version 2>/dev/null || true
```

**Command unavailable, or output doesn't parse -> skip silently.** No hook-time
version probing; this check lives only in the skill, and only degrades gracefully.

If it parses, compare the MINOR component of the live version against
`worker.cli_version`'s minor component. Surface a one-line requalification prompt when
either holds: the minor-version delta is >= 10, or the user directly reports a
model-generation change (a new Sonnet/Opus generation, a CLI major bump, etc.):

```
Worker epoch check: CLI moved from <worker.cli_version> to <live version> (delta N
minors) since this project's worker block was last recorded on <recorded_at>. Consider
a requalification pass: see docs/requalification.md.
```

This is a prompt, not a gate -- proceed with the session either way. Only update
`.harness/harness.json`'s `worker` block (`cli_version`, `models`, `recorded_at`) once
the user has actually run (or explicitly deferred with a reason) the requalification
pass; firing the prompt alone is not a reason to rewrite the block.

## Step 3: Set Effort Level

Set effort based on the current phase:

- Architecture decisions, debugging failing tests, reviewing returned agent work: `/effort high`
- Feature implementation (TDD loop), file refactoring: `/effort medium` (default)
- Formatting, linting fixes, boilerplate generation: `/effort low`

Adjust as you transition between phases during the session.

## Step 4: Decide Mode

**Choose Single-Session if:**
- One feature is next and it touches fewer than 5 files
- The feature is sequential (can't be parallelized)
- User explicitly asks for focused work

When choosing single-session, explicitly declare it: "Running in single-session mode — I'm both lead and implementer." This makes the decision conscious and documented, preventing ambiguity between "I forgot plan mode" and "plan mode doesn't apply here."

**Choose Workflow mode (the primary parallel path) if:**
- Two or more **independent, spec-verified** features are ready, where independent means
  **empty `depends_on` AND non-overlapping `scope`**. (When two verified independent
  features each touch fewer than 5 files, workflow mode still wins over single-session —
  the parallel gain outweighs single-session's simplicity once two independent verified
  features exist.)
- User explicitly asks for parallel work.

Workflow mode orchestrates via the plugin's `/vv-harness:implement-features` workflow
(Step 5b): one Sonnet implementer per feature in an isolated worktree, then a reviewer
per feature, returning structured per-feature results the lead integrates. `agent()`
returns are runtime-guaranteed and schema-validated (no message-delivery protocol to
babysit), worktree isolation is first-class, and a run is resumable in-session — the
structural fixes for the coordination failure classes this project hit.

**Availability probe.** Workflow mode needs Claude Code ≥ 2.1.154 and the `Workflow`
tool present (not org-disabled via `disableWorkflows`). Probe by capability: parse
`claude --version` and confirm the `Workflow` tool is available. **If unavailable**
(older CLI, `disableWorkflows`, or a plan without it), fall back to the
worktree-isolated plain-subagent path below.

**Peer-debate exception:** research or competing-hypothesis work that genuinely needs
inter-agent discussion is *not* what the implement→review pipeline does. For that, spawn
plain parallel subagents.

**Fallback — plain worktree-isolated subagents:**

When workflow mode is unavailable, do NOT abort parallel work. Fall back to direct
subagents spawned via the Agent tool using the same vv-harness agent types
(`vv-harness:feature-implementer`, `vv-harness:layer-implementer`,
`vv-harness:researcher`, `vv-harness:reviewer`), passing `isolation: "worktree"` at
spawn time for independent feature scopes — worktree isolation is documented platform
behavior for subagents. Sequencing stays with the lead: it merges the worktree
branches at synthesis and spawns dependent work only after its prerequisites are
merged.

Ask the user if it's ambiguous:

```
I see [N] verified features ready. I can either:
1. Work on F00X in a focused single session
2. Launch the implement-features workflow on F00X and F00Y in parallel

Which do you prefer?
```

---

## Step 5a: Single-Session Workflow

### Setup

1. Select highest-priority incomplete feature
2. Update `features.json`: set status to `"in-progress"`, set `assigned_to` to `"single-session"`
3. Create a structured task list using TaskCreate (these survive compaction):

```
TaskCreate({ subject: "F001: Read existing code in [scope directories]", description: "Understand patterns before implementing", activeForm: "Reading existing code", metadata: { feature_id: "F001" } })
TaskCreate({ subject: "F001: Write failing test for [feature]", description: "[feature description] — TDD red phase", activeForm: "Writing failing test", metadata: { feature_id: "F001" } })
TaskCreate({ subject: "F001: Implement minimum code to pass", description: "TDD green phase", activeForm: "Implementing feature", metadata: { feature_id: "F001" } })
TaskCreate({ subject: "F001: Run full test suite", description: "Verify no regressions", metadata: { feature_id: "F001" } })
TaskCreate({ subject: "F001: Verify coverage >= 95% on touched code", description: "Coverage gate", metadata: { feature_id: "F001" } })
TaskCreate({ subject: "F001: Update features.json", description: "Set status to passing, populate test_file and coverage", metadata: { feature_id: "F001" } })
TaskCreate({ subject: "F001: Update context_summary.md with learnings", description: "Persist decisions and patterns", metadata: { feature_id: "F001" } })
```

Use `TaskUpdate` to mark each task `in_progress` when starting and `completed` when done. Task updates must happen at the moment of state change, not in batch. The rule: when you finish something, the NEXT action is `TaskUpdate` — before responding to the user, before starting the next task. If planned tasks no longer match reality (scope changed, new work appeared), update or delete stale tasks immediately. A stale task list is worse than no task list because it creates false confidence about state.

4. Run smoke test: `./.harness/init.sh smoke_test`

### Implement with TDD

1. Write failing test that defines "done" for this feature
   - TaskUpdate: mark test task `in_progress`
2. Confirm it fails (proves test is valid)
3. Implement minimum code to pass
   - TaskUpdate: mark implementation task `in_progress`
4. Confirm test passes
   - TaskUpdate: mark test task `completed`
5. Refactor if needed
6. Repeat until feature is complete
7. Run full suite; coverage >= 95% on touched code

No exceptions unless tooling is broken.

### Context Updates During Work

Treat `context_summary.md` updates as part of the task, not after the task. Specifically: after every bug fix that reveals a non-obvious root cause, write the gotcha to `context_summary.md` BEFORE moving to the next request. The cost is 30 seconds; the value is permanent. A future session will benefit from knowing the root cause without re-discovering it.

For the `context_summary.md` structure and section-by-section update rules, read `${CLAUDE_PLUGIN_ROOT}/rules/context-summary.md`.

### When Feature Passes

1. Update `.harness/features.json`: set status to `"passing"`, add `test_file` and `coverage`, clear `assigned_to`. Also populate `approaches_tried` with a brief note on what worked (even for single-session work — this feeds the retrospective).
2. Append architectural decisions and discovered patterns to `.harness/context_summary.md`
3. If you discovered a need for a new feature while implementing this one, add it to `features.json` with `discovered_via` pointing to this feature's ID.

### Compaction Strategy

If approaching context limit, compact at a clean breakpoint:
- After tests pass for a subtask
- After a clear phase completes

Before compacting, ensure:
- Task list has your current state (should already be current if you're updating after every step)
- `context_summary.md` has any important context that must survive

Use `/compact` with a focus instruction, e.g.:
```
/compact Focus on: current feature F003 state, TDD progress, decisions made about auth architecture
```

After compaction, the plugin's SessionStart hook (matcher `compact`) automatically
injects a recovery block plus fresh orientation: re-read `.harness/context_summary.md`
Active Context and the task list. Follow it — it's your recovery path.

### Session End

1. Run full test suite one final time
2. **Pre-commit features.json audit**: Diff `features.json` against the actual work done this session. If any code was changed that relates to a tracked feature, that feature's metadata must be updated (status, test_file, coverage). If work was done that doesn't map to any existing feature, create a new feature entry with `discovered_via` pointing to the trigger. This check is a gate before `git commit`, not an afterthought.
3. **Retrospective (mandatory)**: Run the retrospective regardless of session type. For single-session work, it can be shorter (3-5 bullets), but it must exist. Minimum viable retrospective: (1) what was the session's actual scope vs planned scope? (2) what was discovered that wasn't anticipated? (3) what pattern or gotcha should transfer to future sessions? Write to `context_summary.md` under `## Meta-Session [DATE]` before the final commit. Skip only if this is the project's very first session.
4. **MLD telemetry (lead-only, mandatory)**: Write `.harness/mld/YYYY-MM-DD-<session-id>.md` (the session id is the one the SessionStart orientation printed as `Session: <id>` at the top of this session; if it never printed — a non-harness startup path, or a pre-upgrade plugin copy — use a short label instead) with three sections:
   ```markdown
   ## Mistakes
   - [what went wrong this session, if anything — an empty list is a valid, honest entry]

   ## Learnings
   - [a pattern, gotcha, or fact worth carrying forward]

   ## Desires
   - [something you wanted but didn't have — a tool, a piece of context, a missing check]
   ```
   This file is distinct from the Retrospective above: the Retrospective is cumulative analysis appended to `context_summary.md` for future sessions to read; MLD is a raw, undigested per-session log that nothing in this harness reads back into model context — session-start.sh has a hard, tested guarantee never to read `.harness/mld/`. It exists for periodic human/lead review, not in-session consumption. Only the lead writes it; spawned agents never do. See `${CLAUDE_PLUGIN_ROOT}/rules/mld-review.md` for the review cadence and disposition. `.harness/mld/` is committed by default, the same as the rest of `.harness/`.
5. Write handoff to `claude-progress.txt`:
   ```
   ## Session [N] - [DATE]
   - Feature: F00X - [description]
   - Status: [complete | in-progress | blocked]
   - Tests: [N passing, M failing]
   - Coverage: [X%] on touched code
   - Decisions: [brief list, details in context_summary.md]
   - Next: [what the next session should do]
   - Blockers: [any blockers]
   ```
6. Git commit (see Commit Hygiene rules — separate harness metadata from code commits)

Before declaring the session complete, work through the full checklist in `${CLAUDE_PLUGIN_ROOT}/rules/task-completion.md` (base checklist plus the harness-specific additions).

---

## Step 5b: Workflow Orchestration (primary parallel mode)

The lead (model policy: `${CLAUDE_PLUGIN_ROOT}/rules/parallel-work.md`, "Model
policy") never edits feature code directly in this mode — it prepares
inputs, launches `/vv-harness:implement-features`, and integrates the returned results so
the `TaskCompleted` and commit gates fire in the lead session. Run these steps **in order**:

1. **Verify specs.** Confirm every candidate feature has a verified spec (`spec.verdict:
   "PASS"`, or a fresh `harness-issue-prep` pass). Unverified features are **excluded**
   from the batch, never silently included. Whichever way `risk` and
   `require_plan_approval` get decided (from a prior prep stamp, or by the lead fresh at
   this step per the Dynamic overrides in `${CLAUDE_PLUGIN_ROOT}/rules/parallel-work.md`),
   write them onto the feature object in `features.json` now (F064): this is what makes
   step 3.5's conformance-tester trigger below a durable lookup instead of something
   only this pass remembers.
2. **Mirror tasks — mandatory.** `TaskCreate` one task per feature, **each carrying
   `metadata.feature_id`** (dependencies via `addBlockedBy`). This is what arms the
   `TaskCompleted` gate's focused-test and coverage stages; the norm — including why
   the task-subject `FXXX:` fallback is never to be relied on — is
   `${CLAUDE_PLUGIN_ROOT}/rules/parallel-work.md`, "Task mirroring and integration
   order".
3. **Launch.** Call the workflow with `args` carrying the feature IDs **and each
   feature's verified spec text** (the script has no way to read `features.json` from
   inside a workflow): `{ features: [...], featureSpecs: { F0NN: { spec, scope, risk,
   mergeBase } }, maxReviewRounds: 3 }`. Set `reviewModel: 'opus'` explicitly only if you
   need to force it (Opus review routing is canonical in
   `${CLAUDE_PLUGIN_ROOT}/rules/parallel-work.md`, "Escalation"). Size the
   batch under the platform concurrency cap (min(16, cores−2); guideline < 15) — chain
   multiple runs rather than one oversized batch. Also read the optional
   `workflow.size_guideline` key from `.harness/harness.json` when sizing the batch
   ("small" caps a run at 5 agents, "medium" at 15, "large" sets no cap; absent means
   no advice).
3.5. **Author-blind conformance check (optional, F017/OVI-65)**: for a feature the
   workflow returned as approved, whose `spec.verdict` is `"PASS"` AND EITHER of the
   following holds, spawn the conformance tester BEFORE step 4 flips the feature to
   passing:
   - `features.json`'s `risk` field on this feature is `"elevated"` (F064: a durable
     field, set by `harness-issue-prep` Step 7 at stamp time or by the lead directly
     at step 1 above — read it straight from `features.json`, not from a Linear
     comment or in-session memory).
   - `features.json` records `require_plan_approval: true` on this feature (F064: same
     source and durability as `risk` — set at step 1 above, or carried over from an
     earlier `harness-issue-prep` run).

   **Legacy fallback**: a feature prepped before F064 shipped may have neither field
   set even though it genuinely was elevated-risk or plan-approved. If `risk` and
   `require_plan_approval` are both absent/null AND you have independent reason to
   think the feature was elevated (a still-visible Linear stamp comment, or your own
   step 1 notes in current context), treat the trigger as unknown rather than false —
   mention the ambiguity to the user (e.g. "this feature may have needed plan
   approval, but `features.json` doesn't record it; run a conformance check anyway?")
   and let them decide, same as before F064. Do not backfill the missing fields from a
   guess; only `harness-issue-prep` Step 7 or step 1 above should write them.

   Adapted from agent-os's `conformance-test-writer` pattern (nodera-studio, MIT): a
   single context that writes both the code and its tests can satisfy a bug with a
   test that matches the bug — this step derives tests from the verified spec alone,
   never from the implementation.

   ```
   Agent({
     description: "Author-blind conformance test for F0NN",
     subagent_type: "vv-harness:conformance-tester",
     model: "sonnet",
     prompt: "[the feature's verified description, including its numbered acceptance
               criteria, exactly as it appears in features.json; the feature's scope;
               the project's test conventions (framework, directory layout, naming).
               Do NOT read: [implementer's test_file path], the implementation diff,
               or the implementer's completion message.]"
   })
   ```

   Route the result:
   - All PASS (or PASS plus honest NOT-TESTABLE criteria): proceed to mark the feature
     passing; record `proof.evidence_type: "conformance"` on the feature, with the
     conformance test file(s) as `artifact` and any NOT-TESTABLE criteria named in
     `not_established`.
   - Any FAIL: do NOT mark the feature passing. The FAIL is a finding routed back for
     a fix (to the implementer, or fixed directly by the lead), same as any other
     pre-passing defect — the conformance tester never fixes source itself.

   **Single-session mode**: this step is available but manual — run it only if the
   user asks for it; it is not a default part of the single-session TDD loop.
4. **Integrate per feature, in this order** (only for features the workflow returned as
   approved): **run the feature's focused test + smoke locally → merge its
   `worktree_branch` → flip `features.json` status to passing → mark the mirrored task
   complete (gate fires) → commit (commit gate fires; `git add` and `git commit` as
   SEPARATE calls)**. Never flip status or mark a task complete before its tests pass on
   the merged code. After merging, **remove the changed worktree before any repo-wide
   suite run**. This order and the worktree rationale are canonical in
   `${CLAUDE_PLUGIN_ROOT}/rules/parallel-work.md` ("Task mirroring and integration
   order", "Worktree hygiene").
5. **Surface, never auto-merge, the rest.** A feature returned `status: blocked`, verdict
   `REJECT`/`REVISE`, or in the workflow's `unfinished` list is reported to the user with
   its structured findings. For `unfinished` features (an agent died — e.g. a session
   rate limit), either resume the run after the reset with
   `Workflow({scriptPath, resumeFromRunId, args})` — completed agents replay from
   cache; the ORIGINAL `args` must be resent or the resume fails fast (OVI-147
   field validation) — or reconcile from the committed worktree branches; do not
   silently drop them. Before merging any branch produced by a run you did not watch
   to completion, scope-diff it (`git diff --name-only <mergeBase>...<branch>`) and
   account for every file outside that feature's declared `scope` — see
   `rules/parallel-work.md`, "Worktree hygiene".
5.5. **Re-review a branch, when a fresh verdict is what you need (optional).** For a
   feature surfaced at step 5, or a branch recovered from an interrupted run, launch
   `/vv-harness:review-branch` over that diff scope instead of re-running the whole
   batch: it fans reviewers over named dimensions, deduplicates their findings, then
   sends an adversarial skeptic at each survivor. It is read-only — it never edits,
   merges, or commits — so it produces a verdict, not a fix. Its `args` shape lives in
   `launch-prompts.md` (this skill's directory); do not restate it here.
6. **Retrospective.** Run the retrospective, promotion, and ablation passes plus the
   MLD telemetry — the Retrospective section below.

The launch checklist and `args` shape for this flow live in `launch-prompts.md` (this
skill's directory); the structured-output contracts it references are canonical in
`${CLAUDE_PLUGIN_ROOT}/rules/parallel-work.md`, "Structured-output contracts". The
pre-launch checklist there is: specs verified, tasks mirrored **with `feature_id`**,
branch state clean, `git fetch` + rebase done.

---

## Retrospective (run when the batch completes)

When all features reach `status: "passing"`, run a metacognitive retrospective before the session's final commit. This is the mechanism by which the harness improves its own coordination — not just the domain code.

Review the operational metrics across all features completed this session:

1. **Scope accuracy**: Which features had `scope_expansions > 0`? What does that reveal about how to scope similar work next time? (e.g., "auth/ and user/ are coupled — scope them together")
2. **Model calibration**: Which features had `correction_cycles >= 3`? Were they on Sonnet? If yes, note that similar-scope features should use Opus.
3. **Discovery lineage**: Which features have `discovered_via` set? Does the discovery pattern suggest the initial feature decomposition missed something systematic?
4. **Approach patterns**: What patterns in `approaches_tried` worked repeatedly? What failed repeatedly?
5. **Plan approval value**: Did `require_plan_approval` prevent rework, or was it overhead? Note which feature types benefited.

Write findings to `.harness/context_summary.md` under a new `## Meta-Session [DATE]` section:

```markdown
## Meta-Session 2026-03-23
- Scope accuracy: [findings — which scopes needed expansion and what that means]
- Model calibration: [which features burned correction cycles on Sonnet; upgrade recommendation]
- Discovery lineage: [which features were discovered mid-work; what to probe for at init time]
- Approach patterns: [what worked, what failed]
- Plan approval: [was it worth the overhead for which feature types]
```

**When to skip**: If this is the first session (no historical data in features.json operational metrics), skip the retrospective — there's nothing to analyze yet. Write a note: `## Meta-Session [DATE] — first session, no retrospective data yet`.

Write findings to `## Meta-Patterns` for insights that generalize beyond this session:

```markdown
## Meta-Patterns
- [Insight that applies to future sessions, not just this domain] (backlog)
```

Do NOT write domain-specific decisions here — those go in the Domain sections. Meta-Patterns are coordination insights: when to use Opus, how to scope, when to require plan approval. Each entry carries a disposition marker (`promoted-to: X` | `backlog` | `watching`) at the end of the line; see `${CLAUDE_PLUGIN_ROOT}/rules/context-summary.md` for what each marker means and a worked example. The promotion pass below is what sets and updates these markers.

**Promotion pass (mandatory).** This closes the loop the retrospective used to leave open: a lesson written to `## Meta-Patterns` above stayed prose forever, and no control was ever retired. Classify each Meta-Pattern entry from this session (and each corroborated MLD entry, when P3.1's corroboration marker is present in `.harness/mld/` -- skip this input if that mechanism isn't shipped yet) to its smallest durable owner, using the vv-native promotion ladder, smallest first:

| Rung | What it means | Example |
|---|---|---|
| spawn-prompt tweak | Fix the wording of a future agent spawn or launch prompt | An implementer skipped git identity because its launch prompt never said to; add the line |
| rule file edit | Add or tighten a rule in `rules/*.md` | A commit-hygiene lesson gets folded into `parallel-work.md` |
| hook change | A mechanical check catches this instead of relying on instructions | `enforce-scope.sh` gains a new denied pattern after a near-miss |
| schema field | A schema (e.g. `feature.schema.json`) gains a field to track this going forward | `qa_binding` added to catch a claim/proof-type mismatch |
| agent definition | An implementer or reviewer agent's own `.md` definition changes | `reviewer.md` gains a new review dimension |
| plugin skill | A whole skill's `SKILL.md` changes structurally | A skill's phase ordering is corrected after a self-contradiction is found |
| not-yet | Not enough evidence yet to commit to a fix | A one-off oddity, not yet a repeated pattern |

For each classified item, append (or update) a row in `.harness/HARNESS_BACKLOG.md` (schema below) rather than leaving the classification stranded only in Meta-Patterns prose. Set the corresponding Meta-Patterns entry's disposition marker to match: `promoted-to: <owner>` once actually landed, `backlog` while the row exists but isn't yet applied, `watching` while below the promotion threshold.

**Ablation pass (mandatory).** List every control that fired this session -- a hook rejection, a plan-approval gate, a warning -- and judge it:
- **retain**: it caught something real, or its absence would have let something real through.
- **revise**: it fired, but too noisely or too narrowly to trust as-is.
- **remove**: it fired zero times this session, or every time it fired it was pure friction (no real defect behind it).

Append a `retain` / `revise` / `remove` verdict with its reason as a row in `.harness/HARNESS_BACKLOG.md` for anything not simply `retain` -- put the verdict and its reason in `proposed owner` (e.g. `revise (too noisy; narrow the matcher)`), the same column a `gap` row's type goes in, since an ablation row isn't proposing a promotion destination. Removing a control that no longer earns its carrying cost is a healthy, expected outcome of this pass, not a failure to report defensively.

**`.harness/HARNESS_BACKLOG.md`** (lead-owned; create it the first time either pass produces a candidate). One table:

```markdown
# Harness Backlog

Candidates the retrospective's promotion and ablation passes have surfaced. Not
auto-applied: a human or a dedicated session executes a row, then marks it
promoted. Cross-project pattern aggregation is a future extension, not done
here -- this file is per-project.

| date | observation | proposed owner | evidence pointer | score | status | last_seen |
|---|---|---|---|---|---|---|
| 2026-03-23 | Reviewers occasionally cite an off-by-one line number | not-yet | Meta-Session 2026-03-23 | 1 | candidate | 2026-03-23 |
```

- `score`: count of DISTINCT sessions/episodes that independently produced this same observation. A brand-new row starts at 1.
- `status`: `candidate` | `promoted` | `retired`.
- `last_seen`: date of the most recent session that re-observed this pattern.

On a repeat occurrence of the SAME observation in a later session, bump that row's `score` and `last_seen` instead of appending a duplicate row.

**Promotion threshold**: a candidate needs `score >= 3` (three distinct sessions) before it is promoted into an actual rule/hook/schema/agent/skill change. A single-session promotion (`score` still 1) is allowed only with an explicit override reason recorded in the row (for example: "clear regression risk, promoting at score 1 rather than waiting").

**Decay and retirement** (part of the ablation pass): any `candidate` row whose `last_seen` is more than 60 days old gets `status` flipped to `retired`, keeping a one-line reason -- never silently deleted, never moved to a separate archive.

**Gap entries**: when this session's work fit no existing vv role, scope, or skill and had to be improvised, log a `gap`-type row in the same table (`proposed owner` = `gap`, describing what didn't fit). Three or more similar `gap` rows are themselves a promotion candidate for a new agent or skill -- classify that pattern through the normal ladder above.

**Bounded always-on canon**: a promotion that would land in ALWAYS-loaded context (`templates/CLAUDE.md`'s own invariants, or a SessionStart rule pointer) goes into exactly one "Learned conventions" section, hard-capped at 15 lines total. Exceeding the cap requires evicting the lowest-`score` line first, not silently growing past it. Everything else -- anything that isn't needed in every single session -- goes to `context_summary.md`'s Domain sections instead; this cap exists so always-on context stays bounded even as the backlog grows.

**Linear filing alternative**: if `.harness/harness.json` has a `prep` block with a Linear workspace configured, offer to file promotion/ablation candidates as Linear issues instead of appending to `HARNESS_BACKLOG.md` (reuse the same MCP tool-discovery `harness-issue-prep` already does). Never do both for the same candidate.

**Single-session mode**: run the abbreviated ladder per the existing minimum-retrospective rule in Step 5a above -- classification only; the ablation pass is optional.

**First session on a project**: no retrospective history exists yet -- both passes emit "no data, skipping" and stop; never fabricate a classification or an ablation verdict to fill the section.

**MLD telemetry (lead-only, mandatory)**: the lead — never a spawned agent — writes `.harness/mld/YYYY-MM-DD-<session-id>.md` with `## Mistakes` / `## Learnings` / `## Desires` sections before the session's final commit. Same format and rationale as Step 5a's Session End procedure; see `${CLAUDE_PLUGIN_ROOT}/rules/mld-review.md`.

### Workflow session end

1. Write handoff to `claude-progress.txt`:
   ```
   ## Session [N] - [DATE] (workflow run: [N] features)
   - Features completed: [list]
   - Features in-progress: [list]
   - Dependencies resolved: [any chains that unblocked]
   - Integration issues: [any conflicts resolved, details in context_summary.md]
   - Tests: [N passing, M failing]
   - Cost note: [models used, if relevant]
   - Next: [what the next session should do]
   ```
2. Git commit

---

## Edge Cases

**All high-priority features are complete:**
Report to user. Ask if there are new features to add or if the project is done.

**Feature is blocked:**
Document the blocker in `claude-progress.txt` and `context_summary.md`. Move to the next available feature.

**Tests are failing from a previous session:**
Fix them before starting new work. This is priority zero.

**Context is getting heavy mid-session:**
Compact at the next clean breakpoint. Task list should already be current (you're updating after every step). Ensure `context_summary.md` has any important context, then `/compact`.

**Workflow agent dies mid-run:**
The feature lands on the workflow's `unfinished` list. Resume the run with
`Workflow({scriptPath, resumeFromRunId, args})` — completed agents replay from
cache; the ORIGINAL `args` must be resent or the resume fails fast (OVI-147
field validation) — or reconcile from the committed worktree branches — Step 5b,
step 5.

**Lead session interrupted:**
Completed workflow agents' worktree branches and their commits survive the lead. On restart, read `claude-progress.txt`, `features.json` (check `assigned_to` fields), and `context_summary.md` to reconstruct state; resume the workflow run if one was in flight. Features with `assigned_to` set but status still `in-progress` were likely interrupted mid-work.

**Integration failure between merged features:**
Follow the Integration failure recovery protocol in `${CLAUDE_PLUGIN_ROOT}/rules/parallel-work.md`. Prioritize getting back to green tests over preserving partial work.
