# Eval: Orientation Recovery

## Decision informed

Does the SessionStart orientation block (the "## Harness orientation (auto-injected)"
text `hooks/session-start.sh` injects at the start of every session, including the
`compact` re-injection) earn its complexity? vv's test suite proves the hook script
produces correct *mechanical* output (right feature counts, right next-claimable ID,
right handoff excerpt) but has never checked whether that output actually changes
what an agent *does* in the next turn, as opposed to an agent that would have reached
the same first action anyway by reading the state files itself. This eval settles
whether to keep the mechanism as-is, simplify it, or investigate further.

## Fixed-worker recording

- CLI version: `2.1.220` (`claude --version`, checked immediately before this run).
- Model: the orienting agent in every run used the session's inherited model,
  Sonnet 5 (`claude-sonnet-5`); no per-run model override.
- Fixture: `test/fixtures/harness-project`, copied fresh per condition and
  committed as a `fixture baseline` git commit (matching `make_fixture()` in
  `test/run-tests.sh`), never the live repo.

## One named intervention

**Available vs. not available: the real, unmodified stdout of `hooks/session-start.sh`
run against the fixture**, prepended to the session as "additional context available
at session start." Nothing else differs between condition A and condition B (same
fixture commit, same prompt, same model, same tool access).

- **Condition A (treatment)**: the orienting agent is told the exact orientation text
  below was injected at session start, then asked the fixed prompt.
- **Condition B (baseline)**: the orienting agent is told nothing extra was injected,
  then asked the same fixed prompt.

Fixed prompt, identical in both conditions: *"Continue working on this project. What
do you do first?"*

The orientation text actually used in the recorded condition-A runs (captured by
running the real hook directly against `fixture-a`, immediately before dispatch --
`git status -s` on `fixture-a` confirmed clean, both before and after capture):

```
## Harness orientation (auto-injected)

Features: 1/3 passing
Next claimable: F003 - Render status badges (scope: src/badges/, tests/badges/)

Last handoff (claude-progress.txt, last 12 lines):
    Session 3 handoff (2026-01-15)
    - F001 passing at 97% coverage, committed.
    - F002 in progress: hook coverage reporting, tests scaffolded.
    - Next: finish F002, then claim F003 (status badges).

Active Context (context_summary.md):
    - Currently working on: F002 hook coverage reporting
    - Blocking issues: none
    - Next up: F003 status badges


Agent Teams protocol: read .../rules/agent-teams-protocol.md before spawning teammates.
Code-quality limits: .../rules/code-quality.md (read before writing code).
Context summary format: .../rules/context-summary.md (read before editing context_summary.md).
Completion checklist: .../rules/task-completion.md (read before declaring work complete).
Run /harness-continue for the full interactive flow (mode choice, smoke test, team plan).
```

(Plugin-root paths abbreviated to `.../` above for readability; the real captured
text used the full installed path.)

### A capture defect, caught by an eval subject, corrected before recording

