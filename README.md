# VV Claude Code Harness

A harness system for Claude Code that solves multi-session continuity, parallel agent coordination, and automated quality enforcement. Built on Anthropic's research for long-running tasks, evolved through four major versions into a native Claude Code plugin built on the platform's Agent Teams primitives.

**Current version: v4.0.0** — The harness is now a native Claude Code plugin (`/plugin install vv-harness`). The platform owns what prose and a custom installer used to carry: distribution and atomic updates, session orientation and post-compaction recovery (a SessionStart hook), session-end discipline auditing (a SessionEnd hook), live feature progress (a statusLine), and teammate tool posture (declarative `vv-harness:*` agents). The v3 installer is retired; migration steps are in [INSTALL.md](./INSTALL.md). Full history in [CHANGELOG.md](./CHANGELOG.md).

---

Every AI coding agent has the same Achilles heel: memory. Not the technical kind (context windows are growing). The practical kind. Start a complex project with Claude Code or Cursor. Work for an hour. Hit a context limit or close the session. Come back the next day. The agent has no idea what happened. It's like onboarding a new contractor every morning who's never seen the codebase.

This isn't a model problem. It's an infrastructure "harness" problem. And solving it requires thinking about agents less like chat interfaces and more like software systems that need state management.

## The shift problem

Anthropic's engineering team articulated this beautifully in their [research on effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): imagine a software project staffed by engineers working in shifts, where each new engineer arrives with no memory of what happened on the previous shift. That's exactly what happens with AI agents across context windows. Session ends. Context compacts or resets. New session starts fresh. The agent might have access to the files it created, but it has no memory of why it created them, what worked, what failed, or what comes next.

Two failure patterns emerge consistently:
* First, the agent tries to do too much in a single session; it "one-shots" the entire project, runs out of context mid-implementation, and leaves a half-built mess for the next session to puzzle over.
* Second (and more insidious), after making some progress, the agent looks around, sees working code, and declares victory. The project is 30% complete but the agent thinks it's done.

Both failures stem from the same root cause: no persistent memory of intent, progress, or remaining work.

v2.1 addressed a third failure: parallel agents stepping on each other. v3.0 replaced the custom coordination layer entirely with Claude Code's native Agent Teams. And v3.2 added mechanical enforcement (shell hooks that physically prevent completion without passing tests), v3.3 added metacognitive self-improvement (the harness learns from its own coordination patterns), v3.4 fixed four hooks that were silently broken on real systems, v3.5 tightened session discipline based on real-world violation analysis, and v4.0 packaged the whole harness as a Claude Code plugin — moving session orientation, post-compaction recovery, and discipline auditing from prose into platform hooks.

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

Installed via `/plugin`, updated atomically (each version gets its own cache directory):

```
vv-harness/                                            # Plugin root
├── skills/
│   ├── harness-init/                                  # /harness-init skill + hook templates
│   └── harness-continue/                              # /harness-continue skill + team-spawn-prompts.md
├── agents/                                            # Declarative teammates (spawned as vv-harness:*)
│   ├── feature-implementer.md                         # Sonnet, scoped TDD on one feature
│   ├── layer-implementer.md                           # Sonnet, owns one architectural layer
│   ├── researcher.md                                  # Sonnet, retrieval-only (Write for findings file)
│   └── reviewer.md                                    # Opus, high effort, no Edit/Write tools
├── hooks/
│   ├── session-start.sh                               # Orientation + post-compaction recovery
│   ├── session-end.sh                                 # Session discipline audit
│   └── statusline.sh                                  # Live feature progress (wired by /harness-init)
├── rules/
│   ├── agent-teams-protocol.md                        # Agent Teams rules (harness projects only)
│   └── code-quality.md                                # Mechanical code quality limits
└── templates/
    └── CLAUDE.md                                      # Core standards template (manual copy to ~/.claude/)
```

### Per-project (created by initializer)

