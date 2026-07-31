<!-- Shipped with the vv-harness plugin. There is no auto-loading: the SessionStart
orientation injects this file's absolute path, and the harness skills instruct the lead
to read it when working with context_summary.md. -->

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
     projects: harness-init can import them as starting context.
     Examples: when to use Opus, how to scope work, when plan_approval pays off.
     Each entry carries a disposition marker set by Phase 5.5's promotion pass
     (see skills/harness-continue/SKILL.md), so a pattern stops being restated
     verbatim across sessions once it has a place to live:
       - (promoted-to: X) -- already landed as a rule/hook/schema/agent/skill
         change; X names it (e.g. "promoted-to: rules/agent-teams-protocol.md
         Dynamic overrides"). Keep the entry as a one-line historical pointer,
         not the full original prose.
       - (backlog) -- filed as a row in .harness/HARNESS_BACKLOG.md, not yet
         promoted; still worth restating until it lands somewhere durable.
       - (watching) -- below the promotion score threshold (fewer than 3
         distinct sessions have re-observed it); noted here so a future
         session's retrospective can recognize a repeat and bump the score. -->
- (none yet)

## Meta-Session [DATE]
<!-- One section per completed session's retrospective. Written at session end.
     Analyzes correction_cycles, scope_expansions, model fit, discovery lineage.
     Feeds the Meta-Patterns section with generalizable coordination insights. -->
- Scope accuracy: [findings]
- Model calibration: [findings]
- Discovery lineage: [findings]
- Approach patterns: [what worked, what failed]
- Plan approval: [was it worth the overhead for which feature types]

## Closed Work Streams
<!-- Completed features. Reference only if dependency exists. -->
- [Feature]: completed [date], see [PR/commit]
```

Example:

```markdown
## Meta-Patterns
- Ground-truthing a reviewer's finding before fixing it caught real bugs
  every time it was tried this session. (promoted-to: rules/agent-teams-
  protocol.md's "verify before acting" clause)
- Opus reviewers occasionally cite a line number one off from the real
  diff hunk; worth double-checking before treating a citation as ground
  truth. (watching)
```

**Update when:** a decision is made, a pattern is discovered, a gotcha is encountered, a work stream completes, active context shifts, or a session retrospective completes.

**Do NOT add:** progress updates ("completed task X"), completed todos, conversation summaries, or anything already tracked in `claude-progress.txt`. This file is for decisions, patterns, gotchas, and coordination retrospectives — not a journal.

**Size discipline:** if a domain section exceeds ~300 tokens, summarize or split. Meta-Session entries older than 3 sessions can be summarized into Meta-Patterns and removed.

**Keep Active Context fresh:** this section should reflect right now, not last week.
