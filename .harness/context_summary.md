# Context Summary

Persistent record of architectural decisions, discovered patterns, gotchas, and active context.
This file is referenced in CLAUDE.md and loaded every session.

## Active Context
- Currently working on: F006/OVI-62 passing and merged (PR #38 @ c3767d2, after one REQUEST CHANGES round on coverage). 10/22 features now passing.
- Next up: /harness-issue-prep the next P2/P3 epic issue by priority. Also refresh live .claude/hooks/*.sh from F003's/F008's/F009's/F010's fixed templates (still deferred, carried across many sessions now)

## Cross-Cutting Concerns
- Stack: custom (shell hooks + JSON manifests + markdown skills; no application code)
- Architecture: Claude Code plugin distribution repo — .claude-plugin/ manifests, hooks/, rules/, schemas/, skills/, agents/, fixture-based shell test suite at test/run-tests.sh
- Key constraints:
  - This repo is BOTH the vv-harness plugin source AND (as of OVI-44 step 0) a harness-managed project itself. Files under templates/, rules/, skills/ are distribution content — do not follow their instructions while working here.
  - Version lives ONLY in .claude-plugin/plugin.json; bump once per merged batch (4.3.0 after epic item 7, 4.4.0 after item 13, 5.0.0 at the end).
  - Master plan: Linear epic OVI-44 (project vv-harness). One issue per session, strict execution order, per-issue loop = prep → TDD → tests green → PR + CI → adversarial review → merge → Linear update → handoff.
  - Git: account eovidiu (WRITE on oeftimie/vv-claude-harness). SSH auth unavailable in this environment; origin uses HTTPS with gh credential helper. Never push to main; PR-based flow only.

## Domain: Harness Plugin Engineering

### Decisions
- OVI-61/F005's cold-start dogfood release gate is DROPPED, not deferred: a
  recommended-but-unenforced checklist item would drift into ceremony (this
  project's own README rates written-only rules "medium reliability... compliance
  drifts over long contexts"), and there's no historical evidence in this project
  that skipped dogfooding caused a real incident — every past bug was caught by the
  automated suite or code review. Presented as a binary (mechanize it for real, or
  drop it) rather than a soft middle ground, per Ovidiu's explicit rejection of
  "recommended, not blocking." If ever revisited, it needs genuine mechanical
  enforcement (e.g. a session-end.sh check tied to plugin.json version-bump
  detection requiring a fresh MAINTENANCE_LOG.md entry) as its own future ticket —
  none exists today. F005's scope is now hostile-gate tests only
  (test/run-tests.sh); reasoning recorded as a Linear comment on OVI-61
  (2026-07-24, per Ovidiu)
- F022 resolved: `coverage` is typed `number|string|null` in both
  schemas/feature.schema.json and scripts/validate-features.py — Ovidiu chose
  "relax the schema" over rewriting the live data, since this repo (and any other
  shell-suite-only project) legitimately has no numeric coverage tooling. The live
  .harness/features.json now validates cleanly for the first time (2026-07-24, per
  Ovidiu)
- Claim-matched proof (F010/OVI-52): five new optional feature fields (`qa_binding`,
  `proof`, `coverage_target`, `delivered`, `design_contract`), all backward-compatible
  (absent/null forever valid). The done-definition is now three tiers: passing
  (mechanical: tests + coverage_target) -> done (passing + proof) -> shipped (done +
  delivered). `verify-task-quality.sh`'s coverage_target gate and proof/qa_binding WARN
  both read straight off the TARGETED feature's own object at accept-time — no external
  lookup, no status-field check (the hook itself never sets status="passing", so
  "accepted" is the operative event, not a status transition) (2026-07-24, F010)
- `harness-issue-prep`'s Step 5 template gained a mandatory "QA binding" line, and
  `spec-verification`'s SV-01 check now flags a spec missing one — naturally prospective
  since it's new text in a static agent definition file: only future invocations see it,
  no grandfather-clause logic needed (2026-07-24, F010)
- enforce-scope.sh.template now handles both Edit/Write/MultiEdit and Bash matchers.
  The pre-existing out-of-scope Edit/Write check is untouched (exit 2, "legacy path
  until touched" per Amendment 5). Two new denial paths — lead-owned state files
  (features.json, context_summary.md, claude-progress.txt) and best-effort Bash write
  coverage — use `hookSpecificOutput.permissionDecision: "deny"` (exit 0) with a
  `verified live YYYY-MM-DD on Claude Code X.Y.Z` annotation (format sourced from
  OVI-57 Amendment 1 item 6, though OVI-57 itself is unimplemented) (2026-07-24, F009/OVI-51)
- Bash write-command matching strips heredoc bodies (opening line through closing
  marker) before segmenting on `|`/`;`/`&&`, so payload text can never false-positive
  and a heredoc-into-redirect line's real `>`/`>>` target is still caught; a write
  hidden inside a heredoc body fed to a nested interpreter is an explicit, documented
  residual hole, not solved (2026-07-24, F009/OVI-51)
- `.harness/harness.json` now carries a `prep` block: `prep.linear` (labels `harness-ready` / `harness-needs-prep`, created this session) and `prep.stamp` (`stamper: "ovidiu"`) are configured; `prep.runner` deliberately omitted — no external issue-to-PR runner exists in this environment. This switches `/harness-issue-prep` from local-only to full remote mode (Linear write-back + stamping) for all future preps in this project (2026-07-24, per Ovidiu)
- Custom stack targets: full_test = `bash test/run-tests.sh`; smoke_test = `bash -n hooks/*.sh` + `python3 -m json.tool` over both .claude-plugin/*.json manifests (2026-07-22, per OVI-44)
- Features F001–F021 mirror the 21 OVI-44 sub-issues; depends_on mirrors the epic's dependency graph; "independent after P0" encoded as depends_on the three P0 features (2026-07-22)
- Fixture harness.json version stays frozen at 4.0.0 with a "_note" key — bumping it to the live plugin version would recreate the copied-fact drift OVI-47 removes (2026-07-22)
- LICENSE: MIT, owner decision recorded in the OVI-47 assumptions ledger (2026-07-22)
- All four per-project hook templates anchor to `PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"` and cd there — hooks must not depend on the session's cwd; settings.json invokes them as `"$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh` (2026-07-22, OVI-48)
- verify-task-quality is the only features.json writer besides the lead: targeted feature only, indent=2, trailing newline, atomic .tmp + mv (2026-07-22, OVI-48)
- schemas/feature.schema.json (JSON Schema draft 2020-12) is now the single owner of the features.json envelope + 16-field feature object; scripts/validate-features.py hand-implements the same checks in stdlib Python (no jsonschema dependency, per spec) rather than loading the schema at runtime — the schema documents intent for humans/external tools, the script enforces it (2026-07-23, F004/OVI-49)
- Only the 10 pre-v3.3 core fields are required in the schema/validator; the 5 operational metrics + `spec` are optional and type-checked only when present, so the existing shared test fixture (test/fixtures/harness-project/.harness/features.json, which predates v3.3 and has no envelope fields either) validates unmodified — kept envelope fields (project/created/total_features/passing) optional too for the same backward-compat reason (2026-07-23, F004)
- harness_state.py.template's increment-correction-cycles writes only the `.tmp` file; the final `mv` promotion stays in the bash templates (verify-task-quality.sh.template), preserving the existing grep-tested atomic-write pattern (`grep -q 'mv '`) rather than moving the whole atomic write into Python (2026-07-24, F008/OVI-50)
- increment-correction-cycles preserves the original id-AND-status=='in-progress' match gate exactly (silent no-op, exit 0, no write, if the id exists but status differs); the NEW exit-3 code is reserved strictly for "no feature with that id at all" — these are two different conditions the OVI-50 spec only fully specified for the latter (2026-07-24, F008)
- session-start.sh (plugin-shipped, must support pre-v5 projects) delegates ONLY the next-claimable algorithm to harness_state.py when `.claude/hooks/harness_state.py` exists; the "Features: N/M passing" line and the fallback inline logic are untouched — per the OVI-50 spec's explicit scoping of point 4, not a full rewrite of session-start.sh's read path (2026-07-24, F008)

### Patterns
- Tests must pin env vars the hooks read: run_session_start forces CLAUDE_PLUGIN_ROOT unset (env -u), run_session_start_with_root sets it — never inherit the test shell's env for hook behavior assertions (2026-07-22)
- Fixture tests install templates via install_hooks and invoke them exactly the way settings.json does (`CLAUDE_PROJECT_DIR=<fixture> <fixture>/.claude/hooks/<name>.sh`) — testing through the real invocation form caught the cwd bugs the old `bash relative/path` form hid (2026-07-22)
- To prove a delegated code path produces byte-identical output to the inline path it replaces, install the real module into one fixture and not the other, run the SAME hook against both, and diff the specific output line — don't just assert the delegated path "looks right" in isolation (2026-07-24, F008)
- A portable way to simulate an atomic-write interrupt without OS-specific mocking: chmod the containing directory to remove write permission (555), attempt the write, assert the original file untouched and no tmp file was created, then chmod back — works on macOS and Linux CI without root (2026-07-24, F008)

### Gotchas
- Two existing test fixtures broke silently when F010 added new known feature fields
  and new session-end.sh behavior: (1) F004's "unknown field" test used `proof` as its
  example of a not-yet-existing field name — became a real, validated field this
  session, so the test needed a genuinely-still-unused field name (`custom_metadata`)
  instead. (2) session-end.sh's "clean session prints nothing" fixture had F001
  already `passing` with no `proof` in the BASE shared fixture (unrelated to what the
  test itself mutates) — the new proof-discipline-note logic correctly flagged it,
  breaking the "prints nothing" assertion; fixed by giving F001 a proof object too.
  Both are the same lesson: when a new field/behavior becomes real, grep the whole
  test suite for anything that used its name/shape as a "doesn't exist yet" example or
  relied on a shared fixture's OTHER entries being unaffected by new logic
  (2026-07-24, F010)
- F008's single-writer grep test (`grep -l "json.dump" ...`) false-positived on F009's
  legitimate new `json.dumps(...)` calls (serializing a JSON string for hook stdout,
  not writing features.json at all) — "json.dump" is a substring of "json.dumps".
  Fixed by requiring the literal open-paren: `"json.dump("`, which "json.dumps(" does
  not contain. Any future grep-based test on a substring this loose should check
  whether a legitimate near-miss identifier could collide (2026-07-24, F009/OVI-51)
- The Claude Code Bash tool runs in an OS-level sandbox (macOS Seatbelt) that blocks `security find-generic-password` for the vv-harness-stamp Keychain item — confirmed NOT a Keychain-ACL/prompt issue: rotating the item with `-A` (allow all local apps, no prompt) made zero difference, exact same silent exit code 36 before and after. The block happens before the keychain ACL is ever evaluated. `dangerouslyDisableSandbox: true` on that one Bash call would get past it; Ovidiu declined it for OVI-51's prep, so that spec is normalized-but-unstamped. CONFIRMED PERSISTENT, not a one-off: OVI-52's prep hit the exact same exit 36 with no changes in between; stop re-diagnosing this each session, it's an environmental constant until someone explicitly authorizes the sandbox override or an alternative signing path (2026-07-24, F009/F010 preps)
- Running `security find-generic-password -s <service> -w` prints the RAW SECRET, not a derived value — if a human runs this themselves and pastes the output into the conversation (as opposed to letting the agent invoke it and only see the derived HMAC), that secret is burned per the transcript-secrets doctrine and must be rotated immediately, not reused (2026-07-24, F009/OVI-51 prep)
- Baseline before any change: 66/66 assertions passing on main @ d3661ff (2026-07-22)
- README's v2.x date repeats live under the "## The evolution: v2.0 to v4.2" heading, not a section literally named "Evolution" as OVI-47 claimed (2026-07-22)
- macOS resolves `/var` → `/private/var`, so `git rev-parse --show-toplevel` returns a different prefix than an unresolved `$TMPDIR`/CLAUDE_PROJECT_DIR path — absolute-path prefix-stripping against the git toplevel silently fails on macOS; prefer CLAUDE_PROJECT_DIR (2026-07-22)
- session-start.sh's own warning blocks are the reference pattern for new orientation checks: wrap the whole python heredoc body in try/except pass AND pipe stderr to /dev/null with `|| true` at the shell level — belt-and-suspenders against a malformed features.json ever leaking a traceback into model context (2026-07-23, F002)
- This repo's live .claude/hooks/*.sh lag the fixed templates: the old verify-task-quality corrupted correction_cycles (F003 +1, no trailing newline) when the gate rejected a TDD red-phase task completion; reset to 0 as a false positive. Refresh live hooks from templates after OVI-48 merges (2026-07-22)
- Dogfooding scripts/validate-features.py against this repo's own live .harness/features.json (not required by F004's acceptance criteria, just a sanity check) found F001-F004's `coverage` field holds a descriptive string ("n/a (shell suite, no coverage tooling; full_test N/N is the gate)"), not the number|null the OVI-49 spec types verbatim. Did not loosen the schema or rewrite the live data to make this pass — filed as F022 (discovered_via F004) instead, since silently relaxing a just-verified spec to match existing non-conformant data would be gaming the check, not fixing it (2026-07-23, F004)
- Marking a TDD sub-task "completed" while the suite is intentionally red still trips the TaskCompleted gate and bumps correction_cycles — this is now the FOURTH session in a row (F002, F003, F004, F008) hitting the identical false positive. The procedural fix (mark red-phase tasks complete only after green) keeps slipping under real work pressure; worth tightening harness-continue's task-template wording or the gate itself rather than continuing to just log it (2026-07-24, F008)

## Meta-Patterns
<!-- Coordination insights that apply across features — NOT domain-specific.
     Populated by the retrospective step at session end.
     These transfer to new projects: harness-init can import them as starting context. -->
- Capability-block memories decay: before telling the user something is blocked
  (permissions, tooling), re-verify against current .claude/settings.json and repo
  state — a one-line grep beats a wasted round-trip.
- Small independent-edit batches (docs, hook guards, rule text) fit single-session
  mode regardless of file count; reserve teams for genuinely parallel feature work.

## Meta-Session 2026-07-22
- Scope accuracy: bootstrap session touched only .harness/ and .claude/ as planned; prep
  session touched only features.json (F001), claude-progress.txt — no expansions.
- Model calibration: SV on opus / RV on sonnet per the prep skill worked — SV caught the
  two genuine forks (dates, license), RV cleared cycle 1 cleanly. No re-runs needed.
- Discovery lineage: F001–F021 imported from OVI-44, none discovered organically yet.
  Prep of OVI-47 discovered that bootstrap-minted spec objects hashed the one-line
  feature summaries, not real spec text — F002–F021's PASS records are cosmetic until
  each goes through /harness-issue-prep (already the per-issue plan; do not trust
  pre-prep spec.hash values).
- Approach patterns: per-issue prep loop (SV → human answers → RV → normalize) closed in
  one revision cycle; presenting SV questions verbatim got decisive one-line answers.
- Plan approval: PASS verdicts now carry implicit go-ahead for write-back (owner
  decision 2026-07-22); ASK/BLOCK still stop for Ovidiu. Extended same day: clean
  orientation + a plan with no open questions = default go-ahead, no wait.
- Implementation phase (added post-merge): TDD red (9 failing) → green 77/77 in one
  pass; single-session mode was right for a 10-file batch of small independent edits —
  team overhead would have exceeded the work.
- Review value: opus adversarial reviewer approved with 2 nits and caught a genuinely
  untested boundary (empty-string env var) even on a docs-heavy batch; worth the spawn.
- Stale-memory cost: a session memory claimed gh pr merge was blocked; the permission
  had landed in .claude/settings.json (PR #22) before this session, and trusting the
  memory cost one needless ask. Verify capability-block memories against current
  settings/repo state before acting on them — they decay fast.

## Meta-Session 2026-07-22 (session 3, F003/OVI-48)
- Scope accuracy: F003's scope array (5 templates + run-tests.sh + SKILL.md) matched the
  work exactly — zero expansions. One out-of-scope need surfaced (refreshing this repo's
  live .claude/hooks copies) and was deferred to the handoff instead of expanded into.
- Model calibration: single-session on the lead model; 13-red → green in one pass, no
  correction cycles (the one recorded increment was a gate false positive, see Gotchas).
- Discovery lineage: red phase organically discovered the macOS /private/var symlink bug —
  a defect beyond the four the spec named; fixed by the same CLAUDE_PROJECT_DIR anchor.
- Approach patterns: testing templates through the real settings.json invocation form
  (not a convenience wrapper) is what surfaced both cwd bugs; keep doing this for hooks.
- Gate friction: TaskCompleted rejects marking the "write failing tests" task complete
  during TDD red (suite is intentionally failing) and increments correction_cycles via
  the live hook. Pattern: complete the red-phase task only after green, or expect a
  false-positive metric to reset.
- Review value: two independent reviewers; the opus reviewer reproduced a real blocker
  the lead's self-review missed (a stale features.json.tmp orphaned by a killed run is
  promoted by the guarded mv — guard-on-existence proves the tmp exists, not that this
  run wrote it). Fixed with rm -f before the write + the repro as a regression test.
- Reviewer latency: verdicts arrive in delayed bursts (20-45 min), not streamed. Budget
  for it, ping once, keep doing non-merge work; don't spawn duplicate reviewers (one
  redundant spawn cost a full second review this session).
- Reviewer latency (session 4 correction): the 20-45 min pattern is NOT a guarantee.
  F002's reviewer never reported after ~80 min and a ping. Waited in stages, checked
  with Ovidiu twice via AskUserQuestion rather than guessing, then did a documented
  self-review on his direction — found and fixed one real gap (spec said "!= null",
  code did a truthy check). Self-review under user direction is a legitimate fallback
  when it's this stalled; the F003 lesson (self-review can miss things a real reviewer
  catches) still applies, so treat it as lower-confidence than an actual review, not
  equivalent.

## Meta-Session 2026-07-23 (session 4, F002/OVI-46)
- Scope accuracy: F002's scope array (5 files) matched the work exactly; the fix moved
  entirely within it (session-start.sh, SKILL.md, team-spawn-prompts.md,
  agent-teams-protocol.md, run-tests.sh) — zero expansions.
- Model calibration: single-session, no correction cycles from the quality gate itself
  (only the known TDD-red-phase false-rejection on tasks #6/#7, already a documented
  gotcha, not a real correction).
- Approach patterns: self-review under explicit user direction, after two AskUserQuestion
  checkpoints during an ~80-min reviewer stall, surfaced a genuine spec-vs-code gap
  (truthy check vs. literal "!= null") that a less careful pass would have missed —
  self-review is not worthless, but it is not a substitute for independent review either.
- Gate friction (recurrence): TaskCompleted rejected #6/#7 completion during red phase
  again this session, exactly as logged in session 3's retrospective. This is now a
  confirmed recurring pattern, not a one-off — the fix is procedural (mark red-phase
  tasks complete only after green), not a hook bug.

## Meta-Session 2026-07-23 (session 5, F004/OVI-49)
- Scope accuracy: F004's scope array (6 files/dirs) matched the work exactly — 2 new
  files (schema, validator) plus edits to the 4 listed docs/tests; zero expansions.
- Model calibration: single-session, one correction_cycles increment on F004 — the same
  documented TDD-red-phase false-rejection (marked the "write failing tests" task
  complete while the suite was intentionally red). Third session in a row hitting this;
  the procedural fix (mark red-phase tasks complete only after green) is confirmed but
  still occasionally slips — worth tightening the harness-continue skill's task template
  wording rather than relying on memory alone.
- Discovery lineage: dogfooding the new validator against this repo's own live
  .harness/features.json (not part of F004's acceptance criteria) surfaced a real
  spec-vs-reality gap: `coverage` is typed number|null per the OVI-49 spec, but this
  project's own F001-F004 store a descriptive string there since it has no coverage
  tooling. Filed as F022 (discovered_via F004) rather than silently loosening the schema
  to match — a just-verified spec shouldn't bend to accommodate pre-existing drift
  without a deliberate decision.
- Approach patterns: designing the validator as hand-rolled stdlib checks (not a
  jsonschema-loader reading the schema file) works cleanly once the two are written
  side by side from the same field list; the schema stays the human/external-tool
  reference, the script is the enforcement, and the spec explicitly asked for this
  split (no jsonschema dependency) rather than treating it as duplication to avoid.
- Approach patterns: keeping the 5 v3.3 operational-metric fields (plus `spec`) optional
  and type-checked-only-when-present let the existing shared test fixture
  (test/fixtures/harness-project/.harness/features.json, pre-v3.3 shape, no envelope
  fields) validate without modification — avoided scope creep onto test/fixtures/, which
  wasn't in F004's scope list and is used by many unrelated hook tests.
- Review value: adversarial Opus reviewer independently re-ran the full suite, probed
  every edge case named in the spawn prompt (bool-as-int, missing "features" key,
  non-dict entries, non-object root), and confirmed all 4 acceptance criteria itself
  rather than trusting the lead's claim — APPROVE with 3 non-blocking nits, all already
  captured by F022 or cosmetic (validator's depends_on check relies on the dangling-ref
  check rather than duplicating the schema's `^F[0-9]{3}$` pattern check — acceptable
  drift given the no-jsonschema constraint, but noted for anyone touching this again).
  Merged on green CI (2 checks) + APPROVE @ 5b15018; Linear OVI-49 Done.

## Meta-Session 2026-07-24 (session 6, F008/OVI-50)
- Scope accuracy: F008's scope (harness_state.py.template + the two per-project hook
  templates + session-start.sh + SKILL.md/INSTALL.md + test/run-tests.sh) matched the
  work exactly; the one addition (updating install_hooks() test helper) was implied by
  the refactor itself, not a scope expansion.
- Model calibration: single-session, 2 correction_cycles — both the known TDD-red-phase
  false-rejection (marking a sub-task complete mid-red), not real correction cycles.
- Prep quality: this feature's spec went through SV ASK (4 questions) -> RV PASS in one
  cycle. All 4 questions resolved genuine ambiguities that would have caused rework if
  guessed at implementation time (especially the criterion-1-vs-point-3 contradiction on
  the write-surface test, and the two unspecified edge cases for next-claimable/increment).
  The prep investment paid for itself directly in this session.
- Discovery lineage: none this session (no new features filed).
- Approach patterns: preserving an EXISTING grep-tested pattern (the literal `mv ` string
  in verify-task-quality.sh.template) shaped the module's design — increment-correction-cycles
  writes only the .tmp file rather than doing a complete atomic write internally, keeping
  the real promotion step in bash. Worth checking existing grep-based tests for what they
  actually assert BEFORE consolidating logic into a new shared module, not after.
- Approach patterns: writing a manual before/after comparison (install harness_state.py
  into one fixture, not the other, diff the specific output line) caught that the
  delegation-parity test would otherwise pass vacuously until session-start.sh's actual
  delegation logic existed — a good habit for any "output must be identical" acceptance
  criterion, not just a shell-test assertion.
- Review value: adversarial Opus reviewer independently re-ran the full suite and cited
  exact file:line for every one of the 9 acceptance criteria rather than taking the PR
  description's claims at face value — APPROVE with 3 non-blocking nits (split-write
  footgun in increment-correction-cycles if a future direct caller assumes exit 0 means
  "persisted"; check-remaining-tasks.sh's silent no-fallback if harness_state.py is ever
  missing; a cosmetic stderr-merge detail). Merged clean on green CI + APPROVE @
  d0af1ac (no classifier block this time); Linear OVI-50 Done.

## Meta-Session 2026-07-24 (session 7, F009/OVI-51)
- Scope accuracy: initial scope (5 entries) expanded to 8 mid-implementation once
  Amendment 7's acceptance criterion 8 ("every gate .sh.template carries a Failure
  posture: line") was read closely — it demands touching all 4 gate templates, not
  just enforce-scope.sh.template. This was already implied by the RV-approved spec
  text, so treated as a scope_expansion to record, not a new decision requiring
  re-approval. Lesson: when a spec's acceptance criteria say "every X", check whether
  the feature's own `scope` array actually covers every X before starting.
- Model calibration: single-session, 2 correction_cycles — both the known
  TDD-red-phase false-rejection pattern (now 5 sessions running), not real corrections.
- Prep quality: this was the first BLOCK verdict (not just ASK) this project has seen —
  the spec's base text and its own amendment directly contradicted each other on the
  exit-code contract. Resolving it required a genuine design judgment call (which
  denial paths count as "new" vs "legacy"), not just filling in a missing detail; the
  lead's recommendation, grounded in the amendment's own carve-out clause, is what RV
  ultimately verified as non-capitulating. Worth remembering: a BLOCK from internal
  spec contradiction needs a design decision, not just an answer.
- Discovery lineage: none new filed; found and fixed one PRE-EXISTING test bug (F008's
  overly-broad json.dump grep, see Gotchas) exposed by legitimate new code.
- Approach patterns: this session also stood up the full remote /harness-issue-prep
  flow for the first time (prep.linear + prep.stamp configured, Linear labels created).
  Stamping itself hit a real environmental wall (Bash tool sandbox blocking Keychain
  access) that no amount of Keychain ACL tuning could fix — recognizing "this isn't the
  ACL, it's a different layer" after the identical failure survived an ACL rotation
  was the key diagnostic step, not guessing at more Keychain fixes.
- Approach patterns: a human running a keychain read-and-paste command themselves
  (rather than delegating the read to the agent) exposes the raw secret to the
  transcript — worth flagging immediately and treating as burned, every time, not just
  when the user seems to realize it.
- Review value: the elevated-risk classification earned its keep — the Opus reviewer
  found a real false-positive (redirect_target's first-match regex mistook a `>` inside
  a quoted string for the real redirect operator, denying legitimate in-scope writes
  containing markup/arrows/blockquotes; 205/205 green suite never exercised this because
  no existing test had a `>` inside a string before the real redirect). Fixed with a
  one-line change (take the LAST match, not the first) plus a regression test; re-review
  confirmed APPROVE end-to-end against the real hook, not just re-reading the diff.
  Merged clean @ 8ec5df5; Linear OVI-51 Done.

## Meta-Session 2026-07-24 (session 8, F010/OVI-52)
- Scope accuracy: initial scope (6 entries) expanded to 9 mid-implementation once the
  schema-split-ownership pattern (F004) and the doc-consolidation requirements
  (Amendment item 5) were followed through to their actual file targets
  (scripts/validate-features.py, skills/harness-init/SKILL.md, agents/spec-verification.md).
  Same lesson as F009's session: read acceptance criteria for "every X" claims and check
  the feature's scope array actually covers every X before starting, not after.
- Model calibration: single-session, 4 correction_cycles — all the known TDD-red-phase
  false-rejection pattern (now six sessions running: F002, F003, F004, F008, F009,
  F010). This has never once been a real correction. Worth a harder look at whether the
  procedural fix (mark red-phase tasks complete only after green) needs to become
  mechanical instead of relying on memory, since six sessions of "don't do this" hasn't
  stopped it recurring.
- Prep quality: this spec needed 2 RV cycles, not 1 — cycle 1 surfaced a genuine new
  gap (qa_binding had no machine-readable home) that neither the original SV report nor
  the human's first round of answers had caught. Lesson reinforced from F009: RV isn't
  just re-checking the human's answers, it's re-deriving testability from scratch, and
  that can find things nobody asked about yet.
- Discovery lineage: no new features filed. Found and fixed two pre-existing test
  fragility issues (see Gotchas) — both were "a new field/behavior collided with an
  existing test's fixture assumptions," not the same bug twice, but the same category.
- Approach patterns: designing the coverage_target/proof mechanism required accepting
  that THIS repo's own coverage field (a descriptive string) means the new gate stays
  dormant here — rather than forcing a decision on F022 to make the new feature
  "fully exercised" in this repo, the gate was built to degrade gracefully (skip when
  coverage isn't numeric) so it's correct and testable via fixture for any project,
  including this one whenever F022 is eventually resolved.
- Review value: adversarial Opus reviewer independently exercised validate-features.py
  against ~20 crafted inputs directly (not just re-reading test names), traced the WARN
  block by hand against all 4 AC3 fixture cases, and confirmed session-end.sh's proof
  note never reaches SESSION_INCOMPLETE by reading the code path — APPROVE with 1 real
  nit (a line 1 char over the 100-char limit, fixed before merge) and 1 by-design
  observation (F010 itself ships with no proof of its own, which the spec's
  prospective-rule circularity explicitly permits). Also independently reconfirmed the
  pre-existing F022 gap (live features.json's descriptive-string coverage doesn't pass
  validate-features.py) without being asked — noted as orthogonal, not a defect of this
  PR. Merged clean @ e5f1fdf; Linear OVI-52 Done.
- Review value: even a small, non-Linear internal fix (F022) benefited from review —
  the reviewer confirmed the bool-can't-slip-through-string-check logic empirically,
  ran the fix against the live features.json end-to-end (not just fixtures), grepped
  for other coverage-type consumers to rule out a regression, and caught a real
  (non-blocking) accuracy gap: F022's own `scope` array didn't list
  scripts/validate-features.py or test/run-tests.sh even though the fix necessarily
  touched both. Fixed before merge. Merged clean @ d0c8dff; no Linear issue (internal
  discovery via F004).

## Meta-Session 2026-07-24 (session 9, F005/OVI-61)
- Scope narrowing under pushback: this session's prep produced a soft "recommended,
  not blocking" middle ground for the dogfood-gate half of the original spec. Ovidiu
  rejected it outright ("not agreeing with downgrading. Is either dogfooding or
  useless") — a firm signal that an unenforced checklist item is worse than no item at
  all, since it drifts into ceremony without ever being checked. The lesson: when a
  proposed compromise softens a mechanical-vs-prose distinction this project already
  treats as load-bearing (see README's tiers table), don't offer the soft middle
  ground as the default recommendation — offer the two real options (build it for
  real, or drop it) and let the human pick.
  - Why: the middle ground was proposed once and rejected once already; re-offering it
    would be re-litigating a settled call.
- Discovery lineage: no new features filed. The dropped dogfood-gate scope was
  documented via a Linear comment on OVI-61 rather than a features.json entry, since
  it explicitly will not be implemented (not deferred) — there is nothing to track.
- Approach patterns: for a test-only feature (no hook script behavior changes), there
  is no traditional TDD red phase. Validation instead was: audit existing assertions
  first to avoid duplicate coverage, add each new assertion, run the suite, and
  independently confirm each content check is a real transcription of the hook's
  actual output (cross-referenced against the .sh.template source) rather than a
  tautology. This audit-first step found 2 of the 4 gates already had adequate
  content coverage from earlier features (F009's enforce-scope Edit case,
  F009-era verify-git-identity's name-mismatch case) — only the gaps needed new
  assertions, which kept the diff smaller than a from-scratch pass would have.
- Review value: adversarial Opus reviewer ran the suite itself (265/265), cross-
  checked all 15 new content assertions against the actual .sh.template denial
  strings line-by-line rather than trusting the PR summary, and verified the
  email-mismatch test's isolation (confirmed only the email diverges from the
  fixture's expected identity, so the failure is genuinely attributable to email
  alone). Caught one real but non-blocking nit: the PR description's blanket
  "invariant + repair" phrasing overstated two Bash out-of-scope cases (tee, new
  `>>` redirect) that correctly assert only the invariant, because the underlying
  hook deliberately emits no repair verb on that path — asserting one anyway would
  have been the exact tautology-avoidance failure the review was watching for.
  APPROVE, no code/test change needed. Merged clean @ aa998df; Linear OVI-61 Done.

## Meta-Session 2026-07-24 (session 10, F006/OVI-62)
- Scope accuracy: the prep's scope (SKILL.md, INSTALL.md, harness-continue SKILL.md,
  test/run-tests.sh) was missing the two Python files a testable "report-first
  structural check" actually needs (doctor.py, fixes.py) -- SKILL.md alone is prose an
  LLM follows, not something bash test/run-tests.sh can assert against. Recorded as a
  scope_expansion. Lesson: when a spec names only a SKILL.md for a "checkable"
  feature, ask up front whether the acceptance criteria imply an executable backing
  it, the same way harness_state.py backs verify-task-quality.sh/check-remaining-
  tasks.sh -- prose skills can't be asserted against by a shell test runner.
- Model calibration: single-session, correction_cycles 2 -- both the known TDD-red-
  phase false-rejection pattern (now 7 sessions running: F002-F005, F008-F010, F006).
  Still never once a real correction. The procedural fix (mark red-phase tasks
  complete only after green) is well past the point where "don't do this" should
  have stuck; worth revisiting whether this needs to become mechanical.
- Discovery lineage: no new features filed.
- Approach patterns: manually exercising all 7 acceptance criteria against scratch
  fixtures BEFORE writing the formal test/run-tests.sh assertions caught two real
  bugs pre-review: (1) apply_fixes() trusted each fixer's per-call return value, so
  one add_settings_wiring() call fixing 5 findings at once left the other 4
  misreported as still-open after --fix -- fixed by re-running checks fresh instead
  of tracking per-finding fixer success; (2) substring matching in the gitignore
  check treated '.harness/SESSION_INCOMPLETE_TYPO' as satisfying the
  '.harness/SESSION_INCOMPLETE' requirement (prefix collision) -- fixed by switching
  to exact-line matching. Both were found by hand-testing against real scratch
  fixtures, not by the formal test suite (which was written to match the corrected
  contract) -- a reminder that manually exercising a new checker's actual behavior
  before locking in test assertions catches classes of bug that "test what you
  built" cannot.
  Also: reused the plugin's own scripts/validate-features.py (via CLAUDE_PLUGIN_ROOT)
  for the features.json check rather than duplicating validator logic, honoring
  F004/OVI-49's one-owner design decision -- checked this against the actual
  installed-plugin path convention (INSTALL.md's ${CLAUDE_PLUGIN_ROOT} references)
  before assuming it would resolve correctly outside this repo's own dev context.
- Review value: adversarial Opus reviewer measured actual coverage with the stdlib
  trace module (no coverage tool ships in this repo) by replaying the shipped test
  scenarios against real fixtures -- found doctor.py/fixes.py combined ~79%, below
  the 95% gate, and named 5 specific untested behaviors by file:line rather than
  just citing a percentage. REQUEST CHANGES, not APPROVE-with-nits, on a coverage
  gate alone -- correctness was never in question. Closing the gaps surfaced a real
  design bug the coverage push forced a closer look at: check_mld_non_injection was
  checking session-start.sh under the PROJECT's .claude/hooks/, but that file is
  never copied per-project (it runs directly from CLAUDE_PLUGIN_ROOT) -- the check
  was permanent dead code against any real project. Fixed to check the plugin's own
  copy. Re-measured combined coverage after closing all 5 gaps plus a 6th found via
  self-remeasurement (a commit-gate-template-shipped-but-not-copied case): ~98.6%.
  Lesson: a coverage-gate rejection is worth taking seriously even when the
  reviewer's own listed nits are all "minor" -- the act of closing coverage gaps by
  hand (not just adding assertions to make the number move) is what surfaces bugs
  the original implementation-and-test pass didn't catch, because writing a test to
  match your own mental model of the code doesn't test the model itself.
