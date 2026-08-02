---
name: harness-continue
description: Continue working on a harness-managed project (vv-harness plugin). Orients to current state, picks single-session or Agent Teams mode, and guides implementation with TDD, quality gate hooks, and compaction-aware context management. Use at the start of any session on a harness project.
---

# Harness Continue

## Step 1: Orient Yourself

The vv-harness plugin's SessionStart hook auto-injects orientation at session start:
feature summary, next claimable feature, last handoff, Active Context, a git identity
warning on mismatch, and any SESSION_INCOMPLETE gaps from the previous session. Use
that injected "## Harness orientation" block instead of re-reading the harness files.
Resolve any SESSION_INCOMPLETE gaps it surfaces before starting new work.

This skill covers what the hook does not: mode choice, the smoke test, and team
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

- Architecture decisions, debugging failing tests, reviewing teammate work: `/effort high`
- Feature implementation (TDD loop), file refactoring: `/effort medium` (default)
- Formatting, linting fixes, boilerplate generation: `/effort low`

Adjust as you transition between phases during the session.

## Step 4: Decide Mode

**Choose Single-Session if:**
- One feature is next and it touches fewer than 5 files
- The feature is sequential (can't be parallelized)
- `harness.json` team_structure is null
- User explicitly asks for focused work

When choosing single-session, explicitly declare it: "Running in single-session mode — I'm both lead and implementer." This makes the decision conscious and documented, preventing ambiguity between "I forgot plan mode" and "plan mode doesn't apply here."

**Choose Agent Teams if:**
- Multiple independent features are ready
- The next feature has clearly independent components
- `harness.json` has a team_structure defined
- User explicitly asks for parallel work

**Graceful degradation — Agent Teams unavailable:**

Agent Teams is gated by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; the implicit team,
`SendMessage`, and the `TaskCompleted`/`TeammateIdle` coordination hooks are active only
when it is set. If the variable is unset or team coordination is unavailable, do NOT
abort parallel work. Fall back to direct subagents spawned via the Agent tool using the
same vv-harness agent types
(`vv-harness:feature-implementer`, `vv-harness:layer-implementer`,
`vv-harness:researcher`, `vv-harness:reviewer`), passing `isolation: "worktree"` at
spawn time for independent feature scopes — worktree isolation is documented platform
behavior for subagents. The lead merges the worktree branches at synthesis (Phase 4).

This is the supported, non-experimental path. Team-only machinery does not apply in
this mode: no SendMessage interface negotiation, no TeammateIdle reassignment —
sequencing falls back to the lead, which spawns dependent work only after its
prerequisites are merged.

Ask the user if it's ambiguous:

```
I see [N] features ready. I can either:
1. Work on F00X in a focused single session
2. Spawn a team to work on F00X and F00Y in parallel

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
   This file is distinct from the Retrospective above: the Retrospective is cumulative analysis appended to `context_summary.md` for future sessions to read; MLD is a raw, undigested per-session log that nothing in this harness reads back into model context — session-start.sh has a hard, tested guarantee never to read `.harness/mld/`. It exists for periodic human/lead review, not in-session consumption. Only the lead writes it; teammates never do. See `${CLAUDE_PLUGIN_ROOT}/rules/mld-review.md` for the review cadence and disposition. `.harness/mld/` is committed by default, the same as the rest of `.harness/`.
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

## Step 5b: Agent Teams Workflow

Before any team coordination, Read the Agent Teams protocol at
`${CLAUDE_PLUGIN_ROOT}/rules/agent-teams-protocol.md`. Agent Teams is experimental and
gated by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; the team forms implicitly when the
first teammate is spawned (no setup step) and is cleaned up automatically when the
session ends. This workflow uses Claude Code's native primitives: the Agent tool for
spawning, `TaskCreate`, `TaskUpdate`, `TaskList`, and `SendMessage`.

### Phase 1: Plan (cheap, read-only)

Before spending tokens on teammates, produce a decomposition plan:

1. Analyze the pending features in `.harness/features.json`
2. Use `scope` and `depends_on` from each feature to identify parallelism opportunities and dependency chains
3. **Review historical operational metrics** from past features to calibrate the team:
   - Features with `correction_cycles >= 3` in the same scope directories → upgrade implementer to Opus
   - Features with `scope_expansions >= 3` → assign a broader initial scope to reduce mid-work expansion overhead
   - Features with `discovered_via` depth > 1 → consider folding them into the parent feature's scope
   - Scopes that needed frequent expansion in past sessions → note them as "expansion-prone" when scoping this team
4. Design the team:
   - Which teammates, what scope (from features.json `scope` field), what model (Sonnet default; Opus if historical metrics suggest high difficulty). The plugin agent definitions already default the model per role (implementers and researcher: Sonnet; reviewer: Opus); a spawn-time `model` parameter overrides the definition's frontmatter, so an Opus upgrade needs only the Agent tool call's model param.
   - Which tasks depend on which (from features.json `depends_on` field, mapped to `TaskUpdate` `addBlockedBy` calls after task creation)
   - Whether any teammate needs `require_plan_approval: true`. If a feature has already been through `harness-issue-prep` and stamped, its `risk` (`standard`/`elevated`) may already be set on the feature object — check `features.json` first rather than re-deriving it. Whichever way `risk` and `require_plan_approval` get decided here (from a prior prep, or fresh at this step), write them onto the feature object in `features.json` now (F064): this is what makes step 3.5's conformance-tester trigger below a durable lookup instead of something only this Phase 1 pass remembers.
5. Present the plan to the user:

```
I propose this team structure:

Lead (Opus, plan mode): coordination, synthesis, final review
Teammate "api" (Sonnet): F001 - owns src/api/ and tests/api/
Teammate "ui" (Sonnet): F002 - owns src/components/ and tests/components/
  → blocked by "api" (F002 depends_on F001)
Teammate "reviewer" (Opus): reviews both after completion

Dependencies (from features.json):
  Task 1 (F001 API) → unblocks Task 2 (F002 UI)
  Tasks 1+2 → unblock Task 3 (review)

Plan approval required: No (scopes are straightforward)
Estimated: 3 teammates × Sonnet + 1 reviewer × Opus
Note: Opus lead runs for the full session; total cost depends on session length, not just implementer tokens.

Approve this plan?
```

Wait for user approval before proceeding to Phase 2. That approval is durable: it covers
execution through to the approved goal's completion. Do not stop for further go-aheads at
phase transitions; return to the user only when the goal is accomplished, the work is
blocked, or the approved plan itself must change.

### Phase 2: Execute

1. Activate **plan mode** (Shift+Tab) to restrict yourself to coordination-only tools. Do not edit code directly.

2. Update `features.json`: set `assigned_to` for each feature being worked on.

3. Confirm `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set. There is no team-creation
   step: the implicit team forms when the first teammate is spawned (Step 5) and is
   cleaned up automatically when the session ends.

4. Create tasks with feature metadata, then set dependency chains (derived from features.json `depends_on`):
   ```
   # Create all tasks first (they start as pending by default)
   # Always include metadata.feature_id — hooks and TaskList use it for correlation
   TaskCreate({ subject: "F001: Build API endpoint", description: "[detailed spec]", activeForm: "Building API endpoint", metadata: { feature_id: "F001", scope: "src/api/", model: "sonnet" } })
   # → task id "1"
   TaskCreate({ subject: "F002: Build UI consuming API", description: "[detailed spec]", activeForm: "Building UI layer", metadata: { feature_id: "F002", scope: "src/ui/", model: "sonnet" } })
   # → task id "2"
   TaskCreate({ subject: "Review F001 + F002", description: "[review criteria]", activeForm: "Reviewing implementation", metadata: { feature_id: "F001,F002", scope: "*", model: "opus" } })
   # → task id "3"

   # Then set dependencies via TaskUpdate
   TaskUpdate({ taskId: "2", addBlockedBy: ["1"] })
   TaskUpdate({ taskId: "3", addBlockedBy: ["1", "2"] })
   ```

5. Before each teammate spawn on the shared-branch path, write
   `.claude/teammate-scope.txt` from that feature's `scope` array in `features.json`,
   one pattern per line — this arms the `enforce-scope.sh` PreToolUse hook, which
   otherwise fails open (no file = no enforcement). Rewrite the file whenever
   `TeammateIdle` reassigns that teammate to a different feature; delete it during
   Phase 5 teardown. Worktree-isolated fallback subagents do NOT need this file — their
   isolation is physical, not hook-enforced.

6. Spawn teammates as the vv-harness plugin agent types. Each definition bakes in the
   role's reusable guardrails (TDD discipline, tool allowlist, scope rules, completion
   protocol), so the spawn prompt carries only per-feature specifics — use the templates
   from `team-spawn-prompts.md` in this skill's directory:
   ```
   Agent({
     description: "Implement F001",
     subagent_type: "vv-harness:feature-implementer",
     name: "api",
     model: "sonnet",
     prompt: "[per-feature specifics: feature ID, scope from features.json, deliverable, git identity, plan-approval flag, task ID]"
   })
   ```
   The `name` makes the teammate addressable via `SendMessage`; the team it joins is
   implicit, so there is no `team_name` to pass (the parameter is accepted but ignored).
   Agent types: `vv-harness:feature-implementer`, `vv-harness:layer-implementer`,
   `vv-harness:researcher`, `vv-harness:reviewer`. The spawn-time `model` parameter
   overrides the definition's frontmatter model, so the Phase 1 Opus-upgrade heuristic
   applies unchanged. Include git identity from `harness.json` in each spawn prompt.
   Do not re-paste guardrail prose into spawn prompts — it lives in the agent definitions.
   The spawn tool is exposed as `Agent` (older CLIs called it `Task`); adapt to what your
   CLI exposes.

