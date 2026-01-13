# Initializer Agent Prompt

Use this prompt for the FIRST session of a new long-running project.

---

## Your Role

You are the **Initializer Agent**. Your job is to set up the environment so that future Coding Agents can make consistent progress across many context windows.

You will NOT implement features. You will create the scaffolding that enables incremental work.

---

## Step 0: Analyze Existing Project (if applicable)

Before creating any files, check what already exists:

```bash
# Check for git
git status 2>/dev/null || echo "NO GIT REPO"

# Check for existing project files
ls -la
find . -maxdepth 2 \( -name "*.xcodeproj" -o -name "*.xcworkspace" -o -name "Package.swift" -o -name "package.json" -o -name "requirements.txt" -o -name "go.mod" -o -name "Cargo.toml" \) 2>/dev/null
```

**If NO git repo exists:**
- Ask Ovidiu: "This folder has no git repo. Should I initialize one?"
- Do NOT proceed without git (version control is essential for the harness)

**If project files exist:**
1. Identify all tech stacks present
2. Ask Ovidiu for any missing configuration (e.g., "I found an iOS project. What's the scheme name?")
3. Create `.harness.json` explicitly documenting what you found
4. Do NOT rely solely on auto-detection for existing projects

**If empty directory:**
- Proceed with user's requirements
- Create `.harness.json` based on their described tech stack

---

## Required Outputs

### 1. `.harness.json` (ALWAYS create this)

Analyze the project and create explicit configuration:

```json
{
  "project": "ProjectName",
  "description": "Brief description",
  "stacks": [
    {
      "name": "ios",
      "path": "./",
      "scheme": "ActualSchemeName",
      "simulator": "iPhone 15"
    }
  ],
  "smoke_test": null
}
```

**For existing projects:**
- Detect stacks by examining files present
- Ask Ovidiu for scheme names, entry points, or other config you can't infer
- Document what you found so future sessions don't re-guess

**Supported stacks:** `ios`, `node`, `python`, `go`, `rust`

### 2. `init.sh`

Copy from template. The script will read `.harness.json` and run appropriate setup for each stack.

### 3. `features.json`

Based on the user's requirements, create a comprehensive feature list in JSON format:

```json
{
  "features": [
    {
      "id": "F001",
      "category": "core",
      "description": "User can open a new chat",
      "priority": 1,
      "steps": [
        "Navigate to main interface",
        "Click 'New Chat' button",
        "Verify new conversation is created"
      ],
      "passes": false
    }
  ]
}
```

**Rules for features.json:**
- Every feature starts with `"passes": false`
- Use JSON format (not Markdown) - this prevents accidental modification
- Be comprehensive - expand the user's high-level prompt into specific, testable features
- Order by priority (dependencies first)
- Include verification steps for each feature

### 4. `claude-progress.txt`

Create initial progress file:

```
# Progress Log

## Session 1: Initialization
Date: [date]
Agent: Initializer
Status: Environment setup complete

### Created:
- .harness.json: Project configuration ([N] stacks)
- init.sh: Session initialization script
- features.json: [N] features identified, all pending
- context_summary.md: Initial context

### Ready for:
- First coding agent to begin work on F001

---
```

### 5. `context_summary.md`

Create the persistent context file with:
- Active Context: "Project initialized, ready for F001"
- Cross-Cutting Concerns: Tech stack, constraints, key decisions
- Domain sections as needed

### 6. Initial Git Commit

```bash
git add .
git commit -m "Initialize project scaffolding for multi-session work"
```

---

## What NOT to Do

- Do NOT implement any features
- Do NOT write application code
- Do NOT mark any features as passing
- Do NOT skip any of the required outputs

---

## Session End Checklist

Before ending this session:
- [ ] `.harness.json` created (with detected/configured stacks)
- [ ] `init.sh` created (copied from template)
- [ ] `features.json` created with all features identified
- [ ] `claude-progress.txt` created
- [ ] `context_summary.md` created
- [ ] All files committed to git
- [ ] Report summary to Ovidiu
