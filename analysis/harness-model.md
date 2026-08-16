# The harness, as a model a newcomer can hold

Derived from this repository on 2026-08-16, plugin version 6.0.2
(`.claude-plugin/plugin.json`).

## 1. The one-sentence version

The harness gives a coding agent three things it structurally lacks — memory across
sessions, coordination when several agents run at once, and rules it cannot skip — by
writing state to plain files and enforcing rules with shell exit codes instead of prose
(`README.md:3-7`).

## 2. The problem being solved

`README.md:12-28` frames it as **the shift problem**, borrowed from Anthropic's
engineering write-up: a project staffed by engineers working shifts, each arriving with
no memory of the last shift. Two failure modes follow, and a newcomer should be able to
name both:

- **Overreach**: the agent tries to one-shot the whole project, runs out of context
  mid-implementation, leaves a half-built mess.
- **Premature victory** (the more insidious one): the agent looks around, sees working
  code, and declares done at 30% complete.

The stated fix is not a bigger model — it is infrastructure (`README.md:27-28`).

### Why files rather than a memory system

`README.md:30-37` gives three reasons, and the third is the one people miss:

- **Simplicity** — files need no infrastructure.
- **Transparency** — you can open the file mid-hallucination and see what the agent
  thinks it is doing. You cannot debug a vector database that way.
- **Structure** — `features.json` is JSON because "the model is less likely to
  inappropriately change or overwrite JSON files compared to Markdown files". The
  format itself enforces discipline.

## 3. The two halves of the install

This is the single most common source of confusion, so the site names it early.

**Global half** — installed once via `/plugin`, travels with you, versioned by
`.claude-plugin/plugin.json`'s `version` field, which is also the update cache key
(`README.md:75-78`, `AGENTS.md`). Contains `skills/`, `agents/`, `hooks/`, `rules/`,
`schemas/`, `scripts/`, `templates/` (`README.md:161-205`).

**Per-project half** — created by `/harness-init` inside one repo
(`README.md:207-230`):

```
project-root/
├── .claude/
│   ├── settings.json            # build + quality gate hooks, statusLine, permissions
│   └── hooks/
│       ├── verify-task-quality.sh   # TaskCompleted enforcement
│       ├── enforce-scope.sh         # PreToolUse scope enforcement
│       ├── verify-git-identity.sh   # PreToolUse git identity check
│       ├── commit-gate.sh           # PreToolUse commit-content gate
│       ├── harness_state.py         # shared features.json read/write
│       └── statusline.sh
└── .harness/
    ├── harness.json             # config, git identity, plugin_version
    ├── features.json            # feature tracking
    ├── context_summary.md       # decisions, patterns, gotchas
    ├── claude-progress.txt      # session-boundary handoff
    ├── mld/                     # optional per-session Mistakes/Learnings/Desires
    ├── SESSION_INCOMPLETE       # discipline gaps from last session (gitignored)
    └── init.sh                  # build/test script
```

The rule that falls out of this: **`.harness/` is the project's memory, `.claude/hooks/`
is the project's immune system.** Installing the plugin alone does nothing to a repo
until `/harness-init` runs.

## 4. Three files, three jobs

A newcomer conflates these constantly. They are distinct by design:

| File | Written by | Read when | Answers |
|------|-----------|-----------|---------|
| `features.json` | Lead only | Every session start | *What is the work, and where does it stand?* |
| `context_summary.md` | Lead only | Every session start | *What did we learn that isn't in the code?* |
| `claude-progress.txt` | Lead only | Every session start | *What was the last shift doing, and what's next?* |

All three are **lead-owned state**: `enforce-scope.sh` blocks edits to them regardless of
the editing agent's assigned scope (`README.md:242`, `rules/parallel-work.md` §"Lead-owned
state"). A spawned implementer physically cannot write them. That is deliberate — it is
what stops five parallel agents from racing on one JSON file.