7. At team start, confirm plan-approval messaging uses type `"message"` (the
   `plan_approval_response` delivery-bug workaround) — one SendMessage round-trip with a
   teammate is the check; if it fails on a newer CLI, fall back to the worktree-subagent
   mode (Step 4, graceful degradation).

### Phase 3: Monitor

1. Check `TaskList` for progress
2. Respond to incoming `SendMessage` messages:
   - **Task complete message**: review the work, verify tests passed (TaskCompleted hook handles mechanical check)
   - **Blocked message**: unblock or reassign
   - **Scope expansion request**: approve or deny, update scope in features.json
   - **Plan approval request**: review plan, approve or reject with a direct `SendMessage` (type `"message"`, not `"plan_approval_response"` which has a delivery bug)
   - **Completion report from a role-limited teammate** (e.g. a reviewer or a researcher,
     structurally unable to claim any remaining feature work): if it reports its
     assigned work is done and has nothing left it can claim, send it a
     `shutdown_request` promptly instead of leaving it idle until Phase 5 (F059). Do NOT
     do this for an implementer between features -- it remains a legitimate
     `TeammateIdle` reassignment target for as long as the team is running.
3. Resolve conflicts if teammates need overlapping files
4. After 3 check-ins with no progress from a teammate, take over that scope or spawn a replacement

