# Harness Backlog

Candidates the Phase 5.5 promotion and ablation passes have surfaced. Not
auto-applied: a human or a dedicated session executes a row, then marks it
promoted. Cross-project pattern aggregation is a future extension, not done
here -- this file is per-project.

| date | observation | proposed owner | evidence pointer | score | status | last_seen |
|---|---|---|---|---|---|---|
| 2026-08-09 | Recurring bug classes get fixed one call site at a time (ARG_MAX argv class needed 3 fixes across 3 sessions); no rule tells the implementer to sweep the class | rule file edit (tdd.md or debugging.md: "when fixing an instance of a recurring class, grep for the class") | Meta-Session 2026-08-09 (batch), F096 + review round | 1 | candidate | 2026-08-09 |
| 2026-08-09 | Feature scope arrays omit test/run-tests.sh even though every feature writes tests there; enforce-scope would deny a teammate its own TDD writes | skill (harness-issue-prep/harness-init: default the project's test-runner path into scope for testable features) | review finding "F094/F095/F096 edited test/run-tests.sh outside their recorded scope" | 1 | candidate | 2026-08-09 |
| 2026-08-09 | Multi-dimension review workflows verify duplicate findings separately (~2x verify cost); dedup barrier before verify fan-out is the fix | not-yet (workflow authoring pattern, no durable owner file yet) | Meta-Session 2026-08-09 (batch), review workflow wf_62aae2ac-e3b | 1 | candidate | 2026-08-09 |
| 2026-08-09 | Ablation: commit-gate compound-stage-and-commit denial fired twice on the lead's own merge/suite one-liners (git commit && bash suite) -- both times a false positive on a non-staging command, repaired by splitting; matcher may be too broad | revise (narrow the compound detection to commands that actually stage) | this session's merge phase, two denials | 1 | candidate | 2026-08-09 |