A fourth, `.harness/mld/`, is a raw per-session log of Mistakes / Learnings / Desires.
Its defining property: **nothing reads it back into model context.**
`session-start.sh` carries a hard, tested guarantee never to read `.harness/mld/`
(`skills/harness-continue/SKILL.md:245`). It exists for periodic human review, not
in-session consumption. Distinguishing it from the retrospective in
`context_summary.md` is a real comprehension checkpoint.

## 5. The feature object

Canonical definition: `schemas/feature.schema.json`. Enforced by
`scripts/validate-features.py` (stdlib only, no `jsonschema` dependency), which is wired
into `test/run-tests.sh` (`README.md:291-296`).

**Ten required fields**: `id`, `description`, `priority`, `status`, `scope`,
`depends_on`, `assigned_to`, `test_file`, `coverage`, `notes`.

**Status enum, exhaustive**: `pending`, `in-progress`, `blocked`, `passing`, `failed`.

**Optional operational metrics** — these are the interesting ones, because they are what
lets a later session make a *better* decision rather than the same one:
`correction_cycles`, `scope_expansions`, `approaches_tried`, `failure_reason`,
`discovered_via`, `spec`, `qa_binding`, `proof`, `coverage_target`, `delivered`,
`design_contract`, `risk`, `require_plan_approval`.

Two fields carry most of the teaching weight:

- **`scope`** — the directories and files this feature owns. It is pasted into a
  spawned agent's prompt to define its boundary, and `enforce-scope.sh` enforces it
  mechanically on Edit/Write.
- **`depends_on`** — feature ids that must reach `passing` first. Together with
  non-overlapping `scope`, an empty `depends_on` is the *definition* of "independent",
  which is the precondition for running work in parallel
  (`skills/harness-continue/SKILL.md:114-115`, `rules/parallel-work.md:12-17`).

`description` has a trap worth teaching: once a `spec` object is attached, editing the
description string invalidates `spec.hash` (`schemas/feature.schema.json`). This is why
the session-start hook can warn about "spec drift".

## 6. The session loop

What actually happens, in order, from `skills/harness-continue/SKILL.md`:

1. **Orient** (Step 1) — the plugin's SessionStart hook has *already* injected feature
   status, the next claimable feature, the last handoff, Active Context, a git-identity
   warning on mismatch, and any `SESSION_INCOMPLETE` gaps. Use the injected block rather
   than re-reading the files. Resolve surfaced gaps before starting new work.
2. **Verify git identity** (Step 2) — the hook compared `git config user.email` against
   `harness.json`; the SSH identity it does *not* check, so `ssh -T git@github.com` is
   still on you.
3. **Smoke test** (Step 2.5) — `./.harness/init.sh smoke_test`, within the first five
   actions, every session. Framed explicitly as *a gate, not a diagnostic*: it proves
   the environment was already good before you touched it, so a later failure is
   provably yours. There is a documented footgun here (OVI-106): `init.sh`'s own default
   target is `full_test`, so omitting the argument silently runs the whole suite instead
   of the fast gate.
4. **Worker epoch check** (Step 2.6) — compares the live CLI version against the
   recorded `worker` block; prompts for requalification on a large delta. Degrades
   silently when absent or unparseable. A prompt, never a gate.
5. **Set effort** (Step 3) — high for architecture/debugging/reviewing returned agent
   work; medium for the TDD loop; low for formatting.
6. **Decide mode** (Step 4) — single-session or workflow. See §8.
7. **Work** (Step 5a or 5b).
8. **Close out** — full suite, `features.json` audit, mandatory retrospective, MLD file,
   handoff to `claude-progress.txt`, commit
   (`skills/harness-continue/SKILL.md:229-259`).

### Compaction is a first-class event, not an accident

When context runs low you compact at a clean breakpoint — after tests pass, after a
phase completes — with a focused instruction. Afterward the SessionStart hook's
`compact` matcher re-injects a recovery block plus fresh orientation
(`skills/harness-continue/SKILL.md:210-227`, `README.md:98`). The practical rule for a
newcomer: **tasks and files survive compaction; conversation prose does not.**

