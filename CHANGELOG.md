# Changelog

Version history for the VV Claude Code Harness. The current version lives in `.claude-plugin/plugin.json`.

### v6.0.2 (2026-08-14)

Documentation restructure plus the release-consistency repair.

1. **README describes only the current harness** — it opens with what the plugin is,
   the problem it solves, how to install it, and how to use it. The v2.0 → v6.0
   evolution narrative, the Anthropic/Manus origin story, and the
   instructional-to-mechanical progression moved verbatim to
   [docs/history.md](./docs/history.md), which states up front that nothing in it
   describes current behavior. Half the old README described machinery that no longer
   exists, which is the wrong first impression for someone evaluating the plugin.
   "Known challenges" is now "Known limitations" and lists only what is still true.
2. **release-consistency no longer reports drift it cannot avoid** — the tag assertion
   ran on push-to-main, where a release commit has bumped the manifest before its tag
   exists, so it opened an issue on every release (nine were hand-closed on
   2026-08-14) and buried one genuine finding: `v5.2.0` was never tagged at all. The
   assertion now runs on the tag push, a daily schedule, and manual dispatch; the
   workflow closes a cleared drift issue itself.

### v6.0.1 (2026-08-14)

Four fixes from v6.0.0's own field validation, plus the CI repair it uncovered.

1. **Elevation escalates the review stage, not the implementer (F118)** —
   `rules/parallel-work.md` told the lead twice to "upgrade its implementer to Opus"
   for elevated features, while the same section, OVI-140's model policy, and
   `implement-features.js` all scope escalation to the review pass. The rule carried
   Teams-era residue; the script was right. Swept the rule to match, and added an
   optional per-feature `featureSpecs[ID].implementModel` so the historical-signals
   table's `correction_cycles >= 3` case has an actual lever (default unchanged:
   Sonnet).
2. **The mandated conformance proof no longer warns (F119)** — `harness-continue`
   Step 5b step 3.5 requires `proof.evidence_type: "conformance"` on an elevated
   feature, and `verify-task-quality.sh` then warned that it didn't match the
   declared `qa_binding`: following the documented path guaranteed a warning. Exempts
   exactly that pair (conformance + elevated); a conformance proof on a standard-risk
   feature still warns.
3. **A declared-but-unmeasured coverage target is surfaced (F120)** — a feature that
   sets a numeric `coverage_target` and records no `coverage` now gets a visible,
   non-blocking note instead of silence. Deliberately narrow: projects that declare no
   target, and this repo's own descriptive coverage strings, stay silent.
4. **Scope-diff recovered worktree branches before merging (F121)** — an interrupted
   run leaves a branch nobody reviewed, and the PreToolUse scope gate reports per call,
   not per branch. OVI-147's fallback drill recovered one carrying an unrelated edit
   that removed the project's own `permissions.deny: ["Workflow"]`, caught only because
   a human read the diff. Now a documented step in the rule and the skill.
5. **CI repair** — two harness-doctor health assertions compared the tool's whole
   output to the literal `healthy`, so v6.0.0's own workflow-support notices failed the
   suite in any environment without a `claude` CLI. `main` had been red since
   2026-08-12 and two releases merged over it.

### v6.0.0 (2026-08-14)

**Breaking: Agent Teams machinery removed. Dynamic workflows are the orchestration
backbone (OVI-140, Phases 3–6).**

- **Breaking (F114/OVI-144)**: the Agent Teams coordination path is gone —
  `TeammateIdle` wiring, the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env flag,
  `check-remaining-tasks.sh`, and `teammate-scope.txt` are no longer installed;
  `harness-doctor` gained the migration check that reports and (with `--fix`) removes
  all four from existing projects.
- **Rules & docs rewrite (F115/OVI-145)**: `rules/parallel-work.md` is the single
  canonical orchestration rule (script authoring constraints, structured-output
  contracts, task mirroring, the pinned test→merge→status-flip→task-complete→commit
  integration order, author blindness, worktree hygiene, escalation, model policy);
  agent definitions are plain-subagent/workflow shaped with zero teammate/SendMessage
  vocabulary.
- **Dashboard alignment and trim (F116/OVI-146)**: capture is a fixed field allowlist
  (`ts`, `hook_event_name`, `session_id`, `agent_id`, `agent_type`) closing the
  redaction gap structurally; `serve.py` 404s unknown sessions before SSE headers,
  exits idle after 600 s clientless (`--idle-exit-seconds`), and detects viewer
  disconnect without log traffic; workflow/subagent runs render as agent spokes.

- **Field validation (F117/OVI-147)**: the release was proven end to end before
  tagging — a fresh toy project through init → spec gate → workflow mode →
  integration with all four gates observed; failure-path drills (REVISE loop bounded
  at ≤3, blocked feature surfaced-not-merged, kill + `resumeFromRunId` resume with
  `features.json` untouched, `disableWorkflows` degradation to plain worktree
  subagents with outcome parity); a v5.7.0 fixture upgraded via the documented
  doctor path (idempotent, byte-identical data). Records:
  `evals/workflow-migration-validation.md`. Drill-caught fixes shipped in this
  release: doctor check 10 no longer false-positives on always-skip `focused_test`
  scripts, and the resume contract text now names the resend-`args` requirement.

**Migration (v5.x → v6)**: `/plugin` update → `/harness-doctor --fix` from a clean git
state. No data migration — `features.json` is unchanged. A repeat `--fix` is a
zero-finding no-op. Skipping doctor breaks nothing loudly (the stale `TeammateIdle`
hook never fires; the env flag is dead weight) but skips the workflow-availability
check. Rollback: reinstall v5.7.0 via `/plugin`; no data migration in either
direction. Full guide: INSTALL.md → "Migrating a v5.x project to v6".

### v5.7.0 (2026-08-10)

**Agent Teams → Dynamic Workflows migration, Phases 0–2 (OVI-140).** Workflow mode
becomes the primary parallel path; Agent Teams is demoted, not yet removed (its
retirement is a later phase — this release is additive and the rollback boundary holds).

1. **Phase 0 verification (F110/OVI-141)** — `evals/workflow-gate-verification.md`
   records grounded verdicts for all 8 spike questions. Established empirically:
   PreToolUse gates and the secret scan fire for worktree workflow agents (via the
   `CLAUDE_PROJECT_DIR`-unset git-toplevel fallback — a fragility flagged for doctor);
   `TaskCompleted` fires on lead self-completion; `SubagentStart`/`Stop` reach hooks
   with `agent_id`/`agent_type`; unchanged worktrees auto-remove while changed ones need
   lead cleanup; `acceptEdits` coexists with exit-2 denies; and `args` arrives as a
   JSON **string** (scripts must `JSON.parse`).
2. **Workflow scripts (F111/F112/OVI-142)** — `workflows/implement-features.js` (one
   Sonnet implementer per feature in an isolated worktree, then an Opus reviewer over
   the branch diff; returns per-feature results with a partial-result/`unfinished`
   contract; never merges, commits, or edits `features.json`) and
   `workflows/review-branch.js` (fan reviewers, dedup findings before an adversarial
   verify pass, ranked confirmed verdicts, optional author-blind conformance). Covered
   by structural assertions plus node-guarded **executable** tests of the pure helpers.
