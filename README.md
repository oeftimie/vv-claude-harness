# Ovidiu's Claude Code Harness v2.1

A harness system for Claude Code combining Anthropic's guidelines for long-running tasks, the [Manus-style persistent markdown planning](https://github.com/OthmanAdi/planning-with-files), and module-level locking for parallel agent coordination.

---

Every AI coding agent has the same Achilles heel: memory. Not the technical kind (context windows are growing). The practical kind. Start a complex project with Claude Code or Cursor. Work for an hour. Hit a context limit or close the session. Come back the next day. The agent has no idea what happened. It's like onboarding a new contractor every morning who's never seen the codebase.

This isn't a model problem. It's an infrastructure "harness" problem. And solving it requires thinking about agents less like chat interfaces and more like software systems that need state management.

## The shift problem

Anthropic's engineering team articulated this beautifully in their [research on effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): imagine a software project staffed by engineers working in shifts, where each new engineer arrives with no memory of what happened on the previous shift. That's exactly what happens with AI agents across context windows. Session ends. Context compacts or resets. New session starts fresh. The agent might have access to the files it created, but it has no memory of why it created them, what worked, what failed, or what comes next.

Two failure patterns emerge consistently:
* First, the agent tries to do too much in a single session; it "one-shots" the entire project, runs out of context mid-implementation, and leaves a half-built mess for the next session to puzzle over.
* Second (and more insidious), after making some progress, the agent looks around, sees working code, and declares victory. The project is 30% complete but the agent thinks it's done.

Both failures stem from the same root cause: no persistent memory of intent, progress, or remaining work.

**v2.1 adds a third failure pattern this harness now addresses**: parallel agents stepping on each other. When you spawn multiple coding agents to work faster, they can modify the same files, create merge conflicts, or make incompatible changes. Without coordination, parallelism creates chaos.

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

## The combined harness v2.1

Building on both approaches, I've built a combined harness for long-running projects. Version 2.1 adds module locking for safe parallel work.

### Architecture

The harness uses Claude Code's native memory system:

```
~/.claude/                              # Global (travels with you)
├── CLAUDE.md                           # Core engineering standards
├── rules/
│   ├── orchestrator.md                 # 4-file pattern, sub-agent management
│   └── harness/
│       ├── coding-agent.md             # Path-scoped coding rules
│       ├── module-locking.md           # Path-scoped locking rules
│       └── scheduling.md               # Path-scoped scheduling rules
├── commands/
│   ├── project-harness-init.md
│   └── project-harness-continue.md
├── skills/
│   └── context-graph/
│       └── SKILL.md                    # Module claim/release
└── templates/                          # For project initialization
```

```
project-root/                           # Per-project (travels with repo)
├── .harness/
│   ├── features.json                   # Feature tracking
│   ├── claude-progress.txt             # Session log
│   ├── harness.json                    # Project config
│   └── init.sh                         # Build/test script
├── .context/
│   └── modules.yaml                    # Module map + locks
├── context_summary.md                  # Persistent learnings
├── task_plan.md                        # Current task phases
└── notes.md                            # Research notes
```

### Components

**1. Initializer**

The initialization phase runs once, at project start. It doesn't write code. It creates scaffolding: a feature list expanded from your high-level prompt, a progress log initialized for tracking, a context file capturing decisions and constraints, a module map defining code boundaries, and a build script that verifies the environment works.

The initializer's job is to transform "build me an app" into a structured work breakdown that subsequent sessions can execute against.

**2. Module map**

New in v2.1. The `.context/modules.yaml` file defines code boundaries:

```yaml
modules:
  auth:
    paths:
      - src/auth/
      - src/handlers/auth/
    locked_by: null
    locked_for: null

  payments:
    paths:
      - src/payments/
    locked_by: "session-xyz"
    locked_for: "F002 - Add Stripe integration"
```

Before a coding agent modifies code, it claims the relevant modules. If another agent already holds a lock, the agent reports to the orchestrator and waits. One agent per module at a time. Conflicts prevented, not resolved.

**3. Session protocol**

