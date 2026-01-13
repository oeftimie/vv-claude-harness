# Initialize Long-Running Project Harness

Run this command to set up a project for multi-session work.

---

## Pre-Flight Check

Before initializing, verify:
- [ ] Git repository exists (or will create one)
- [ ] Project requirements are clear
- [ ] This is a multi-session project (not a quick task)

---

## Initialization Steps

### Step 1: Create Scaffolding Files

Create these files in the project root:

**init.sh:**
```bash
#!/bin/bash
# Customize for your project's tech stack
set -e
echo "=== Session Initialization ==="
echo "[1/3] Installing dependencies..."
# Add your dependency commands
echo "[2/3] Starting development server..."
# Add your server start command
echo "[3/3] Running smoke test..."
# Add your smoke test
echo "=== Initialization Complete ==="
```

**features.json:**
```json
{
  "project": "[PROJECT_NAME]",
  "created": "[DATE]",
  "total_features": 0,
  "passing": 0,
  "features": []
}
```

**claude-progress.txt:**
```
# Progress Log

Read this at the START of every session.

---

## Session 1: Initialization
Date: [DATE]
Agent: Initializer
Status: Pending

### To Create:
- [ ] init.sh
- [ ] features.json (populated)
- [ ] context_summary.md
- [ ] Initial git commit

---
```

### Step 2: Analyze Requirements

Based on the user's prompt, create a comprehensive feature list:
- Expand high-level requirements into specific, testable features
- Each feature should have clear verification steps
- Order by priority (dependencies first)
- Aim for 10-50+ features for complex projects

### Step 3: Populate features.json

For each feature:
```json
{
  "id": "F001",
  "category": "core|auth|ui|api|etc",
  "description": "Specific, testable description",
  "priority": 1,
  "steps": [
    "What to do",
    "What to verify",
    "Expected outcome"
  ],
  "passes": false,
  "notes": ""
}
```

### Step 4: Create context_summary.md

Initialize with:
- Active Context: "Project initialized, ready for F001"
- Cross-Cutting Concerns: Tech stack, constraints
- Domain sections as needed

### Step 5: Git Commit

```bash
chmod +x init.sh
git add .
git commit -m "Initialize multi-session harness"
```

### Step 6: Update claude-progress.txt

Mark initialization complete, note what's ready for next agent.

---

## Handoff

After initialization:
1. Report to Ovidiu what was created
2. Summarize feature count and categories
3. Confirm first feature (F001) is ready for implementation
4. Next session should use coding-agent-prompt.md

---

## Do NOT

- Implement any features (that's for coding agent)
- Skip any scaffolding files
- Leave features.json empty
- Forget the git commit
