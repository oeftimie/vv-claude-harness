# vv Evals

Adapted from harness-engineering's eval method (CC BY 4.0): test behavioral effect,
not terminology. An intervention succeeds when it changes what an agent actually
does next, not when a transcript merely repeats the intervention's own words back.
vv adopts this at proportionate scale -- semi-manual, small-N, decision-scoped --
and explicitly skips the research apparatus (contamination scans, escrowed corpora,
statistical power analysis) a general-purpose eval suite would need.

## The contract

Every vv eval states, up front:

1. **The decision it informs.** Name the actual choice this eval's result will
   settle (keep a mechanism, simplify it, remove it, or investigate further) --
   not a vague "does this help" framing. If there's no decision waiting on the
   result, it isn't a vv eval yet, just curiosity.
2. **Exactly one named intervention.** Baseline (condition A) and treatment
   (condition B) must differ by exactly one thing, stated explicitly. Any other
   difference between the two conditions invalidates the comparison -- see the
   checklist below.
3. **Fresh sessions.** Every run starts with no memory of any other run in the
   eval, baseline or treatment. A continued or resumed session contaminates the
   signal (prior turns leak context the intervention didn't actually provide).
4. **The same fixture and worker config across every run.** Same starting
   repository state, same model(s), same CLI version. Record the fixed-worker
   discipline's fields (`claude --version`, and the model(s) used for each role
   in play) in the eval's own results table -- a rerun on a different worker
   config starts a new epoch (P4.2 language) and is a different eval, not a
   continuation of this one.
5. **At least 3 runs per condition.** A single run per condition cannot
   distinguish "the intervention did this" from "this run happened to go this
   way." 3 is the proportionate floor for vv's scale, not a statistical claim.
6. **Availability, retrieval, and relevance recorded separately.** These are
   three different facts about an intervention and collapsing them hides the
   real finding:
   - **Available**: was the intervention actually present for this run (the
     file existed, the hook fired, the flag was set)?
   - **Retrieved**: did the agent actually consume it (read the file, the hook's
     output appeared in context, the agent's own transcript shows it was seen)?
   - **Relevant**: did having it change what the agent did, compared to a run
     where it wasn't available?
   An intervention can be available but never retrieved (dead weight), or
   retrieved but not relevant (harmless but not earning its complexity), or
   relevant in ways narrower than hoped. Only "available AND retrieved AND
   relevant" supports keeping something on the strength of this eval alone.

## Invalid-result checklist

Before trusting a result, rule out each of these (adapted subset -- HE's full
list is broader; this is the part that matters at vv's scale):

- **Treatment never retrieved.** If the treatment condition's intervention was
  available but no run's transcript shows it was actually consumed, the eval
  measured nothing about the intervention -- it measured absence twice.
- **Extra differences between conditions.** If baseline and treatment differ in
  more than the one named intervention (different fixture state, different
  model, different prompt wording, different tool access), the comparison is
  confounded and the result is uninterpretable, however clean it looks.
- **One rollout treated as representative.** Citing a single run's transcript
  as "the" result when 3+ runs exist per condition is cherry-picking, even
  unintentionally. Report the full per-run table.
- **Activity metrics standing in for outcomes.** Counting tool calls, response
  length, or turns taken is not the same as checking whether the accepted
  outcome the eval names actually happened. Grade the outcome, not the busyness.

## Scope and honesty about scale

vv evals are semi-manual by design: a person (or an agent, self-disclosed as
such) reads each transcript and grades it against named, binary facts stated in
advance. A vv eval is a bounded, one-decision instrument -- its result supports
a local decision about the intervention it tested, on the fixture and worker
config it used, on the day it ran. It does not support a general claim about
"how well Claude follows instructions" or any claim broader than the one named
decision.

**Cost bound**: a vv eval at proportionate scale costs roughly what ~6 short
sessions cost (2 conditions x 3+ runs, each a fresh short session) -- not a
research-grade sample, and not meant to be one. If a decision genuinely needs
more than that to settle, that itself is a finding worth stating plainly rather
than quietly running a bigger eval than this method was designed for.

## The other instrument in this directory

`evals/hillclimb/` is not a vv eval and is not graded by the method above. It is
a deterministic conformance suite over the shipped plugin -- the hooks and gates
under adversarial input, the manifests and file pointers, output determinism,
and `test/run-tests.sh` folded in as an aggregate. Run it with `bash
autoresearch.sh` from the repo root; it prints `METRIC harness_score=<0..100>`,
the weighted fraction of its checks that pass, plus one line per failing check.

The two answer different questions and neither substitutes for the other. A vv
eval asks whether an intervention changed what an agent *did*, which needs a
model in the loop and a human reading transcripts. The hillclimb suite asks
whether the plugin's own machinery behaves as specified, which needs no model at
all: it is offline, hermetic per fixture, and byte-reproducible, so a change in
its score is a change in the plugin rather than in the weather.

Its checks are additive by policy. A check may be added; one may not be removed,
weakened, or made conditional to raise the score, and `checks_total` must never
decrease. When a mutation to shipped code leaves every check passing, that is a
gap in the suite, not evidence the code is safe.

---

Adapted from harness-engineering's eval method, CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/).
