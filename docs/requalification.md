<!-- Shipped with the vv-harness plugin. Triggered by harness-continue's Step 2.6
worker epoch check (skills/harness-continue/SKILL.md), or run by hand any time a
worker (model + coding agent) changes materially. F016/OVI-57. -->

# Worker Requalification Checklist

HE fixed-worker thesis: hold the worker constant for one epoch, record its
configuration, and requalify on every material change. "Requalification includes
subtraction" — a better worker absorbs capabilities that used to need scaffolding, and
that scaffolding should be retired, not carried forward out of habit.

Run this checklist when `harness-continue`'s Step 2.6 prompts a requalification, or any
time you're consciously changing which model or CLI version this project's worker uses.

## 1. Re-run the orientation eval

Re-run the P5.3 orientation eval (OVI-60/F021, "Eval method doc + first behavioral
eval") against the fixture project. This confirms the new worker still produces the
orientation quality the harness assumes. **Not yet shipped**: if F021 hasn't landed
yet, note that this step was skipped for that reason and move on; do not fabricate an
eval result.

## 2. Review the bindings table

`rules/agent-teams-protocol.md`'s Model Selection section holds the ONE bindings table:
role -> model. Requalification updates a row in THAT table — never the protocol prose
around it ("lead needs deep reasoning" is policy and doesn't change; "lead: Opus" is a
binding that might). When these names age, the fix is one row in that table and a
settings edit, not a protocol change.

## 3. Review operational-metric baselines

`correction_cycles`, `scope_expansions`, and the other dynamic-override signals in
`features.json` are worker-epoch-scoped: a Sonnet from last quarter's `correction_cycles
>= 3` says little about this quarter's Sonnet. After requalifying, add a note to
`.harness/context_summary.md`'s Active Context: pre-epoch operational metrics are
advisory only, not a mechanical trigger, until enough post-epoch data accumulates.

## 4. Inherit vs. pinned, per role

For each role (lead, implementer, reviewer), decide explicitly: `model: inherit` (rides
whatever model the session itself is running under — zero maintenance as model names
churn, but no cost control) vs. a pinned model name (predictable cost, needs updating at
every requalification). Default outcome stays **pinned** for implementers (cost control
matters more at that volume); the **reviewer is the first inherit candidate** (one call
per feature, and review quality tracking the session's own model is usually worth more
than the cost delta). Record the decision and its reasoning in the bindings table update
from step 2.

**The `CLAUDE_CODE_SUBAGENT_MODEL` footgun**: setting this environment variable flattens
every vv agent's frontmatter `model` field to the same value, silently defeating the
per-role bindings table entirely. Never set it in a harness project; see the invariant in
`templates/CLAUDE.md`.

## 5. Verified-live annotations

Every hook or protocol clause whose correctness depends on specific platform behavior
(not just vv's own code) carries a `verified live YYYY-MM-DD on Claude Code X.Y.Z`
annotation at the point of the claim. This is worker-epoch pinning applied at the file
level: the annotation says exactly which worker generation last confirmed the behavior,
so staleness is visible instead of assumed. Requalification refreshes every annotation
touched by the epoch change (re-verify the claim under the new CLI, update the date and
version, or flag it for removal if the behavior no longer holds); the repo-side
maintenance loop (`docs/maintenance-runbook.md`) does the same on its own schedule for
platform-behavior claims that aren't tied to a specific project's epoch.

## 6. Degradation is not escalation

A turn where a provider outage or rate limit forced a fallback response is not evidence
about that model tier's actual capability — don't let a degraded turn count toward (or
against) an escalation decision. When a degraded turn happens during planning or
review, add a one-line note to `context_summary.md` (what degraded, and why) so the
distinction between "this model tier is weak here" and "the provider had an outage" stays
readable in later retrospectives, instead of quietly contaminating the signal.

## 7. Subtraction pass

Requalification is not only "does the new worker still need everything the old one
needed" — it's actively looking for what the new worker has absorbed. Walk this list
(and any project-specific candidates) and record a keep / revise / remove verdict with
evidence for each, the same rubric `harness-continue`'s Phase 5.5 ablation pass uses:

| Candidate | Why it might be removable | Evidence to check |
|---|---|---|
| Per-edit PostToolUse type-check hooks | Redundant if the worker reliably self-checks its own edits, or if `TaskCompleted`'s test run already covers the same error class | Did the hook catch anything this epoch that `TaskCompleted` didn't already catch? |
| Plan-approval ceremony for small scopes | A more capable worker may need less hand-holding on scopes that used to warrant a plan-approval gate | Did any small-scope plan approval this epoch actually change the plan, or was it a rubber stamp? |
| Compaction-recovery redundancy | If the platform's own compaction recovery improves, a project-level recovery mechanism may duplicate what the platform now does natively | Compare the platform's native recovery injection against what the project-level mechanism adds on top |
| The 4000-char orientation budget | A worker that orients faster/more reliably from less context may not need the full budget | Did sessions this epoch actually use the full budget, or consistently orient well from less? |

A candidate found removable here is itself a promotion candidate for
`harness-continue`'s own ablation pass (`.harness/HARNESS_BACKLOG.md`, F015/OVI-55)
rather than being acted on unilaterally — requalification identifies subtraction
candidates; it does not auto-apply them.
