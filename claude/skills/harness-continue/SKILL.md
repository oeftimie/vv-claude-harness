---
name: harness-continue
description: Continue working on a harness-managed project (v3.4.0). Orients to current state, picks single-session or Agent Teams mode, and guides implementation with TDD, quality gate hooks, and compaction-aware context management. Use at the start of any session on a harness project.
---

# Harness Continue v3.4.0

## Step 1: Orient Yourself

```bash
cat .harness/claude-progress.txt | tail -50
cat .harness/context_summary.md
git log --oneline -10
cat .harness/features.json
cat .harness/harness.json
```

Summarize what you find:

```
Project state:
- Last session: [date, what was done]
- Features: [N passing / M total]
- Next up: [highest priority incomplete feature]
- Blockers: [any noted in progress or context_summary]
- Git identity: [from harness.json]
```

## Step 2: Verify Git Identity

```bash
ssh -T git@github.com 2>&1 || true
git config user.name
git config user.email
```

Compare against `.harness/harness.json` `git_identity`. If mismatch, fix before proceeding. Do not skip this.

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

**Choose Agent Teams if:**
- Multiple independent features are ready
- The next feature has clearly independent components
- `harness.json` has a team_structure defined
- User explicitly asks for parallel work

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

Use `TaskUpdate` to mark each task `in_progress` when starting and `completed` when done. Tasks are your crash-recovery journal: if compaction hits unexpectedly, stale tasks are worse than no tasks.

4. Run smoke test: `./.harness/init.sh`

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

After compaction, the **PostCompact hook** fires automatically and reminds you to re-read `.harness/context_summary.md` and the task list. Follow that reminder — it's your recovery path.

### Session End

1. Run full test suite one final time
2. If all features are now passing, run the retrospective (see Phase 5.5 above — same process applies to single-session work). Skip if this is the project's first completed session.
3. Write handoff to `claude-progress.txt`:
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
3. Git commit

---

## Step 5b: Agent Teams Workflow

The Agent Teams protocol is loaded automatically from your global rules. This workflow uses Claude Code's native team primitives: `TeamCreate`, `TaskCreate`, `TaskUpdate`, `TaskList`, `Task`, `SendMessage`, `TeamDelete`.

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
   - Which teammates, what scope (from features.json `scope` field), what model (Sonnet default; Opus if historical metrics suggest high difficulty)
   - Which tasks depend on which (from features.json `depends_on` field, mapped to `TaskUpdate` `addBlockedBy` calls after task creation)
   - Whether any teammate needs `require_plan_approval: true`
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

Wait for user approval before proceeding to Phase 2.

### Phase 2: Execute

1. Activate **plan mode** (Shift+Tab) to restrict yourself to coordination-only tools. Do not edit code directly.

2. Update `features.json`: set `assigned_to` for each feature being worked on.

3. Create the team:
   ```
   TeamCreate({ team_name: "PROJECT-sprint-N", description: "Parallel implementation of F001 and F002" })
   ```

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

5. Spawn teammates using templates from `team-spawn-prompts.md` in this skill's directory:
   ```
   Task({
     description: "Implement F001",
     subagent_type: "general-purpose",
     name: "api",
     team_name: "PROJECT-sprint-N",
     model: "sonnet",
     prompt: "[filled template with scope from features.json, deliverable, git identity, rules]"
   })
   ```
   Include git identity from `harness.json` in each spawn prompt.

### Phase 3: Monitor

1. Check `TaskList` for progress
2. Respond to incoming `SendMessage` messages:
   - **Task complete message**: review the work, verify tests passed (TaskCompleted hook handles mechanical check)
   - **Blocked message**: unblock or reassign
   - **Scope expansion request**: approve or deny, update scope in features.json
   - **Plan approval request**: review plan, approve or reject with a direct `SendMessage` (type `"message"`, not `"plan_approval_response"` which has a delivery bug)
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
- [Insight that applies to future sessions, not just this domain]
```

Do NOT write domain-specific decisions here — those go in the Domain sections. Meta-Patterns are coordination insights: when to use Opus, how to scope, when to require plan approval.

### Phase 5: Teardown

1. Send `shutdown_request` to all teammates via `SendMessage`
2. Wait for `shutdown_response` from each
3. Call `TeamDelete` to clean up team files
4. Write handoff to `claude-progress.txt`:
   ```
   ## Session [N] - [DATE] (Agent Teams: [N] teammates)
   - Team: [name]
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
In-process teammates are lost if the lead dies. Use tmux display mode for long-running team sessions. On restart, read `claude-progress.txt`, `features.json` (check `assigned_to` fields), and `context_summary.md` to reconstruct state. Features with `assigned_to` set but status still `in-progress` were likely interrupted mid-work.

**Integration failure between teammates:**
Follow the Integration Failure Recovery protocol in agent-teams-protocol.md. Prioritize getting back to green tests over preserving partial work.
