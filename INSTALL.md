# Claude Code Harness Installation

## Quick Install

```bash
claude plugins install /path/to/vv-claude-harness

# Verify
claude plugins list
```

## What's Included

```
claude-plugin.json
commands/
├── project-harness-init.md      # /project:harness-init command
└── project-harness-continue.md  # /project:harness-continue command
agents/
├── harness-initializer.md       # First session agent
└── harness-coding-agent.md      # Subsequent session agent
skills/
└── harness-overview.md          # Harness overview and guidance
templates/
├── init.sh                      # Multi-language build/test script
├── harness.json                 # Project config template
├── features.json                # Feature list template
└── claude-progress.txt          # Progress log template
```

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
