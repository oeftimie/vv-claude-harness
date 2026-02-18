# Ovidiu's Claude Code Harness

A harness system for Claude Code that solves multi-session continuity, parallel agent coordination, and automated quality enforcement. Built on Anthropic's research for long-running tasks, evolved through three major versions into a system that uses 100% of Claude Code's native Agent Teams primitives.

**Current version: v3.2.1**

---

Every AI coding agent has the same Achilles heel: memory. Not the technical kind (context windows are growing). The practical kind. Start a complex project with Claude Code or Cursor. Work for an hour. Hit a context limit or close the session. Come back the next day. The agent has no idea what happened. It's like onboarding a new contractor every morning who's never seen the codebase.

This isn't a model problem. It's an infrastructure "harness" problem. And solving it requires thinking about agents less like chat interfaces and more like software systems that need state management.

## The shift problem

Anthropic's engineering team articulated this beautifully in their [research on effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): imagine a software project staffed by engineers working in shifts, where each new engineer arrives with no memory of what happened on the previous shift. That's exactly what happens with AI agents across context windows. Session ends. Context compacts or resets. New session starts fresh. The agent might have access to the files it created, but it has no memory of why it created them, what worked, what failed, or what comes next.

Two failure patterns emerge consistently:
* First, the agent tries to do too much in a single session; it "one-shots" the entire project, runs out of context mid-implementation, and leaves a half-built mess for the next session to puzzle over.
* Second (and more insidious), after making some progress, the agent looks around, sees working code, and declares victory. The project is 30% complete but the agent thinks it's done.

Both failures stem from the same root cause: no persistent memory of intent, progress, or remaining work.

v2.1 addressed a third failure: parallel agents stepping on each other. v3.0 replaced the custom coordination layer entirely with Claude Code's native Agent Teams. And v3.2 added the thing that actually makes parallel work reliable: mechanical enforcement. Not instructions that agents drift from over long contexts, but shell hooks that physically prevent completion without passing tests.

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

## The evolution: v2.0 to v3.2

### v2.0: The foundation (January 2025)

The first version combined both approaches: Anthropic's two-phase architecture with Manus's planning-with-files pattern. An initializer created the scaffolding. Coding agents followed the structure. Four files bridged sessions. It worked, but only for sequential work: one agent, one feature at a time.

### v2.1: Module locking (February 2025)

The second version added parallel safety. A `.context/modules.yaml` file defined code boundaries. Before an agent touched code, it claimed the modules it needed. If another agent held a lock, the requesting agent waited. One agent per module at a time. Conflicts prevented, not resolved.

It worked, but the coordination was custom. The orchestrator rules were prose-based ("always orchestrate, never implement directly"). The module locking was a skill that agents had to remember to call. And "remember to call" is exactly the kind of instruction that drifts over long contexts.

### v3.0: Native Agent Teams (February 2026)

Claude Code shipped Agent Teams as an experimental feature: native primitives for creating teams, assigning tasks, messaging between agents, and managing shared task lists. This was the coordination layer I'd been building by hand, but implemented at the platform level.

v3.0 threw away the custom module locking, the orchestrator rules, the `.context/` directory, and the slash commands. Everything was replaced with native primitives: `TeamCreate`, `TaskCreate`, `SendMessage`, `TaskList`, `TeamDelete`. The 4-file pattern was replaced with compaction-aware context management using `TodoWrite`.

The lead agent operates in delegate mode (Shift+Tab), restricting itself to coordination tools. No code editing. It spawns teammates, assigns scoped tasks, monitors progress, and synthesizes results. Teammates work independently, each in their own context window, communicating through `SendMessage`.

### v3.1: Mechanical enforcement (February 2026)

The realization that made v3.1 necessary: prose-based instructions are medium-reliability enforcement. An agent told "use TDD" will use TDD most of the time. An agent told "don't touch files outside your scope" will comply most of the time. But "most of the time" isn't good enough when you have three teammates running in parallel.

v3.1 added shell hooks that make quality gates mechanical:

* **TaskCompleted hook**: when a teammate marks work done, a shell script runs the test suite. If tests fail, the completion is rejected with feedback. The teammate can't finish until tests pass. No exceptions. No "I'll fix it later."
* **TeammateIdle hook**: when a teammate finishes and goes idle, a shell script checks `features.json` for remaining work. If pending features exist, the teammate gets auto-assigned. No wasted capacity.
* **PostToolUse hook**: after every file edit, a stack-specific type/build check runs. TypeScript gets `tsc --noEmit`. Swift gets `swift build`. Python gets `py_compile`. Errors caught at the keystroke, not at the commit.

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

## Architecture

### Global (travels with you)

