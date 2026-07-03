<!-- Shipped with the vv-harness plugin. There is no auto-loading: the SessionStart
orientation injects this file's absolute path, and /harness-continue instructs the lead
to read it before any team coordination begins. -->

# Agent Teams Protocol

Rules for coordinating work through Claude Code's native Agent Teams. These activate when a `.harness/` directory exists and apply when a lead agent spawns teammates for parallel work.

## Enabling Agent Teams

Agent Teams is **experimental and disabled by default**. Enable it by setting
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the environment or in `settings.json`:

```json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```

Without that variable no team forms at session start and the lead cannot spawn
teammates. Confirm it is set before relying on any team workflow below.

Once enabled, each session has exactly **one implicit team** (the lead plus the
teammates it spawns). There is no create step and no teardown step: the team forms
when the first teammate is spawned and its shared state is cleaned up automatically
when the session ends. `TeamCreate`, `TeamDelete`, and `TeamList` do not exist —
teammates are spawned directly via the Agent tool with a `name`. The `team_name`
argument is accepted but ignored.

### Display Mode

`teammateMode` controls whether teammates run in the main terminal or in split panes.
Its default is `"in-process"`. Allowed values: `"in-process"` (all teammates in the
main terminal, works anywhere), `"auto"` (split panes when already inside tmux or
iTerm2, else in-process), `"tmux"` (split-pane mode), and `"iterm2"` (iTerm2 native
panes, requires the `it2` CLI). The default no longer opens panes — set it explicitly
(`"teammateMode": "auto"` in `settings.json`, or `--teammate-mode auto`) to get them.

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
  "notes": null,
  "correction_cycles": 0,
  "scope_expansions": [],
  "approaches_tried": [],
  "failure_reason": null,
  "discovered_via": null,
  "spec": null
}
```

**Status values** (exhaustive enum):
- `pending`: ready for work, no one has claimed it
- `in-progress`: a teammate or single-session agent is actively working on it
- `blocked`: waiting on another feature or external dependency
- `passing`: complete, tests passing, coverage met
- `failed`: attempted and failed; needs re-assessment

**`scope`**: directories and files this feature owns. Used in spawn prompts to define teammate boundaries.

**`depends_on`**: array of feature IDs (e.g., `["F001"]`). Maps to `TaskUpdate` `addBlockedBy` calls after task creation.

**`assigned_to`**: teammate name when Agent Teams is active, `null` otherwise. Helps the lead reconstruct state if the session dies and restarts.

**Operational metrics** (who updates what):
- `correction_cycles` — incremented automatically by `verify-task-quality.sh` on each TaskCompleted rejection. **Never manually set.**
- `scope_expansions` — array of files/dirs added to scope after initial assignment. Lead appends here when approving a scope expansion request.
- `approaches_tried` — brief notes on approaches attempted before the passing implementation. Teammate includes this in the task-complete SendMessage; lead populates the field.
- `failure_reason` — lead sets this when moving a feature to `status: "failed"`. Must explain why, not just that it failed.
- `discovered_via` — lead sets this when adding a feature that emerged from another feature's implementation. Value is the source feature's ID (e.g., `"F002"`). Different from `depends_on` (technical dependency) — this is discovery lineage.

**Spec verification** (optional): when a feature's spec has passed the verification gate
(`/harness-init` Step 5.1 or the `harness-issue-prep` skill), it carries a `spec` object:
`{"hash", "verdict", "sv_version", "verified_at", "source"}`. `hash` is sha256 over the
`description` string exactly as stored (see `schemas/readiness-stamp.md` for the canonical
recipe); editing the description invalidates it, and the SessionStart orientation warns on
that drift. Absent or `null` means unverified. Hooks and the lead must tolerate all three
states. A stamp-sourced `risk: "elevated"` maps to `require_plan_approval: true` plus an
Opus implementer (see the dynamic-override table).

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

The four vv-harness agent definitions (`vv-harness:feature-implementer`,
`vv-harness:layer-implementer`, `vv-harness:researcher`, `vv-harness:reviewer`) carry
these per-role model, effort, and tool defaults in their frontmatter (reviewer: Opus with
high effort; implementers and researcher: Sonnet). The dynamic Opus-upgrade heuristics
below still apply: the spawn-time `model` parameter overrides the definition's
frontmatter.

**Static overrides**: if an implementer's scope is architecturally complex (10+ files, cross-cutting concerns, security-sensitive), upgrade to Opus regardless of history.

**Dynamic overrides** (based on operational metrics from past sessions): Before assigning models, the lead reviews `features.json` for historical patterns in the same scope directories:

| Historical signal | Action |
|-------------------|--------|
| `correction_cycles >= 3` on a past feature in the same scope | Upgrade this feature's implementer to Opus |
| `scope_expansions >= 3` on a past feature | Assign a broader initial scope; note it as expansion-prone in the spawn prompt |
| `failure_reason` mentions "approach mismatch" or "misunderstood interface" | Set `require_plan_approval: true` |
| `discovered_via` depth > 1 (discovered features spawning discovered features) | Fold into parent scope rather than spawning a separate teammate |
| Stamp or prep marked risk: "elevated" | Set require_plan_approval: true and upgrade the implementer to Opus |

These are judgment calls for the lead, not mechanical rules. If no historical data exists (first session, new scope), default to Sonnet.

The lead specifies model in the Agent tool call via `model: "sonnet"` or `model: "opus"`. Default to Sonnet for implementers; use Opus only when justified.

## Lead Agent Responsibilities

The lead agent is the coordinator. It operates in **plan mode** (Shift+Tab) by default, restricting itself to coordination-only tools: spawning, messaging, task management, and shutdown. No code editing.

The lead:

1. Reads project state (`.harness/features.json`, `claude-progress.txt`, `context_summary.md`, git log)
2. Produces a decomposition plan (Phase 1 of the workflow in harness-continue)
3. Presents the plan to the user for approval before spawning any teammates
4. Confirms `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set (the team forms implicitly when the first teammate is spawned — there is no create step)
5. Creates tasks via `TaskCreate`, then sets dependencies via `TaskUpdate` with `addBlockedBy` (derived from features.json `depends_on`)
6. Spawns teammates via the Agent tool with a `name`, model, and role-specific prompt (any `team_name` argument is ignored)
7. Monitors progress via `TaskList` and incoming `SendMessage` messages
8. Resolves conflicts if two teammates need overlapping files
9. Reviews completed work (exit plan mode if needed for code review)
10. Synthesizes results after all teammates complete
11. Updates `.harness/features.json` (status, assigned_to, test_file, coverage, approaches_tried, scope_expansions, failure_reason as appropriate)
12. Runs retrospective (Phase 5.5 in harness-continue): analyzes correction_cycles, scope_expansions, model fit, discovery lineage across the session's features
13. Updates `.harness/context_summary.md` with decisions, patterns, and retrospective findings (Meta-Session + Meta-Patterns sections)
14. Writes session handoff to `claude-progress.txt`
15. Sends `shutdown_request` to all teammates, waits for `shutdown_response`
16. Commits (the team's shared state is cleaned up automatically when the session ends)

If the lead catches itself starting to implement code instead of delegating, it should stop and spawn a teammate for that work.

## Teammate Responsibilities

Each teammate is a focused implementer. It:

1. Reads its spawn prompt for scope, deliverable, and constraints
2. If `require_plan_approval` is true: sends a `plan_approval_request` via `SendMessage` and waits for a direct message approval from the lead before writing any code
3. Runs `.harness/init.sh` to verify the project builds
4. Claims its task via `TaskUpdate({ taskId: "[ID]", status: "in_progress", owner: "[teammate-name]" })`
5. Works ONLY within its assigned scope (files, directories)
6. Follows TDD: write failing test, implement, verify, refactor
7. Sends messages via `SendMessage` to the lead or other teammates as needed
8. Marks task complete via `TaskUpdate(status: "completed")`
9. Writes its deliverable to a file (not just conversation output)
10. Does not modify files outside its assigned scope without messaging the lead first

When the `TaskCompleted` hook runs, it will verify tests pass. If the hook rejects (exit code 2), the teammate receives feedback and must fix the issues before re-completing.

When the `TeammateIdle` hook runs after task completion, the teammate may be prompted to pick up a new task.

## Native Messaging Protocol

All team communication uses `SendMessage`. These are the message patterns for harness projects:

**Teammate to Lead:**

| Situation | SendMessage call |
|-----------|-----------------|
| Task complete | `SendMessage({ type: "message", recipient: "team-lead", content: "Task #N complete. [summary]. Tests passing. Coverage: [X%].", summary: "Task #N done" })` then `TaskUpdate({ taskId: "N", status: "completed" })` |
| Blocked | `SendMessage({ type: "message", recipient: "team-lead", content: "Blocked on task #N: [what I need, who has it]", summary: "Blocked: [reason]" })` |
| Scope expansion needed | `SendMessage({ type: "message", recipient: "team-lead", content: "Need access to [files] because [reason]. Currently outside my scope.", summary: "Scope expand: [files]" })` |
| Plan for approval | `SendMessage({ type: "plan_approval_request", recipient: "team-lead", content: "# Implementation Plan\n\n1. [step]\n2. [step]\n...", summary: "Plan for task #N" })` |

**Completion deduplication**: Send the "Task #N complete" message exactly once per task ID.
If the TeammateIdle hook immediately prompts you to pick up a new task after completing:
1. Claim the new task first via TaskUpdate
2. Then send the completion message for the previous task
3. Never send two completion messages for the same task ID
4. If you already sent a completion message and the TaskCompleted hook rejected it (tests failed), fix the issue and re-complete the task — do not send a new "complete" message until the hook accepts

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

Set up dependency chains so sequenced work auto-unblocks. Map directly from the `depends_on` field in features.json. TaskCreate only accepts `subject`, `description`, `activeForm`, and `metadata` — dependencies must be set after creation via TaskUpdate.

```
# Step 1: Create all tasks (they start as pending by default)
TaskCreate({ subject: "F001: Build API endpoint", description: "..." })
# → task id "1"

TaskCreate({ subject: "F002: Build UI consuming API", description: "..." })
# → task id "2"

TaskCreate({ subject: "F003: Integration tests", description: "..." })
# → task id "3"

# Step 2: Set dependencies via TaskUpdate
TaskUpdate({ taskId: "2", addBlockedBy: ["1"] })
# → task 2 blocks until task 1 completes

TaskUpdate({ taskId: "3", addBlockedBy: ["1", "2"] })
# → task 3 blocks until BOTH task 1 and task 2 complete
```

Teammates poll `TaskList` and only see claimable (pending) tasks. They don't need to understand the dependency graph; the system handles it.

When the lead plans the team (Phase 1 of harness-continue), it reads `depends_on` from features.json and translates them to `addBlockedBy` in `TaskUpdate` calls after creating tasks.

Dependencies can also be added after initial setup. If a teammate discovers an unexpected dependency mid-work:
```
TaskUpdate({ taskId: "3", addBlockedBy: ["4"] })
```
This dynamically blocks task 3 until task 4 completes.

Tasks support a `metadata` field for storing arbitrary key-value pairs (e.g., feature ID, scope, model). This is optional — `features.json` already tracks this information for the harness.

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

Post-compaction recovery is handled by the plugin's SessionStart hook (matcher
`compact`), which re-injects orientation directly into model context after `/compact`
or automatic compaction. There is no per-project PostCompact hook.

