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
| 2026-08-09 | Ablation: commit-gate denied a non-staging `git commit --no-edit 2>&1` one-liner. CORRECTED diagnosis (first row version blamed && chains -- wrong): the F052 bare-pathspec rule read the unquoted redirection `2>&1` as a pathspec; chains/pipes segment correctly. Fixed as F109 (redirections skipped when the RAW token is unquoted/unescaped; quoted `'2>&1'` still denies as a real pathspec) | hook change | F109, v5.6.1 | 1 | promoted | 2026-08-09 |
| 2026-08-09 | Push guard blocked `git push origin v5.6.0` (a tag push) while checked out on main. Two causes found: the "main" substring scan ran over the WHOLE compound command (a `git log origin/main` in a later segment triggered it), and the bare-push branch check ignored explicit non-main refspecs. Fixed in ~/.claude/hooks/git-guard.sh (personal hook, not repo content): per-segment evaluation, refspec-aware (HEAD counts as current branch; --all/--mirror/--branches treated as branch-carrying; bare push keeps the branch check; unresolvable still asks). 20-case matrix verified under /bin/bash 3.2 | hook change (personal, done) | v5.6.0 release phase blocks; fix session 2026-08-09 | 1 | promoted | 2026-08-09 |
