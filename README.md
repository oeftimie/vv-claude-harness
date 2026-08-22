# VV Claude Code Harness

A Claude Code plugin that gives coding agents what they structurally lack: memory across
sessions, coordination when several run in parallel, and quality rules they cannot skip.
It ships as skills, declarative agents, and shell hooks — `/harness-init` scaffolds a
project, `/harness-continue` picks it up in every later session, and the hooks enforce
tests, scope, and git identity mechanically rather than by asking politely.

[Install](#install) · [What's in the box](#whats-in-the-box) · [Architecture](#architecture)
· [CHANGELOG](./CHANGELOG.md) · [INSTALL.md](./INSTALL.md) · [History and design origins](./docs/history.md)

New to the harness? The [field guide](https://oeftimie.github.io/vv-claude-harness/)
walks through the install, one session end to end, the gates, and parallel work. Its
source is in [`site/`](./site).

## The problem it solves

Every AI coding agent has the same Achilles heel: memory. Not the technical kind (context
windows keep growing) — the practical kind. Start a complex project, work for an hour, hit
a context limit or close the session, come back tomorrow. The agent has no idea what
happened. It is like onboarding a new contractor every morning who has never seen the
codebase.

Anthropic's engineering team framed it as
[the shift problem](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents):
a project staffed by engineers working shifts, where each new engineer arrives with no
memory of the previous shift. Two failures follow. The agent tries to one-shot the whole
project, runs out of context mid-implementation, and leaves a half-built mess. Or, more
insidiously, it looks around, sees working code, and declares victory at 30% complete.

The fix is not a bigger model. It is infrastructure: externalize state into files the next
session reads, and enforce the rules that matter with code instead of prose.

### Why files, not a memory system

* **Simplicity**: files need no infrastructure. The agent writes, the agent reads, done.
* **Transparency**: when an agent goes off the rails you can open the file and see what it
  thinks it is doing. You cannot debug a vector database mid-hallucination.
* **Structure**: `features.json` is JSON because, [as Anthropic noted](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents),
  "the model is less likely to inappropriately change or overwrite JSON files compared to
  Markdown files." The format itself enforces discipline.

The longer version — where this design came from, and how it changed across six major
versions — is in [docs/history.md](./docs/history.md).

## Install

**Prerequisites:** Claude Code CLI, git initialized in your project, `python3`, and
`jq` (`brew install jq` on macOS — used by the per-project build hooks `/harness-init`
writes).

From inside any Claude Code session:

```
/plugin marketplace add oeftimie/vv-claude-harness
/plugin install vv-harness
```

Claude Code auto-discovers the plugin's skills, agents, and hooks. Then initialize any
project that will span multiple sessions:

```bash
cd ~/Projects/MyApp
claude
/harness-init
```

Full prerequisites, migrating from the retired v3 installer, and optional setup (cost
telemetry, spec-gate signing config) are in [INSTALL.md](./INSTALL.md).

## Upgrade

**The plugin itself:**

```
/plugin update vv-harness
```

Updates are atomic — each version gets its own cache directory, so there's nothing to
clean up by hand. Updates land only when `.claude-plugin/plugin.json`'s version is
bumped; that's the update cache key.

**An existing harness-managed project**, after the plugin updates:

```
/harness-doctor          # report-first: what's out of date
/harness-doctor --fix    # apply the fix
```

`--fix` mechanically applies every upgrade step (hook copies, `.gitignore` rules,
`settings.json` wiring, the recorded `plugin_version`). See INSTALL.md's "Upgrading an
existing harness project" for what it does under the hood.

## Usage recommendations

### Solo work (most common)

Install the plugin (`/plugin install vv-harness`), then run `/harness-init` on any project that will span multiple sessions. At the start of every session, run `/harness-continue` — it reads your progress files, verifies git identity, and picks up where you left off.

Use **single-session mode** for features touching fewer than 5 files. The harness tracks progress via `TaskCreate`/`TaskUpdate` (which survive compaction), runs async build checks after edits, and mechanically blocks git pushes with wrong identity.

The plugin's SessionStart hook recovers your context automatically after compaction — its `compact` matcher re-injects feature status, Active Context, and the last handoff directly into model context.

### Parallel work (workflow mode)

Use workflow mode when two or more independent, spec-verified features are ready. The lead launches the `/vv-harness:implement-features` workflow: one Sonnet implementer per feature in an isolated worktree, then an Opus reviewer per feature, returning structured per-feature results the lead integrates. Each agent gets a physically separate copy of the repo — cleanest separation, no scope violations possible; the lead merges worktree branches during integration. When the Workflow tool is unavailable (older CLI, org-disabled), `/harness-continue` falls back to plain worktree-isolated subagents using the same `vv-harness:*` agent types.

The `TaskCompleted` hook mechanically enforces passing tests before any mirrored task can be marked complete, and the commit gate fires in the lead session at integration.

**Optional dual-engine review (F018/OVI-66)**: configure `.harness/harness.json`'s
`review.second_engine: "codex"` to have the lead run a Codex CLI review in parallel
with — and blind to — the Claude reviewer's own review. Absent the config, or absent
the `codex` CLI on `PATH`, behavior is unchanged (single-engine review); a missing CLI
skips with an explicit note rather than silently. Synthesis rules for combining both
engines' findings (dedupe by defect, a single-engine CRITICAL always survives,
cross-engine agreement raises confidence, provenance verified via `git show`) live in
`rules/parallel-work.md`'s Dual-Engine Review section. The second engine costs
Codex-subscription usage, not Claude tokens; the two engines disagree often on style,
so only correctness/security findings get the cross-engine consensus treatment.

### When NOT to use

* **Don't parallelize** features touching fewer than 3 files each — sequential single-session mode is cheaper. The Opus lead runs for the entire session regardless of how many agents a run launches; orchestration overhead adds up.
* **Don't use worktree isolation** when agents share interfaces — they need to see each other's changes in real time. Give one feature the shared interface and sequence the rest behind it.

### Token budget

The harness's always-on overhead is `CLAUDE.md`: ~4.2K tokens (if you copied the template to `~/.claude/CLAUDE.md`). In v4 the rule files are NOT auto-loaded by globs — they cost tokens only when the model reads them, following the pointers in the SessionStart orientation:
* `parallel-work.md`: ~4K, read before parallel work in harness projects
* `code-quality.md`: ~0.3K, read before writing code in harness projects

This is down from ~14.7K always-on in v3.2.1 (before eliminating redundant `engineering-standards.md` and `non-harness-workflow.md` rule files).

In non-harness projects, only CLAUDE.md loads (~4.2K). The orientation hook stays silent (no `.harness/` directory), so neither rule file is pointed to or read.

## What's in the box

| Component | Purpose |
|-----------|---------|
| `skills/harness-init/` | Project initialization with hooks and scaffolding |
| `skills/harness-continue/` | Session continuation with workflow launch prompts and the subagent fallback |
| `skills/harness-issue-prep/` | Verify and normalize a spec (Linear issue, pasted text, or a feature), then mark it ready for implementation |
| `skills/harness-issue-debug/` | Open a failed feature or a runner-parked Linear issue in a live repair session |
| `skills/harness-doctor/` | Report-first, idempotent instance health check with an optional `--fix` upgrade mode |
| `skills/harness-improve/` | Observation-first improvement loop: record a job contract, observe the baseline, one intervention, verify at the claim boundary |
| `skills/harness-dashboard/` | Launch F090's dashboard server (if not already running) and open F091's live session view in a browser |
| `agents/` | Declarative agent definitions (feature-implementer, layer-implementer, researcher, reviewer, spec-verification, reverification-guard, conformance-tester) |
| `schemas/` | Data contracts published for external consumers (readiness stamp, park/resolution formats) |
| `scripts/stamp.sh` | Deterministic file emitter for `/harness-init`, new + upgrade mode |
| `scripts/validate-features.py` | Stdlib `features.json` validator, run by harness-doctor and CI |
| `hooks/` | Plugin continuity hooks: session-start, session-end, statusline |
| `rules/parallel-work.md` | Parallel-work rules: feature schema, model selection, lead-owned state (harness projects only) |
| `rules/code-quality.md` | Mechanical code quality limits |
| `rules/context-summary.md` | `context_summary.md` template and update rules |
| `rules/debugging.md` | Four-phase systematic root-cause debugging process |
| `rules/mld-review.md` | Cadence and disposition rules for reviewing `.harness/mld/` entries |
| `rules/task-completion.md` | Task completion checklist |
| `rules/tdd.md` | 5-step TDD loop and coverage bar |
| `templates/CLAUDE.md` | Core engineering standards template (manual copy to `~/.claude/`) |
| `test/` | Fixture-based hook test suite, run in CI |
| `evals/` | Proportionate behavioral evals: does an intervention change what the agent actually does, not just its terminology (semi-manual, not CI-wired) |
| `evals/hillclimb/` + `autoresearch.sh` | Deterministic conformance suite over the shipped plugin — `harness_score`, 0–100, offline (see [How the harness is checked](#how-the-harness-is-checked)) |

## Architecture

### Global (travels with you)

Installed via `/plugin`, updated atomically (each version gets its own cache directory):

```
vv-harness/                                            # Plugin root
├── skills/
│   ├── harness-init/                                  # /harness-init skill + hook templates
│   ├── harness-continue/                              # /harness-continue skill + launch-prompts.md
│   ├── harness-issue-prep/                            # Spec gate: verify, normalize, stamp a spec
│   ├── harness-issue-debug/                           # Repair loop for failed or runner-parked work
│   ├── harness-doctor/                                # Report-first instance health check + --fix
│   ├── harness-improve/                               # Observation-first improvement loop for one job
│   └── harness-dashboard/                             # /harness-dashboard skill: launch F090's server + open F091's page
├── agents/                                            # Declarative agent definitions (spawned as vv-harness:*)
│   ├── feature-implementer.md                         # Sonnet, scoped TDD on one feature
│   ├── layer-implementer.md                           # Sonnet, owns one architectural layer
│   ├── researcher.md                                  # Sonnet, retrieval-only (Write for findings file)
│   ├── reviewer.md                                    # Opus, high effort, no Edit/Write tools
│   ├── spec-verification.md                           # Opus, read-only spec gate (SV-01..SV-06)
│   ├── reverification-guard.md                        # Sonnet, read-only re-verify of human revisions
│   └── conformance-tester.md                          # Sonnet, author-blind behavior tests from spec alone
├── hooks/
│   ├── session-start.sh                               # Orientation, spec-drift warning, compaction recovery
│   ├── session-end.sh                                 # Session discipline audit
│   ├── dashboard-log.sh                               # Opt-in event capture for the live dashboard (VV_HARNESS_DASHBOARD=1)
│   ├── dashboard/                                     # SSE server + node-graph view served locally
│   └── statusline.sh                                  # Live feature progress (wired by /harness-init)
├── rules/
│   ├── code-quality.md                                # Mechanical code quality limits
│   ├── context-summary.md                             # context_summary.md template + update rules
│   ├── debugging.md                                   # Four-phase systematic root-cause process
│   ├── mld-review.md                                  # Cadence + disposition rules for .harness/mld/ entries
│   ├── parallel-work.md                               # Parallel-work rules: feature schema, model selection, lead-owned state
│   ├── task-completion.md                             # Completion checklist
│   └── tdd.md                                         # 5-step TDD loop + coverage bar
├── schemas/
│   ├── readiness-stamp.md                             # Stamp, hashing, HMAC, park/resolution contracts
│   └── feature.schema.json                            # Canonical features.json envelope + feature object
├── scripts/
│   ├── stamp.sh                                       # Deterministic file emitter for /harness-init (+ upgrade mode)
│   └── validate-features.py                           # Stdlib features.json validator, run by harness-doctor
└── templates/
    └── CLAUDE.md                                      # Core standards template (manual copy to ~/.claude/)
```

### Per-project (created by initializer)

```
project-root/
├── CLAUDE.md
├── .claude/
│   ├── settings.json                                  # Build + quality gate hooks, statusLine,
│   │                                                  #   permissions allowlist
│   └── hooks/
│       ├── verify-task-quality.sh                     # TaskCompleted enforcement
│       ├── enforce-scope.sh                           # PreToolUse scope enforcement (incl. lead-owned state)
│       ├── verify-git-identity.sh                     # PreToolUse git identity verification
│       ├── commit-gate.sh                             # PreToolUse commit-content gate (secret scan)
│       ├── harness_state.py                           # Shared features.json read/write module
│       └── statusline.sh                              # Project copy of the plugin status line
└── .harness/
    ├── harness.json                                   # Config, git identity, workflow config, plugin_version
    ├── features.json                                  # Feature tracking (with scope, dependencies)
    ├── context_summary.md                             # Decisions, patterns, gotchas, active context
    ├── claude-progress.txt                            # Session-boundary handoff
    ├── mld/                                           # Optional: builder-only Mistakes/Learnings/Desires
    ├── SESSION_INCOMPLETE                             # Discipline gaps from last session (gitignored)
    └── init.sh                                        # Build/test script
```

## Three tiers of enforcement

There are three reliability tiers for agent coordination, and it matters which tier each rule lives in. A rule that only exists as prose gets followed most of the time; a rule that exists as an exit code gets followed every time.

**Mechanical (shell hooks, exit codes)**: very high reliability. The hook blocks the action; the agent cannot proceed without satisfying the constraint.

| Hook | Event | What it enforces |
|------|-------|-----------------|
| `verify-task-quality.sh` | TaskCompleted | Tests must pass before task completion is accepted |
| `commit-gate.sh` | PreToolUse (Bash) | The full suite must pass before a commit may flip a feature to `passing` |
| `enforce-scope.sh` | PreToolUse (Edit/Write/MultiEdit) | Edits blocked outside the agent's assigned scope, and to the three lead-owned state files (`features.json`, `context_summary.md`, `claude-progress.txt`) regardless of scope |
| `verify-git-identity.sh` | PreToolUse (Bash) | Git push/pull blocked if identity doesn't match harness.json |

The task gate is tiered rather than all-or-nothing: on each completion it runs the fast
`smoke_test`, then the targeted feature's own recorded test file via `focused_test` — never
the whole suite, because per-task full runs cost minutes per checkpoint and let unrelated
red jam every completion. The full suite runs where it actually decides something: the
commit that flips a feature to `passing`, and the lead's session-end run. A stack with no
per-file runner reports a skip rather than a fake green.

**Prompted (shell hooks with feedback)**: high reliability. The hook delivers a message to the agent, but the agent decides whether to follow it. `enforce-scope.sh`'s Bash coverage lives here rather than in the mechanical tier above: it does block the call, but the *detection* itself is pattern-based and evadable by construction (unlike Edit/Write, where the tool reports the real target unambiguously) — the goal is stopping accidental drift, not defeating an adversarial agent.

| Hook | Event | What it does |
|------|-------|-------------|
| `session-start.sh` (plugin) | SessionStart | Injects orientation at start; its `compact` matcher re-injects context after compaction |
| `session-end.sh` (plugin) | SessionEnd | Audits discipline into `SESSION_INCOMPLETE`, surfaced at next session start |
| `enforce-scope.sh` | PreToolUse (Bash) | Best-effort: denies Bash write commands (`>`, `>>`, `tee`, `cp`, `mv`, `sed -i`, `rm`) whose target is outside scope or is a lead-owned state file |
| `commit-gate.sh` | PreToolUse (Bash) | Best-effort: denies `git commit` calls that stage-and-commit in one step, or whose staged additions look like a secret; opt-in house-style scan. Pattern-based and evadable by construction, same posture as `enforce-scope.sh`'s Bash coverage |

**Structural (file existence, JSON schema)**: high reliability. `features.json` requiring `test_file` and `coverage` fields. The `.harness/` directory gating mode selection. Agents respect structure more than prose.

**Instructional (prose in CLAUDE.md, rules, skills)**: medium reliability. "Use TDD." "Don't modify files outside scope." "Verify git identity before push." These work most of the time. Over long contexts, compliance drifts.

## Core principles

These have held steady across all versions:

* **Predictable input**: When Claude orchestrates and starts sub-agents, each sub-agent verifies the initialization state is the same, avoiding tangents to fix things outside the defined prompt.

* **Prescribed output format**: Each sub-agent has defined exit expectations: testing, checks, status updates. When they return to the orchestrator, they all return at the same level of quality.

* **Progressive discovery**: Context storage is hierarchical to protect the agent's context window. Drop MCP tools if they're not necessary. If there's an API, prefer to ask the sub-agent to build the necessary API calls based on documentation rather than loading 100 tools in context.

* **Mechanical over instructional**: If a rule matters enough to write down, it matters enough to enforce with a hook. Shell scripts don't drift over long contexts.

* **Filesystem as connective tissue**: Not because files are the optimal data structure for agent memory (they're not), but because they're the optimal trade-off between simplicity, transparency, and effectiveness.

## The spec gate

`/harness-init` Step 5.1 and the `harness-issue-prep` skill spawn the `spec-verification` and
`reverification-guard` agents (read-only, spec-in-prompt) to verify a specification is
testable, unambiguous, and internally consistent before any implementation starts. The
harness is the **mint**: it verifies specs interactively, where human judgment is cheap,
and emits proof of verification: a local `spec` field on a feature, or a signed
readiness stamp posted to a Linear issue. An external issue-to-PR runner (out of scope
for this repo) is a **consumer**: it validates the stamp's hash and HMAC before trusting
an issue as ready for unattended work. See [schemas/readiness-stamp.md](./schemas/readiness-stamp.md)
for the stamp shape, the canonical hashing recipe, and the consumer verification rules.

The `features.json` envelope and the 16-field feature object have a single owner too:
[schemas/feature.schema.json](./schemas/feature.schema.json) is the canonical definition;
`scripts/validate-features.py` enforces it (stdlib only, no `jsonschema` dependency) and is
wired into `test/run-tests.sh`. The worked example lives in the Feature Schema section of
`rules/parallel-work.md` — this README and `skills/harness-init/SKILL.md` link there
instead of restating the field list.

## How the harness is checked

The gates decide whether your work may proceed. Something has to decide whether the
gates still work — a separate question needing a separate instrument. There are two,
and they are not interchangeable.

**Behavioral evals** (`evals/*.md`) ask whether an intervention changed what an agent
actually *did*. Two conditions, three runs each, fresh sessions, one named decision;
a person reads the transcripts and grades them against binary facts stated in advance.
Availability, retrieval and relevance are recorded separately — an intervention can be
present but never read, or read but change nothing. Method: [evals/README.md](./evals/README.md).

**The hillclimb suite** (`evals/hillclimb/`) asks whether the plugin's own machinery
behaves as specified, and needs no model at all:

```bash
bash autoresearch.sh        # ~200s, prints METRIC harness_score=<0..100>
```

Roughly 4,200 boolean checks across six weighted suites — behavior (0.25), gates
(0.20), regression (0.20), contracts (0.15), static (0.10), determinism (0.10). Every
check runs the real shipped file against a fixture built fresh in a temp directory with
its own `HOME`, no git config, and a fixed timezone and locale, so two concurrent runs
are byte-identical and a score change is a plugin change. `test/run-tests.sh` is folded
in whole as the regression aggregate: without it, the cheapest way to raise the score
would be to trade an existing guarantee for a new one.

Failing checks print one line each naming what failed and why, so the output is a work
list rather than a verdict.

The checks are additive by policy — one may be added, but not removed, weakened, or
made conditional to raise the score, and the total may never decrease. The suite is
itself mutation-tested: deliberate breakages are introduced into shipped files one at a
time to confirm a check notices. When a mutation leaves every check passing, that is a
gap in the suite, not evidence the code is safe. The recurring gap it exposes is
asserting *shape* instead of *content* — "the report is well-formed" still passes after
the thing being reported has been removed.

## Known limitations

* **Lead session resumption**: if the lead session dies mid-run, completed workflow agents'
  worktree branches survive and a run can be resumed (`resumeFromRunId`, resent with its
  original `args`) — but the lead's own in-flight integration state is reconstructed from
  `features.json` and `claude-progress.txt`, not recovered.
* **SessionEnd cannot block**: the session-end discipline audit records gaps and surfaces
  them at the next session start, but by platform design it cannot stop a session from
  ending with those gaps. Self-healing, not preventive.
* **Bash-level enforcement is best-effort**: scope and commit gates inspect Bash commands
  by pattern, so they stop accidental drift rather than an adversarial agent. Edit/Write
  coverage is exact; Bash coverage is not.
* **Coverage is self-reported**: the coverage gate compares the number a feature records
  against its target. On a stack with no coverage tooling the stage skips, and a feature
  that declares a target but records nothing is flagged rather than blocked.

## Some screenshots from my sessions

<img width="1248" height="1076" alt="Screenshot 2026-01-09 at 12 47 25" src="https://github.com/user-attachments/assets/25b4be66-c384-4225-92a6-cd4d2c8964a8" />
<img width="849" height="766" alt="Screenshot 2026-01-09 at 12 42 01" src="https://github.com/user-attachments/assets/031c3dfb-4a35-4b6b-bac9-200049c7ee28" />

### UI test automation with Xcode & Claude Code

https://github.com/user-attachments/assets/9684d120-3cbf-438d-a01f-469387f507ff

---

Version history: [CHANGELOG.md](./CHANGELOG.md). Design origins and the v2.0 → v6.0
evolution: [docs/history.md](./docs/history.md).