3. **harness-continue workflow mode (F113/OVI-143)** — Step 4 is now a three-way mode
   decision (single-session / workflow / peer-debate) with an availability probe and a
   plain-subagent fallback; a new Step 5b orchestration flow pins the integration order
   (local tests → merge → status flip → task complete → commit), mandatory
   `feature_id`-carrying task mirroring, worktree hygiene, and resume of unfinished
   runs. Agent Teams is retained as Step 5c (legacy).

One adversarial-review round over the combined diff fixed 20 confirmed findings in the
new scripts and tests before release (severity-rank inversion, an un-interpolated
`<mergeBase>`, silent conformance no-ops, dead-agent accounting, and the grep-only tests
that let those ship green — now backed by executed helper coverage).

### v5.6.1 (2026-08-09)

One commit-gate fix (F109): shell redirections after `git commit` are no longer
misread as pathspecs. The F052 bare-pathspec rule denied any flagless token after
`commit`, so `git commit --no-edit 2>&1` was blocked as compound-stage-and-commit —
but bash consumes an unquoted redirection before git ever runs. The gate now skips
a genuine redirection (and its detached target, e.g. `> log`), deciding on the RAW
token only: quoting or escaping any of it (`git commit '2>&1'`, `2\>file`) still
denies as a real working-tree-commit pathspec, and the F034 bypass shapes (a real
staging flag before *or after* the redirection) still deny. Raw tokens are now
threaded through the parser for exactly this decision, since the flag view strips
quotes and cannot tell the two forms apart.

### v5.6.0 (2026-08-09)

Clears the entire remaining feature backlog (F087, F094–F098, F107, F108) in one
parallel-implementation batch, plus one adversarial-review round over the combined
diff.

1. **Doctor detects a stale `focused_test` skip contract (F108)** — `harness-doctor`
   now flags a per-project `init.sh` that supports `focused_test` but predates
   v5.5.0's exit-3 skip protocol (F106), as upgrade-available with a hand-apply
   repair; `--fix` never rewrites `init.sh`. The check reads non-comment lines only
   and positively detects leftover pre-F106 `treating as pass` arms, so a partially
   hand-applied repair or a marker-quoting comment cannot clear a live fake-green.
   `INSTALL.md` now states `init.sh` is never auto-refreshed.
2. **ARG_MAX silent-allow residuals closed (F096)** — `enforce-scope.sh` and
   `commit-gate.sh` now feed `$COMMAND` to their analysis python via stdin (the
   remaining call site of the class F088–F093 fixed), cap `DENY_REASON` at 2048
   chars, and — found by this release's review round — cap the passing-flip deny
   reason's `full_test` tail, which could previously blow argv and silently convert
   that DENY into an ALLOW.
3. **Measured orientation total (F097)** — `session-start.sh` buffers the orientation
   body and enforces the 10k platform cap against its actual accumulated length
   (additive to the per-section budgets), with the rule-pointer footer built
   separately so truncation can never drop it.
4. **Reassignment message caps (F107)** — `check-remaining-tasks.sh`'s `Next:` line
   gets the same description/scope truncate-and-point caps as the orientation
   (F071/F085 class), with a null-safe, guarded formatter so a malformed feature
   entry degrades instead of suppressing the exit-2 nudge.
5. **Dashboard fixes (F094, F095)** — ring positioning moved off `transform` (owned
   exclusively by anime.js now) onto `style.left/top`, and gate badges are keyed
   per gate+verdict so different gates' findings no longer overwrite one badge.
6. **Readiness-stamp HMAC round-trip (F087)** — env-var-key round-trip test with an
   independent schema-recipe oracle and spec_hash/base_sha/lane/repo/key tamper
   negatives. `prep.stamp` remains deliberately unconfigured on this repo.
7. **Single-load regression pin (F098)** — a behavioral test proves the session-start
   checks share one `features.json`-loading python spawn (the consolidation itself
   had already landed via an earlier perf commit).

### v5.5.0 (2026-08-09)

Closes out the v5.4.0 review's deferred findings plus one older orientation bug.

1. **Exit-3 skip protocol for `focused_test` (F106)** — `init.sh`'s exit-code contract
   is now explicit: 0 means the test executed and passed; 3 means the script skipped
   the stage (no per-file runner for the stack, or the recorded test file does not
   exist). 3 is **reserved**: a runner's own exit 3 is remapped to 1 (pytest exits 3
   on INTERNALERROR; mocha exits the failing-test count), so a real failure cannot be
   laundered into an accepted skip. The TaskCompleted hook accepts a 3 on smoke alone,
   surfaces `init.sh`'s own output on stderr, and records **no** focused baseline —
   removing the fake-green class that could arm a false green-to-red
   `correction_cycles` increment. Any other nonzero exit still rejects as a real
   failure. Note: `init.sh` is a per-project copy, so **existing projects keep their
   old skip arms until their `init.sh` is refreshed by hand** — a `harness-doctor`
   check for the stale contract is filed as F108.
2. **Not-run baseline keys are dropped (F105)** — `focused:<id>` / `coverage:<id>`
   entries in `.harness/last_gate.json` are deleted when the hook reaches the stage
   and finds it unconfigured (test_file removed, `focused_test` support gone, coverage
   no longer numeric): a baseline exists only while its stage is genuinely being
   exercised. A stage skipped because an *earlier* stage failed keeps its baseline —
   ordering is not deconfiguration — so the normal fail-fix loop keeps its
   attribution.
3. **Orientation scope cap (F085)** — the `Next claimable:` line's scope field (382
   chars real, 711 in the adversarial fixture) gets the same truncate-and-point
   treatment as the description: 150-char cap with a marker naming the path count.

The never-run-the-full-suite guarantee for `focused_test` now has two independent
pins: the v5.4.0 structural check plus a behavioral test running the real template
with a canary test file and asserting exact exit codes — closing the
single-assertion gap the v5.4.0 review flagged.

### v5.4.0 (2026-08-08)

**Quality-gate redesign: full_test moves from every task completion to the moment a
feature is declared done.** Motivated by a live report from a project running v3.5.0
hooks, where the per-task full suite (minutes per checkpoint in a Rust workspace)
embedded a workspace-aggregate 99% coverage bar that could never go green mid-project
-- jamming every completion -- and where four bookkeeping task completions falsely
incremented `correction_cycles` on unrelated in-progress features.

1. **Tiered TaskCompleted gate (F101)** — `verify-task-quality.sh` now runs
   `smoke_test` plus, when the targeted feature records a `test_file` and the
   project's `init.sh` supports the new `focused_test <file>` target, exactly that
   feature's own test file. The unconditional `full_test` stage is gone (it also
   contradicted harness-init SKILL.md's own documented contract). Older `init.sh`
   scripts without `focused_test` stay smoke-only with a stderr note — no breakage.
   `init.sh.template` gains per-stack focused runners.
2. **Passing-flip commit gate (F102)** — `commit-gate.sh` compares the staged
   `.harness/features.json` against the commit's actual parent (HEAD, or HEAD^ for
   `git commit --amend`, which replaces HEAD — abbreviations like `--amen` resolve
   the way real git resolves them) and runs `full_test` whenever a feature's status
   flips to `passing`, denying the commit (with the flipped IDs and the output tail)
   on failure. Demotions, no-flip commits, and non-commit commands never trigger it.
   This is where the full suite decides something, so this is where it is enforced.
