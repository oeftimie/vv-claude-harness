---
globs:
  - .harness/**
---

# Agent Teams Protocol

Rules for coordinating work through Claude Code's native Agent Teams. These activate when a `.harness/` directory exists and apply when a lead agent spawns teammates for parallel work.

## When to Use Agent Teams

Use Agent Teams when:
- Two or more independent features are ready for implementation
- A single feature has independent components (e.g., backend API + frontend UI + test suite)
- Research and implementation can proceed in parallel
- Code review or security audit benefits from multiple perspectives

Do NOT use Agent Teams when:
- The task is a single feature touching fewer than 5 files
- Work is sequential (step B depends on step A's output with no other work available)
- The coordination overhead exceeds the parallelism benefit
- Two features each touch fewer than 3 files (sequential is cheaper; see Cost Considerations)

When in doubt, start with a single session. Escalate to Agent Teams if the task naturally decomposes.

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
  "notes": null
}
```

**Status values** (exhaustive enum):
- `pending`: ready for work, no one has claimed it
- `in-progress`: a teammate or single-session agent is actively working on it
- `blocked`: waiting on another feature or external dependency
- `passing`: complete, tests passing, coverage met
- `failed`: attempted and failed; needs re-assessment

**`scope`**: directories and files this feature owns. Used in spawn prompts to define teammate boundaries.

**`depends_on`**: array of feature IDs (e.g., `["F001"]`). Maps directly to `TaskCreate` `blocked_by` chains.

**`assigned_to`**: teammate name when Agent Teams is active, `null` otherwise. Helps the lead reconstruct state if the session dies and restarts.

Feature is not done until: `status` is `"passing"`, `test_file` points to a test, and `coverage` >= 95% on touched code.

## Model Selection

Choose models based on the cognitive demand of each role:

| Role | Model | Reasoning |
|------|-------|-----------|
| Lead (coordinator) | Opus | Decomposition, synthesis, and quality judgment require deep reasoning |
| Feature implementer | Sonnet | Scoped TDD within a well-defined directory; doesn't need Opus |
| Layer implementer | Sonnet | Same as feature implementer |
| Researcher | Sonnet | Web search and doc reading are retrieval-heavy, not reasoning-heavy |
| Reviewer | Opus | Deep code review catches subtle bugs; worth the cost |

**Override**: if an implementer's scope is architecturally complex (10+ files, cross-cutting concerns, security-sensitive), upgrade to Opus.

The lead specifies model in the `Task()` call via `model: "sonnet"` or `model: "opus"`. Default to Sonnet for implementers; use Opus only when justified.

## Lead Agent Responsibilities

The lead agent is the coordinator. It operates in **delegate mode** (Shift+Tab) by default, restricting itself to coordination-only tools: spawning, messaging, task management, and shutdown. No code editing.

The lead:

1. Reads project state (`.harness/features.json`, `claude-progress.txt`, `context_summary.md`, git log)
2. Produces a decomposition plan (Phase 1 of the workflow in harness-continue)
3. Presents the plan to the user for approval before spawning any teammates
4. Creates the team via `TeamCreate`
5. Creates tasks via `TaskCreate`, using `depends_on` from features.json to set `blocked_by` chains
6. Spawns teammates via `Task` with team_name, model, and role-specific prompts
7. Monitors progress via `TaskList` and incoming `SendMessage` messages
8. Resolves conflicts if two teammates need overlapping files
9. Reviews completed work (exit delegate mode if needed for code review)
10. Synthesizes results after all teammates complete
11. Updates `.harness/features.json` (status, assigned_to, test_file, coverage)
12. Updates `.harness/context_summary.md` with decisions and patterns from the session
13. Writes session handoff to `claude-progress.txt`
14. Sends `shutdown_request` to all teammates, waits for `shutdown_response`
15. Calls `TeamDelete` to clean up
16. Commits

If the lead catches itself starting to implement code instead of delegating, it should stop and spawn a teammate for that work.

## Teammate Responsibilities

Each teammate is a focused implementer. It:

1. Reads its spawn prompt for scope, deliverable, and constraints
2. If `require_plan_approval` is true: sends a `plan_approval_request` via `SendMessage` and waits for a direct message approval from the lead before writing any code
3. Runs `.harness/init.sh` to verify the project builds
4. Claims its task via `TaskUpdate(status: "in_progress")`
5. Works ONLY within its assigned scope (files, directories)
6. Follows TDD: write failing test, implement, verify, refactor
7. Sends messages via `SendMessage` to the lead or other teammates as needed
8. Marks task complete via `TaskUpdate(status: "completed")`
9. Writes its deliverable to a file (not just conversation output)
10. Does not modify files outside its assigned scope without messaging the lead first

When the `TaskCompleted` hook runs, it will verify tests pass. If the hook rejects (exit code 2), the teammate receives feedback and must fix the issues before re-completing.

When the `TeammateIdle` hook runs after task completion, the teammate may receive a new task assignment automatically.

## Native Messaging Protocol

All team communication uses `SendMessage`. These are the message patterns for harness projects:

**Teammate to Lead:**

| Situation | SendMessage call |
|-----------|-----------------|
| Task complete | `SendMessage({ type: "message", recipient: "team-lead", content: "Task #N complete. [summary]. Tests passing. Coverage: [X%].", summary: "Task #N done" })` then `TaskUpdate({ taskId: "N", status: "completed" })` |
| Blocked | `SendMessage({ type: "message", recipient: "team-lead", content: "Blocked on task #N: [what I need, who has it]", summary: "Blocked: [reason]" })` |
| Scope expansion needed | `SendMessage({ type: "message", recipient: "team-lead", content: "Need access to [files] because [reason]. Currently outside my scope.", summary: "Scope expand: [files]" })` |
| Plan for approval | `SendMessage({ type: "plan_approval_request", recipient: "team-lead", content: "# Implementation Plan\n\n1. [step]\n2. [step]\n...", summary: "Plan for task #N" })` |

**Lead to Teammate:**

| Situation | SendMessage call |
|-----------|-----------------|
| Scope expansion approved | `SendMessage({ type: "message", recipient: "teammate-name", content: "Approved. You now own [files] in addition to your original scope." })` |
| Plan approved | `SendMessage({ type: "message", recipient: "teammate-name", content: "Plan approved. Proceed with implementation." })` |
| Plan rejected | `SendMessage({ type: "message", recipient: "teammate-name", content: "Plan rejected. Revise: [feedback]. Resubmit before implementing." })` |
| Shutdown | `SendMessage({ type: "shutdown_request", recipient: "teammate-name", content: "All tasks complete, shutting down team." })` |

> **Known bug:** `plan_approval_response` type in `SendMessage` reports success but the message is never delivered to the recipient. Use `type: "message"` for all plan approvals and rejections. This workaround is confirmed working as of Claude Code v2.1.33+.

**Teammate to Teammate:**

| Situation | SendMessage call |
|-----------|-----------------|
| Interface proposal | `SendMessage({ type: "message", recipient: "other-teammate", content: "I'm defining the API types at src/types/api.ts. Proposed interface: [details]. Does this work for your layer?" })` |
| Discovery affecting others | `SendMessage({ type: "broadcast", content: "Found that [module] has a breaking change. All teammates touching [X] should be aware." })` |

## Task Dependencies

Use `TaskCreate` with dependency chains so sequenced work auto-unblocks. Map directly from the `depends_on` field in features.json:

```
# Independent tasks: start as pending, claimable immediately
TaskCreate({ subject: "F001: Build API endpoint", description: "...", status: "pending" })
# → task id "1"

# Dependent tasks: start as blocked, auto-unblock when dependency completes
TaskCreate({ subject: "F002: Build UI consuming API", description: "...", status: "blocked", blocked_by: ["1"] })
# → auto-transitions to "pending" when task 1 is completed

# Multiple dependencies
TaskCreate({ subject: "F003: Integration tests", description: "...", status: "blocked", blocked_by: ["1", "2"] })
# → unblocks only when BOTH task 1 and task 2 complete
```

Teammates poll `TaskList` and only see claimable (pending) tasks. They don't need to understand the dependency graph; the system handles it.

When the lead plans the team (Phase 1 of harness-continue), it reads `depends_on` from features.json and translates them to `blocked_by` in `TaskCreate` calls.

## Plan Approval

For complex or risky work, require teammates to submit a plan before implementing.

**When to require plan approval:**
- Feature touches 10+ files or spans multiple modules
- Cross-cutting refactors (changing a shared interface)
- Security-sensitive code (authentication, authorization, crypto)
- First feature in a new codebase (establishing patterns)

**When to skip:**
- Straightforward feature in a well-scoped directory, under 5 files
- Adding tests to existing code
- Research tasks (no implementation)
- Review tasks (read-only)

**How it works:**

1. Lead sets `require_plan_approval: true` in the spawn prompt
2. Teammate reads the codebase and produces an implementation plan
3. Teammate sends `plan_approval_request` via `SendMessage`
4. Lead reviews and responds with a direct `SendMessage` (type `"message"`, not `"plan_approval_response"` which has a delivery bug)
5. On rejection: teammate revises and resubmits
6. On approval: teammate proceeds with implementation

The lead can include approval criteria in the spawn prompt: "Only approve plans that include test coverage for edge cases" or "Reject plans that modify the database schema without migration."

## Quality Gates

The harness installs two hooks that enforce quality mechanically:

**TaskCompleted hook** (`verify-task-quality.sh`):
- Runs the project's test suite via `.harness/init.sh`
- If tests fail: rejects completion (exit code 2), sends failure details to teammate
- If tests pass: accepts completion (exit code 0)
- The teammate receives feedback and must fix issues before re-completing

**TeammateIdle hook** (`check-remaining-tasks.sh`):
- Checks `.harness/features.json` for pending features
- If work remains: sends the next feature assignment (exit code 2), keeps teammate working
- If no work remains: allows idle (exit code 0)

These hooks mean:
- Teammates can't mark tasks done with failing tests (mechanical TDD enforcement)
- Idle teammates automatically pick up the next available feature (no wasted capacity)
- The lead doesn't need to micromanage task assignment after initial setup

### Hook Verification

After installing hooks (during `/harness-init`), verify they fire correctly:

1. Run the TaskCompleted hook directly: `echo '{}' | bash .claude/hooks/verify-task-quality.sh`
2. Run the TeammateIdle hook directly: `echo '{}' | bash .claude/hooks/check-remaining-tasks.sh`
3. Confirm exit codes match expectations (0 = accept, 2 = reject with feedback)

If either script fails to execute, fix the issue before proceeding. Silent hook failures mean quality gates don't enforce anything.

## Scope Assignment Guidelines

Good scopes are:
- **Directory-based**: "You own `src/auth/` and `tests/auth/`"
- **Feature-based**: "You own everything related to the payment flow"
- **Layer-based**: "You own the API handlers; teammate B owns the database layer"

Bad scopes are:
- "Work on the backend" (too vague)
- Overlapping with another teammate's scope (conflict risk)
- Requiring constant coordination with another teammate (defeats the purpose)

If two features share a module, either: assign both to one teammate, or have one teammate own the shared code and the other depend on it (with explicit `SendMessage` for interface changes).

Scopes are stored in `features.json` under the `scope` field for each feature. The lead includes them in spawn prompts and uses them to detect overlaps before spawning.

## Conflict Resolution

If two teammates need the same file:
1. The lead assigns ownership to one teammate
2. The other teammate sends a `SendMessage` to the owner with what it needs
3. The owner makes the change and messages back when done
4. If this happens repeatedly, the lead should merge those scopes into one teammate

## Integration Failure Recovery

When the lead's synthesis step (Phase 4) reveals integration issues between teammates' work:

1. Run `git diff` to identify the conflicting changes
2. Run the full test suite to pinpoint which tests fail and which teammate's changes are involved
3. If one teammate's work is clearly wrong: revert those files with `git checkout -- <files>`, update the feature status to `failed` in features.json, and either re-scope for a replacement teammate or take over directly (exit delegate mode)
4. If both sides are partially right: the lead exits delegate mode and merges manually, keeping the passing tests from both sides
5. If the conflict is architectural (shared interface mismatch): revert both, document the conflict in `context_summary.md`, and re-plan with a single teammate owning the shared interface
6. Update features.json with accurate statuses after resolution
7. Record the conflict and resolution in `context_summary.md` so future sessions know about it

The goal is always: get back to green tests as fast as possible. A clean revert is better than a broken merge.

## Git Strategy for Teams

Each teammate works on the same branch unless the lead explicitly creates per-teammate branches. The preferred approach:

1. Lead creates a feature branch from main
2. All teammates work on that branch
3. Teammates commit within their scope
4. Lead does a final review commit if needed
5. Lead opens the PR

If teammates are working on truly independent features, the lead can create separate branches and separate PRs.

## Cost Considerations

Model mixing reduces per-implementer token cost by roughly 5x (Sonnet vs Opus). But Agent Teams has coordination overhead that offsets some of that savings:

- **Lead overhead**: the lead runs on Opus for the entire session (planning, monitoring, synthesis). This is fixed cost regardless of teammate count.
- **SendMessage round-trips**: scope expansion, plan approval, interface negotiation: each costs tokens on both ends.
- **TeammateIdle re-assignment**: teammates that finish early and pick up new work run longer, consuming more Sonnet tokens.
- **Phase 1 planning**: reading all harness files, analyzing features, designing team structure, presenting the plan: this happens before any implementation tokens are spent.

**Rules of thumb:**
- Agent Teams becomes cost-effective when total implementation work exceeds ~30 minutes of single-session effort
- For two features that each touch fewer than 3 files, sequential single-session is cheaper
- The more independent the features, the better the parallelism payoff (less SendMessage overhead)
- Reviewer teammates on Opus are worth the cost for features touching 10+ files; skip them for smaller scopes

Don't optimize for cost at the expense of quality. The point of model mixing is to put reasoning power where it matters most (lead decisions, code review) and use efficient models for well-scoped, well-defined implementation work.

## Known Limitations

- **plan_approval_response delivery bug**: `SendMessage` with `type: "plan_approval_response"` reports success but the message never reaches the recipient. Use `type: "message"` for all plan approvals. The `plan_approval_request` type (teammate to lead) works fine; only the response direction is broken.
- **No session resumption**: if the lead session dies, in-process teammates are lost. Use tmux mode for sessions that might be interrupted. On restart, `features.json` `assigned_to` fields help reconstruct what was in progress.
- **One team per session**: a lead can only manage one team at a time.
- **No nested teams**: teammates can't create their own sub-teams.
- **Permission inheritance**: teammates inherit the lead's permission mode by default.
- **Heartbeat timeout**: if a teammate crashes, it triggers a 5-minute heartbeat timeout before the lead is notified.
- **Split-pane limitations**: tmux split-screen doesn't work with VS Code integrated terminal, Windows Terminal, or Ghostty.

## Integration with Harness

In a harness-managed project, the lead agent:

1. Reads `.harness/features.json` to select features (using `scope` and `depends_on` to plan team structure)
2. Maps features to teammate scopes and task dependencies
3. Sets `assigned_to` in features.json when spawning teammates
4. Creates tasks via `TaskCreate` (with `blocked_by` derived from `depends_on`)
5. Updates `features.json` as teammates complete work (sets status, test_file, coverage, clears assigned_to)
6. Appends to `.harness/context_summary.md` any architectural decisions made during the team session
7. Writes the session handoff to `claude-progress.txt` with a summary of all teammate work

Teammates do NOT write to `features.json`, `context_summary.md`, or `claude-progress.txt`. That's the lead's job. Teammates write code, tests, and communicate via `SendMessage`.
