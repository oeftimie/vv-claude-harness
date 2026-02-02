# /project:harness-init

Initialize a new project with harness scaffolding.

## Templates Location

Templates are in `~/.claude/templates/`. Use these as starting points.

## What It Creates

```
project-root/
├── .harness/
│   ├── harness.json           # Project config
│   ├── features.json          # Feature tracking
│   ├── claude-progress.txt    # Session log
│   └── init.sh                # Build/test script
├── .context/
│   └── modules.yaml           # Module map + locks
├── context_summary.md         # Persistent learnings (4-file pattern)
├── task_plan.md               # Current task tracking (4-file pattern)
└── notes.md                   # Research notes (4-file pattern, create as needed)
```

## Steps

1. **Gather requirements**
   - What are you building?
   - What's the tech stack?
   - Any existing code?

2. **Create .harness/** (use templates from ~/.claude/templates/)
   - harness.json with project config
   - features.json with initial features
   - claude-progress.txt initialized
   - init.sh for build/test (make executable)

3. **Analyze project structure**
   - Look for package.json, go.mod, etc.
   - Identify domain boundaries
   - Propose module map

4. **Create .context/modules.yaml**
   - Present proposed modules to user
   - Wait for confirmation
   - Create with all locks null

5. **Create 4-file pattern files**
   - context_summary.md - initialize with project context
   - task_plan.md - initialize for first task

6. **Git commit**
   ```bash
   git add .harness/ .context/ context_summary.md task_plan.md
   git commit -m "Initialize harness v2.1 scaffolding"
   ```

7. **Report completion**

## After Initialization

Run `/project:harness-continue` to start working on features.
