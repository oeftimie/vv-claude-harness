# Claude Code Harness v2.1 Installation

## What's New in v2.1

This version uses Claude Code's native memory system:
- **`.claude/rules/`** - Auto-loaded rule files
- **Path-scoped rules** - Harness rules only active in harness projects
- **`@import` syntax** - CLAUDE.md imports harness documentation
- **Slimmer CLAUDE.md** - Core standards only, orchestration in rules/

## Quick Install

```bash
# 1. Extract
unzip claude-harness-v2.1.zip

# 2. Backup existing CLAUDE.md (if customized)
cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.backup 2>/dev/null

# 3. Copy to ~/.claude/
cp -r claude/* ~/.claude/

# 4. Copy templates (used by harness-init command)
mkdir -p ~/.claude/templates
cp -r templates/* ~/.claude/templates/

# 5. Make init.sh template executable
chmod +x ~/.claude/templates/init.sh

# 6. Verify
ls ~/.claude/CLAUDE.md
ls ~/.claude/rules/
ls ~/.claude/commands/
ls ~/.claude/skills/
```

## Package Structure

```
claude-harness-v2.1.zip
├── INSTALL.md
├── claude/
│   ├── CLAUDE.md                    # Core standards + @imports
│   ├── rules/
│   │   ├── orchestrator.md          # 4-file pattern, sub-agents
│   │   └── harness/
│   │       ├── coding-agent.md      # Path-scoped: .harness/**
│   │       ├── module-locking.md    # Path-scoped: .context/**
│   │       └── scheduling.md        # Path-scoped: .harness/**
│   ├── commands/
│   │   ├── project-harness-init.md
│   │   └── project-harness-continue.md
│   └── skills/
│       └── context-graph/
│           └── SKILL.md
└── templates/
    ├── features.json
    ├── modules.yaml
    ├── harness.json
    ├── claude-progress.txt
    ├── context_summary.md
    ├── task_plan.md                 # 4-file pattern
    ├── notes.md                     # 4-file pattern
    └── init.sh
```

## After Installation

```
~/.claude/
├── CLAUDE.md                        # Your core standards
├── rules/
│   ├── orchestrator.md              # Always loaded
│   └── harness/
│       ├── coding-agent.md          # Loaded when in harness project
│       ├── module-locking.md        # Loaded when in harness project
│       └── scheduling.md            # Loaded when in harness project
├── commands/
│   ├── project-harness-init.md
│   └── project-harness-continue.md
├── skills/
│   └── context-graph/
│       └── SKILL.md
└── templates/                       # For project initialization
        ├── features.json
        ├── modules.yaml
        ├── harness.json
        ├── claude-progress.txt
        ├── context_summary.md
        ├── task_plan.md
        ├── notes.md
        └── init.sh
```

## How It Works

### Auto-Loading

Claude Code automatically loads:
1. `~/.claude/CLAUDE.md` - always
2. All `.md` files in `~/.claude/rules/` - always
3. Path-scoped rules only when working with matching files

### Path-Scoped Rules

Rules in `harness/` have YAML frontmatter:

```yaml
---
paths:
  - ".harness/**"
  - ".context/**"
---
```

These rules only activate when Claude works with files in those directories.

### @import Syntax

CLAUDE.md can import other files:

```markdown
@rules/orchestrator.md
@rules/harness/coding-agent.md
```

## Usage

### Initialize Project

```bash
cd ~/Projects/MyApp
git init
claude
/project:harness-init
```

### Continue Working

```bash
cd ~/Projects/MyApp
claude
/project:harness-continue
```

## Upgrading

### From v2.0

1. Install v2.1 (will restructure files)
2. Your features.json and modules.yaml remain compatible
3. New path-scoped rules replace monolithic prompts

### From v1.x

1. Backup `~/.claude/CLAUDE.md`
2. Install v2.1
3. Merge custom sections from backup
4. For each project, run `/project:harness-init`

## Customization

### Add Custom Rules

Create files in `~/.claude/rules/`:

```markdown
# ~/.claude/rules/my-custom-rules.md

## My Team's Conventions
- Always use conventional commits
- ...
```

### Path-Scoped Custom Rules

```yaml
---
paths:
  - "src/api/**"
---

# API Rules
All endpoints must have OpenAPI docs...
```

## Troubleshooting

### Rules not loading

Check with `/memory` command in Claude Code.

### Path-scoped rules not activating

Ensure YAML frontmatter is at the very top of the file with no leading whitespace.