These hooks mean:
- Teammates can't mark tasks done with failing tests (mechanical TDD enforcement)
- Idle teammates are prompted to pick up the next available feature (no wasted capacity)
- The lead doesn't need to micromanage task assignment after initial setup
- Post-compaction context recovery is injected automatically by the plugin

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

### Mechanical Scope Enforcement

The harness installs a PreToolUse hook (`enforce-scope.sh`) that blocks edits to files outside the teammate's assigned scope. The hook reads scope patterns from `.claude/teammate-scope.txt`. This file is created by the lead when spawning teammates — it is NOT a harness-init artifact.

The lead writes this file before spawning each teammate:
```bash
# .claude/teammate-scope.txt (created per-teammate, not committed)
src/auth/
tests/auth/
```

When the teammate tries to edit a file outside these paths, the hook blocks the edit (exit code 2) and suggests messaging the lead for scope expansion.

This promotes scope enforcement from instructional to mechanical. This hook is the
doc-grounded way to keep teammates inside their scope; subagents spawned with worktree
isolation in the fallback mode don't need it (they have physical isolation instead).

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
3. If one teammate's work is clearly wrong: revert those files with `git checkout -- <files>`, update the feature status to `failed` in features.json, and either re-scope for a replacement teammate or take over directly (exit plan mode)
4. If both sides are partially right: the lead exits plan mode and merges manually, keeping the passing tests from both sides
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

