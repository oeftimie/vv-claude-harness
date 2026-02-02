# /project:harness-continue

Continue working on a harness-managed project.

## Prerequisites

Project must have `.harness/` and `.context/` directories.
If not, run `/project:harness-init` first.

## Session Flow

### Start
1. Orient: read progress, git log, features.json, modules.yaml
2. Select feature (priority, not assigned, modules available)
3. Claim modules via context-graph skill
4. Update features.json: `assigned_to`, `modules_claimed`
5. Run smoke test: `./.harness/init.sh`

### Implement
6. TDD: failing test → implement → verify → refactor
7. Coverage >= 95% on touched code

### End
8. Run all tests
9. Update `.harness/claude-progress.txt`
10. Update `features.json` (passes, assigned_to=null, etc.)
11. Update `context_summary.md` with learnings
12. Release modules via context-graph skill
13. Git commit
14. Leave handoff notes if incomplete

## Quick Reference

**Claim modules:**
```
Use context-graph skill: claim
Modules needed: [list]
Feature: F00X - [description]
```

**Release modules:**
```
Use context-graph skill: release
```

**Check status:**
```
Use context-graph skill: status
```

## Rules

- ONE feature per session
- Claim before coding
- Release before ending
- Tests required (95% coverage)
- Never modify unclaimed modules

See `~/.claude/rules/harness/` for detailed protocols.
