---
name: harness-overview
description: Explain the long-running agent harness and when to use it.
---

# Long-Running Agent Harness

A setup for multi-session projects where work spans many context windows.

Based on:
- [Anthropic: Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- Claude 4 Best Practices: Multi-context window workflows

---

## The Problem

> Each new session begins with no memory of what came before. Imagine engineers working in shifts, where each new engineer arrives with no memory of what happened on the previous shift.

**Failure modes without a harness:**

| Failure | What Happens |
|---------|--------------|
| One-shotting | Agent tries to do too much, runs out of context mid-implementation, leaves half-done undocumented work |
| Premature victory | Agent sees progress was made, declares job done before it's actually complete |
| Context loss | Agent has to guess what previous agent was doing, wastes time re-orienting |
| Regression | Agent breaks previously-working features while implementing new ones |

---

## The Solution: Two-Phase Architecture

### Phase 1: Initializer Agent (First Session Only)

Creates the scaffolding that enables incremental work:

| Artifact | Purpose |
|----------|---------|
| `init.sh` | Script to start dev environment, run smoke test |
| `features.json` | Comprehensive feature list (JSON, all `passes: false`) |
| `claude-progress.txt` | Log of what each agent session accomplished |
| `context_summary.md` | Persistent context across sessions |
| Initial git commit | Baseline for all future work |

**Prompt:** Use `initializer-prompt.md`

### Phase 2: Coding Agent (All Subsequent Sessions)

Makes incremental progress, one feature at a time:

| Action | Purpose |
|--------|---------|
| Read progress files | Understand where previous agent left off |
| Run `init.sh` | Verify environment works before changing anything |
| Pick ONE feature | Avoid scope creep and context exhaustion |
| Test end-to-end | Only mark `passes: true` after real testing |
| Update artifacts | Leave clear handoff for next agent |
| Commit progress | Never leave uncommitted changes |

**Prompt:** Use `coding-agent-prompt.md`

---

## File Structure

```
project/
├── init.sh                 # Environment startup script
├── features.json           # Feature list (JSON, not Markdown)
├── claude-progress.txt     # Agent session log
├── context_summary.md      # Persistent context
├── task_plan.md            # Current task (per-session)
├── notes.md                # Research notes (per-session)
└── .git/                   # Version control (essential)
```

---

## Why JSON for Features?

From Anthropic's research:

> After some experimentation, we landed on using JSON for this, as the model is less likely to inappropriately change or overwrite JSON files compared to Markdown files.

The structured format with explicit `"passes": false` creates a clear contract. The agent can only flip the boolean, not redefine what success means.

---

## Session Flow

### First Session
```
1. Run initializer-prompt.md
2. Initializer creates scaffolding
3. Initializer commits to git
4. Initializer reports completion
```

### Every Subsequent Session
```
1. Run coding-agent-prompt.md
2. Agent reads progress files + git log
3. Agent runs init.sh (smoke test)
4. Agent picks highest-priority incomplete feature
5. Agent implements + tests ONE feature
6. Agent updates all artifacts
7. Agent commits progress
8. Agent hands off to next session
```

---

## Integration with CLAUDE.md

The harness complements your existing setup:

| Your Setup | Harness Addition |
|------------|------------------|
| `context_summary.md` | ✅ Same file, persistent context |
| `task_plan.md` | ✅ Same file, per-task planning |
| `notes.md` | ✅ Same file, per-task research |
| 4-file pattern | + `features.json` and `claude-progress.txt` |
| Checkpoints | + Session start/end routines |
| TDD | + End-to-end testing emphasis |

---

## Critical Rules (from Anthropic)

> "It is unacceptable to remove or edit tests because this could lead to missing or buggy functionality."

Translated to this harness:
- NEVER remove features from `features.json`
- NEVER edit feature descriptions to make them easier to pass
- NEVER mark `passes: true` without end-to-end testing
- NEVER leave the codebase in a broken state

---

## When to Use This Harness

**Use for:**
- Projects that will span multiple sessions
- Complex implementations that can't be done in one context window
- Projects with many discrete features
- Work where progress must be trackable

**Skip for:**
- Single-session tasks
- Quick fixes
- Research-only work
- Tasks where "done" is obvious

---

## Setup Checklist

1. [ ] Copy `initializer-prompt.md` to your prompts directory
2. [ ] Copy `coding-agent-prompt.md` to your prompts directory
3. [ ] Copy templates (`features.json`, `claude-progress.txt`, `init.sh`) from the plugin templates directory
4. [ ] For first session: use initializer prompt
5. [ ] For subsequent sessions: use coding agent prompt
6. [ ] Ensure git is initialized in project

---

## References

- [Anthropic Engineering: Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Claude 4 Best Practices: Multi-context window workflows](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-4-best-practices)
- [Claude Agent SDK Quickstart](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)