## Worktree Isolation

`isolation: "worktree"` in an Agent/Task spawn creates a temporary git worktree — a
physically separate copy of the repo. The spawned agent literally cannot affect the main
working tree, which promotes scope enforcement from instructional to mechanical.

**Platform status — know what is documented before relying on it:**
- Worktree isolation is platform-documented for SUBAGENTS spawned via the Agent/Task
  tool. That includes the non-experimental fallback mode (harness-continue, Step 4
  graceful degradation), where the lead spawns vv-harness agent types directly as
  worktree-isolated subagents.
- It is NOT documented for Agent Teams teammates. The platform docs advise avoiding
  teammate file conflicts through disjoint file ownership instead. If teammate worktrees
  appear to work on your CLI version, treat that as unverified experimental behavior
  that may break across versions — do not build a workflow on it.

**Doc-grounded patterns** (pick one):
1. Agent Teams with disjoint scope ownership plus the `enforce-scope.sh` hook (see
   Mechanical Scope Enforcement).
2. Worktree-isolated subagents spawned directly via the Agent/Task tool — the
   non-experimental fallback mode.

**When worktree-isolated subagents fit:**
- Features with truly independent scopes (no shared files)
- When scope violations have caused problems before
- Security-sensitive features where contamination risk is high

**When NOT to use worktree isolation:**
- Work that shares interfaces requiring real-time coordination (worktrees don't see each
  other's changes until merge)
- Quick tasks where merge overhead exceeds the benefit
- Layer-based work negotiating a shared interface file

**How it works:**

1. Lead spawns a subagent with `isolation: "worktree"`:
   ```
   Agent({
     description: "Implement F001",
     subagent_type: "vv-harness:feature-implementer",
     name: "api",
     model: "sonnet",
     isolation: "worktree",
     prompt: "[filled template]"
   })
   ```
   `subagent_type` selects the agent definition and `name` labels the subagent; adapt
   to whatever the spawn tool exposes on your CLI version.
2. The subagent works in its own worktree branch, commits normally
3. On completion, the worktree path and branch are returned to the lead
4. Lead merges worktree branches during Phase 4 (synthesis)
5. If the subagent makes no changes, the worktree is auto-cleaned

**Synthesis with worktrees:**

During Phase 4, the lead merges each worktree branch:
```bash
git merge worktree-branch-name --no-ff
```
If conflicts arise, follow the Integration Failure Recovery protocol. The advantage of
worktrees is that each agent's work is on a clean branch, making selective reverts
trivial.

**Trade-off**: Adds git merge complexity during synthesis, but eliminates scope violation
risk entirely. For independent feature scopes, this is almost always worth it.

## Cost Considerations

Model mixing reduces per-implementer token cost by roughly 5x (Sonnet vs Opus). But Agent Teams has coordination overhead that offsets some of that savings:

- **Lead overhead**: the lead runs on Opus for the entire session (planning, monitoring, synthesis). This is fixed cost regardless of teammate count.
- **SendMessage round-trips**: scope expansion, plan approval, interface negotiation: each costs tokens on both ends.
- **TeammateIdle re-assignment**: teammates that finish early and pick up new work run longer, consuming more Sonnet tokens.
- **Phase 1 planning**: reading all harness files, analyzing features, designing team structure, presenting the plan: this happens before any implementation tokens are spent.

**Measure the break-even, don't estimate it:**
- With telemetry enabled (see INSTALL.md, "Optional: Cost Telemetry"), derive the
  break-even from `claude_code.token.usage` and `claude_code.cost.usage` grouped by
  `model` and `query_source` (main vs subagent): compare a team session's measured cost
  against single-session work on a comparable scope, and let that calibrate when teams
  pay off in this project. `agent.name` only distinguishes official-marketplace agents —
  personal-marketplace agent names (including vv-harness roles) are redacted to
  `"custom"`, so it cannot separate the harness roles.
- Without a collector, use the in-session `/usage` breakdown, which attributes recent
  usage to skills, subagents, plugins, and MCP servers as percentages (the plan-usage
  breakdown view requires a subscription plan — Pro/Max/Team/Enterprise; the session
  token/cost stats are universal).
- The Phase 5.5 retrospective should cite measured token counts per model and per query
  source in the Meta-Session entry instead of estimates.
- With no telemetry at all, fall back to judgment: parallelize only when the planned team
  work clearly exceeds what one focused session would finish.

**Rules of thumb:**
- For two features that each touch fewer than 3 files, sequential single-session is cheaper
- The more independent the features, the better the parallelism payoff (less SendMessage overhead)
- Reviewer teammates on Opus are worth the cost for features touching 10+ files; skip them for smaller scopes

Don't optimize for cost at the expense of quality. The point of model mixing is to put reasoning power where it matters most (lead decisions, code review) and use efficient models for well-scoped, well-defined implementation work.

## Known Limitations

- **plan_approval_response delivery bug**: `SendMessage` with `type: "plan_approval_response"` reports success but the message never reaches the recipient. Use `type: "message"` for all plan approvals. The `plan_approval_request` type (teammate to lead) works fine; only the response direction is broken.
- **No session resumption**: if the lead session dies, in-process teammates are lost. Since `teammateMode` defaults to `"in-process"`, set it explicitly to `tmux` (or `auto`) for sessions that might be interrupted. On restart, `features.json` `assigned_to` fields help reconstruct what was in progress.
- **One team per session**: a lead can only manage one team at a time.
- **No nested teams**: teammates can't create their own sub-teams.
- **Permission inheritance**: teammates inherit the lead's permission mode by default.
- **Heartbeat timeout**: if a teammate crashes, it triggers a 5-minute heartbeat timeout before the lead is notified.
- **Split-pane limitations**: tmux split-screen doesn't work with VS Code integrated terminal, Windows Terminal, or Ghostty.
- **No CLI version pin**: `plugin.json` has no version-pin field; the platform's model is
  graceful degradation (older CLIs ignore unknown manifest fields). The harness targets
  the implicit-team model introduced in Claude Code v2.1.178+. Agent Teams is experimental (gated
  by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and may break across CLI versions; the
  worktree-subagent fallback mode (harness-continue, Step 4) covers that case.

## Integration with Harness

In a harness-managed project, the lead agent:

1. Reads `.harness/features.json` to select features (using `scope`, `depends_on`, and operational metrics to plan team structure and model selection)
2. Maps features to teammate scopes and task dependencies
3. Sets `assigned_to` in features.json when spawning teammates
4. Creates tasks via `TaskCreate`, then sets dependencies via `TaskUpdate` with `addBlockedBy` (derived from `depends_on`)
5. Updates `features.json` as teammates complete work (sets status, test_file, coverage, approaches_tried, clears assigned_to; appends to scope_expansions on approvals; sets failure_reason on failure)
6. Runs the retrospective (Phase 5.5) after all features pass: analyzes operational metrics, writes Meta-Session entry and updates Meta-Patterns in `context_summary.md`
7. Writes the session handoff to `claude-progress.txt` with a summary of all teammate work

Teammates do NOT write to `features.json`, `context_summary.md`, or `claude-progress.txt`. That's the lead's job. Teammates write code, tests, and communicate via `SendMessage`. The one exception: teammates include `approaches_tried` notes in their task-complete SendMessage so the lead can populate the field.
