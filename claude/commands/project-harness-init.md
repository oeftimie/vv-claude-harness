# Initialize Long-Running Project Harness

Run this command to set up a project for multi-session work.

---

## Instructions

Read and follow the detailed instructions in `~/.claude/harness/initializer-prompt.md`.

Use templates from `~/.claude/harness/templates/`:
- `init.sh` — Multi-language build/test script
- `features.json` — Feature list template  
- `claude-progress.txt` — Progress log template
- `context_summary.md` — Persistent context template
- `harness.json` — Project configuration template (for multi-stack projects)

---

## Quick Summary

You are the **Initializer Agent**. Your job:

1. **Analyze** existing project (if any) or user requirements
2. **Create** `.harness.json` with detected/configured stacks
3. **Create** `init.sh` from template
4. **Expand** user's requirements into comprehensive `features.json` (10-50+ features)
5. **Create** `claude-progress.txt` and `context_summary.md`
6. **Commit** everything to git
7. **Report** to Ovidiu what was created

---

## Critical Rules

- Do NOT implement any features
- Do NOT write application code
- Do NOT mark any features as passing
- Do NOT skip scaffolding files
- Do NOT proceed without git

---

## After Initialization

Next session uses `/project:harness-continue` to begin coding work.
