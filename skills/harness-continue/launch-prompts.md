# Launch Prompt Templates

Launch checklist, `args` shape, and structured-output schemas for
`/harness-continue` Step 5b's workflow orchestration.

---

## Workflow launch (primary — `/vv-harness:implement-features`)

### Pre-launch checklist

Before launching the workflow, confirm all of:

- **Specs verified** — every feature in the batch has `spec.verdict: "PASS"` (or a fresh
  `harness-issue-prep` pass). Unverified features are excluded from the batch.
- **Tasks mirrored WITH `feature_id`** — one `TaskCreate` per feature, each carrying
  `metadata.feature_id`. This arms the `TaskCompleted` gate's focused-test/coverage
  stages; the norm (and the task-subject fallback's fragility) is
  `${CLAUDE_PLUGIN_ROOT}/rules/parallel-work.md`, "Task mirroring and integration
  order".
- **Branch clean, rebased** — `git fetch` + rebase on the integration branch; working
  tree clean before launch.

### `args` shape

```
{
  features: ["F0NN", "F0MM"],
  featureSpecs: {
    F0NN: { spec: "<the verified spec text, verbatim>", scope: ["path/…"], risk: "standard|elevated", mergeBase: "<sha or branch>" },
    F0MM: { … }
  },
  maxReviewRounds: 3,
  reviewModel: "opus"   // optional; omit to use the reviewer agent's own model
}
```

### Structured-output schemas

The implementer/reviewer/conformance result shapes are canonical in
`${CLAUDE_PLUGIN_ROOT}/rules/parallel-work.md`, "Structured-output contracts"; the
`schema` constants in `workflows/*.js` enforce them at runtime. The workflow itself
returns `{ per_feature: [{ feature_id, implement, review, outcome:
approved|blocked|needs-lead|died }], unfinished: [ids], complete: bool }`.

The lead integrates approved features per Step 5b's ordered flow; `blocked` / non-APPROVE
/ `unfinished` features are surfaced to the user, never auto-merged.
