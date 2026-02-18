---
description: Structured planning workflow for projects not using the harness. Skip this file entirely if .harness/ exists in the project root.
---

# Non-Harness Structured Workflow

**Skip this file if `.harness/` exists.** Harness projects use `/harness-continue` instead.

This workflow is for projects without the Long-Running Agent Harness. It provides a lightweight planning approach for non-trivial tasks.

## When to Use Structured Planning

**Use it for:**
- Tasks with material risk: auth changes, data mutations, API contracts, security-sensitive code
- Tasks spanning 3+ files or requiring coordination
- Research tasks requiring synthesis
- Tasks where failure would require significant rollback

**Skip it for:**
- Direct factual questions
- Single-file edits with obvious correctness (styling, typos, simple refactors)
- Clarifying questions
- Low-risk changes where failure is immediately visible and easily reversed

The question isn't "how big?" but "what's the blast radius if this goes wrong?"

## Planning Steps

1. **Create `task_plan.md` FIRST** for non-trivial work
2. **Define phases** with checkboxes
3. **Analyze parallelization potential:**
   - What can run concurrently via sub-agents?
   - What has sequential dependencies?
   - What's the critical path?
4. **Present a structured plan** with work breakdown, sub-agents to invoke, risks, and what CANNOT be done with available tools
5. **Wait for explicit "Go ahead"**
   - Do NOT proceed without approval
   - Do NOT interpret silence as consent
   - Do NOT start "just the easy parts" while waiting
6. **Update after each phase**

Use `notes.md` for research findings and `context_summary.md` (defined in CLAUDE.md) for cross-task persistent context.

## Core Loop

```
Loop 1: Read context_summary.md (if exists) → Create task_plan.md with goal and phases
Loop 2: Research → save to notes.md → update task_plan.md
Loop 3: Read notes.md → create deliverable → update task_plan.md
Loop 4: Validate output matches goal → update context_summary.md → deliver
```

**Before each major action:** read `task_plan.md` (refresh goals in attention window)
**After each phase:** edit `task_plan.md` (mark complete, update status)
**When storing information:** write `notes.md` (don't stuff conversation context)
**When task completes:** update `context_summary.md` (persist learnings)

## Templates

### task_plan.md

```markdown
# Task Plan: [Brief Description]

## Goal
[One sentence describing the end state]

## Phases
- [ ] Phase 1: Plan and setup
- [ ] Phase 2: Research/gather information
- [ ] Phase 3: Execute/build
- [ ] Phase 4: Test and verify
- [ ] Phase 5: Review and deliver

## Key Questions
1. [Question to answer]
2. [Question to answer]

## Decisions Made
- [Decision]: [Rationale]

## Errors Encountered
- [Error]: [Resolution]

## Status
**Currently in Phase X** - [What I'm doing now]
```

### notes.md

```markdown
# Notes: [Topic]

## Sources

### Source 1: [Name]
- URL: [link]
- Key points:
  - [Finding]
  - [Finding]

## Synthesized Findings

### [Category]
- [Finding]
- [Finding]
```

## Anti-Patterns

| Don't | Do Instead |
|-------|------------|
| State goals once and forget | Re-read plan before each decision |
| Hide errors and retry | Log errors to plan file |
| Stuff everything in context | Store large content in files |
| Start executing immediately | Create plan file FIRST |
