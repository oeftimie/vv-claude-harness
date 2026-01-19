# Claude Code Harness Installation

## Quick Install

```bash
# Extract and copy to ~/.claude/
unzip claude-harness.zip
cp -r claude/* ~/.claude/

# Make init.sh template executable
chmod +x ~/.claude/harness/templates/init.sh

# Verify
ls -la ~/.claude/harness/
ls -la ~/.claude/commands/
```

## What's Included

```
claude/
├── commands/
│   ├── project-harness-init.md      # /project:harness-init (invokes initializer-prompt.md)
│   └── project-harness-continue.md  # /project:harness-continue (invokes coding-agent-prompt.md)
└── harness/
    ├── README.md                    # Documentation (optional, not used at runtime)
    ├── initializer-prompt.md        # Full instructions for first session
    ├── coding-agent-prompt.md       # Full instructions for subsequent sessions
    └── templates/
        ├── init.sh                  # Multi-language build/test script
        ├── harness.json             # Project config template
        ├── features.json            # Feature list template
        ├── claude-progress.txt      # Progress log template
        └── context_summary.md       # Persistent context template
```

## Dependencies

The `init.sh` script requires:

| Dependency | Required | Install |
|------------|----------|---------|
| `jq` | Yes | `brew install jq` |
| `xcpretty` | No (iOS only) | `gem install xcpretty` |

## How It Works

```
/project:harness-init
        │
        ▼
commands/project-harness-init.md
        │
        ▼ (references)
harness/initializer-prompt.md  ──▶  Creates scaffolding files
        │
        ▼ (uses templates from)
harness/templates/*
```

**Commands** are lightweight entry points (invoked via `/project:harness-*`).
**Prompts** contain the full detailed instructions.
**Templates** are copied into your project during initialization.

## Usage

### Start a New Project

```bash
cd ~/Projects/MyApp
git init  # or use existing repo
claude
```

Then in Claude Code:
```
/project:harness-init

Build [describe your app]...
```

### Continue Working

```bash
cd ~/Projects/MyApp
claude
```

Then:
```
/project:harness-continue
```

## Supported Languages

init.sh auto-detects or reads .harness.json for:
- iOS/Swift (*.xcodeproj, Package.swift)
- Node.js (package.json)
- Python (requirements.txt, pyproject.toml)
- Go (go.mod)
- Rust (Cargo.toml)

## Requirements

- Claude Code installed
- Git
- Language-specific tools (Xcode, Node, Python, etc.)