The first capture attempt (used in an initial, now-discarded round-1 batch of 3
condition-A runs) additionally carried a `WARNING: the previous session ended with
unresolved discipline gaps: F002 is in-progress but missing test_file or coverage...`
block. `hooks/session-start.sh` only prints that block when `.harness/SESSION_INCOMPLETE`
exists (`session-start.sh:53`); that file is absent from both the committed
`test/fixtures/harness-project` and the actual `fixture-a` copy used for the real
runs. The block had leaked into the capture from an *unrelated* scratch directory used
earlier in the same session for an unrelated auth test (a `claude -p` invocation had
run there and its `SessionEnd` hook wrote a real `SESSION_INCOMPLETE` file describing
that directory's own state) -- the capture command was re-run against the wrong path.

**One of the round-1 condition-A subjects caught this itself, unprompted**, by trying
to reproduce the warning against the fixture it could actually see and finding the
gating file absent -- exactly the kind of self-consistency check the invalid-result
checklist exists to encourage. The lead verified the report, confirmed the root cause
empirically (reproducing the leak, then confirming `fixture-a`/`fixture-b` were both
clean), discarded all 3 round-1 condition-A runs as invalid (the treatment condition's
own claim was not reproducible against the fixture the subjects were told to trust),
and re-captured the text directly against `fixture-a` immediately before re-dispatch.
This is recorded as a worked example of the invalid-result checklist catching a real
defect, not smoothed over -- see the Results section below for what was discarded.

### A second, smaller disclosed deviation: an added hint in the corrected batch

The re-dispatched condition-A prompts (below, in Results) additionally contained one
sentence condition B never received: a note that "some earlier runs of this same check
discovered [the fixture's data/reality mismatch, detailed below]... if you
independently notice the same thing, that's expected." This was added defensively
after the round-1 discard, to avoid over-indexing the corrected runs on re-litigating
whether the *lead's* capture was trustworthy rather than orienting normally -- but it
is, strictly, a second difference between condition A and condition B beyond the one
named intervention, and the invalid-result checklist's own "extra differences between
conditions" clause applies to it. Disclosed rather than hidden: the mitigating
observation is that all 3 condition-B runs (which never received this hint)
independently found the identical fixture mismatch anyway, via a single `git ls-files`
or `find` call each -- so the hint's practical effect on the graded facts below appears
small, but this is judgment, not proof, and is recorded as a limitation on this eval's
result, not erased from it.

This does mean the eval reports a graded result despite an acknowledged extra
difference -- evals/README.md's own checklist calls that "uninterpretable, however
clean it looks," with no stated exception. The directional argument for why this
particular case survives: the hint could only push condition A *toward* more
verification and more explicit skepticism, never away from it. Condition B, with no
hint at all, converged on the identical verify-then-refuse behavior anyway. A
confound that can only inflate detection in one direction, when the other direction
already shows the same detection unaided, cannot be what *produced* the observed
null (no differential effect) -- at worst it makes the null slightly less
surprising, not the reason both conditions agree. This is still an argument, not a
proof, which is why it's recorded as a limitation rather than treated as resolving
the issue.

## Method deviation from the spec's literal protocol (disclosed, not silent)

The spec calls for running each condition via `claude -p` as a literal, independently
authenticated CLI subprocess. **That was attempted first and confirmed blocked in this
session's sandboxed environment**: `claude -p ... --output-format json` in the fixture
directory returned `"result":"Not logged in · Please run /login"` with zero cost and
zero tokens -- the subprocess could not authenticate, and this session's own working
credentials are supplied by its runtime rather than the on-disk credential files a
fresh CLI process reads. Fixing this would mean touching keychain/credential-store
configuration, which is out of bounds without Ovidiu's explicit confirmation (global
CLAUDE.md), so the literal `claude -p` protocol was not forced through.

**Substitute used instead**: each condition/run pair was a genuinely fresh
general-purpose subagent (no memory of this session or of any other run), given
either the real captured orientation text (condition A) or nothing (condition B) as
part of its initial prompt, with Read/Glob/Grep access to the actual fixture
directory and explicit instruction not to modify anything. This preserves "fresh
session" and "one named intervention, everything else identical" faithfully. It does
**not** preserve "SessionStart hook fires automatically inside a real `claude -p`
process" -- the orientation text's *content* is real and unmodified (captured by
actually running the hook against the actual fixture), but its *delivery* was a
prompt-level substitution rather than a live hook firing. This is a known,
disclosed deviation, not a silent one: treat this eval's result as evidence about
"does having this content change the next action," not as a black-box end-to-end
proof that the shipped hook wiring itself fires correctly in every real CLI
environment (that mechanical claim is already covered by `test/run-tests.sh`'s
`session-start.sh` suite, which tests the hook script directly).

## Grading: 3 binary facts, decided in advance

Each transcript is graded strictly on these three, independent of writing style or
length:

1. **F003-correct**: does the response identify F003 ("Render status badges") as the
   next feature to work on, without wrongly re-deriving a different next feature or
   getting the ID/description wrong?
2. **F002-respected**: does the response treat F002 as already in progress (not to be
   restarted from scratch), consistent with "finish F002, then claim F003"?
3. **No-overreach**: does the response orient without reading source directories
   (`src/parser/`, `src/hooks/`, `src/badges/`, `tests/`) that aren't needed to answer
   "what do you do first" -- i.e., does it stick to the state files
   (`.harness/features.json`, `.harness/context_summary.md`,
   `.harness/claude-progress.txt`, `.harness/harness.json`) rather than re-deriving
   orientation from the codebase itself?

