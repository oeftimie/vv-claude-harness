# Long-Running Agent Harness

A setup for multi-session projects where work spans many context windows.

Based on:
- [Anthropic: Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Manus-style planning-with-files pattern](https://github.com/OthmanAdi/planning-with-files)

---

## Quick Start

```bash
# First session: initialize project
cd ~/Projects/MyApp
claude
/project:harness-init
# Describe what you want to build...

# Every subsequent session: continue work
claude
/project:harness-continue
```

---

## How It Works

### File Structure (in ~/.claude/)

```
~/.claude/
├── commands/
│   ├── project-harness-init.md      # Slash command entry point
│   └── project-harness-continue.md  # Slash command entry point
└── harness/
    ├── initializer-prompt.md        # Full instructions (referenced by command)
    ├── coding-agent-prompt.md       # Full instructions (referenced by command)
    └── templates/
        ├── init.sh                  # Copied into your project
        ├── harness.json             # Copied into your project (multi-stack)
        ├── features.json            # Copied into your project
        ├── claude-progress.txt      # Copied into your project
        └── context_summary.md       # Copied into your project
```

### Invocation Flow

```
You type: /project:harness-init
                │
                ▼
Claude reads: ~/.claude/commands/project-harness-init.md
                │
                ▼
Command says: "Read ~/.claude/harness/initializer-prompt.md"
                │
                ▼
Claude reads full instructions
                │
                ▼
Claude uses templates from ~/.claude/harness/templates/
                │
                ▼
Creates scaffolding in YOUR project directory
```

**Commands** are lightweight entry points with quick reference summaries.
**Prompts** contain the full detailed instructions.
**Templates** are copied into your project during initialization.

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

**Invoke:** `/project:harness-init`

Creates the scaffolding that enables incremental work:

| Artifact | Purpose |
|----------|---------|
| `.harness.json` | Project configuration (tech stacks) |
| `init.sh` | Script to start dev environment, run smoke test |
| `features.json` | Comprehensive feature list (JSON, all `passes: false`) |
| `claude-progress.txt` | Log of what each agent session accomplished |
| `context_summary.md` | Persistent context across sessions |
| Initial git commit | Baseline for all future work |

**Full instructions:** `~/.claude/harness/initializer-prompt.md`

### Phase 2: Coding Agent (All Subsequent Sessions)

**Invoke:** `/project:harness-continue`

Makes incremental progress, one feature at a time:

| Action | Purpose |
|--------|---------|
| Read progress files | Understand where previous agent left off |
| Run `init.sh` | Verify environment works before changing anything |
| Pick ONE feature | Avoid scope creep and context exhaustion |
| Test end-to-end | Only mark `passes: true` after real testing |
| Update artifacts | Leave clear handoff for next agent |
| Commit progress | Never leave uncommitted changes |

**Full instructions:** `~/.claude/harness/coding-agent-prompt.md`

---

## Multi-Language Support

The `init.sh` script supports multiple tech stacks via auto-detection or explicit configuration.

### Auto-Detection

If no `.harness.json` exists, `init.sh` detects:

| Stack | Detection |
|-------|-----------|
| iOS/Swift | `*.xcodeproj`, `*.xcworkspace`, `Package.swift` |
| Node.js | `package.json` |
| Python | `requirements.txt`, `pyproject.toml`, `setup.py` |
| Go | `go.mod` |
| Rust | `Cargo.toml` |

### Explicit Configuration

For multi-stack projects, the initializer creates `.harness.json`:

```json
{
  "project": "MyFullStackApp",
  "stacks": [
    {"name": "ios", "path": "./", "scheme": "MyApp"},
    {"name": "node", "path": "./backend"}
  ],
  "smoke_test": "./scripts/e2e-test.sh"
}
```

### Local Overrides (Optional)

For machine-specific settings that shouldn't be committed to git, create `.harness-local.sh`:

```bash
# .harness-local.sh - Machine-specific overrides (add to .gitignore)

# Override iOS scheme for this machine
export IOS_SCHEME="MyApp-Debug"

# Local environment variables
export NODE_ENV="development"
export DATABASE_URL="postgres://localhost/dev"

# Custom smoke test function (optional)
smoke_test() {
    curl -sf http://localhost:3000/health || exit 1
}
```

**When to use:**
- Different iOS schemes per developer machine
- Local database URLs or API keys
- Custom smoke tests for your environment
- Paths that vary between machines

**Note:** Add `.harness-local.sh` to your `.gitignore`. It's sourced by `init.sh` if present.

---

## File Structure (in your project)

```
project/
├── .harness.json           # Project configuration (created by initializer)
├── .harness-local.sh       # Machine-specific overrides (optional, gitignored)
├── init.sh                 # Environment startup script (created by initializer)
├── features.json           # Feature list with test tracking (created by initializer)
├── claude-progress.txt     # Agent session log (created by initializer, updated each session)
├── context_summary.md      # Persistent context (created by initializer, updated each session)
├── task_plan.md            # Current task plan (created per-session by coding agent)
├── notes.md                # Research notes (created per-session by coding agent)
├── tests/                  # Test files (created by coding agent, referenced in features.json)
└── .git/                   # Version control (essential)
```

**Initializer creates:** `.harness.json`, `init.sh`, `features.json`, `claude-progress.txt`, `context_summary.md`

**Coding agent creates/updates:** `task_plan.md`, `notes.md`, test files; updates `features.json` (passes, test_file, coverage), `claude-progress.txt`, `context_summary.md`

---

## Why JSON for Features?

From Anthropic's research:

> After some experimentation, we landed on using JSON for this, as the model is less likely to inappropriately change or overwrite JSON files compared to Markdown files.

The structured format with explicit `"passes": false` creates a clear contract. The agent can only flip the boolean, not redefine what success means.

---

## Session Flow

### First Session
```
1. cd into project directory
2. Run: /project:harness-init
3. Describe what you want to build
4. Initializer creates scaffolding
5. Initializer commits to git
6. Initializer reports completion
```

### Every Subsequent Session
```
1. cd into project directory
2. Run: /project:harness-continue
3. Agent reads progress files + git log
4. Agent runs init.sh (smoke test)
5. Agent picks highest-priority incomplete feature
6. Agent implements + tests ONE feature
7. Agent updates all artifacts
8. Agent commits progress
9. Agent hands off to next session
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
- NEVER mark `passes: true` without automated tests
- NEVER mark `passes: true` with coverage < 95% for touched code
- NEVER leave the codebase in a broken state
- NEVER ask Ovidiu to test manually when tooling works

---

## Testing Requirements

### Coverage Threshold

**95% coverage required** for code touched by each feature.

The coding agent runs all tests and reports coverage. A feature is not complete without automated tests.

### Test Tooling

| Stack | Test Runner | Coverage |
|-------|-------------|----------|
| iOS/Swift | `xcodebuild test` | Xcode reports |
| Node.js | `npm test -- --coverage` | Jest/nyc |
| Python | `pytest --cov=.` | pytest-cov |
| Go | `go test -cover ./...` | Built-in |
| Rust | `cargo tarpaulin` | tarpaulin |

### Browser E2E Tests

For web applications requiring browser automation:
- Assumes **Playwright MCP** is installed
- If unavailable, agent reports to user and requests help configuring

### Test Tracking

Each feature in `features.json` tracks:
```json
{
  "passes": true,
  "test_file": "tests/test_feature.py",
  "coverage": 97.2
}
```

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

## Installation

```bash
# Unzip and copy to ~/.claude/
unzip claude-harness.zip
cp -r claude/* ~/.claude/

# Make template executable
chmod +x ~/.claude/harness/templates/init.sh

# Verify
ls ~/.claude/commands/project-harness-*.md
ls ~/.claude/harness/*.md
```

### Dependencies

The `init.sh` script requires:

| Dependency | Required | Purpose |
|------------|----------|---------|
| `jq` | Yes | JSON parsing for `.harness.json` |
| `xcpretty` | No (iOS only) | Prettier Xcode build output |

**Install on macOS:**
```bash
brew install jq
gem install xcpretty  # Optional, for iOS
```

### Verify Commands Work

```bash
cd ~/Projects/SomeProject
claude
# Type: /project:harness
# Should autocomplete to harness-init and harness-continue
```

---

## References

- [Anthropic Engineering: Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Claude 4 Best Practices: Multi-context window workflows](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-4-best-practices)
- [Claude Agent SDK Quickstart](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)