```
~/.claude/
├── CLAUDE.md                                         # Core engineering standards (all projects)
├── rules/
│   ├── engineering-standards.md                       # Global rules (always loaded)
│   ├── agent-teams-protocol.md                        # Agent Teams rules (harness projects only)
│   └── non-harness-workflow.md                        # Planning workflow (non-harness projects only)
└── skills/
    ├── harness-init/
    │   ├── SKILL.md                                   # /harness-init skill
    │   ├── init.sh.template                           # Build/test script template
    │   ├── verify-task-quality.sh.template             # TaskCompleted hook
    │   └── check-remaining-tasks.sh.template           # TeammateIdle hook
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
│       └── check-remaining-tasks.sh                   # TeammateIdle auto-reassignment
└── .harness/
    ├── harness.json                                   # Config + git identity + team structure
    ├── features.json                                  # Feature tracking (with scope, dependencies)
    ├── context_summary.md                             # Decisions, patterns, gotchas, active context
    ├── claude-progress.txt                            # Session-boundary handoff
    └── init.sh                                        # Build/test script
```

## Three tiers of enforcement

The real insight from iterating through these versions: there are three reliability tiers for agent coordination, and you need to know which tier each rule lives in.

**Mechanical (shell hooks, exit codes)**: very high reliability. The `TaskCompleted` hook runs the test suite. If tests fail, the completion is rejected. The agent can't bypass this. It's not an instruction; it's physics.

**Structural (file existence, JSON schema)**: high reliability. `features.json` requiring `test_file` and `coverage` fields. The `.harness/` directory gating mode selection. Agents respect structure more than prose.

**Instructional (prose in CLAUDE.md, rules, skills)**: medium reliability. "Use TDD." "Don't modify files outside scope." "Verify git identity before push." These work most of the time. Over long contexts, compliance drifts.

The progression from v2.0 to v3.2 is the story of promoting critical rules from instructional to mechanical enforcement. TDD went from "please use TDD" to a shell hook that rejects non-passing code. Idle reassignment went from "check for remaining work" to an automatic hook. The rules that matter most should be the ones agents can't skip.

## Core principles

These have held steady across all versions:

* **Predictable input**: When Claude orchestrates and starts sub-agents, each sub-agent verifies the initialization state is the same, avoiding tangents to fix things outside the defined prompt.

* **Prescribed output format**: Each sub-agent has defined exit expectations: testing, checks, status updates. When they return to the orchestrator, they all return at the same level of quality.

* **Progressive discovery**: Context storage is hierarchical to protect the agent's context window. Drop MCP tools if they're not necessary. If there's an API, prefer to ask the sub-agent to build the necessary API calls based on documentation rather than loading 100 tools in context.

* **Mechanical over instructional**: If a rule matters enough to write down, it matters enough to enforce with a hook. Shell scripts don't drift over long contexts.

* **Filesystem as connective tissue**: Not because files are the optimal data structure for agent memory (they're not), but because they're the optimal trade-off between simplicity, transparency, and effectiveness.

## What remains unsolved

* **Scope enforcement**: Teammates told "don't touch files outside your scope" will sometimes violate. No mechanical enforcement of scope boundaries today. This is the next rule to promote from instructional to mechanical.

* **Session resumption**: If the lead session dies, in-process teammates are lost. `features.json` helps reconstruct state, but the work in flight is gone. tmux mode helps, but it's a mitigation, not a solution.

* **Git identity verification**: The harness captures git identity at init and stores it in `harness.json`. But verifying it before every push is still instructional. A PreToolUse hook on git commands could make this mechanical.

* **Cost modeling**: Agent Teams cost is hard to predict. Lead overhead, SendMessage round-trips, TeammateIdle re-assignment, and Phase 1 planning all vary by project. Better cost instrumentation (logging tokens per role) would help.

* **SendMessage reliability**: The `plan_approval_response` delivery bug suggests other message types might have similar issues. The harness works around the known bug, but systematic message delivery testing would build more confidence.

## Getting started

Everything you need is in this repo:

1. Download [harness-v3.2.1.zip](https://github.com/oeftimie/vv-claude-harness/releases)
2. Follow the [INSTALL.md](./INSTALL.md) instructions
3. Review the [CLAUDE.md](./claude/CLAUDE.md) for core engineering standards

### Quick install

```bash
unzip harness-v3.2.1.zip
cp claude/CLAUDE.md ~/.claude/CLAUDE.md
cp -r claude/rules/*.md ~/.claude/rules/
cp -r claude/skills/harness-init ~/.claude/skills/
cp -r claude/skills/harness-continue ~/.claude/skills/

# Enable Agent Teams
echo 'export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1' >> ~/.zshrc
source ~/.zshrc
```

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
| `rules/engineering-standards.md` | Global rules (always loaded) |
| `rules/agent-teams-protocol.md` | Agent Teams coordination (harness projects only) |
| `rules/non-harness-workflow.md` | Planning workflow (non-harness projects only) |
| `skills/harness-init/` | Project initialization with hooks and scaffolding |
| `skills/harness-continue/` | Session continuation with team spawn templates |

## Some screenshots from my sessions

<img width="1248" height="1076" alt="Screenshot 2026-01-09 at 12 47 25" src="https://github.com/user-attachments/assets/25b4be66-c384-4225-92a6-cd4d2c8964a8" />
<img width="849" height="766" alt="Screenshot 2026-01-09 at 12 42 01" src="https://github.com/user-attachments/assets/031c3dfb-4a35-4b6b-bac9-200049c7ee28" />

### UI test automation with Xcode & Claude Code

https://github.com/user-attachments/assets/9684d120-3cbf-438d-a01f-469387f507ff

---

## Changelog

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