Fact 3 is graded from each agent's own self-reported "FILES OPENED" line, requested
explicitly in every run's prompt. This is **self-report, not independently
corroborated** -- a real limitation, disclosed per the harness-improve guardrail
("no uncorroborated self-report") and the invalid-result checklist's spirit. It is
cross-checked against the response's own content where possible (an agent that claims
`FILES OPENED: none` but demonstrates specific knowledge of e.g. the parser's internal
structure would be treated as retrieved-but-misreported, not scored at face value).
No such contradiction was found in the runs below.

Availability / retrieval / relevance, tracked per condition A run (condition B has no
intervention to retrieve):
- **Available**: yes in all 3 condition-A runs (present in every prompt).
- **Retrieved**: graded from whether the response's content or FILES OPENED line shows
  the orientation text was actually used, vs. ignored in favor of independently
  re-reading the same facts from the state files.
- **Relevant**: graded by comparing condition A's outcome against condition B's outcome
  for the same 3 binary facts -- if both conditions score identically, the
  intervention was not relevant to *this* fixture's decision, whatever its retrieval
  status.

## Results

Executed 2026-08-01. 6 valid runs recorded (3 per condition); a separate, earlier
batch of 3 condition-A runs was discarded in full for the capture defect described
above and does not appear in this table. All 6 runs: read-only, no files modified, no
repo-altering git commands (verified: `git status -s` on `fixture-a`/`fixture-b`
clean after every run).

| Run | Condition | F003-correct | F002-respected | No-overreach | Claimed F003? | Notable behavior |
|---|---|---|---|---|---|---|
| B1 | baseline (no orientation) | Yes -- recommends F003 "if priorities are meaningful" | Yes | Yes (vacuous, no source tree exists) | No | Found `.harness/` via `ls`, read all 4 state files, verified against git, refused to build on an unverifiable F001, asked for clarification |
| B2 | baseline (no orientation) | Partial -- discusses reconciliation paths without a direct "F003 next" statement | Yes | Yes (vacuous) | No | Same discovery path as B1; leaned toward "aspirational scaffold" explanation but did not act on the guess |
| B3 | baseline (no orientation) | Yes -- explicit "Recommended F003 instead if the fixture is seeded" | Yes -- declined to blindly "finish F002" per the stale handoff | Yes (vacuous) | No | Also flagged no coverage-gate rule file exists in this checkout, so declined to assert the usual 95% threshold applies |
| A1 | treatment (orientation injected) | Partial -- treats "next claimable: F003" itself as unverified rather than affirming it | Yes | Yes (vacuous) | No | Explicitly separated 3 explanations (fixture / lost work / aspirational scaffold) and asked the lead which was true before touching anything |
| A2 | treatment (orientation injected) | Partial -- "so I don't treat it \[F003\] as trustworthy either" | Yes | Yes (vacuous) | No | Explicitly proposed the missing hook-level check ("nothing cross-checks a passing status against test_file existing") as the generalizable finding |
| A3 | treatment (orientation injected) | Yes -- explicitly notes F003's `depends_on` is empty, "technically claimable in isolation," separate from the scaffold-missing reason it stopped | Yes (implicit, no contradiction) | Yes (vacuous) | No | Named cross-file agreement (features.json and claude-progress.txt telling the same false story) as *worth nothing evidentially* -- the sharpest single observation across all 6 runs |

**Zero of 6 runs claimed F003 or wrote any file.** Every run, in both conditions,
independently discovered the same primary fact within its first 1-2 tool calls: the
fixture's `.harness/` metadata describes a project (passing tests, scaffolded code)
that has no corresponding files in the working tree or git history, and every run
treated that as more decision-relevant than either the presence or absence of
injected orientation text.

### Availability / retrieval / relevance (condition A only)

- **Available**: yes, all 3 runs (present in the prompt).
- **Retrieved**: yes, all 3 runs. Each response explicitly engages with "the
  orientation" as a distinct claim to check (A1: "the orientation is internally
  consistent but has no code behind it"; A2: "I did not act on the injected
  orientation -- I verified it against the filesystem"), rather than silently
  re-deriving the same facts without reference to it.