## 7. Four gates, and the tier each lives in

`README.md:232-263` is the conceptual heart of the project, and the site treats it that
way. The claim: *a rule that only exists as prose gets followed most of the time; a rule
that exists as an exit code gets followed every time.*

**Mechanical** (shell hooks, exit codes) — very high reliability:

| Hook | Event | Enforces |
|------|-------|----------|
| `verify-task-quality.sh` | TaskCompleted | Tests pass before a task may be marked complete |
| `commit-gate.sh` | PreToolUse (Bash) | Full suite passes before a commit flips a feature to `passing` |
| `enforce-scope.sh` | PreToolUse (Edit/Write/MultiEdit) | Edits outside assigned scope blocked; the three lead-owned state files blocked regardless of scope |
| `verify-git-identity.sh` | PreToolUse (Bash) | Push/pull blocked when identity ≠ `harness.json` |

**The task gate is tiered, and the reason is a real engineering trade-off**
(`README.md:245-250`): on each completion it runs the fast `smoke_test`, then only the
targeted feature's own recorded test file via `focused_test` — never the whole suite,
because per-task full runs cost minutes per checkpoint and let unrelated red jam every
completion. The full suite runs where it actually decides something: the commit that
flips a feature to `passing`, and the lead's session-end run. A stack with no per-file
runner reports a **skip**, not a fake green.

Test targets, from `skills/harness-init/init.sh.template:3-22`:

```
.harness/init.sh [smoke_test | full_test | focused_test <test_file>]   # default: full_test
```

**Prompted** (hooks with feedback) — high reliability, agent still decides:
`session-start.sh`, `session-end.sh`, and the *Bash* coverage of `enforce-scope.sh` and
`commit-gate.sh`. The honesty here is worth teaching: Bash detection is pattern-based and
**evadable by construction**, so the goal is stopping accidental drift, not defeating an
adversarial agent (`README.md:252`, `README.md:307-309`). Edit/Write coverage is exact
because the tool reports the real target.

**Structural** (file existence, JSON schema) — high reliability. `features.json`
requiring `test_file` and `coverage`; the `.harness/` directory gating mode selection.

**Instructional** (prose in CLAUDE.md, rules, skills) — medium reliability. Compliance
drifts over long contexts. `rules/tdd.md` says this about its own subject: the same
discipline lived as always-on prose for a full measurement window and `buggy_code` still
led the friction table at 33%; what measurably worked was wiring TDD to a gate.

## 8. Single-session vs workflow mode

**Single-session** when one feature is next and touches fewer than 5 files, or the work
is sequential. Declare it out loud — "I'm both lead and implementer" — so the choice is
conscious (`skills/harness-continue/SKILL.md:106-111`).

**Workflow mode** when two or more **independent, spec-verified** features are ready,
where independent means empty `depends_on` **and** non-overlapping `scope`. Notably: two
verified independent features win over single-session even when each touches fewer than
5 files (`skills/harness-continue/SKILL.md:113-118`).

Mechanism: the lead launches `/vv-harness:implement-features` — one implementer per
feature in an isolated worktree, then a reviewer per feature, returning structured
per-feature results the lead integrates. The lead never edits feature code in this mode
(`skills/harness-continue/SKILL.md:263-268`). Availability is probed by capability;
when the `Workflow` tool is unavailable the documented fallback is plain
worktree-isolated subagents using the same `vv-harness:*` agent types — *do not abort
parallel work* (`skills/harness-continue/SKILL.md:128-147`).

**When not to** (`README.md:117-120`, `rules/parallel-work.md:21-26`): only one feature
ready; work is sequential; orchestration overhead exceeds the benefit; features touch
fewer than 3 files each; or agents share interfaces — worktree isolation is exactly wrong
there, because they need to see each other's changes. Give one feature the shared
interface and sequence the rest behind it.

### Model policy is a tier split, not a model list

