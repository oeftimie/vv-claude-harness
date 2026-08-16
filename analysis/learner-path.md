# What a new engineer needs, in what order

The audience: an engineer who is competent with git and tests, has used Claude Code at
least once, and has never seen this harness. The goal of the site is not coverage — it is
that after 20 minutes they can run a session correctly and know why each step exists.

## The ordering principle

Motivation before mechanism, mechanism before reference. Someone who installs a plugin
without believing in the problem it solves will skip the parts that feel like ceremony —
and in this harness, the parts that feel like ceremony (the smoke test, the retrospective,
the handoff) are the parts that carry the value.

So: **problem → install → one real session → the gates → parallelism → reference.**

## The six stops

### 1. Why this exists
The shift problem, and its two failure modes: overreach, and premature victory at 30%.
Then the design answer: files, not a memory system, for simplicity / transparency /
structure. Ends on the line the rest of the site rests on — *mechanical over
instructional*.

**Done when** they can say what happens to an agent's knowledge between two sessions
without the harness.

### 2. Quickstart
Two commands to install the plugin, one to initialize a project, one to start every later
session. Prerequisites stated up front (Claude Code CLI, git initialized, `python3`,
`jq`). What `/harness-init` writes, and the split between the global plugin and the
per-project `.harness/` + `.claude/hooks/`.

**Done when** they can point at a directory listing and say which half of the install
produced each file.

### 3. One session, end to end
The `/harness-continue` loop: orient → git identity → smoke test → effort → mode →
work → close out. The smoke test gets its own beat because the reasoning is
counter-intuitive and generalizes: *it is a gate, not a diagnostic* — it proves the
environment was good before you touched it. Compaction gets a beat because it is the
mechanic most newcomers meet by accident.

**Done when** they can list what survives compaction (files, tasks) and what does not
(conversation prose).

### 4. The gates
The four hooks, the three reliability tiers, and the tiered task gate. This is the
section where the site must be honest rather than impressive: Bash-level enforcement is
pattern-based and evadable by construction, SessionEnd cannot block, coverage is
self-reported. A newcomer who learns the limits trusts the parts that are exact.

**Done when** they can say why the task gate runs `focused_test` and not the full suite,
and where the full suite *does* run.

### 5. Parallel work
The definition of independent (empty `depends_on` **and** non-overlapping `scope`), the
worktree model, the role→tier model policy, the fallback when the `Workflow` tool is
unavailable, and — given equal weight — when *not* to parallelize.

**Done when** they can look at two features and say correctly whether they may run in
parallel.

### 6. Reference
Commands, the feature object, status enum, test targets, the completion checklist, and a
glossary. Optimized for return visits, not first reads.

## Misconceptions to pre-empt

These are the ones the source material implies people actually hit. Each gets an explicit
callout on the site rather than being left to inference.

| Misconception | The correction | Source |
|---|---|---|
| "Installing the plugin sets up my repo." | It does nothing to a repo until `/harness-init` runs. Plugin = global; `.harness/` = per project. | `README.md:55-62` |
| "`./.harness/init.sh` runs the quick check." | Its default target is `full_test`. Omit the argument and you silently run the whole suite. Pass `smoke_test` explicitly. | `skills/harness-continue/SKILL.md:50` |
| "The retrospective and the MLD file are the same thing." | The retrospective is cumulative analysis in `context_summary.md` that future sessions read. MLD is a raw per-session log that **nothing** reads back into context — `session-start.sh` is guaranteed never to read `.harness/mld/`. | `skills/harness-continue/SKILL.md:234-245` |
| "Elevated risk means a stronger implementer." | Elevation escalates the *review*, not the implementer. Executors stay on the execution tier. | `rules/parallel-work.md:165-176` |
| "Fewer than 5 files ⇒ single-session." | Two *verified independent* features beat single-session even when each touches fewer than 5 files. The <5-file rule decides between one feature and one session, not between one and two features. | `skills/harness-continue/SKILL.md:113-118` |
| "Worktree isolation is always the safer choice." | Not when agents share an interface — they need to see each other's changes. Give one feature the shared interface and sequence the rest. | `README.md:120` |
| "No `Workflow` tool means no parallel work." | Fall back to plain worktree-isolated subagents using the same `vv-harness:*` agent types. Do not abort. | `skills/harness-continue/SKILL.md:138-147` |
| "The hooks make cheating impossible." | Edit/Write scope enforcement is exact. Bash-level enforcement is pattern-based and evadable by construction; it stops accidental drift. | `README.md:252`, `README.md:307-309` |
| "A green task gate means the suite passes." | The task gate runs `smoke_test` + that feature's own `focused_test`. The full suite runs at the commit that flips a feature to `passing`, and at session end. | `README.md:245-250` |
| "Coverage is measured for me." | Coverage is self-reported: the gate compares a recorded number against a target, and skips where no tooling exists. | `README.md:310-312` |

## Tone

The repo's own voice is direct and admits limits (`AGENTS.md`, `README.md`'s "Known
limitations"). The site matches it. No "revolutionary", no "seamless". Where a mechanism
is best-effort, the site says best-effort.