The `TeammateIdle` hook prompts idle teammates to pick up remaining features, so you don't need to manually reassign after each task completes.

### Phase 4: Synthesize

When all teammates complete:
1. Exit plan mode if needed for hands-on review
2. Run the full test suite
3. If integration issues arise, follow the Integration Failure Recovery protocol in the Agent Teams rules:
   - Identify conflicting changes via `git diff`
   - Revert cleanly rather than attempting broken merges
   - Record conflict resolution in `context_summary.md`
3.5. **Author-blind conformance check (optional, F017/OVI-65)**: for a feature whose
   `spec.verdict` is `"PASS"` AND EITHER of the following holds, spawn the conformance
   tester BEFORE marking the feature passing:
   - `features.json`'s `risk` field on this feature is `"elevated"` (F064: a durable
     field, set by `harness-issue-prep` Step 7 at stamp time or by the lead directly
     at Phase 1 above — read it straight from `features.json`, not from a Linear
     comment or in-session memory).
   - `features.json` records `require_plan_approval: true` on this feature (F064: same
     source and durability as `risk` — set at Phase 1 above, or carried over from an
     earlier `harness-issue-prep` run).

   **Legacy fallback**: a feature prepped before F064 shipped may have neither field
   set even though it genuinely was elevated-risk or plan-approved. If `risk` and
   `require_plan_approval` are both absent/null AND you have independent reason to
   think the feature was elevated (a still-visible Linear stamp comment, or your own
   Phase 1 notes in current context), treat the trigger as unknown rather than false —
   mention the ambiguity to the user (e.g. "this feature may have needed plan
   approval, but `features.json` doesn't record it; run a conformance check anyway?")
   and let them decide, same as before F064. Do not backfill the missing fields from a
   guess; only Step 7 or a fresh Phase 1 pass should write them.

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
4. Update `.harness/features.json` for each completed feature (status, test_file, coverage, clear assigned_to)
5. Append decisions and patterns to `.harness/context_summary.md`

### Phase 5.5: Retrospective (run before teardown when all features complete)

When all features reach `status: "passing"`, run a metacognitive retrospective before teardown. This is the mechanism by which the harness improves its own coordination — not just the domain code.

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
| spawn-prompt tweak | Fix the wording of a future teammate spawn prompt | A teammate forgot to verify git identity because the spawn prompt never said to; add the line |
| rule file edit | Add or tighten a rule in `rules/*.md` | A commit-hygiene lesson gets folded into `agent-teams-protocol.md` |
| hook change | A mechanical check catches this instead of relying on instructions | `enforce-scope.sh` gains a new denied pattern after a near-miss |
| schema field | A schema (e.g. `feature.schema.json`) gains a field to track this going forward | `qa_binding` added to catch a claim/proof-type mismatch |
| agent definition | A teammate or reviewer agent's own `.md` definition changes | `reviewer.md` gains a new review dimension |
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

Candidates the Phase 5.5 promotion and ablation passes have surfaced. Not
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

**MLD telemetry (lead-only, mandatory)**: the lead — never a teammate — writes `.harness/mld/YYYY-MM-DD-<session-id>.md` with `## Mistakes` / `## Learnings` / `## Desires` sections before Phase 5 teardown. Same format and rationale as Step 5a's Session End procedure; see `${CLAUDE_PLUGIN_ROOT}/rules/mld-review.md`.

### Phase 5: Teardown

1. Send `shutdown_request` to all REMAINING teammates via `SendMessage` (F059) --
   any released early during Phase 3 for being role-limited are already down
2. Wait for `shutdown_response` from each remaining teammate
3. Delete `.claude/teammate-scope.txt` if it exists — it is per-teammate transient
   state, not a harness-init artifact, and must not survive the team it armed.
4. Write handoff to `claude-progress.txt`:
   ```
   ## Session [N] - [DATE] (Agent Teams: [N] teammates)
   - Teammates: [name (model): scope] for each
   - Tasks: [N completed, M blocked, P pending]
   - Features completed: [list]
   - Features in-progress: [list]
   - Dependencies resolved: [any chains that unblocked]
   - Integration issues: [any conflicts resolved, details in context_summary.md]
   - Tests: [N passing, M failing]
   - Cost note: [models used, if relevant]
   - Next: [what the next session should do]
   ```
5. Git commit

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

**Teammate crashes or stalls:**
The 5-minute heartbeat timeout will notify the lead. Spawn a replacement teammate for the stalled scope, or take over the scope directly (exit plan mode). Update `assigned_to` in features.json.

**Lead session interrupted:**
In-process teammates are lost if the lead dies. `teammateMode` defaults to `"in-process"`, so set it explicitly (`tmux` or `auto`) for long-running team sessions that might be interrupted. On restart, read `claude-progress.txt`, `features.json` (check `assigned_to` fields), and `context_summary.md` to reconstruct state. Features with `assigned_to` set but status still `in-progress` were likely interrupted mid-work.

**Integration failure between teammates:**
Follow the Integration Failure Recovery protocol in agent-teams-protocol.md. Prioritize getting back to green tests over preserving partial work.
