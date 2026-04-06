# VV Claude Code Harness

A harness system for Claude Code that solves multi-session continuity, parallel agent coordination, and automated quality enforcement. Built on Anthropic's research for long-running tasks, evolved through three major versions into a system built on Claude Code's native Agent Teams primitives.

**Current version: v3.5.0** — Session discipline improvements from real-world harness violations. Adds mandatory smoke test gate, pre-commit features.json audit, mandatory retrospective for all session types, inline context updates during bug fixes, commit-at-breakpoints hygiene, stale task prevention, and coverage blocker documentation.

---

Every AI coding agent has the same Achilles heel: memory. Not the technical kind (context windows are growing). The practical kind. Start a complex project with Claude Code or Cursor. Work for an hour. Hit a context limit or close the session. Come back the next day. The agent has no idea what happened. It's like onboarding a new contractor every morning who's never seen the codebase.

This isn't a model problem. It's an infrastructure "harness" problem. And solving it requires thinking about agents less like chat interfaces and more like software systems that need state management.

## The shift problem

Anthropic's engineering team articulated this beautifully in their [research on effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): imagine a software project staffed by engineers working in shifts, where each new engineer arrives with no memory of what happened on the previous shift. That's exactly what happens with AI agents across context windows. Session ends. Context compacts or resets. New session starts fresh. The agent might have access to the files it created, but it has no memory of why it created them, what worked, what failed, or what comes next.

Two failure patterns emerge consistently:
* First, the agent tries to do too much in a single session; it "one-shots" the entire project, runs out of context mid-implementation, and leaves a half-built mess for the next session to puzzle over.
* Second (and more insidious), after making some progress, the agent looks around, sees working code, and declares victory. The project is 30% complete but the agent thinks it's done.

Both failures stem from the same root cause: no persistent memory of intent, progress, or remaining work.

v2.1 addressed a third failure: parallel agents stepping on each other. v3.0 replaced the custom coordination layer entirely with Claude Code's native Agent Teams. And v3.2 added mechanical enforcement (shell hooks that physically prevent completion without passing tests), v3.3 added metacognitive self-improvement (the harness learns from its own coordination patterns), v3.4 fixed four hooks that were silently broken on real systems, and v3.5 tightened session discipline based on real-world violation analysis.

## Two solutions, one insight

Two independent approaches emerged to solve the memory problem, and they converged on the same fundamental insight.

Anthropic's research proposed a two-phase architecture:
1. An initializer agent that runs in the first session and sets up scaffolding, followed by
2. Coding agents that make incremental progress in subsequent sessions.

