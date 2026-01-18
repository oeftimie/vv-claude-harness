---
name: project:harness-continue
description: Start a coding session using the long-running project harness.
---

# Continue Long-Running Project

Run this command at the START of every coding session (after initialization).

---

## Session Start Routine

Execute IN ORDER. Do not skip steps.

### Step 1: Orient
```bash
pwd
ls -la
```

Verify you're in the right project directory.

### Step 2: Read Progress Log
```bash
cat claude-progress.txt
```

Understand:
- What did the last agent work on?
- What was completed?
- What was left undone?
- What did they say the next agent should do?

### Step 3: Check Git State
```bash
git status
git log --oneline -10
```

Verify:
- No uncommitted changes from previous session
- Understand recent commits

### Step 4: Check Feature Status
```bash
cat features.json | jq '.features[] | select(.passes == false) | {id, priority, description}' | head -20
```

Or without jq:
```bash
cat features.json
```

Identify:
- Highest priority feature with `"passes": false`
- Total progress (how many passing vs total)

### Step 5: Verify Environment
```bash
./init.sh
```

If this fails:
- Fix environment issues FIRST
- Log the issue in claude-progress.txt
- Do NOT proceed to new features until environment works

### Step 6: Read Context
```bash
cat context_summary.md
```

Refresh:
- Active focus
- Cross-cutting concerns
- Relevant domain knowledge

---

## Ready to Work

After completing all 6 steps, you may begin work on ONE feature.

Remember:
- Work on ONE feature only
- Test end-to-end before marking complete
- Update all artifacts before session ends
- Commit progress frequently

---

## Session End Routine

Before ending, execute these steps:

### Step 1: Verify App Works
```bash
./init.sh
```

### Step 2: Commit All Progress
```bash
git add .
git commit -m "[Feature ID] [Brief description]"
```

### Step 3: Update features.json

If feature complete and tested:
- Change `"passes": false` to `"passes": true`
- Do NOT modify anything else

### Step 4: Append to claude-progress.txt

```
---
## Session N: [Feature ID]
Date: [date]
Agent: Coding Agent

### Worked On:
- [Feature ID]: [description]

### Completed:
- [list]

### Incomplete/Blocked:
- [list with reasons]

### For Next Agent:
- [immediate next steps]
- [gotchas or context needed]

### Git Commits:
- [hash]: [message]
```

### Step 5: Update context_summary.md

Add any:
- Decisions made
- Patterns discovered
- Gotchas encountered

### Step 6: Final Verification
```bash
git status  # Should be clean
./init.sh   # Should pass
```

---

## If Running Out of Context

If you notice context getting full:

1. STOP current work immediately
2. Commit whatever progress exists
3. Write detailed handoff in claude-progress.txt
4. Update context_summary.md
5. End session cleanly

The next agent will continue from your handoff.
