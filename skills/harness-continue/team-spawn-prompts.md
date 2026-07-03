# Agent Teams Spawn Prompt Templates

Per-feature spawn prompts for the vv-harness plugin agents. The lead fills in the
placeholders and passes the result as the `prompt` parameter in Agent tool calls, with
`subagent_type` set to the matching agent type.

> Reusable guardrails — TDD discipline, tool posture, scope discipline, and the
> completion/SendMessage protocol — are baked into the vv-harness agent definitions
> (`agents/` at the plugin root) and MUST NOT be re-pasted into spawn prompts. Spawn
> prompts carry only the per-feature specifics below.

The agent definitions set the default model per role (implementers and researcher:
Sonnet; reviewer: Opus). A spawn-time `model` parameter overrides the frontmatter, so
the lead applies the dynamic Opus-upgrade heuristic via the Agent tool call alone.

---

## Feature Implementer (`subagent_type: "vv-harness:feature-implementer"`)

**Plan approval**: false by default; lead decides at spawn time (complex or
security-sensitive scope → true; append the Plan Approval Addendum below).

```
Project: [PROJECT_NAME]
Feature: [FEATURE_ID] - [FEATURE_DESCRIPTION]
Scope you own: [DIRECTORY_LIST from features.json scope]
Files you must NOT touch: [BOUNDARIES]
Deliverable: [SPECIFIC_DELIVERABLE_DESCRIPTION — tests required, success criteria]
Git identity: [USER_NAME] <[USER_EMAIL]> with SSH key [SSH_KEY]
Branch: [BRANCH]
require_plan_approval: [true|false]

Claim your task before starting:
  TaskUpdate({ taskId: "[TASK_ID]", status: "in_progress", owner: "[YOUR_NAME]" })
```

---

## Layer Implementer (`subagent_type: "vv-harness:layer-implementer"`)

**Plan approval**: false by default; true if the layer has complex shared interfaces.

```
Project: [PROJECT_NAME]
Layer: [LAYER_NAME]
Feature: [FEATURE_ID] - [FEATURE_DESCRIPTION]
Scope you own: [DIRECTORY_LIST from features.json scope]
Files you must NOT touch: [OTHER_LAYERS]
Deliverable: [SPECIFIC_DELIVERABLE_DESCRIPTION]
Interface partners: [OTHER_TEAMMATE] via [INTERFACE_FILE or API contract]
Git identity: [USER_NAME] <[USER_EMAIL]> with SSH key [SSH_KEY]
Branch: [BRANCH]
require_plan_approval: [true|false]

Claim your task before starting:
  TaskUpdate({ taskId: "[TASK_ID]", status: "in_progress", owner: "[YOUR_NAME]" })
```

---

## Researcher (`subagent_type: "vv-harness:researcher"`)

**Plan approval**: false (research is read-only; no implementation risk).

```
Project: [PROJECT_NAME]
Research question: [RESEARCH_QUESTION]
Specific questions to answer:
1. [SPECIFIC_QUESTION_1]
2. [SPECIFIC_QUESTION_2]
3. [SPECIFIC_QUESTION_3]
Output file: [OUTPUT_FILE]

Claim your task before starting:
  TaskUpdate({ taskId: "[TASK_ID]", status: "in_progress", owner: "[YOUR_NAME]" })
```

---

## Reviewer (`subagent_type: "vv-harness:reviewer"`)

**Plan approval**: false (review cannot edit files).

```
Project: [PROJECT_NAME]
Review target: [FEATURE_IDS] - [FILES_TO_REVIEW]
Scope the work was assigned: [DIRECTORY_LIST from features.json scope]
Deliverable: report findings to the lead via SendMessage (teammate mode) or in your
final message (fallback mode). The lead persists them to a file if a record is needed.
Branch: [BRANCH]

Claim your task before starting:
  TaskUpdate({ taskId: "[TASK_ID]", status: "in_progress", owner: "[YOUR_NAME]" })
```

---

## Plan Approval Addendum

When `require_plan_approval` is true, append this block to the implementer's prompt:

```
Before writing any code, submit an implementation plan for approval:

  SendMessage({
    type: "plan_approval_request",
    recipient: "team-lead",
    content: "# Implementation Plan for [FEATURE_ID]\n\n## Approach\n[description]\n\n## Files to create/modify\n[list]\n\n## Test strategy\n[what tests, what they prove]\n\n## Risks\n[potential issues]",
    summary: "Plan for [FEATURE_ID]"
  })

Wait for a direct message from the lead approving or rejecting your plan before writing
any code. (The lead replies with type "message" due to a delivery bug in
plan_approval_response.) If rejected, revise based on feedback and resubmit.
```

---

## Anti-Patterns to Avoid

1. **Vague scope**: "Work on the backend" gives no boundaries. Always list specific
   directories or files (from features.json `scope` field).
2. **Overlapping scope**: Two teammates owning `src/utils/` guarantees merge conflicts.
   One owner per file.
3. **Missing deliverable**: "Implement the feature" doesn't define done. Specify test
   requirements, output files, success criteria.
4. **Shared interfaces without a layer owner**: when teammates share an interface, spawn
   the owner as `vv-harness:layer-implementer` and name the interface partners in its
   prompt.
5. **Missing git identity**: Teammates load project CLAUDE.md but not harness config.
   Include git identity explicitly in every implementer spawn prompt.
6. **Re-pasting guardrails**: TDD rules, scope discipline, and the completion protocol
   are in the agent definitions. Duplicating them in spawn prompts drifts out of sync.
7. **Skipping plan approval on complex tasks**: If a feature touches 10+ files or is
   security-sensitive, require a plan. One `SendMessage` round-trip is cheap compared to
   a wrong approach.
