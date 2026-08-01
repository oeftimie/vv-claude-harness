---
name: harness-improve
description: Run an observation-first improvement loop on a harness-managed project -- record a job contract, observe the baseline, locate the earliest failed handoff, classify the gap to its smallest vv-native owner, implement one intervention, verify at the claim boundary, rerun fresh, then retain/revise/remove. Use when a user asks why an agent failed or underperformed on a harness project, when a session ends with correction_cycles >= 3 on any feature, or when the user says "improve the harness".
---

# Harness Improve

Adapted from harness-engineering's `playbooks/improve-harness.md` (CC BY 4.0):
improvement driven by an OBSERVED TRAJECTORY, never by a feature idea alone.

**Non-harness projects**: if `.harness/` doesn't exist, stop and point the user at
`/harness-init` -- this whole loop depends on evidence only `.harness/` provides
(Step 2); there is nothing to observe without it.

## Guardrails (read before Step 1)

- **Bounded claim**: one before-and-after run supports only a bounded claim about
  THAT job, on THAT worker config, THAT day -- never generalize past what was
  actually observed.
- **Retrieved-or-invoked check**: a successful rerun says nothing about an
  instruction the trajectory never actually used. Before crediting an
  intervention, confirm it was genuinely retrieved (the file was read) or invoked
  (the hook fired, the check ran) during the rerun -- not just present on disk.
- **No uncorroborated self-report**: a model's own claim that it "understood" or
  "will do better" is not evidence. Only observed behavior counts.

## Step 1: Record the Job Contract

Before touching anything, write down: the target job + revision (feature ID or
task description); the fixed worker config (`.harness/harness.json`'s `worker`
block, F016/OVI-57, if present -- note "unrecorded" if absent, don't guess); a
representative job (the actual session/task under review); the accepted outcome
(what "done" looked like); the evidence available; the budget/stop conditions for
this improvement pass itself; the suspected gap (a hypothesis, not a conclusion
yet).

## Step 2: Observe the Baseline

Gather evidence vv already has -- don't reconstruct from memory:
- `.harness/features.json`: `correction_cycles`, `scope_expansions`,
  `approaches_tried`, `failure_reason` on the job's feature(s).
- `.harness/SESSION_INCOMPLETE` history, if still present: what gaps got flagged
  and left open.
- `.harness/mld/*.md` entries (F055; P3.1's corroboration marker, when present):
  `## Mistakes` / `## Learnings` / `## Desires` from past sessions on this job.
- The actual session transcript, if still available.

## Step 3: Locate and Classify the Earliest Failed Handoff

Find the FIRST point in the trajectory where something needed did not arrive --
not the last symptom, the earliest cause. Classify it; each class maps to its
smallest vv-native owner:

| Gap class | vv-native owner |
|---|---|
| Context | `context_summary.md` entry, or a `rules/*.md` pointer |
| Capability | A `.harness/init.sh` change, or a new/fixed tool |
| Domain ownership | A `schemas/*.json` field |
| Authority | A hook (`.claude/hooks/*.sh`) |
| Proof | A `proof`/`qa_binding` field (`schemas/feature.schema.json`) |
| Feedback/delivery | A teammate spawn prompt |
| Worker limitation | Hold as an open candidate -- one failed run cannot establish this; needs corroboration across distinct sessions (F015/OVI-55's score>=3 promotion threshold) before acting |

## Step 4: One Intervention Hypothesis

State it in this exact shape, so it is falsifiable, not just a fix:

> If **X** (the change) at owner **Y** (from Step 3's table), then observable
> change **Z** on job **J** (the SAME job class from Step 1), because mechanism
> **M** (why this should work). Evidence that would weaken this hypothesis: [name
> it]. Carrying cost: [what this adds -- a new file to maintain, a slower check,
> a longer prompt].

Exactly ONE intervention per pass. Resist bundling several fixes into one round.

## Step 5: Implement the Smallest Change

Implement Step 4's change at its named owner -- nothing broader. Verify two ways:
native checks (the project's own test suite -- `bash test/run-tests.sh` in this
repo) AND the job's own claim boundary (does the specific accepted outcome from
Step 1 now hold, not just "tests pass").

## Step 6: Fresh-Session Rerun

Rerun the SAME CLASS of job, on the SAME worker config recorded in Step 1, in a
genuinely fresh session -- not a continuation of this one, since prior-session
context would contaminate the signal. Before crediting the intervention, apply
the retrieved-or-invoked guardrail: confirm it was actually used this run, not
just present on disk.

**Consequential jobs that can't safely be rerun**: use the recent-session
inspection variant instead -- review the most recent real occurrence's
transcript for the same signal, rather than deliberately reproducing a costly
failure just to test the fix.

## Step 7: Retain, Revise, or Remove

Verdict on the intervention, with reasoning:
- **Retain**: the rerun showed the predicted change, cleanly.
- **Revise**: partial signal, or a side effect Step 4 didn't predict.
- **Remove**: no signal, or the carrying cost exceeds the benefit.

Record a compact result record (template below) to `.harness/context_summary.md`.
If the lesson generalizes beyond this one job (a plugin-level pattern, not a
project-specific fix), route it to `.harness/HARNESS_BACKLOG.md` instead
(F015/OVI-55's promotion pass) -- this skill fixes ONE job; the backlog is where
a fix earns broader promotion.

## Result Record Template

```markdown
## Improve-Harness Result: <job> (<date>)
- Outcome: retain | revise | remove
- Proof: <what was actually observed, with a pointer -- test output, file diff, transcript>
- Relay/latency: <how long from hypothesis to verified rerun>
- Risk vs. carrying cost: <what this could break, weighed against what it costs to keep>
- Decision: <the Step 7 verdict, one line>
- Known limits: <what this result does NOT establish -- the bounded-claim guardrail, made concrete>
```

---

Adapted from harness-engineering's `playbooks/improve-harness.md`, CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/).
