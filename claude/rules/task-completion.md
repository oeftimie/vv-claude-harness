---
globs:
  - "**/.harness/**"
  - "**/features.json"
---

# Task Completion Checklist

Before declaring ANY task complete:
- [ ] All tests pass (including new tests written via TDD)
- [ ] No uncommitted changes remain
- [ ] Sub-agent/teammate work validated against lead context
- [ ] Documentation updated (existing docs only)
- [ ] `context_summary.md` updated with decisions, patterns, or gotchas discovered
- [ ] User informed of what changed

Additional for harness projects:
- [ ] `features.json` audited against actual work done — every touched feature has updated status, test_file, coverage; unmapped work gets a new feature entry with `discovered_via`
- [ ] `context_summary.md` has any non-obvious root causes, gotchas, or patterns discovered this session
- [ ] Retrospective written to `context_summary.md` under `## Meta-Session [DATE]` (mandatory even for single-session work)
- [ ] `claude-progress.txt` has session handoff
- [ ] Task list is current — no stale in-progress or pending tasks that no longer reflect reality

Do NOT skip this checklist.