The main Claude instance acts as an orchestrator for all coding agents. The harness provides the standard structure in which all sub-agents start their work, making execution predictable in terms of input and expected output.

When a session starts, the coding agent:
1. Reads the progress log ("what happened?")
2. Checks the feature list ("what's left?")
3. Checks module locks ("what's available?")
4. Claims modules for the selected feature
5. Runs the build script ("does it still work?")
6. Reads the context file ("what should I remember?")

Only then does it start coding.

At session end, the agent:
1. Runs all tests
2. Updates the feature list
3. Appends to the progress log
4. Updates context_summary.md with learnings
5. Releases module locks
6. Commits with a clean handoff

**4. Single-feature rule**

Each session works on exactly one feature. Not two. Not "as many as I can." This forces incremental progress. The agent can't exhaust context trying to build everything at once because the harness explicitly forbids it.

**5. End-to-end verification**

The agent can't mark a feature complete just because it wrote the code. It has to actually test it. Not unit tests alone (they can pass while the feature is broken). Not manual inspection (the agent can convince itself anything works). Real verification that proves the feature actually functions.

## Module locking for parallel work

The v2.1 addition that enables safe parallelism.

### The problem

You want to speed up development by running multiple agents in parallel. Agent A works on authentication. Agent B works on payments. But what if both need to modify a shared utility file? Or what if Agent C wants to work on a feature that touches authentication while Agent A is still working?

Without coordination, you get:
- Merge conflicts
- Incompatible changes
- Silent overwrites
- Agents fixing each other's "bugs" that were actually in-progress work

### The solution

Module locking. Before an agent touches code, it claims the modules it needs:

```
Use context-graph skill: claim
Modules needed: [auth, database]
Feature: F003 - Add password reset
```

If all modules are available, the agent gets exclusive access. If any are locked, the agent stops and reports to the orchestrator.

The orchestrator then schedules work based on module availability:

```
Feature    | Modules Required | Available? | Assignable?
-----------|------------------|------------|------------
F001       | [auth, db]       | auth: NO   | BLOCKED
F002       | [payments]       | YES        | YES
F003       | [api]            | YES        | YES
```

Agents A and B work in parallel on non-overlapping modules. Agent C waits until Agent A releases auth. Maximum parallelism within the constraint of conflict-free work.

## The init.sh script

I initially started my exploration building iOS apps. Now at the second iteration with this harness, I adapted it to be used for multiple programming languages. Every session starts by running `init.sh`, which installs dependencies, builds the project, and runs a smoke test. If `init.sh` fails, the agent fixes it before doing anything else.

This seems minor but it's load-bearing. Without it, agents accumulate subtle environment drift across sessions. Dependencies get out of sync. Build configurations rot. The agent starts a session, tries to work, hits a mysterious failure, spends half its context debugging something that has nothing to do with the feature it's supposed to build.

For multi-language projects (iOS app with a Node backend, say), the script auto-detects or reads from a config file:

```json
{
  "stacks": [
    {"name": "ios", "path": "./", "scheme": "MyApp"},
    {"name": "node", "path": "./backend"}
  ]
}
```

Each stack gets its own initialization. If any fails, the session stops and fixes before proceeding.

## Why this combination works

The Anthropic approach and the Manus approach complement each other precisely because they solve different parts of the problem.

Anthropic's two-phase architecture solves the **macro problem**: how do you structure work across many sessions? You need an initializer that creates the structure. You need coding agents that follow the structure. You need artifacts that bridge sessions.

The Manus planning-with-files pattern solves the **micro problem**: how does an agent stay focused within a session? You externalize findings instead of stuffing context. You re-read the plan before decisions. You log errors to avoid repetition.

Module locking solves the **parallel problem**: how do multiple agents work simultaneously without conflicts? You define boundaries. You enforce exclusive access. You let the orchestrator schedule non-overlapping work.

Putting them together: the initializer creates `features.json` (Anthropic pattern), `modules.yaml` (coordination), and `task_plan.md` (Manus pattern). The coding agent reads `claude-progress.txt` (Anthropic pattern), claims modules (coordination), and writes to `notes.md` (Manus pattern). The session protocol ensures clean handoffs (Anthropic pattern) while module locking ensures parallel safety (coordination).