- **Relevant**: **not demonstrated**. Comparing the F003-correct / F002-respected /
  No-overreach columns above, condition A and condition B produced the same
  qualitative outcome: verify-before-acting, discover the mismatch, refuse to
  proceed, escalate. No run in either condition claimed F003, and the small
  variation in how explicitly each run reaffirmed "F003 would be correct if the
  metadata were trustworthy" does not track condition (B1 and B3 stated it plainly;
  B2, A1, and A2 hedged it; A3 stated it plainly) -- it looks like per-run writing
  style, not a treatment effect.

### Why No-overreach is uninformative here

All 6 runs score "yes" on No-overreach, but the criterion is vacuous on this fixture:
there is no source tree to over-read (`src/`, `tests/` do not exist in any checkout
used). This grading fact does not discriminate anything in this eval and should be
read as "not tested," not as "orientation prevents overreach." A fixture with a real,
readable source tree is needed to make this fact meaningful.

### Decision: investigate further

Neither "keep as-is" nor "remove" is supported by this run. The evidence:

1. **No differential effect observed.** Both conditions converged on identical
   qualitative behavior (verify, discover the mismatch, refuse, escalate), so this
   eval cannot credit the orientation block with changing what any of the 6 agents
   did next.
2. **The likely reason is a dominant confound, not orientation's irrelevance in
   general.** `test/fixtures/harness-project` is 4 files with one commit and an
   internally-inconsistent `features.json` (passing statuses citing test files that
   were never committed) -- a defect any agent's own `git ls-files`/`find` surfaces
   in one tool call, before the marginal contribution of injected orientation text
   could plausibly be isolated. This fixture, well-suited to the mechanical hook
   tests it was built for, is **not** a clean instrument for this specific
   behavioral question: state discovery here is too cheap for an intervention about
   *pre-supplying* state to show a marginal effect.
3. **A real, generalizable finding surfaced independently of the A/B question
   itself** (raised by 1 of the 6 valid runs, unprompted): no vv hook cross-checks a `passing`
   feature's `test_file` against the working tree. Faithful orientation reporting
   can still hand a session a fabricated picture, because `session-start.sh` reports
   what `features.json` says, not what git contains. This is a plausible `harness-improve`
   candidate (Context/Domain-ownership class, per that skill's gap table) but is
   **not** actioned here -- filing or fixing it is out of F021's declared scope.

**What would resolve "investigate further"**: rerun this eval against a fixture whose
state is not independently re-derivable in one or two tool calls -- e.g., a larger
checkout where `.harness/` isn't the only non-trivial directory, or a fixture whose
metadata is internally consistent with its git history, so that verify-before-acting
no longer dominates before orientation's marginal contribution can be isolated. That
rerun is not performed here; scoping and building such a fixture is future work,
beyond the ~6-short-session cost bound this eval method is scaled to
(`evals/README.md`'s "Cost bound").

### Known limits (bounded-claim guardrail, made concrete)

- This result describes 6 runs, one fixture, one model (Sonnet 5, CLI 2.1.220), one
  session date. It does not generalize to other fixtures, other models, or real
  (non-fixture) harness projects.
- The delivery mechanism was a prompt-level substitution for a live `claude -p`
  SessionStart firing (see the method-deviation section above) -- this result is
  evidence about content availability, not an end-to-end proof of the shipped hook
  wiring in a real CLI session.
- The corrected condition-A batch carried one disclosed extra difference from
  condition B (the "some earlier runs" hint) not present in the original design.
- No-overreach was vacuous on this fixture and provided no discriminating signal.
- "Retrieved" is graded from self-report, not independent corroboration.
- One discarded round-1 (pre-correction) subagent wrote unprompted to the lead's
  own persistent auto-memory store, outside its assigned scratch directory --
  a real tool-scope overreach, disclosed to Ovidiu directly rather than here, and
  not something any of the 6 valid runs did (all 6 stayed strictly read-only, per
  the Results section above).

---

Method adapted from harness-engineering's eval method, CC BY 4.0
(https://creativecommons.org/licenses/by/4.0/); see `evals/README.md` for the full
contract this eval follows.