`rules/parallel-work.md:115-148`. Roles map to cognitive-demand tiers, and which model
*name* fills each tier is a **binding** updated by requalification, not policy:

| Role | Tier | Reasoning |
|------|------|-----------|
| Lead (coordinator) | Opus | Decomposition, synthesis, quality judgment |
| Feature implementer | Sonnet | Scoped TDD in a defined directory |
| Layer implementer | Sonnet | Same |
| Researcher | Sonnet | Retrieval-heavy, not reasoning-heavy |
| Reviewer | Opus | Deep review catches subtle bugs; worth the cost |

The subtlety a newcomer gets wrong: **elevation escalates the review, not the
implementer** (`rules/parallel-work.md:165-176`). A feature marked `risk: "elevated"`
buys a deeper review pass and optionally an author-blind conformance check — both judge
the work rather than produce it. Executors stay on the execution tier.

Static elevation criteria (`rules/parallel-work.md:151-158`): 10+ files or multiple
modules; cross-cutting concerns; security-sensitive code; first feature in a new
codebase.

## 9. The spec gate: the harness as a mint

`README.md:279-289`. `/harness-init` Step 5.1 and the `harness-issue-prep` skill spawn
read-only `spec-verification` and `reverification-guard` agents to prove a spec is
testable, unambiguous, and internally consistent **before implementation starts**.

The framing to teach: the harness is the **mint** — it verifies specs interactively,
where human judgment is cheap, and emits proof of that verification (a local `spec`
field, or a signed readiness stamp on a Linear issue). An external issue-to-PR runner is
a **consumer** — it validates the stamp's hash and HMAC before trusting an issue as ready
for unattended work. Verdicts are PASS / ASK / BLOCK.

`reverification-guard` exists for a specific failure: when a human answers the gate's
questions, the guard re-runs every check on the amended text and **refuses to advance on
pressure alone** (`agents/reverification-guard.md`). Anti-sycophancy encoded as an agent.

## 10. Known limitations, stated plainly

`README.md:298-312`. The site reproduces these rather than burying them:

- **Lead session resumption** — completed workflow agents' worktree branches survive and
  a run is resumable (`resumeFromRunId`, resent with its original `args`), but the lead's
  own in-flight integration state is reconstructed from `features.json` and
  `claude-progress.txt`, not recovered.
- **SessionEnd cannot block** — the discipline audit records gaps and surfaces them next
  session; by platform design it cannot stop a session ending with them. Self-healing,
  not preventive.
- **Bash enforcement is best-effort** — pattern-based, so it stops accidental drift, not
  an adversarial agent. Edit/Write coverage is exact.
- **Coverage is self-reported** — the gate compares a recorded number against a target.
  With no coverage tooling the stage skips; a feature declaring a target but recording
  nothing is flagged, not blocked.

## 11. Core principles that have held across versions

`README.md:265-277`:

- **Predictable input** — every sub-agent verifies the same initialization state, so it
  doesn't wander off fixing things outside its prompt.
- **Prescribed output format** — each sub-agent has defined exit expectations, so work
  returns to the orchestrator at the same level of quality.
- **Progressive discovery** — context storage is hierarchical to protect the context
  window. Drop MCP tools you don't need; prefer teaching a sub-agent to build API calls
  from docs over loading 100 tools.
- **Mechanical over instructional** — if a rule matters enough to write down, it matters
  enough to enforce with a hook.
- **Filesystem as connective tissue** — not the optimal data structure for agent memory,
  the optimal trade-off between simplicity, transparency, and effectiveness.

## 12. Token cost, because someone will ask

`README.md:122-131`. Always-on overhead is `CLAUDE.md` at ~4.2K tokens. Rule files are
**not** auto-loaded by globs — they cost tokens only when read, following pointers in the
SessionStart orientation (`parallel-work.md` ~4K, `code-quality.md` ~0.3K). Down from
~14.7K always-on in v3.2.1. In non-harness projects only CLAUDE.md loads and the
orientation hook stays silent.
