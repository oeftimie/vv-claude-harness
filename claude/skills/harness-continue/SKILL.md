---
name: harness-continue
description: Continue working on a harness-managed project (v3.2.1). Orients to current state, picks single-session or Agent Teams mode, and guides implementation with TDD, quality gate hooks, and compaction-aware context management. Use at the start of any session on a harness project.
---

# Harness Continue v3.2.1

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
3. Create a structured task list using TodoWrite (these survive compaction):

```
TodoWrite({
  todos: [
    { id: "1", content: "Read existing code in [scope directories]", status: "in_progress" },
    { id: "2", content: "Write failing test for [feature description]", status: "not_started" },
    { id: "3", content: "Implement minimum code to pass", status: "not_started" },
    { id: "4", content: "Run full test suite", status: "not_started" },
    { id: "5", content: "Verify coverage >= 95% on touched code", status: "not_started" },
    { id: "6", content: "Update features.json", status: "not_started" },
    { id: "7", content: "Update context_summary.md with learnings", status: "not_started" }
  ]
})
```

**Update todo status after every meaningful step.** Don't wait for a clean breakpoint. Todos are your crash-recovery journal: if compaction hits unexpectedly, stale todos are worse than no todos.

4. Run smoke test: `./.harness/init.sh`

### Implement with TDD

1. Write failing test that defines "done" for this feature
   - Update TodoWrite: test written
2. Confirm it fails (proves test is valid)
3. Implement minimum code to pass
   - Update TodoWrite: implementation started
4. Confirm test passes
   - Update TodoWrite: test passing
5. Refactor if needed
   - Update TodoWrite: refactor complete
6. Repeat until feature is complete
7. Run full suite; coverage >= 95% on touched code

No exceptions unless tooling is broken.

### When Feature Passes

1. Update `.harness/features.json`: set status to `"passing"`, add `test_file` and `coverage`, clear `assigned_to`
2. Append architectural decisions and discovered patterns to `.harness/context_summary.md`

### Compaction Strategy

If approaching context limit, compact at a clean breakpoint:
- After tests pass for a subtask
- After a clear phase completes

Before compacting, ensure:
- TodoWrite has your current task state (should already be current if you're updating after every step)
- `context_summary.md` has any important context that must survive

Use `/compact` with a focus instruction, e.g.:
```
/compact Focus on: current feature F003 state, TDD progress, decisions made about auth architecture
```

### Session End

1. Run full test suite one final time
2. Write handoff to `claude-progress.txt`:
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
3. Design the team:
   - Which teammates, what scope (from features.json `scope` field), what model (Sonnet for implementers, Opus for reviewers)
   - Which tasks depend on which (from features.json `depends_on` field, mapped to `TaskCreate` `blocked_by` chains)
   - Whether any teammate needs `require_plan_approval: true`
4. Present the plan to the user:

```
I propose this team structure:

Lead (Opus, delegate mode): coordination, synthesis, final review
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

1. Activate **delegate mode** (Shift+Tab) to restrict yourself to coordination-only tools. Do not edit code directly.

2. Update `features.json`: set `assigned_to` for each feature being worked on.

3. Create the team:
   ```
   TeamCreate({ team_name: "PROJECT-sprint-N", description: "Parallel implementation of F001 and F002" })
   ```

4. Create tasks with dependency chains (derived from features.json `depends_on`):
   ```
   TaskCreate({ subject: "F001: Build API endpoint", description: "[detailed spec]", status: "pending" })
   TaskCreate({ subject: "F002: Build UI consuming API", description: "[detailed spec]", status: "blocked", blocked_by: ["1"] })
   TaskCreate({ subject: "Review F001 + F002", description: "[review criteria]", status: "blocked", blocked_by: ["1", "2"] })
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

The `TeammateIdle` hook automatically assigns remaining features to idle teammates, so you don't need to manually reassign after each task completes.

### Phase 4: Synthesize

When all teammates complete:
1. Exit delegate mode if needed for hands-on review
2. Run the full test suite
3. If integration issues arise, follow the Integration Failure Recovery protocol in the Agent Teams rules:
   - Identify conflicting changes via `git diff`
   - Revert cleanly rather than attempting broken merges
   - Record conflict resolution in `context_summary.md`
4. Update `.harness/features.json` for each completed feature (status, test_file, coverage, clear assigned_to)
5. Append decisions and patterns to `.harness/context_summary.md`

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
Compact at the next clean breakpoint. TodoWrite should already be current (you're updating after every step). Ensure `context_summary.md` has any important context, then `/compact`.

**Teammate crashes or stalls:**
The 5-minute heartbeat timeout will notify the lead. Spawn a replacement teammate for the stalled scope, or take over the scope directly (exit delegate mode). Update `assigned_to` in features.json.

**Lead session interrupted:**
In-process teammates are lost if the lead dies. Use tmux display mode for long-running team sessions. On restart, read `claude-progress.txt`, `features.json` (check `assigned_to` fields), and `context_summary.md` to reconstruct state. Features with `assigned_to` set but status still `in-progress` were likely interrupted mid-work.

**Integration failure between teammates:**
Follow the Integration Failure Recovery protocol in agent-teams-protocol.md. Prioritize getting back to green tests over preserving partial work.
