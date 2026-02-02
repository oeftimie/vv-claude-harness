---
paths:
  - ".harness/features.json"
  - ".harness/claude-progress.txt"
  - ".context/modules.yaml"
---

# Coding Agent Rules (Harness Projects)

These rules activate when working in a harness-managed project (detected by presence of .harness/ and .context/ files).

When `.harness/` and `.context/` exist, this is a harness-managed project. Follow these protocols for ALL work in the project, not just harness files.

## Your Role

You are a **sub-agent** implementing ONE feature per session. You:
- Implement features directly (you ARE the implementer)
- Follow TDD strictly (95% coverage)
- Respect module locks
- Report to orchestrator on completion or blockers

## Session Start

```bash
# Orient yourself
cat .harness/claude-progress.txt | tail -50
git log --oneline -10
cat .harness/features.json
cat .context/modules.yaml
cat context_summary.md 2>/dev/null
```

## Feature Selection

Pick highest-priority feature where:
- `passes: false`
- `assigned_to: null`
- All `modules_required` are unlocked

If blocked, report to orchestrator.

## Module Claiming

Before coding, claim modules:

```
Use context-graph skill: claim
Modules needed: [list]
Feature: F00X - [description]
```

Update features.json:
- Set `assigned_to` to your session
- Set `modules_claimed` to what you claimed

## Implementation

1. Run smoke test: `./.harness/init.sh`
2. TDD: failing test → implement → verify → refactor
3. Coverage >= 95% on touched code

## Session End

1. Run all tests
2. Update `.harness/claude-progress.txt`
3. Update `features.json`:
   - `passes`: true if complete
   - `assigned_to`: null
   - `modules_claimed`: []
4. Update `context_summary.md` with learnings
5. Release modules:
   ```
   Use context-graph skill: release
   ```
6. Commit with descriptive message
7. Leave handoff notes if incomplete

## Critical Rules

**Do:**
- Claim before coding
- Release at session end
- Update context_summary.md with patterns/gotchas

**Do NOT:**
- Modify unclaimed modules
- Mark passing without tests
- Skip module release
- Hide errors from orchestrator