The filesystem becomes the connective tissue. Not because files are the optimal data structure for agent memory (they're not), but because they're the optimal trade-off between simplicity, transparency, and effectiveness.

## Core principles

As I've seen working reliably:

* **Predictable input**: When Claude orchestrates and starts sub-agents, we provide a way for each sub-agent to verify the initialization state is the same, avoiding tangents to fix things outside the defined prompt.

* **Prescribed output format**: We define for each sub-agent what the exit expectations are: testing, checks, module release. When they return to the orchestrator, they all return at the same level of quality.

* **Progressive discovery**: Context storage is hierarchical to protect the agent's context window. Drop MCP tools if they're not necessary. If there's an API, prefer to ask the sub-agent to build the necessary API calls based on documentation rather than loading 100 tools in context.

* **Parallel safety** (new in v2.1): Module boundaries are explicit. Locking is mandatory. One agent per module. The orchestrator schedules non-conflicting work.

## What remains unsolved

This harness addresses core challenges of multi-session continuity and parallel coordination, but questions remain:

* **Granularity**: What's the right size for features? Too coarse and you're back to one-shotting. Too fine and you spend all your time on coordination overhead. The sweet spot probably varies by project.

* **Module boundaries**: How do you define modules in a codebase that wasn't designed with boundaries? The harness requires explicit module definitions, but legacy codebases often have tangled dependencies.

* **Beyond coding**: How do these patterns generalize to research, writing, or analysis tasks? The file patterns likely transfer, but the specifics (what's the equivalent of `modules.yaml` for a research project?) remain to be worked out.

* **Orchestrator context**: Even with sub-agents doing the work, the orchestrator accumulates context. For very large projects, orchestrator context management becomes its own challenge.

## Getting started

Everything you need is in this repo:

1. Download [claude-harness-v2.1.zip](https://github.com/oeftimie/vv-claude-harness/releases)
2. Follow the [INSTALL.md](./INSTALL.md) instructions
3. Review my [CLAUDE.md](./claude/CLAUDE.md) for the core engineering standards

### Quick install

```bash
unzip claude-harness-v2.1.zip
cp -r claude/* ~/.claude/
mkdir -p ~/.claude/templates && cp -r templates/* ~/.claude/templates/
chmod +x ~/.claude/templates/init.sh
```

### Usage

```bash
# Initialize a new project
cd ~/Projects/MyApp
git init
claude
/project:harness-init

# Continue working
claude
/project:harness-continue
```

### What's in the box

| Component | Purpose |
|-----------|---------|
| `CLAUDE.md` | Core engineering standards |
| `rules/orchestrator.md` | 4-file pattern, sub-agent management |
| `rules/harness/*.md` | Path-scoped rules for harness projects |
| `commands/*.md` | Slash commands for init and continue |
| `skills/context-graph/` | Module locking skill |
| `templates/` | Project scaffolding templates |

## Some screenshots from my sessions

<img width="1248" height="1076" alt="Screenshot 2026-01-09 at 12 47 25" src="https://github.com/user-attachments/assets/25b4be66-c384-4225-92a6-cd4d2c8964a8" />
<img width="849" height="766" alt="Screenshot 2026-01-09 at 12 42 01" src="https://github.com/user-attachments/assets/031c3dfb-4a35-4b6b-bac9-200049c7ee28" />

### UI test automation with Xcode & Claude Code

https://github.com/user-attachments/assets/9684d120-3cbf-438d-a01f-469387f507ff

---

## Changelog

### v2.1 (2025-02-01)
- Added module locking for parallel agent coordination
- Added `.context/modules.yaml` for defining code boundaries
- Added context-graph skill (claim/release/status/force-release)
- Restructured to use Claude Code's native memory system (`rules/`, `@imports`)
- Added path-scoped rules that activate only in harness projects
- Added `modules_required` and `assigned_to` fields to features.json
- Separated CLAUDE.md (core standards) from orchestration rules

### v2.0 (2025-01-24)
- Initial public release
- Two-phase architecture (initializer + coding agents)
- 4-file pattern integration
- Multi-language init.sh support