```
project-root/
├── CLAUDE.md
├── .claude/
│   ├── settings.json                                  # Build + quality gate hooks, statusLine,
│   │                                                  #   Agent Teams env flag, permissions allowlist
│   └── hooks/
│       ├── verify-task-quality.sh                     # TaskCompleted enforcement
│       ├── check-remaining-tasks.sh                   # TeammateIdle prompted reassignment
│       ├── enforce-scope.sh                           # PreToolUse scope enforcement
│       ├── verify-git-identity.sh                     # PreToolUse git identity verification
│       └── statusline.sh                              # Project copy of the plugin status line
└── .harness/
    ├── harness.json                                   # Config + git identity + team structure
    ├── features.json                                  # Feature tracking (with scope, dependencies)
    ├── context_summary.md                             # Decisions, patterns, gotchas, active context
    ├── claude-progress.txt                            # Session-boundary handoff
    ├── SESSION_INCOMPLETE                             # Discipline gaps from last session (gitignored)
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
| `session-start.sh` (plugin) | SessionStart | Injects orientation at start; its `compact` matcher re-injects context after compaction |
| `session-end.sh` (plugin) | SessionEnd | Audits discipline into `SESSION_INCOMPLETE`, surfaced at next session start |

**Structural (file existence, JSON schema)**: high reliability. `features.json` requiring `test_file` and `coverage` fields. The `.harness/` directory gating mode selection. Agents respect structure more than prose.

**Instructional (prose in CLAUDE.md, rules, skills)**: medium reliability. "Use TDD." "Don't modify files outside scope." "Verify git identity before push." These work most of the time. Over long contexts, compliance drifts.

The progression from v2.0 to v3.4 is the story of promoting critical rules from instructional to mechanical enforcement. TDD went from "please use TDD" to a shell hook that rejects non-passing code. Scope enforcement went from "don't touch files outside your scope" to a PreToolUse hook that blocks the edit. Git identity verification went from "check before pushing" to a PreToolUse hook that blocks the push. The rules that matter most should be the ones agents can't skip.

v4.0 extends the same promotion to the harness itself: session orientation, post-compaction recovery, session-end discipline auditing, progress visibility (the statusLine), and reviewer/researcher tool posture all moved from prose instructions to plugin hooks and declarative agent definitions. The reviewer cannot edit files by construction (its definition grants no Edit/Write tools); its Bash use is restricted to test runs and git diff by instruction.

## Core principles

These have held steady across all versions:

* **Predictable input**: When Claude orchestrates and starts sub-agents, each sub-agent verifies the initialization state is the same, avoiding tangents to fix things outside the defined prompt.

* **Prescribed output format**: Each sub-agent has defined exit expectations: testing, checks, status updates. When they return to the orchestrator, they all return at the same level of quality.

* **Progressive discovery**: Context storage is hierarchical to protect the agent's context window. Drop MCP tools if they're not necessary. If there's an API, prefer to ask the sub-agent to build the necessary API calls based on documentation rather than loading 100 tools in context.

* **Mechanical over instructional**: If a rule matters enough to write down, it matters enough to enforce with a hook. Shell scripts don't drift over long contexts.

* **Filesystem as connective tissue**: Not because files are the optimal data structure for agent memory (they're not), but because they're the optimal trade-off between simplicity, transparency, and effectiveness.

## Usage recommendations

### Solo work (most common)

Install the plugin (`/plugin install vv-harness`), then run `/harness-init` on any project that will span multiple sessions. At the start of every session, run `/harness-continue` — it reads your progress files, verifies git identity, and picks up where you left off.

Use **single-session mode** for features touching fewer than 5 files. The harness tracks progress via `TaskCreate`/`TaskUpdate` (which survive compaction), runs async build checks after edits, and mechanically blocks git pushes with wrong identity.

The plugin's SessionStart hook recovers your context automatically after compaction — its `compact` matcher re-injects feature status, Active Context, and the last handoff directly into model context.

### Parallel work (Agent Teams)

Use Agent Teams when two or more independent features are ready. The lead operates in plan mode (Shift+Tab), spawns Sonnet teammates for implementation, and reserves Opus for itself and reviewers.

**For features with independent scopes**: spawn worktree-isolated subagents (`isolation: "worktree"`) — the same pattern the non-experimental fallback mode uses. Each gets a physically separate copy of the repo. Cleanest separation, no scope violations possible. The lead merges worktree branches during synthesis. Worktree isolation is platform-documented for subagents, not for Agent Teams teammates; keep teammates on disjoint scopes instead.

**For shared-branch work**: the `enforce-scope.sh` PreToolUse hook blocks edits outside the teammate's assigned scope file (`.claude/teammate-scope.txt`). The lead creates this file before spawning each teammate.

The `TaskCompleted` hook mechanically enforces passing tests before any task can be marked complete. The `TeammateIdle` hook prompts (but doesn't force) idle teammates to pick up the next pending feature.

### When NOT to use

* **Don't use Agent Teams** for features touching fewer than 3 files each — sequential single-session mode is cheaper. The Opus lead runs for the entire session regardless of teammate count; coordination overhead adds up.
* **Don't use worktree isolation** when agents share interfaces — they need to see each other's changes in real time. Use the scope enforcement hook instead.
* **Don't treat TeammateIdle as automatic** — it prompts the teammate to pick up work, but the model decides whether to follow through. Monitor via `TaskList`.

### Token budget

The harness's always-on overhead is `CLAUDE.md`: ~4.2K tokens (if you copied the template to `~/.claude/CLAUDE.md`). In v4 the rule files are NOT auto-loaded by globs — they cost tokens only when the model reads them, following the pointers in the SessionStart orientation:
* `agent-teams-protocol.md`: ~4.5K, read before team coordination in harness projects
* `code-quality.md`: ~0.3K, read before writing code in harness projects

This is down from ~14.7K always-on in v3.2.1 (before eliminating redundant `engineering-standards.md` and `non-harness-workflow.md` rule files).

In non-harness projects, only CLAUDE.md loads (~4.2K). The orientation hook stays silent (no `.harness/` directory), so neither rule file is pointed to or read.

## Known challenges

**Solved in v3.2.2:**

* **Scope enforcement**: Worktree isolation (`isolation: "worktree"`) provides physical separation for independent features. A PreToolUse hook (`enforce-scope.sh`) blocks edits outside the teammate's scope file for shared-branch work. Both are mechanical enforcement.

* **Git identity verification**: A PreToolUse hook (`verify-git-identity.sh`) checks git identity against `.harness/harness.json` before every push/pull/clone. Blocks the operation if identity doesn't match.

**Addressed in v4.0:**

* **Cost modeling**: Per-model and main-vs-subagent cost in a team session is now measured, not estimated (per-agent names are redacted to "custom" for personal marketplaces). Opt-in OTel telemetry exports `claude_code.token.usage` and `claude_code.cost.usage` attributed by model and query source; the in-session `/usage` breakdown works with zero infrastructure. See [INSTALL.md](./INSTALL.md), "Optional: Cost Telemetry".

* **Agent Teams fragility**: When Agent Teams is unavailable (flag off, team tools missing on a CLI version), `/harness-continue` falls back to worktree-isolated subagents using the same `vv-harness:*` agent types — a non-experimental, platform-documented path.

**Still open:**

* **Session resumption**: If the lead session dies, in-process teammates are lost. `features.json` helps reconstruct state, but the work in flight is gone. tmux mode helps, but it's a mitigation, not a solution.

* **SendMessage reliability**: The `plan_approval_response` delivery bug suggests other message types might have similar issues. The harness works around the known bug, but systematic message delivery testing would build more confidence.

* **SessionEnd can't block**: The session-end discipline audit records gaps and surfaces them at the next session start, but by platform design it cannot stop a session from ending with those gaps. Self-healing, not preventive.

* **Teammate worktrees unverified**: Worktree isolation is platform-documented for subagents only. Whether it works for Agent Teams teammates is unverified; the harness doesn't build on it.

* **Agent Teams is still experimental**: Gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and subject to change between CLI versions. The tested CLI version (v2.1.175) is documented in [INSTALL.md](./INSTALL.md).

## Getting started

The harness ships as a Claude Code plugin:

1. Install via the `/plugin` flow below
2. Migrating from the v3 installer? Follow the manual cleanup steps in [INSTALL.md](./INSTALL.md)
3. Review [templates/CLAUDE.md](./templates/CLAUDE.md) for the core engineering standards template

### Quick install

From inside any Claude Code session:

```
/plugin marketplace add oeftimie/vv-claude-harness
/plugin install vv-harness
```

Update later with `/plugin update vv-harness` — updates are atomic; each version gets its own cache directory. The v3 installer is retired: `./install` now only prints these instructions. See [INSTALL.md](./INSTALL.md) for migration from v3 and optional setup (cost telemetry, Agent Teams env flag, permissions).

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
| `skills/harness-init/` | Project initialization with hooks and scaffolding |
| `skills/harness-continue/` | Session continuation with team spawn prompts and the subagent fallback |
| `agents/` | Declarative teammate definitions (feature-implementer, layer-implementer, researcher, reviewer) |
| `hooks/` | Plugin continuity hooks: session-start, session-end, statusline |
| `rules/agent-teams-protocol.md` | Agent Teams coordination (harness projects only) |
| `rules/code-quality.md` | Mechanical code quality limits |
| `templates/CLAUDE.md` | Core engineering standards template (manual copy to `~/.claude/`) |
| `test/` | Fixture-based hook test suite, run in CI |

## Some screenshots from my sessions

<img width="1248" height="1076" alt="Screenshot 2026-01-09 at 12 47 25" src="https://github.com/user-attachments/assets/25b4be66-c384-4225-92a6-cd4d2c8964a8" />
<img width="849" height="766" alt="Screenshot 2026-01-09 at 12 42 01" src="https://github.com/user-attachments/assets/031c3dfb-4a35-4b6b-bac9-200049c7ee28" />

### UI test automation with Xcode & Claude Code

https://github.com/user-attachments/assets/9684d120-3cbf-438d-a01f-469387f507ff

---

## Changelog

Moved to [CHANGELOG.md](./CHANGELOG.md).