3. **Green-to-red correction_cycles attribution (F103)** — the hook records each
   stage verdict in `.harness/last_gate.json` (advisory baseline, gitignored,
   deliberately persistent across sessions) and increments `correction_cycles` only
   when the failing stage was green on the previous recorded run. Every key is
   per-feature (`smoke:F00X`, `focused:F00X`, `coverage:F00X`), so one feature's
   green run never arms the counter for another's inherited breakage. A
   pre-existing red gate is not a correction cycle; an unknown baseline records the
   verdict without incrementing; a pass re-arms the counter, and repeated failures
   of an already-red stage are never double-counted.
4. **full_test authoring guidance, pinned (F104)** — harness-init SKILL.md now
   states the rule the jammed project violated: `full_test` must stay satisfiable
   mid-project; workspace-aggregate metrics enter as never-decrease ratchets against
   a stored baseline; fixed high thresholds belong to per-feature scope (the
   existing `coverage_target` gate) or a release feature's acceptance criteria.
5. **Deterministic stamp-test fixture (F100)** — the f012 HMAC cross-check ran the
   extracted Step-7 snippet with `/usr/bin` on PATH, so a real `vv-harness-stamp`
   Keychain item shadowed the fixture key file: the suite was green on CI but red on
   any machine that had actually stamped an issue. The fixture now neutralizes the
   Keychain the same way the sibling resolution-chain scenarios always did.

