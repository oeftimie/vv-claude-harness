# Continue Long-Running Project

Run this command at the START of every coding session (after initialization).

---

## Instructions

Read and follow the detailed instructions in `~/.claude/harness/coding-agent-prompt.md`.

---

## Session Start Routine (Quick Reference)

Execute IN ORDER. Do not skip steps.

```bash
# 1. Orient
pwd && ls -la

# 2. Read progress
cat claude-progress.txt

# 3. Check git
git status && git log --oneline -10

# 4. Check features
cat features.json

# 5. Verify environment (FIX IF BROKEN)
./init.sh

# 6. Read context
cat context_summary.md
```

---

## Work Rules

- Work on **ONE** feature only (highest priority with `passes: false`)
- Test **end-to-end** before marking complete
- Update **all artifacts** before session ends
- Commit progress **frequently**

---

## Session End Routine (Quick Reference)

```bash
# 1. Verify app works
./init.sh

# 2. Commit progress
git add . && git commit -m "[Feature ID] description"

# 3. Update features.json (passes: true if complete)

# 4. Append to claude-progress.txt

# 5. Update context_summary.md

# 6. Final check
git status && ./init.sh
```

---

## If Running Out of Context

1. STOP current work immediately
2. Commit whatever progress exists
3. Write detailed handoff in claude-progress.txt
4. Update context_summary.md
5. End session cleanly

The next agent will continue from your handoff.