The key innovation was externalizing state into files that persist between sessions:
* A `features.json` file tracks what needs to be built (and what's done).
* A `claude-progress.txt` file logs what each session accomplished.

The coding agent reads these files at the start of every session, orients itself, picks up where the last session left off.

Almost at the same time, the Manus team (before their acquisition) discovered the same principle through production experience. They distilled it into what the community now calls the "planning-with-files" pattern. Their insight: the context window is RAM; the filesystem is disk. Anything important gets written to disk.

Manus uses three files for every complex task: `task_plan.md` (phases and progress), `notes.md` (research and discoveries), and `context_summary.md` (persistent learnings). The agent re-reads the plan before major decisions. It writes findings immediately rather than holding them in context. It logs errors so it doesn't repeat them.

Same problem. Same solution. Different vocabulary.

## Why files, not memory systems?

You might wonder: why markdown files? Why not Jira, GitHub issues, vector databases, RAG pipelines, or proper memory systems?

Three reasons:
* **Simplicity**: Files require no infrastructure and no assumptions. The agent writes. The agent reads. Done.
* **Transparency**: When an agent goes off the rails, you can open `task_plan.md` and see exactly what it thinks it's doing. You can't really debug a vector database when an agent starts hallucinating. Files are inspectable, editable, and version-controlled.
* **Structure**: Anthropic specifically chose JSON for their features file because, [as they noted](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), "the model is less likely to inappropriately change or overwrite JSON files compared to Markdown files." Structured formats create implicit contracts. The agent knows that `passes: false` means work remains. It knows not to delete entries. The file format itself enforces discipline.

## The evolution: v2.0 to v3.4

### v2.0: The foundation (January 2025)

The first version combined both approaches: Anthropic's two-phase architecture with Manus's planning-with-files pattern. An initializer created the scaffolding. Coding agents followed the structure. Four files bridged sessions. It worked, but only for sequential work: one agent, one feature at a time.

### v2.1: Module locking (February 2025)

The second version added parallel safety. A `.context/modules.yaml` file defined code boundaries. Before an agent touched code, it claimed the modules it needed. If another agent held a lock, the requesting agent waited. One agent per module at a time. Conflicts prevented, not resolved.

It worked, but the coordination was custom. The orchestrator rules were prose-based ("always orchestrate, never implement directly"). The module locking was a skill that agents had to remember to call. And "remember to call" is exactly the kind of instruction that drifts over long contexts.

### v3.0: Native Agent Teams (February 2026)

Claude Code shipped Agent Teams as an experimental feature: native primitives for creating teams, assigning tasks, messaging between agents, and managing shared task lists. This was the coordination layer I'd been building by hand, but implemented at the platform level.

v3.0 threw away the custom module locking, the orchestrator rules, the `.context/` directory, and the slash commands. Everything was replaced with native primitives: `TeamCreate`, `TaskCreate`, `SendMessage`, `TaskList`, `TeamDelete`. The 4-file pattern was replaced with compaction-aware context management using task persistence (originally `TodoWrite`, now `TaskCreate`/`TaskUpdate`).

The lead agent operates in plan mode (Shift+Tab), restricting itself to coordination tools. No code editing. It spawns teammates, assigns scoped tasks, monitors progress, and synthesizes results. Teammates work independently, each in their own context window, communicating through `SendMessage`.

### v3.1: Mechanical enforcement (February 2026)

The realization that made v3.1 necessary: prose-based instructions are medium-reliability enforcement. An agent told "use TDD" will use TDD most of the time. An agent told "don't touch files outside your scope" will comply most of the time. But "most of the time" isn't good enough when you have three teammates running in parallel.

v3.1 added shell hooks that make quality gates mechanical:

* **TaskCompleted hook**: when a teammate marks work done, a shell script runs the test suite. If tests fail, the completion is rejected with feedback. The teammate can't finish until tests pass. No exceptions. No "I'll fix it later."
* **TeammateIdle hook**: when a teammate finishes and goes idle, a shell script checks `features.json` for remaining work. If pending features exist, the teammate is prompted to pick up next work. No wasted capacity.
* **PostToolUse hook**: after every file edit, a stack-specific type/build check runs. TypeScript gets `tsc --noEmit`. Swift gets `swift build`. Python gets `py_compile`. Errors surfaced shortly after edits (async since v3.2.2), not at the commit.

v3.1 also added plan-first workflows (the lead presents a decomposition plan before spending tokens on teammates), model mixing (Opus for leads and reviewers, Sonnet for implementers), and task dependency chains via `TaskCreate` with `blocked_by`.

### v3.2: Schema, recovery, and honesty (February 2026)

v3.2 addressed gaps discovered during real Agent Teams sessions:

**Extended feature schema.** The original `features.json` had `id`, `description`, `priority`, `status`. That's not enough for team coordination. v3.2 added `scope` (which directories the feature owns), `depends_on` (which features must complete first), and `assigned_to` (which teammate claimed it). The lead can now reconstruct team state from `features.json` alone if a session dies.

**Unified context file.** Harness projects used `decisions.md`. Non-harness projects used `context_summary.md`. Same concept, different names. v3.2 unified on `context_summary.md` everywhere: decisions, patterns, gotchas, and active context in one file.

**Integration failure recovery.** When teammates' work conflicts during synthesis, the protocol is: identify via `git diff`, run tests to pinpoint which side broke, revert cleanly rather than attempting a broken merge, document in `context_summary.md`. A clean revert is always better than a broken merge.

**Delegation framework.** The old "always orchestrate, never implement directly" rule conflicted with single-session harness mode. v3.2 replaced it with clear criteria: delegate when subtasks are parallelizable or research-heavy; implement directly when coordination overhead exceeds the work itself.

**Cost recalibration.** The README used to claim "5x cost reduction" from model mixing. That's 5x per implementer token, not 5x overall. The Opus lead running for the full session, SendMessage round-trips, and Phase 1 planning overhead all add up. v3.2 is honest: Agent Teams becomes cost-effective when total work exceeds ~30 minutes of single-session effort.

**TodoWrite discipline.** Changed from "update before compaction" to "update after every TDD step." Todos are the crash-recovery journal. If automatic compaction hits mid-TDD-cycle with stale todos, you lose your place.

### v3.2.1: Bug fixes from production (February 2026)

Two bugs discovered in real Agent Teams sessions:

**PostToolUse hook schema.** The hooks were generated with `postToolUse` (wrong casing) and a flat structure that Claude Code silently ignores. Fixed to `PostToolUse` with proper nested `matcher` + `hooks` array. The kind of bug you only catch by actually running the system.

**plan_approval_response delivery bug.** `SendMessage` with `type: "plan_approval_response"` reports success but the message never reaches the recipient. Discovered when a lead agent kept sending approvals that teammates never received. The workaround (confirmed in production): use `type: "message"` for all plan approvals. The harness now documents this as a known Claude Code bug and routes all approvals through direct messages.

### v3.3: Metacognitive self-improvement (March 2026)

Inspired by [Facebook Research's HyperAgents framework](https://arxiv.org/abs/2603.19461), v3.3 added the ability for the harness to learn from its own coordination patterns. Five operational metrics in `features.json` (`correction_cycles`, `scope_expansions`, `approaches_tried`, `failure_reason`, `discovered_via`) feed a structured retrospective (Phase 5.5) that runs after all features pass. The retrospective writes findings to `context_summary.md` under `Meta-Session` and `Meta-Patterns` sections.

The practical effect: after 3-4 Agent Teams sessions, the harness knows which scopes are tricky (upgrade to Opus), which features need plan approval (past interface misunderstandings), and where to probe for hidden features at init time. Dynamic model selection uses these signals — `correction_cycles >= 3` in the same scope upgrades the next implementer from Sonnet to Opus.

v3.3 also split `init.sh` test runs into two stages: a fast `smoke_test` (compile/syntax only, <15s) and `full_test` (complete suite). The TaskCompleted hook runs smoke first, rejecting compile errors before spending time on the full suite.

### v3.4: Hook reliability fixes (April 2026)

v3.4 came from analyzing Claude Code's internal multi-agent implementation and comparing it against the harness's external hook protocol. Four hooks were silently broken or producing wrong results on real systems:

**Scope enforcement was broken.** Tool input provides absolute paths (`/Users/name/project/src/auth/login.ts`). Scope patterns are relative (`src/auth/`). The prefix match never matched. Every teammate could edit any file. Fixed by stripping the project root before comparison.

**Dependency filtering was missing.** The TeammateIdle hook offered all pending/failed features regardless of `depends_on`. A teammate could be assigned F002 before F001 (its dependency) was done. Fixed by checking all dependencies have `status: "passing"` before offering a feature.

**Correction cycles hit wrong targets.** `verify-task-quality.sh` incremented `correction_cycles` for every in-progress feature on any rejection. In a 3-teammate session, one teammate's test failure corrupted metrics for all teammates. Fixed by extracting the feature ID from task metadata and targeting only that feature.

**JSON parsing was fragile.** `init.sh` used a `grep`/`sed` chain to read `stack` from `harness.json` — the only script in the harness not using `python3` for JSON. Fixed for consistency and robustness.

v3.4 also added context management conventions (proactive compaction between features), a PostCompact circuit breaker (escalate after repeated compaction context collapse), TaskCreate metadata for task-to-feature correlation, and completion message deduplication guidance.

## Architecture

### Global (travels with you)

```
~/.claude/
├── CLAUDE.md                                         # Core engineering standards (all projects)
├── rules/
│   ├── agent-teams-protocol.md                        # Agent Teams rules (harness projects only)
│   └── code-quality.md                                # Mechanical code quality limits (all projects)
└── skills/
    ├── harness-init/
    │   ├── SKILL.md                                   # /harness-init skill
    │   ├── init.sh.template                           # Build/test script template
    │   ├── verify-task-quality.sh.template             # TaskCompleted hook
    │   ├── check-remaining-tasks.sh.template           # TeammateIdle hook
    │   ├── enforce-scope.sh.template                   # PreToolUse scope enforcement hook
    │   └── verify-git-identity.sh.template             # PreToolUse git identity hook
    └── harness-continue/
        ├── SKILL.md                                   # /harness-continue skill
        └── team-spawn-prompts.md                      # Spawn templates with model + plan approval
```

### Per-project (created by initializer)

```
project-root/
├── CLAUDE.md
├── .claude/
│   ├── settings.json                                  # Build hooks + quality gate hooks
│   └── hooks/
│       ├── verify-task-quality.sh                     # TaskCompleted enforcement
│       ├── check-remaining-tasks.sh                   # TeammateIdle prompted reassignment
│       ├── enforce-scope.sh                           # PreToolUse scope enforcement
│       └── verify-git-identity.sh                     # PreToolUse git identity verification
└── .harness/
    ├── harness.json                                   # Config + git identity + team structure
    ├── features.json                                  # Feature tracking (with scope, dependencies)
    ├── context_summary.md                             # Decisions, patterns, gotchas, active context
    ├── claude-progress.txt                            # Session-boundary handoff
    └── init.sh                                        # Build/test script
```

## Three tiers of enforcement

The real insight from iterating through these versions: there are three reliability tiers for agent coordination, and you need to know which tier each rule lives in.

**Mechanical (shell hooks, exit codes)**: very high reliability. The hook blocks the action; the agent cannot proceed without satisfying the constraint.

| Hook | Event | What it enforces |
|------|-------|-----------------|
| `verify-task-quality.sh` | TaskCompleted | Tests must pass before task completion is accepted |
| `enforce-scope.sh` | PreToolUse (Edit/Write) | Edits blocked outside teammate's assigned scope |
| `verify-git-identity.sh` | PreToolUse (Bash) | Git push/pull blocked if identity doesn't match harness.json |

**Prompted (shell hooks with feedback)**: high reliability. The hook delivers a message to the agent, but the agent decides whether to follow it.

| Hook | Event | What it does |
|------|-------|-------------|
| `check-remaining-tasks.sh` | TeammateIdle | Prompts teammate to pick up next pending feature |
| PostCompact prompt | PostCompact | Injects "re-read context_summary.md and TaskList" into model context |

**Structural (file existence, JSON schema)**: high reliability. `features.json` requiring `test_file` and `coverage` fields. The `.harness/` directory gating mode selection. Agents respect structure more than prose.

**Instructional (prose in CLAUDE.md, rules, skills)**: medium reliability. "Use TDD." "Don't modify files outside scope." "Verify git identity before push." These work most of the time. Over long contexts, compliance drifts.

The progression from v2.0 to v3.4 is the story of promoting critical rules from instructional to mechanical enforcement. TDD went from "please use TDD" to a shell hook that rejects non-passing code. Scope enforcement went from "don't touch files outside your scope" to a PreToolUse hook that blocks the edit. Git identity verification went from "check before pushing" to a PreToolUse hook that blocks the push. The rules that matter most should be the ones agents can't skip.

## Core principles

These have held steady across all versions:

* **Predictable input**: When Claude orchestrates and starts sub-agents, each sub-agent verifies the initialization state is the same, avoiding tangents to fix things outside the defined prompt.

* **Prescribed output format**: Each sub-agent has defined exit expectations: testing, checks, status updates. When they return to the orchestrator, they all return at the same level of quality.

* **Progressive discovery**: Context storage is hierarchical to protect the agent's context window. Drop MCP tools if they're not necessary. If there's an API, prefer to ask the sub-agent to build the necessary API calls based on documentation rather than loading 100 tools in context.

* **Mechanical over instructional**: If a rule matters enough to write down, it matters enough to enforce with a hook. Shell scripts don't drift over long contexts.

* **Filesystem as connective tissue**: Not because files are the optimal data structure for agent memory (they're not), but because they're the optimal trade-off between simplicity, transparency, and effectiveness.

## Usage recommendations

### Solo work (most common)

Install the harness globally, then run `/harness-init` on any project that will span multiple sessions. At the start of every session, run `/harness-continue` — it reads your progress files, verifies git identity, and picks up where you left off.

Use **single-session mode** for features touching fewer than 5 files. The harness tracks progress via `TaskCreate`/`TaskUpdate` (which survive compaction), runs async build checks after edits, and mechanically blocks git pushes with wrong identity.

The PostCompact prompt hook recovers your context automatically after compaction — it injects a reminder to re-read `context_summary.md` and the task list.

### Parallel work (Agent Teams)

Use Agent Teams when two or more independent features are ready. The lead operates in plan mode (Shift+Tab), spawns Sonnet teammates for implementation, and reserves Opus for itself and reviewers.

**For features with independent scopes**: spawn teammates with `isolation: "worktree"`. Each gets a physically separate copy of the repo. Cleanest separation, no scope violations possible. The lead merges worktree branches during synthesis.

**For shared-branch work**: the `enforce-scope.sh` PreToolUse hook blocks edits outside the teammate's assigned scope file (`.claude/teammate-scope.txt`). The lead creates this file before spawning each teammate.

The `TaskCompleted` hook mechanically enforces passing tests before any task can be marked complete. The `TeammateIdle` hook prompts (but doesn't force) idle teammates to pick up the next pending feature.

### When NOT to use

* **Don't use Agent Teams** for features touching fewer than 3 files each — sequential single-session mode is cheaper. The Opus lead runs for the entire session regardless of teammate count; coordination overhead adds up.
* **Don't use worktree isolation** when teammates share interfaces — they need to see each other's changes in real time. Use the scope enforcement hook instead.
* **Don't treat TeammateIdle as automatic** — it prompts the teammate to pick up work, but the model decides whether to follow through. Monitor via `TaskList`.

### Token budget

The harness adds ~8.7K tokens to your context when active:
* `CLAUDE.md`: ~4.2K (always loaded)
* `agent-teams-protocol.md`: ~4.5K (loaded only when `.harness/` files are read)

This is down from ~14.7K in v3.2.1 (before eliminating redundant `engineering-standards.md` and `non-harness-workflow.md` rule files). A 41% reduction.

In non-harness projects, only CLAUDE.md loads (~4.2K). The agent-teams-protocol rule is not triggered because no `.harness/` files are read.

## Known challenges

**Solved in v3.2.2:**

* **Scope enforcement**: Worktree isolation (`isolation: "worktree"`) provides physical separation for independent features. A PreToolUse hook (`enforce-scope.sh`) blocks edits outside the teammate's scope file for shared-branch work. Both are mechanical enforcement.

* **Git identity verification**: A PreToolUse hook (`verify-git-identity.sh`) checks git identity against `.harness/harness.json` before every push/pull/clone. Blocks the operation if identity doesn't match.

**Still open:**

* **Session resumption**: If the lead session dies, in-process teammates are lost. `features.json` helps reconstruct state, but the work in flight is gone. tmux mode helps, but it's a mitigation, not a solution.

* **Cost modeling**: Agent Teams cost is hard to predict. Lead overhead, SendMessage round-trips, TeammateIdle re-assignment, and Phase 1 planning all vary by project. Better cost instrumentation (logging tokens per role) would help.

* **SendMessage reliability**: The `plan_approval_response` delivery bug suggests other message types might have similar issues. The harness works around the known bug, but systematic message delivery testing would build more confidence.

## Getting started

Everything you need is in this repo:

1. Download [harness-v3.4.0.zip](https://github.com/oeftimie/vv-claude-harness/releases)
2. Follow the [INSTALL.md](./INSTALL.md) instructions
3. Review the [CLAUDE.md](./claude/CLAUDE.md) for core engineering standards

### Quick install

```bash
unzip vv-claude-harness-v3.4.0.zip
cd vv-claude-harness
./install
```

The installer backs up existing files, personalizes CLAUDE.md with your name, and handles upgrades from older versions. See [INSTALL.md](./INSTALL.md) for options (`--dry-run`, `--name`, `--upgrade-only`).

### Usage

```bash
# Initialize a new project
cd ~/Projects/MyApp
git init
claude
/harness-init

# Continue working (start of every session)
claude
/harness-continue
```

### What's in the box

| Component | Purpose |
|-----------|---------|
| `CLAUDE.md` | Core engineering standards (all projects) |
| `rules/agent-teams-protocol.md` | Agent Teams coordination (harness projects only) |
| `skills/harness-init/` | Project initialization with hooks and scaffolding |
| `skills/harness-continue/` | Session continuation with team spawn templates |

## Some screenshots from my sessions

<img width="1248" height="1076" alt="Screenshot 2026-01-09 at 12 47 25" src="https://github.com/user-attachments/assets/25b4be66-c384-4225-92a6-cd4d2c8964a8" />
<img width="849" height="766" alt="Screenshot 2026-01-09 at 12 42 01" src="https://github.com/user-attachments/assets/031c3dfb-4a35-4b6b-bac9-200049c7ee28" />

### UI test automation with Xcode & Claude Code

https://github.com/user-attachments/assets/9684d120-3cbf-438d-a01f-469387f507ff

---

## Changelog

### v3.5.0 (2026-04-06)

**Session discipline improvements** based on root cause analysis of 11 harness violations observed during a real iOS project session (voice fix, test expansion, app icon work).

**Five serious violation remediations:**

1. **Pre-commit features.json audit** — Session end now requires diffing `features.json` against actual work done. Any code change relating to a tracked feature must update that feature's metadata. Work that doesn't map to any feature gets a new entry with `discovered_via`. This is a gate before `git commit`, not an afterthought.

2. **Inline context_summary.md updates** — `context_summary.md` updates are now part of the task, not after the task. After every bug fix revealing a non-obvious root cause, write the gotcha to `context_summary.md` BEFORE moving to the next request.

3. **Mandatory retrospective for all session types** — The retrospective is now explicitly mandatory at session end regardless of whether the session used Agent Teams or single-session mode. Minimum viable: 3-5 bullets covering actual vs planned scope, unanticipated discoveries, and transferable patterns.

4. **Task updates at moment of state change** — Task updates must happen immediately when state changes, not in batch. When you finish something, the NEXT action is `TaskUpdate`. Stale tasks are explicitly called out as worse than no tasks.

5. **Smoke test gate at session start** — `init.sh` is now a dedicated Step 2.5 in the orient flow, run within the first 5 actions of every session. Its purpose is to establish known-good state before changes, not to diagnose problems.

**Four moderate/minor violation remediations:**

6. **Single-session mode declaration** — When choosing single-session over Agent Teams, the lead must explicitly declare it to make the decision conscious and documented.

7. **Bug fix diagnosis before editing** — Debugging Phase 1 now requires stating diagnosis and proposed fix in 2-3 sentences before editing code, even for seemingly obvious fixes.

8. **Commit at natural breakpoints** — Commit hygiene rules now require committing after each feature/fix passes tests, separating harness metadata from code, and checkpointing inherited uncommitted work before making new changes.

9. **Untracked file and task metadata audit at orient** — The orient step now checks for unknown untracked files (surfaced to user) and verifies inherited tasks have required `feature_id` metadata.

**Two standards improvements:**

10. **Coverage blocker documentation** — If coverage measurement isn't available in the project's tooling, document it as a gotcha in `context_summary.md` and create a feature to enable it. Silent coverage gate skipping is no longer acceptable.

11. **Strengthened task completion checklist** — Harness-specific checklist items now explicitly require features.json audit, context_summary.md updates, retrospective, and task list currency check.

### v3.4.0 (2026-04-02)

**Bug fixes and convention improvements** based on analysis of Claude Code's internal multi-agent implementation compared against the harness's external hook protocol.

**Four bug fixes:**

1. **Scope enforcement path normalization** — `enforce-scope.sh` now strips the project root from absolute paths before matching. Tool input always provides absolute paths; scope patterns are relative. The prefix match was silently passing everything through.

2. **`depends_on` enforcement in idle hook** — `check-remaining-tasks.sh` now filters claimable features by dependency chains. A feature is only offered if all its `depends_on` entries have `status: "passing"`. Previously, blocked features were assigned as if ready.

3. **Targeted `correction_cycles` increment** — `verify-task-quality.sh` now extracts the feature ID from task metadata or subject prefix and only increments `correction_cycles` for that feature. Previously, all in-progress features were incremented on any teammate's rejection, corrupting metrics in multi-teammate sessions.

4. **Consistent JSON parsing in init.sh** — Replaced the fragile `grep`/`sed` chain for reading `stack` from `harness.json` with `python3 -c "import json; ..."`, matching every other script in the harness.

**Three convention changes:**

5. **Context Management in spawn templates** — Feature Implementer and Layer Implementer templates now instruct teammates to compact proactively before starting a new feature (after TeammateIdle reassignment) to prevent mid-implementation context loss.

6. **PostCompact circuit breaker** — The PostCompact hook prompt now detects repeated compaction context collapse (third+ compaction in rapid succession) and instructs the teammate to save state and escalate to the lead rather than looping.

7. **TaskCreate metadata convention** — All TaskCreate examples now include `metadata: { feature_id: "FXXX" }` for task-to-feature correlation that survives compaction. Enables the targeted `correction_cycles` fix.

**One docs change:**

8. **Completion message deduplication** — Added guidance to the Agent Teams messaging protocol to prevent duplicate completion messages when the TeammateIdle hook fires immediately after task completion.

### v3.3.0 (2026-03-28)

**Metacognitive self-improvement**: The harness now learns from its own coordination patterns, not just from domain work. Inspired by [Facebook Research's HyperAgents framework](https://arxiv.org/abs/2603.19461), which demonstrated that systems whose improvement mechanisms are themselves improvable outperform fixed-meta alternatives.

**Five coordinated changes:**

1. **Operational metrics in features.json** — Five new fields track coordination quality:
   - `correction_cycles`: auto-incremented by TaskCompleted hook on rejection. Signals features harder than expected.
   - `scope_expansions`: files/dirs added to scope after initial assignment. Reveals initial scoping accuracy.
   - `approaches_tried`: brief notes on what worked/failed before the passing implementation.
   - `failure_reason`: why a feature reached `status: "failed"`. Root cause without re-reading history.
   - `discovered_via`: discovery lineage — which feature's implementation revealed the need for this one (distinct from `depends_on` technical dependencies).

2. **Structured retrospective (Phase 5.5)** — Runs after all features pass, before teardown. Analyzes `correction_cycles`, `scope_expansions`, `discovered_via`, and `approaches_tried` across the session. Writes findings to `context_summary.md` under:
   - `## Meta-Session [DATE]`: session-specific insights (scope accuracy, model calibration, discovery patterns, approach successes/failures, plan approval value)
   - `## Meta-Patterns`: generalizable coordination insights that transfer to new projects (when to use Opus, how to scope, when plan approval pays off)
   - Applies to both single-session and Agent Teams workflows. Skipped on first session (no data yet).

3. **Tiered test evaluation in init.sh** — Split test runs into two stages (inspired by HyperAgents' staged evaluation):
   - `smoke_test`: compile/syntax check only, completes in <15s
   - `full_test`: complete suite with coverage (existing behavior)
   - TaskCompleted hook now runs smoke first; only runs full if smoke passes. Reduces cost of early rejection for compile errors.

4. **Meta-Patterns section in context_summary.md** — Dedicated section for coordination insights, distinct from domain-specific patterns. Populated by retrospective step. Intended to transfer to new projects as starting context.

5. **Dynamic model selection heuristics** — Phase 1 planning now reviews historical operational metrics before assigning Sonnet vs Opus:
   - `correction_cycles >= 3` in same scope → upgrade implementer to Opus
   - `scope_expansions >= 3` → assign broader initial scope, note as "expansion-prone"
   - `failure_reason` mentions interface misunderstandings → set `require_plan_approval: true`
   - `discovered_via` depth > 1 → consider folding into parent scope
   - All judgment calls for the lead, not mechanical rules.

**What this enables:** The harness accumulates coordination wisdom across sessions. After 3-4 Agent Teams sessions, it knows which scopes are tricky, which features need Opus, where to probe for hidden features at init. This is the practical version of HyperAgents' "metacognitive self-modification" — improving how the system improves, not just what it produces.

### v3.2.2 (2026-03-21)
- Replaced TodoWrite with TaskCreate/TaskUpdate (TodoWrite no longer exists in Claude Code)
- Renamed "delegate mode" to "plan mode" to match current Claude Code terminology
- Added worktree isolation for teammate scope enforcement (`isolation: "worktree"` in Task() calls)
- Added PostCompact hook for automatic context re-injection after compaction
- Made PostToolUse build-check hooks async (non-blocking)
- Added Auto-Memory vs context_summary.md guidance
- Synced CLAUDE.md template with installed global copy (Agent Autonomy override callout, git identity mismatch fix, context_summary.md anti-patterns)
- Added path-scoped frontmatter to agent-teams-protocol.md (already had `globs: [.harness/**]`)
- Removed `non-harness-workflow.md` rule; core loop folded into CLAUDE.md (saves ~3K tokens per session)
- Removed `engineering-standards.md` rule; 100% redundant with CLAUDE.md (saves ~3K tokens per session)
- Fixed TaskCreate API shape: dependencies set via TaskUpdate addBlockedBy, not TaskCreate blocked_by
- Fixed TeammateIdle documentation: hook prompts reassignment, doesn't auto-assign
- Fixed PostCompact hook: uses `type: "prompt"` for mechanical context injection
- Added PreToolUse scope enforcement hook (`enforce-scope.sh`) — blocks edits outside assigned scope
- Added PreToolUse git identity hook (`verify-git-identity.sh`) — blocks push/pull with wrong identity
- Added native `owner` field on TaskUpdate for task assignment alongside features.json `assigned_to`
- Added `activeForm` to TaskCreate examples for better spinner UX
- Added usage recommendations section to README
- Updated enforcement tier documentation with honest hook classification (mechanical vs prompted)

### v3.2.1 (2026-02-18)
- Fixed PostToolUse hook schema: PascalCase event name, proper nested `hooks` array
- Fixed hook commands to parse `tool_input.file_path` from stdin JSON via `jq`
- Documented `plan_approval_response` delivery bug; all plan approvals use direct messages

### v3.2 (2026-02-18)
- Extended features.json schema: `scope`, `depends_on`, `assigned_to` fields
- Defined exhaustive status enum: pending, in-progress, blocked, passing, failed
- Unified on `context_summary.md` across all modes (replaces `decisions.md`)
- Added hook verification step to harness-init
- Added Integration Failure Recovery protocol
- Recalibrated cost framing: "5x per implementer" not "5x overall"
- Tightened TodoWrite discipline: update after every TDD step
- Added delegation decision framework
- Extracted non-harness workflow to separate rules file
- Fixed plan-and-wait contradiction for teammate spawns

### v3.1 (2026-02-18)
- Added TaskCompleted and TeammateIdle hooks for mechanical quality enforcement
- Added plan-first workflow with user approval before spawning teammates
- Added model mixing guidance (Opus lead/reviewer, Sonnet implementers)
- Replaced custom messaging with native SendMessage protocol
- Added delegate mode as default for lead agents
- Added task dependency chains via TaskCreate blocked_by
- Added plan approval protocol for complex features

### v3.0 (2026-02-17)
- Replaced module locking with native Agent Teams integration
- Replaced 4-file pattern with compaction-aware approach (TodoWrite)
- Simplified features.json
- Added global engineering rules
- Added git identity capture and verification

### v2.1 (2025-02-01)
- Added module locking for parallel agent coordination
- Added `.context/modules.yaml` for defining code boundaries
- Added context-graph skill (claim/release/status/force-release)
- Restructured to use Claude Code's native memory system (`rules/`, `@imports`)

### v2.0 (2025-01-24)
- Initial public release
- Two-phase architecture (initializer + coding agents)
- 4-file pattern integration
- Multi-language init.sh support