Also fixed en route: `harness-doctor --fix`'s gitignore fixer had never learned the
`.harness/dashboard/` line (`fixes.py`'s mirror of `REQUIRED_GITIGNORE_LINES` was out
of sync with `doctor.py`'s), so doctor reported the gap but could not repair it. Both
lists now carry all four entries, including the new `.harness/last_gate.json`.

Projects initialized under older versions get all of this via `/plugin` update
followed by `/harness-doctor --fix` (which re-copies the gate hooks and appends the
new gitignore line).

### v5.3.0 (2026-08-07)

**Promotes the dashboard chain (F088-F093, v5.2.0) out of alpha** — no functional
change to the dashboard itself; the alpha designation from v5.3.0-alpha is lifted
now that it's had broader real-world use.

**Performance pass across the harness's own scripts**, no user-facing behavior
change (all fixes verified as pure refactors, full suite passes identically
before/after): merges duplicate JSON/harness.json parses that ran as separate
python3 processes on the same input within a single hook invocation
(verify-git-identity.sh, verify-task-quality.sh, commit-gate.sh, session-start.sh),
fixes session-start.sh/session-end.sh to prefer CLAUDE_PROJECT_DIR over
git-toplevel resolution matching every other hook, and replaces init.sh's
per-file py_compile loop with one batched call.

### v5.3.0-alpha (2026-08-05)

**Alpha designation for the v5.2.0 dashboard chain (F088-F093), no functional change.**
Marks the dashboard feature (an opt-in, live, animated view of Agent Teams session
activity — see v5.2.0's entry below for what it does) as alpha quality while it gets
broader real-world use before being folded into a stable release. Pin a single project
to this exact tag for isolated testing without affecting any other project's installed
version — see INSTALL.md, "Installing a specific version (alpha/pre-release/pinned),
in one project only", for the `extraKnownMarketplaces` setup. Also fixes a real bug
this alpha's own release process caught: `test/run-tests.sh`'s semver check only
matched a bare `MAJOR.MINOR.PATCH` and rejected any pre-release suffix, which this
version needed.

### v5.2.0 (2026-08-05)

**An opt-in, live, animated dashboard for watching an Agent Teams session as it runs**
(F088-F093, the 2026-08-05 grilling session's dashboard chain). New capability, not a
bugfix.

Set `VV_HARNESS_DASHBOARD=1` before launching the session you want to watch — the
hooks that write the event log are wired at Claude Code startup, so enabling it
mid-session has no effect — then run `/harness-dashboard` from a second terminal.
`hooks/dashboard-log.sh` (F088) and matching inline instrumentation added to all four
quality-gate scripts (F089, both the plugin templates and this repo's own installed
copies) write a redacted, gitignored JSON-line event log per session to
`.harness/dashboard/<session_id>.jsonl` — short summaries only (a file path, a Bash
command's `description`), never raw commands, file content, or prompts.
`hooks/dashboard/serve.py` (F090) is a dependency-free Python stdlib SSE server,
loopback-only on `127.0.0.1:8765`, that replays a session's backlog on connect and
tails new events with no polling. `hooks/dashboard/index.html` (F091), using a
vendored local copy of animejs (no CDN), renders that stream as a live node graph: a
hub for the lead, spokes for each subagent, pulsing on tool use, badged for
quality-gate verdicts, judge subagents, and permission prompts. The `/harness-dashboard`
skill (F092) launches the server detached at the OS level via `nohup`+`disown` (so it
outlives the invoking session) or reuses one already running, then opens the page.

Known, documented limitations: the graph is a flat hub-and-spoke layout (no
parent-agent field exists anywhere in the hook payload set, so spawn ancestry can't be
reconstructed); teammate nodes are labeled by `agent_type` only, never a custom
`teammate_name` (the two identities have no correlation field); the view is live-only
and one session at a time, with no cross-session history or aggregation; and the
server has no authentication, relying solely on its loopback-only bind.

**Tests**: `test/run-tests.sh` grew from 1587 (main's pre-branch baseline) to 1832
assertions — covering the event-log contract and per-tool-type redaction (F088),
gate-script instrumentation at every decision point (F089), the SSE server's
backlog/tail/traversal/port-in-use behavior (F090), and structural checks on the
frontend, skill, and this release's own docs and version bump (F091-F093; F091/F092
are `qa_binding: manual`, proven primarily
by direct end-to-end verification outside the harness, documented in each feature's
own `features.json` coverage field).

### v5.1.1 (2026-08-03)

**A round of adversarial review on v5.0.1/v5.1.0's own fixes, closing every deferred nit
from those reviews plus completing OVI-105's third task.** Pure bugfixes and test-quality
hardening -- no new capability.

`hooks/session-start.sh`'s orientation could still exceed the platform's 10,000-char cap
(OVI-105's third task): the `SESSION_INCOMPLETE` warning, `claude-progress.txt`'s tail, and
`context_summary.md`'s Active Context were each capped by line count only, which bounds
nothing if the lines themselves are long. Added the same truncate-and-point pattern
already used for feature descriptions to all three -- calibrated once, then recalibrated
after review caught the first value already truncating this repo's own real Active
Context on ordinary content.

Four nits deferred from the v5.0.1/v5.1.0 review rounds, picked up and fixed: `doctor.py`'s
consolidated `CLAUDE_PLUGIN_ROOT`-unset finding named the `.harness/mld/` non-injection
check even for projects with no `mld/` directory, where that check was never going to run
regardless; `harness_state.py`'s top-level `import fcntl` made every read-only verb
Unix-only, not just the write path that actually needs it; a shell wrapper merged
`harness_state.py`'s stderr diagnostics onto its own stdout, which Claude Code discards
entirely on the TaskCompleted hook's rejection path -- burying every diagnostic exactly
when it mattered most; and a permanent flock error (e.g. `ENOLCK`) was treated identically
to ordinary lock contention, burning the full lock timeout before reporting a misleading
message.

**Tests**: `test/run-tests.sh` carries 1559 assertions, up from 1541 -- every fix above is
independently pinned and mutation-tested, several against empirically-verified failure
modes (real inter-process lock contention, a real blocked import, real stdout/stderr
channel separation) rather than only reasoned about.

### v5.1.0 (2026-08-02)

**The additive follow-ups from the same external code review pass that shipped v5.0.1**
(feedback_vivi.md), tracked as Linear issues OVI-104, OVI-82, and OVI-81. New capability,
not bugfixes, per the v5.0.1 entry's own note about keeping the two kinds of change out
of the same patch release.

`harness-doctor --fix` couldn't restore a missing `commit-gate.sh` (OVI-104): the
"upgrade available" finding had no `fix_id`, unlike its `harness_state.py` sibling. A new
`copy_commit_gate` fixer closes the gap. Separately, four of `doctor.py`'s checks
(commit-gate.sh presence, `features.json` cross-validation, `plugin_version` drift, the
`.harness/mld/` non-injection guarantee) each silently returned no findings when
`CLAUDE_PLUGIN_ROOT` was unset — individually correct, but four independent silent skips
added up to a "healthy" report that verified less than it looked like it did. One
consolidated finding now names all four. Dogfooding this fix on itself surfaced a related,
already-shipped bug: `doctor --fix`'s `.gitignore` fixer could never add a newer required
line (`.harness/features.json.lock`, from v5.0.1's OVI-107 fix) for any already-initialized
project, because it early-returned on the presence of an older required line alone. Fixed
alongside — the fixer now appends whichever required lines are missing.

Two new rule files join the SessionStart orientation's rule-pointer block, both moved out
of Ovidiu's personal `~/.claude/CLAUDE.md` per a separate handoff (OVI-73: "the harness
should own development discipline, not the global file"). `rules/debugging.md` (OVI-82)
is a four-phase systematic root-cause process. `rules/tdd.md` (OVI-81) is the 5-step TDD
loop and coverage bar, including the finding that this exact discipline as always-on
CLAUDE.md prose didn't measurably reduce `buggy_code` — the coverage gate and adversarial
review did.

**Tests**: `test/run-tests.sh` carries 1541 assertions, up from 1510 — every new check and
fixer above is independently pinned and mutation-tested.

### v5.0.1 (2026-08-02)

**Three correctness fixes from an external code review pass** (feedback_vivi.md, verified
against commit `6a4f7d3` post-v5.0.0), tracked as Linear issues OVI-105/106/107. A pure
bugfix patch release — no new capability, nothing additive. The same review's remaining,
additive follow-ups (OVI-104/81/82) are queued for a future minor release, not bundled
here.

`features.json` writes could race under parallel `TaskCompleted` hooks (OVI-107):
`harness_state.py`'s write path used a fixed tmp filename that one concurrent invocation
could delete out from under another, and the atomic rename lived in the shell wrapper,
split across two processes, not one. `harness_state.py` now owns the entire
lock-acquire + read + modify + write + rename cycle itself (`fcntl.flock` on a
persistent `.lock` file, PID-suffixed tmp names, `os.replace`) — stress-tested to
120-way concurrency with zero lost writes; the old design measurably lost 8-9 of 12
concurrent increments.

`session-start.sh`'s orientation could exceed the platform's 10,000-char output cap
(OVI-105): the next-claimable feature's full description printed untruncated, and a
single long description (13,222 chars measured on this repo's own `features.json`)
could crowd out the git-identity warning and rule pointers that print after it. Now
truncated to 200 chars with a pointer to the full text, in both code paths that print
it.

`/harness-continue`'s documented "smoke test" (Step 2.5) actually ran the full test
suite (OVI-106): a bare `./.harness/init.sh` invocation hits `init.sh`'s own
`full_test` default, not `smoke_test`. Both call sites now pass `smoke_test`
explicitly.

**Tests**: `test/run-tests.sh` carries 1510 assertions, up from 1489 — the concurrency,
truncation, and smoke-test regressions above are each independently pinned and
mutation-tested.

### v5.0.0 (2026-08-02)

**The v5 upgrade: absorbing harness-engineering's evidence and meta loops.** A comparative
analysis against lopopolo/harness-engineering (CC BY 4.0) found vv-harness strong on
mechanical enforcement and distribution but with three real gaps: feedback that never
flowed back into the harness itself, proof that stopped at coverage percentage, and no
maintenance loop against weekly platform drift. This release closes all three, adapting
the applicable ideas rather than transplanting them (per HE's own doctrine), plus
mechanisms from two further harnesses reconciled in wave 2: AlexCiortan/setlist (CC BY
4.0) and nodera-studio/agent-os (MIT). 21 planned capabilities, tracked as Linear epic
OVI-44.

**Correctness first (P0).** Scope enforcement is now armed in the actual spawn path
(`harness-continue`'s Phase 2 writes `.claude/teammate-scope.txt` on every teammate
spawn; previously the only instruction to create it lived in prose nobody executed).
Single-owner truth fixes: the version line, dates, and identity checks now agree with
`plugin.json` and each other. The 5 per-project hook templates gained real test coverage
(previously excluded from both `bash -n` and the fixture suite) and were then hardened
against roughly 30 parsing and evasion edge cases found by adversarial dogfooding —
quoting, redirects, ANSI-C escapes, compound commands, flag-taking short options, and
more, all in `enforce-scope.sh.template` and `commit-gate.sh.template`.

**One concept, one owner (P1).** `schemas/feature.schema.json` is now the single
canonical definition of the `features.json` envelope and the feature object, enforced by
a stdlib-only validator (`scripts/validate-features.py`, no `jsonschema` dependency) wired
into the test suite and into `harness-doctor`. A shared `harness_state.py` module
replaces per-hook reimplementations of `features.json` parsing across
`verify-task-quality.sh` and `check-remaining-tasks.sh`.

**Authority and proof (P2).** Lead-only ownership of `.harness/` state files
(`features.json`, `context_summary.md`, `claude-progress.txt`) is now mechanically
enforced, not just documented — `enforce-scope.sh` blocks a teammate write to any of the
three regardless of its assigned scope, with a best-effort Bash-write backstop for the
same three plus scope boundaries generally. Features gained claim-matched proof: a
`proof` object (claim, evidence type, artifact, what the evidence did NOT establish),
per-feature `coverage_target` overrides for claim types unit coverage measures poorly,
and a `delivered` closure field for PR-shipped projects. The readiness stamp's HMAC key
now resolves from a three-source chain (macOS Keychain, a mode-600 key file, or an
explicitly-discouraged env var) instead of Keychain only, so the spec gate's signing
recipe is exercised on Linux CI for the first time.

**Feedback becomes infrastructure (P3).** `.harness/mld/` gives the harness a builder-only
telemetry channel (Mistakes/Learnings/Desires) with a hard, tested non-injection
guarantee: `session-start.sh` never reads it, on any SessionStart source. The Phase 5.5
retrospective gained a promotion pass (classify each observed pattern to its smallest
durable owner: spawn-prompt tweak, rule edit, hook change, schema field, agent
definition, or plugin skill) and an ablation pass (retain/revise/remove controls that
fired zero times or produced only friction), with candidate lifecycle tracking
(score, status, decay) recorded in `.harness/HARNESS_BACKLOG.md`.

**Continuous maintenance (P4).** `docs/maintenance-runbook.md` is the loop that watches
for platform drift on Claude Code's experimental Agent Teams surface: a weekly CI probe,
a monthly live-agent probe checklist, and durable state in `MAINTENANCE_LOG.md` where a
quiet no-op run is a successful run, not a skipped one. Every documented workaround now
carries an explicit retirement condition. A new optional `worker` block in
`harness.json` records the CLI version and model bindings an epoch's operational metrics
belong to, with a requalification checklist (`docs/requalification.md`) triggered on a
version-delta jump — including a mandatory subtraction pass, since a worker upgrade can
absorb scaffolding a harness project no longer needs.

**Meta and distribution (P5).** A new root `AGENTS.md` (plus nested guides under
`skills/` and `test/`) gives non-Claude agents (Codex, Cursor) a real map of this repo,
with `CLAUDE.md` reduced to a one-line import and a small Claude-specific overlay. The
new `harness-improve` skill runs HE's improve-one-harnessed-job loop: record a job
contract, observe the baseline, make one intervention, verify at the claim boundary a
guardrail actually prevents. `evals/` documents the eval method (decision-first,
one-intervention, fresh-sessions) and ships the first behavioral eval, an orientation-
recovery A/B.

**Two new health-check and safety mechanisms (wave 2).** `skills/harness-doctor/` is a
report-first, idempotent instance health check with an optional `--fix` upgrade mode —
it replaces the five-step manual upgrade INSTALL.md used to document, and now also
tracks `plugin_version` drift between a project's recorded sync point and the currently
installed plugin, bootstrapping or refreshing that field on `--fix`. `scripts/stamp.sh`
is the deterministic file emitter behind `/harness-init`: "never hand-write what a stamp
can emit; never stamp what a decision shapes" — every framework-fixed file (hooks
byte-verbatim, settings templated, `plugin_version` read directly from the plugin's own
manifest) comes from the stamp, with new-mode collision pre-flight and upgrade-mode
byte-identical-only overwrites. A new commit-content gate (`commit-gate.sh`) denies
compound stage-and-commit forms and staged secret-shaped content before they land.

**Two new review mechanisms.** `agents/conformance-tester.md` derives behavior tests
from a feature's verified spec alone — it never reads the implementation diff, the
implementer's completion message, or the implementer's own tests, closing the
reward-hacking surface where a single context that writes both code and tests can
satisfy a bug with a test that matches the bug. An optional dual-engine review
(`review.second_engine` in `harness.json`) runs a second, independently-run reviewer
(e.g. Codex) blind to the first, with explicit synthesis rules: dedupe by defect not
line, a single-engine CRITICAL survives, cross-engine agreement raises confidence,
provenance checked against `git show <merge-base>:<file>` before labeling a finding NEW
vs. PRE-EXISTING.

**The TeammateIdle identity correction.** This release also corrects a claim shipped
since v4.1.0: the `TeammateIdle` hook payload does carry the teammate's `teammate_name`
(and deprecated `team_name`) — it was never true that the hook has no way to know which
teammate is idling. The original claim traced to a documentation fetch that truncated
before reaching the relevant section of a long reference page and silently answered from
the wrong table; a raw fetch of the same page corrected it. The hook still doesn't act on
`teammate_name` — that remains a deliberate design decision (`rules/agent-teams-protocol.md`),
not a platform limitation: the field is caller-chosen free text with no enforced naming
contract, and a wrong automated guess (silently suppressing a nudge for a teammate that
legitimately has more work) is worse than the current bounded, visible cost of one extra
decline per stale nudge. The correct remedy — the lead releasing a role-limited or
scoped-one-shot teammate promptly once its work is delivered — already existed as a rule
and simply needed to be followed, not mechanized around.

**Dogfooding found the rest.** This repo ran its own harness on itself for the entire
upgrade (`/harness-init` on vv-claude-harness, per the epic's self-execution protocol).
Beyond the 21 planned issues, that surfaced and fixed 48 further defects — mostly the
scope-enforcement hardening pass above, plus a `harness-doctor` check that a
`passing`/`in-progress` feature's `test_file` actually exists, a mutation-testing gap in
`fixes.py`'s settings-wiring drift check, and the TeammateIdle-idle-nudge scope gaps this
entry already covers. Full per-defect detail lives in this repo's own `.harness/features.json`,
not restated here at that granularity.

**Tests**: `test/run-tests.sh` carries 1489 assertions covering every mechanism above
plus the hardening pass, with each non-trivial check mutation-tested against the
specific defect it guards.

### v4.2.2 (2026-07-04)

**A go-ahead is durable.** In practice, sessions governed by the template's "present a
plan and wait for Go ahead" invariant were stopping at every phase transition of
/harness-continue and asking again, because each phase looked like new non-trivial work.
Both sides now state the principle explicitly: the Phase 1 plan approval covers execution
through to the approved goal's completion, and the lead returns to the user only when the
goal is accomplished, the work is blocked, or the approved plan itself must change.
`templates/CLAUDE.md` gains the same durability clause on the invariant, so the rule and
the workflow no longer fight each other. Gate the intake, not the execution.

### v4.2.1 (2026-07-03)

**Fix: plugin-internal references now resolve for installed users.** The spec-gate
skills and the Agent Teams protocol referenced `schemas/readiness-stamp.md` as a bare
relative path. That resolves inside this repo, but in an installed plugin the session
would look for it in the user's project and fail. All eight references now use
`${CLAUDE_PLUGIN_ROOT}/schemas/readiness-stamp.md`, the same convention the other
skills already use for cross-plugin paths. No behavior change on this repo; a
works-for-everyone fix for installed users.

### v4.2.0 (2026-07-03)

**Skill rename for discoverability.** `issue-prep` and `issue-debug` are now
`harness-issue-prep` and `harness-issue-debug`, so every harness skill shares the
`harness-` prefix and typing `/h` surfaces the whole toolkit (`harness-init`,
`harness-continue`, `harness-issue-prep`, `harness-issue-debug`) without memorizing
names. Behavior is unchanged; all cross-references in the agents, hooks, schema,
protocol, docs, and tests are updated. If you learned the v4.1.0 names, they are gone:
there is no alias, per the replace-don't-deprecate rule. The v4.1.0 entry below is left
as written; it describes that release accurately.

### v4.1.0 (2026-07-03)

**The spec gate.** The harness had one verified intake gap: `/harness-init` Step 5 wrote
features into `.harness/features.json` on bare user confirmation, with nothing checking
that a proposed feature was testable, unambiguous, edge-covered, or internally
consistent before implementers burned tokens on it. Step 5.1 closes it: the entire
confirmed feature proposal is spawned as a read-only subagent to the new
`spec-verification` agent (Opus), which returns `PASS`/`ASK`/`BLOCK` with a numbered,
groundable report; `features.json` is written only on `PASS`, or after the user resolves
the `ASK`/`BLOCK` questions and the gate re-runs. A waived gate ("skip verification")
writes features with `"spec": null` and notes the waiver in `claude-progress.txt`.

**Two new agents.** `agents/spec-verification.md` runs the six checks (testability,
ambiguity, edge/error coverage, non-functional requirements, dependencies, cross-feature
consistency) against a spec under test. `agents/reverification-guard.md` is the
integrity check on the gate's one human touchpoint: every human-amended revision is
re-verified from scratch, and it explicitly refuses to let a grounded `BLOCK` or `ASK`
reverse on pressure or reassurance alone, only on new spec content. Both are spawned
read-only, spec-in-prompt, and never fetch anything themselves.

**Two new skills.** `skills/issue-prep/` interactively drives a spec (a Linear issue via
the Linear MCP, a pasted spec, or an existing feature) through spec-verification and the
human loop, normalizes it into a canonical template on `PASS`, and records the result: a
`spec` field locally, or a signed readiness stamp and label on Linear. `skills/issue-debug/`
opens a failed feature or a runner-parked Linear issue in a live repair session and
exits by resuming the runner, routing back through `issue-prep`, or marking the work
failed.

**New `schemas/` directory and the readiness stamp contract.** `schemas/readiness-stamp.md`
publishes the data contracts between the spec gate (the mint) and any external consumer,
primarily an autonomous issue-to-PR runner that imports no code from this repo and only
validates these formats: the readiness stamp itself, the canonical hashing recipe, the
HMAC recipe, consumer verification rules, and the park/debug-resolution contracts shared
with `issue-debug`. **Honesty note:** the stamp's HMAC protects the Linear boundary only
(anyone with workspace access can edit an issue, so that boundary needs cryptography).
`features.json`'s local `spec` field carries no signature, by design: you are the only
writer of your own file, so local trust needs none.

**SessionStart spec-drift warning.** The orientation hook now recomputes the local hash
for any feature whose `spec.hash` is set and warns when it no longer matches the current
`description` (an edit after verification invalidates the spec, and that's the feature,
not a bug). Local-only, network-free, and silent when no feature carries a `spec` field.

**Fix: `TeammateIdle` no longer assigns implementation work to the reviewer.** The
`check-remaining-tasks.sh` template offered the next pending feature to any idle
teammate, including a reviewer that just finished a review and has no Edit/Write tools.
The `TeammateIdle` hook payload does carry the teammate's `teammate_name`, but the hook
itself does not use it to decide whether to fire — a deliberate design decision (see F069
in `rules/agent-teams-protocol.md`), not a missing field. The fix lives in
`agents/reviewer.md` instead: its Constraints section now instructs the reviewer to
decline an offered implementation feature and message the lead. Because this
ships in the plugin's own agent definition rather than a per-project hook template, it
reaches every project on the next `/plugin update vv-harness`; no `/harness-init`
re-run required.

**Tests**: `test/run-tests.sh` gains a `spec drift` section (hash match, hash mismatch,
malformed `spec` field, output-length regression) and a `spec gate artifacts` section
(the readiness-stamp schema parses, both new skills' frontmatter is sane, a clean session
with a verified feature still produces no `SESSION_INCOMPLETE`).

### v4.0.2 (2026-07-03)

**Documentation correction — no behavior change.** Corrected the CHANGELOG's account of why post-compaction recovery uses a `SessionStart` `compact` hook rather than a PreCompact or PostCompact hook. Per [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks), a hook's stdout is added to the model's context only for `SessionStart`, `UserPromptSubmit`, and `UserPromptExpansion`; PreCompact and PostCompact stdout never reaches the model, which is why they cannot inject recovery context. The harness already used the correct mechanism — only the stated rationale was imprecise.

### v4.0.1 (2026-07-01)

**`templates/CLAUDE.md` trimmed from 461 to 356 lines.** Two reference-heavy blocks that only matter at specific moments — the full `context_summary.md` template and the task completion checklist — moved out of the always-on core into plugin rule files, and verbose always-on sections (systematic debugging, sub-agent failure handling, error recovery) were condensed in place without losing substance.

**Two new plugin rule files** carry the extracted detail, surfaced the same way `code-quality.md` and `agent-teams-protocol.md` already are (no auto-loading — there is no manifest key for it):
- `rules/context-summary.md` — the full `context_summary.md` template and section-by-section update rules.
- `rules/task-completion.md` — the base completion checklist plus the harness-specific additions.

**Wiring** — `hooks/session-start.sh` injects pointers to both new rules in the harness orientation block, and `skills/harness-continue/SKILL.md` references them at the context-update and session-end steps. `templates/CLAUDE.md` gains a Rule Index table mapping each rule file to when it should be read.

**Why not a full split** — the core-standards file ships as a manually copied `~/.claude/CLAUDE.md` with no auto-loader, so always-on content (invariants, TDD, debugging, git identity, security) stays in the template; only genuinely on-demand reference material was extracted. This adapts PR #8's routing-table idea to the v4.0 plugin model.

**Tests**: `test/run-tests.sh` gains assertions that the SessionStart orientation includes the two new rule pointers.

### v4.0.0 (2026-06-30)

**The harness is now a native Claude Code plugin.** The story of every version since v3.1 has been promoting rules from instructional to mechanical enforcement. v4.0 applies that to the harness itself: distribution, session orientation, post-compaction recovery, discipline auditing, progress visibility, and teammate tool posture — all carried by prose and a custom installer until now — are handed to the platform. This release ships what was planned as the v4.0–v4.3 milestone series in one release.

**Breaking change: the v3 installer is retired.** `./install` is now a shim that only prints the new instructions; it modifies nothing. Install with `/plugin marketplace add oeftimie/vv-claude-harness` then `/plugin install vv-harness`. Manual steps for removing the files the v3 installer placed in `~/.claude/` are in [INSTALL.md](./INSTALL.md). The version number now lives only in `.claude-plugin/plugin.json`.

**Plugin packaging** — `.claude-plugin/plugin.json` (name `vv-harness`, version 4.0.0) and `marketplace.json`; the `claude/` directory layout moved to top-level `rules/`, `skills/`, and `templates/CLAUDE.md`; INSTALL.md rewritten for the `/plugin` flow; updates are atomic (each version gets its own cache directory).

**Continuity hooks** — plugin-level, firing in any project with a `.harness/` directory:
- `hooks/session-start.sh` injects orientation at session start: features passing count, next claimable feature, last handoff, Active Context, and a git identity warning on mismatch. Its `compact` matcher also handles post-compaction recovery.
- `hooks/session-end.sh` audits session discipline (handoff written, retrospective present, metadata committed) into `.harness/SESSION_INCOMPLETE`, which the next session start surfaces loudly. Self-healing by design: SessionEnd cannot block.
- `hooks/statusline.sh` renders live "⬡ N/M passing" feature progress. Wired per-project by `/harness-init` because plugins cannot set `statusLine`; `/harness-init` also writes the Agent Teams env flag and a permissions allowlist into project settings and gitignores `SESSION_INCOMPLETE`. The per-project PostCompact hook is gone — the SessionStart `compact` source covers post-compaction recovery, making it redundant.

**Declarative agents** — `agents/feature-implementer.md`, `layer-implementer.md`, `researcher.md`, and `reviewer.md` carry model, effort, and tool posture in frontmatter. The reviewer runs Opus at high effort and cannot edit files by construction (no Edit/Write tools; Bash restricted to test runs by instruction); the researcher is retrieval-only, with Write allowed only for its findings file. Teammates spawn by `vv-harness:*` agent type, and `team-spawn-prompts.md` shrank from 253 to 135 lines (per-feature specifics only). A spawn-time `model` parameter overrides frontmatter, so the Opus-upgrade heuristic survives.

**Agent Teams model** — the protocol and skills track Claude Code's v2.1.178+ implicit-team model: a team forms on the first teammate spawn (the `TeamCreate`/`TeamDelete`/`TeamList` lifecycle tools were removed), the `team_name` argument is accepted but ignored, and `teammateMode` defaults to `"in-process"` (set it to `tmux` or `auto` for split panes). The development baseline remains v2.1.175.

**Measured cost and resilience** — INSTALL.md documents opt-in OTel telemetry (`claude_code.token.usage` and `claude_code.cost.usage`): per-model and main-vs-subagent cost is measured (per-agent names are redacted to `"custom"` for personal marketplaces), plus the zero-infrastructure `/usage` alternative. The Agent Teams protocol replaces the ~30-minute cost rule of thumb with a measured break-even, and reframes worktree isolation honestly: platform-documented for subagents, unverified for teammates. `/harness-continue` gains a supported, non-experimental fallback — worktree-isolated subagents using the same agent types — for when Agent Teams is unavailable. Compatibility is documented against Claude Code v2.1.175.

**Tests and CI** — `test/run-tests.sh` (51 fixture-based assertions over the hook scripts, no dependencies) and `.github/workflows/test.yml` running it on ubuntu-latest.

**Deviations from the original modernization plan**, each forced by a platform constraint verified June 2026:
- Plugin manifest keys for a global CLAUDE.md, rules, or settings (env, permissions, statusLine) don't exist — the core-standards file ships as `templates/CLAUDE.md` (documented manual copy) and `/harness-init` writes env, permissions, and statusLine per-project.
- The plan's PreCompact-based context injection was dropped — a hook's stdout is added to the model's context only for `SessionStart`, `UserPromptSubmit`, and `UserPromptExpansion`, so neither PreCompact nor PostCompact stdout ever reaches the model; the SessionStart `compact` source (whose stdout does reach the model) handles post-compaction recovery instead.
- No CLI version-pin manifest key exists — the tested CLI version (v2.1.175) is documented instead.
- The plan's optional TaskCreated metadata-enforcement hook was dropped — the TaskCreated payload carries no metadata field to check.

### v3.6.0 (2026-04-26)

**Stale-file detection in the installer.** Before v3.6.0, the installer silently auto-deleted a small list of deprecated files (`engineering-standards.md`, `non-harness-workflow.md`) and missed the v2.x module-lock residue entirely (`orchestrator.md`, `scheduling.md`, `coding-agent.md`, the `context-graph` skill). Anyone who upgraded from v2.x kept those dead files in `~/.claude/` and could end up with two competing harness models loaded at once — exactly the conflict that surfaced in a real session and prompted this work.

**Behavior change** — the installer no longer auto-deletes. Stale files are now **detected and reported** by default, listing each one with its `~/.claude/` path. Pass `--clean-stale` to remove them; the regular backup pass picks them up first. This is a deliberate trade: silent cleanup hid both the problem and the fix from users. The new default surfaces the decision.

**Updated stale manifest:**
- v2.x module-lock era (retired in v3.0): `rules/orchestrator.md`, `rules/scheduling.md`, `rules/coding-agent.md`, `skills/context-graph/`, `harness/`, `templates/`, `commands/project-harness-init.md`, `commands/project-harness-continue.md`
- v3.2.x cleanup (retired in v3.2.2): `rules/engineering-standards.md`, `rules/non-harness-workflow.md`

**Scope:** global files only (`~/.claude/`). Per-project residue (`.context/modules.yaml`, old `.harness/` schemas, project-local `.claude/rules/scheduling.md`) is intentionally left alone — projects contain user data and the upgrade flow needs more thought before it touches them.

### v3.5.1 (2026-04-25)

**Hotfix:** v3.5.0 shipped without bumping `install` (`HARNESS_VERSION` constant + banner), `INSTALL.md` title, and the README download/unzip examples. Running `./install` from a v3.5.0 directory reported "Upgrade (v3.5.0 -> v3.4.0)" — a downgrade against the installed copy. No functional changes; version strings only. Repo `CLAUDE.md` updated to add `install` to the version-sync list so this regression can't repeat.

### v3.5.0 (2026-04-06)

**Session discipline improvements** based on root cause analysis of 11 harness violations observed during a real iOS project session (voice fix, test expansion, app icon work).

**Five serious violation remediations:**

1. **Pre-commit features.json audit** — Session end now requires diffing `features.json` against actual work done. Any code change relating to a tracked feature must update that feature's metadata. Work that doesn't map to any feature gets a new entry with `discovered_via`. This is a gate before `git commit`, not an afterthought.

2. **Inline context_summary.md updates** — `context_summary.md` updates are now part of the task, not after the task. After every bug fix revealing a non-obvious root cause, write the gotcha to `context_summary.md` BEFORE moving to the next request.

3. **Mandatory retrospective for all session types** — The retrospective is now explicitly mandatory at session end regardless of whether the session used Agent Teams or single-session mode. Minimum viable: 3-5 bullets covering actual vs planned scope, unanticipated discoveries, and transferable patterns.

4. **Task updates at moment of state change** — Task updates must happen immediately when state changes, not in batch. When you finish something, the NEXT action is `TaskUpdate`. Stale tasks are explicitly called out as worse than no tasks.

5. **Smoke test gate at session start** — `init.sh` is now a dedicated Step 2.5 in the orient flow, run within the first 5 actions of every session. Its purpose is to establish known-good state before changes, not to diagnose problems.

**Four moderate/minor violation remediations:**

6. **Single-session mode declaration** — When choosing single-session over Agent Teams, the lead must explicitly declare it to make the decision conscious and documented.

7. **Bug fix diagnosis before editing** — Debugging Phase 1 now requires stating diagnosis and proposed fix in 2-3 sentences before editing code, even for seemingly obvious fixes.

8. **Commit at natural breakpoints** — Commit hygiene rules now require committing after each feature/fix passes tests, separating harness metadata from code, and checkpointing inherited uncommitted work before making new changes.

9. **Untracked file and task metadata audit at orient** — The orient step now checks for unknown untracked files (surfaced to user) and verifies inherited tasks have required `feature_id` metadata.

**Two standards improvements:**

10. **Coverage blocker documentation** — If coverage measurement isn't available in the project's tooling, document it as a gotcha in `context_summary.md` and create a feature to enable it. Silent coverage gate skipping is no longer acceptable.

11. **Strengthened task completion checklist** — Harness-specific checklist items now explicitly require features.json audit, context_summary.md updates, retrospective, and task list currency check.

### v3.4.0 (2026-04-02)

**Bug fixes and convention improvements** based on analysis of Claude Code's internal multi-agent implementation compared against the harness's external hook protocol.

**Four bug fixes:**

1. **Scope enforcement path normalization** — `enforce-scope.sh` now strips the project root from absolute paths before matching. Tool input always provides absolute paths; scope patterns are relative. The prefix match was silently passing everything through.

2. **`depends_on` enforcement in idle hook** — `check-remaining-tasks.sh` now filters claimable features by dependency chains. A feature is only offered if all its `depends_on` entries have `status: "passing"`. Previously, blocked features were assigned as if ready.

3. **Targeted `correction_cycles` increment** — `verify-task-quality.sh` now extracts the feature ID from task metadata or subject prefix and only increments `correction_cycles` for that feature. Previously, all in-progress features were incremented on any teammate's rejection, corrupting metrics in multi-teammate sessions.

4. **Consistent JSON parsing in init.sh** — Replaced the fragile `grep`/`sed` chain for reading `stack` from `harness.json` with `python3 -c "import json; ..."`, matching every other script in the harness.

**Three convention changes:**

5. **Context Management in spawn templates** — Feature Implementer and Layer Implementer templates now instruct teammates to compact proactively before starting a new feature (after TeammateIdle reassignment) to prevent mid-implementation context loss.

6. **PostCompact circuit breaker** — The PostCompact hook prompt now detects repeated compaction context collapse (third+ compaction in rapid succession) and instructs the teammate to save state and escalate to the lead rather than looping.

7. **TaskCreate metadata convention** — All TaskCreate examples now include `metadata: { feature_id: "FXXX" }` for task-to-feature correlation that survives compaction. Enables the targeted `correction_cycles` fix.

**One docs change:**

8. **Completion message deduplication** — Added guidance to the Agent Teams messaging protocol to prevent duplicate completion messages when the TeammateIdle hook fires immediately after task completion.

### v3.3.0 (2026-03-28)

**Metacognitive self-improvement**: The harness now learns from its own coordination patterns, not just from domain work. Inspired by [Facebook Research's HyperAgents framework](https://arxiv.org/abs/2603.19461), which demonstrated that systems whose improvement mechanisms are themselves improvable outperform fixed-meta alternatives.

**Five coordinated changes:**

1. **Operational metrics in features.json** — Five new fields track coordination quality:
   - `correction_cycles`: auto-incremented by TaskCompleted hook on rejection. Signals features harder than expected.
   - `scope_expansions`: files/dirs added to scope after initial assignment. Reveals initial scoping accuracy.
   - `approaches_tried`: brief notes on what worked/failed before the passing implementation.
   - `failure_reason`: why a feature reached `status: "failed"`. Root cause without re-reading history.
   - `discovered_via`: discovery lineage — which feature's implementation revealed the need for this one (distinct from `depends_on` technical dependencies).

2. **Structured retrospective (Phase 5.5)** — Runs after all features pass, before teardown. Analyzes `correction_cycles`, `scope_expansions`, `discovered_via`, and `approaches_tried` across the session. Writes findings to `context_summary.md` under:
   - `## Meta-Session [DATE]`: session-specific insights (scope accuracy, model calibration, discovery patterns, approach successes/failures, plan approval value)
   - `## Meta-Patterns`: generalizable coordination insights that transfer to new projects (when to use Opus, how to scope, when plan approval pays off)
   - Applies to both single-session and Agent Teams workflows. Skipped on first session (no data yet).

3. **Tiered test evaluation in init.sh** — Split test runs into two stages (inspired by HyperAgents' staged evaluation):
   - `smoke_test`: compile/syntax check only, completes in <15s
   - `full_test`: complete suite with coverage (existing behavior)
   - TaskCompleted hook now runs smoke first; only runs full if smoke passes. Reduces cost of early rejection for compile errors.

4. **Meta-Patterns section in context_summary.md** — Dedicated section for coordination insights, distinct from domain-specific patterns. Populated by retrospective step. Intended to transfer to new projects as starting context.

5. **Dynamic model selection heuristics** — Phase 1 planning now reviews historical operational metrics before assigning Sonnet vs Opus:
   - `correction_cycles >= 3` in same scope → upgrade implementer to Opus
   - `scope_expansions >= 3` → assign broader initial scope, note as "expansion-prone"
   - `failure_reason` mentions interface misunderstandings → set `require_plan_approval: true`
   - `discovered_via` depth > 1 → consider folding into parent scope
   - All judgment calls for the lead, not mechanical rules.

**What this enables:** The harness accumulates coordination wisdom across sessions. After 3-4 Agent Teams sessions, it knows which scopes are tricky, which features need Opus, where to probe for hidden features at init. This is the practical version of HyperAgents' "metacognitive self-modification" — improving how the system improves, not just what it produces.

### v3.2.2 (2026-03-21)
- Replaced TodoWrite with TaskCreate/TaskUpdate (TodoWrite no longer exists in Claude Code)
- Renamed "delegate mode" to "plan mode" to match current Claude Code terminology
- Added worktree isolation for teammate scope enforcement (`isolation: "worktree"` in Task() calls)
- Added PostCompact hook for automatic context re-injection after compaction
- Made PostToolUse build-check hooks async (non-blocking)
- Added Auto-Memory vs context_summary.md guidance
- Synced CLAUDE.md template with installed global copy (Agent Autonomy override callout, git identity mismatch fix, context_summary.md anti-patterns)
- Added path-scoped frontmatter to agent-teams-protocol.md (already had `globs: [.harness/**]`)
- Removed `non-harness-workflow.md` rule; core loop folded into CLAUDE.md (saves ~3K tokens per session)
- Removed `engineering-standards.md` rule; 100% redundant with CLAUDE.md (saves ~3K tokens per session)
- Fixed TaskCreate API shape: dependencies set via TaskUpdate addBlockedBy, not TaskCreate blocked_by
- Fixed TeammateIdle documentation: hook prompts reassignment, doesn't auto-assign
- Fixed PostCompact hook: uses `type: "prompt"` for mechanical context injection
- Added PreToolUse scope enforcement hook (`enforce-scope.sh`) — blocks edits outside assigned scope
- Added PreToolUse git identity hook (`verify-git-identity.sh`) — blocks push/pull with wrong identity
- Added native `owner` field on TaskUpdate for task assignment alongside features.json `assigned_to`
- Added `activeForm` to TaskCreate examples for better spinner UX
- Added usage recommendations section to README
- Updated enforcement tier documentation with honest hook classification (mechanical vs prompted)

### v3.2.1 (2026-02-18)
- Fixed PostToolUse hook schema: PascalCase event name, proper nested `hooks` array
- Fixed hook commands to parse `tool_input.file_path` from stdin JSON via `jq`
- Documented `plan_approval_response` delivery bug; all plan approvals use direct messages

### v3.2 (2026-02-18)
- Extended features.json schema: `scope`, `depends_on`, `assigned_to` fields
- Defined exhaustive status enum: pending, in-progress, blocked, passing, failed
- Unified on `context_summary.md` across all modes (replaces `decisions.md`)
- Added hook verification step to harness-init
- Added Integration Failure Recovery protocol
- Recalibrated cost framing: "5x per implementer" not "5x overall"
- Tightened TodoWrite discipline: update after every TDD step
- Added delegation decision framework
- Extracted non-harness workflow to separate rules file
- Fixed plan-and-wait contradiction for teammate spawns

### v3.1 (2026-02-18)
- Added TaskCompleted and TeammateIdle hooks for mechanical quality enforcement
- Added plan-first workflow with user approval before spawning teammates
- Added model mixing guidance (Opus lead/reviewer, Sonnet implementers)
- Replaced custom messaging with native SendMessage protocol
- Added delegate mode as default for lead agents
- Added task dependency chains via TaskCreate blocked_by
- Added plan approval protocol for complex features

### v3.0 (2026-02-17)
- Replaced module locking with native Agent Teams integration
- Replaced 4-file pattern with compaction-aware approach (TodoWrite)
- Simplified features.json
- Added global engineering rules
- Added git identity capture and verification

### v2.1 (2026-02-01)
- Added module locking for parallel agent coordination
- Added `.context/modules.yaml` for defining code boundaries
- Added context-graph skill (claim/release/status/force-release)
- Restructured to use Claude Code's native memory system (`rules/`, `@imports`)

### v2.0 (2026-01-24)
- Initial public release
- Two-phase architecture (initializer + coding agents)
- 4-file pattern integration
- Multi-language init.sh support
