---
globs:
  - "**/context_summary.md"
  - "**/.harness/**"
---

# context_summary.md

Used in ALL projects (harness and non-harness). The single persistent knowledge store across sessions.

In harness projects: `.harness/context_summary.md`. In non-harness projects: `./context_summary.md` in the project root.

Create once, update continuously.

```markdown
# Context Summary

## Active Context
<!-- Max 500 tokens. Current focus, immediate priorities. Refresh frequently. -->
- Currently working on: [active task]
- Blocking issues: [if any]
- Next up: [queued work]

## Cross-Cutting Concerns
<!-- Security, performance, compatibility constraints that affect all work -->
- [Concern]: [how it affects decisions]

## Domain: [Name]
<!-- One section per major domain/module. Add as needed. -->

### Decisions
- [Decision]: [rationale] (date)

### Patterns
- [Pattern name]: [when to use]

### Gotchas
- [Gotcha]: [how to avoid]

## Meta-Patterns
<!-- Coordination insights that apply across features — NOT domain-specific.
     Written by the retrospective step at session end. These transfer to new
     projects: harness-init can import them as starting context. -->
- (none yet)

## Meta-Session [DATE]
<!-- One section per completed session's retrospective. Written at session end. -->
- Scope accuracy: [findings]
- Model calibration: [findings]
- Discovery lineage: [findings]
- Approach patterns: [what worked, what failed]
- Plan approval: [was it worth the overhead for which feature types]

## Closed Work Streams
<!-- Completed features. Reference only if dependency exists. -->
- [Feature]: completed [date], see [PR/commit]
```

**Update when:** a decision is made, a pattern is discovered, a gotcha is encountered, a work stream completes, active context shifts, or a session retrospective completes.

**Do NOT add:** progress updates ("completed task X"), completed todos, conversation summaries, or anything already tracked in `claude-progress.txt`. This file is for decisions, patterns, gotchas, and coordination retrospectives — not a journal.

**Size discipline:** if a domain section exceeds ~300 tokens, summarize or split. Meta-Session entries older than 3 sessions can be summarized into Meta-Patterns and removed.

**Keep Active Context fresh:** this section should reflect right now, not last week.
