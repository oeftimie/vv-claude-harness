# Context Summary

Persistent record of architectural decisions, discovered patterns, gotchas, and active context.
This file is referenced in CLAUDE.md and loaded every session.

## Active Context
- The entire locally-discovered bug/design-gap chain that started with F023 is now CLOSED: F023-F062 (40 features, no Linear issue) all shipped. Full per-feature detail lives in features.json's own per-feature `notes` fields and the per-feature Meta-Session entries below; `claude-progress.txt`'s consolidated session entries cover the wall-clock history.
- Linear-tracked arc (F012-F021, the OVI-44 A-series/P-series sub-issues), all shipped so far through the same TDD + mutation-test + adversarial-review-to-APPROVE loop: F012/OVI-53 (PR #98), F013/OVI-63 (PR #99, filed F063 as a follow-up), F015/OVI-55 (PR #100), F016/OVI-57 (PR #101), F017/OVI-65 (PR #102, filed F064 as a follow-up -- F016's `risk` trigger and F017's own conformance-tester trigger share the same underlying gap, that `risk`/`require_plan_approval` aren't persisted durably on the feature object), F018/OVI-66 (PR #103, dual-engine review, docs/protocol only), F019/OVI-58 (root AGENTS.md + rewritten CLAUDE.md), F020/OVI-59 (skills/harness-improve/SKILL.md, this session) implemented. See each feature's own `notes`/`approaches_tried` for the specific catches each review round made.
- Ovidiu, before going to sleep, gave a standing instruction to keep working through everything from Linear until done, without waiting for check-ins between features -- F021 (the last remaining Linear OVI-44 sub-issue) and F063/F064 (discovered follow-ups) are next, worked in the same autonomous loop (implement -> TDD/mutation-test -> review -> merge).
- No other locally-discovered work is queued.

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
- Ground-truth a reviewer's OWN restated claim too, not just the original code under
  review -- a "corrected" claim can itself be wrong (F061's round 2->3: a reviewer
  disproved my claim by inspecting real on-disk state, then my OWN correction
  overcorrected into a different false claim, caught only by re-deriving from source
  a second time rather than trusting either restatement).
- A grep-based test that pins a prose change must be checked against the file's
  ACTUAL line-wrapping, not just semantic equivalence -- a target phrase can silently
  straddle a wrap point after an edit (several F059/F062-family test assertions hit
  this: a true, present phrase still failed `grep -q` because it spanned two lines).
  Verify the exact grep target resolves after every prose edit, independent of any
  semantic-equivalence reasoning.
- When a discovered follow-up's investigation shows the original filed scope doesn't
  fit (a guessed code fix turns out to need documentation instead, or vice versa),
  confirm the redirection with the user before shipping it into distributed content
  -- a scope-TYPE pivot (not just a scope expansion) is a decision the user should
  see, not just a fact to record after the fact (F061).
- A test that only exercises the structurally-safer of two code paths a fix touches
  gives false confidence about the riskier one -- verify new assertions run through
  EVERY path the fix changes, not just the one where the bug class is impossible by
  construction (F062: a bash glob case-arm can't have a substring bug, but the
  paired hand-written python startswith() check can, and was untested).

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

## Meta-Session 2026-07-24 (session 11, F007/OVI-56)
- Scope accuracy: the prep's scope array included skills/harness-continue/team-
  spawn-prompts.md for the "if fixed, remove the workaround" scenario, but RV's
  prep-time amendment had already deferred actual removal to a separate follow-up
  -- so that file needed no edit this session (a scope reduction, not an
  expansion, and correctly anticipated at prep time rather than discovered mid-
  implementation). README.md was a genuine scope expansion: enforcing the new
  project-wide "every workaround needs a retirement condition" rule while leaving
  README's own plan_approval_response mention un-conditioned would have been an
  inconsistency a reviewer would likely have caught, so it was added proactively.
- Model calibration: single-session, correction_cycles 3 -- still the same known
  TDD-red-phase false-rejection pattern (8 sessions running now: F002-F010, F007).
  This session it also visibly reverted 3 TaskUpdate(completed) calls back to
  in_progress mid-session before the suite went green, confirming the hook
  actively re-flips status rather than just logging a correction -- worth
  remembering when a task list looks "wrong" mid-session; it may just be this.
- Discovery lineage: no new features filed, but a substantive finding was made
  and recorded directly in MAINTENANCE_LOG.md / rules/agent-teams-protocol.md
  rather than as a features.json entry, since it's a maintenance-loop finding,
  not an implementation task: the live plan_approval_response probe could not be
  completed at all. SendMessage's own schema has no plan_approval_request
  outgoing type for a teammate, and a spawned teammate confirmed via two
  independent ToolSearch lookups that EnterPlanMode/ExitPlanMode aren't exposed
  to it either, even though both tools exist and other agent definitions
  reference ExitPlanMode. This also let us correct an actively wrong claim in
  agent-teams-protocol.md ("plan_approval_request... works fine" for teammates)
  that would otherwise have sat uncorrected indefinitely -- exactly the kind of
  platform drift this feature exists to catch, on its very first run.
- Approach patterns: given a live-testable claim (the delivery-bug retest),
  actually running it via a spawned teammate rather than reasoning from
  documentation alone surfaced a real, more significant finding than the
  original question ("is bug X fixed") asked about. When Ovidiu was consulted
  mid-probe about whether to dig further or record-and-move-on, he chose the
  latter ("Record it as found and move on") -- a useful calibration: a
  maintenance probe's job is to surface drift accurately, not to fully resolve
  every thread it opens in the same session.
- Review value: the first review pass caught something no amount of self-
  checking would have surfaced -- when I hedged the run-#0 correction in
  agent-teams-protocol.md, I only edited the one Known Limitations entry and
  didn't notice 3 other sites in the SAME file (Teammate Responsibilities,
  Native Messaging Protocol table, Plan Approval steps) still gave teammates
  unqualified instructions to do the exact thing the correction said couldn't
  be verified. A single-paragraph fix silently left a self-contradiction in
  shipped plugin content. The reviewer also caught something I should have
  caught myself: my "correction" swapped one flat, overconfident claim
  ("works fine") for the opposite flat, overconfident claim ("not accurate...
  at all"), when the actual evidence (recorded correctly in MAINTENANCE_LOG.md)
  was properly hedged as inconclusive. Fixing an overstated claim by asserting
  its negation just moves the overstatement, it doesn't remove it -- worth
  remembering as a pattern next time a "correction" is being written.
  Also caught: a missing GH Actions `permissions:` block that would have
  silently 403'd the exact failure-reporting path this feature exists to
  provide -- the kind of bug that only shows up when the thing it protects
  against actually happens, so it would never surface in a normal green-CI
  review pass. Second review round proved the value of MUTATION TESTING test
  assertions, not just reading them: the reviewer literally reverted my fixes
  on a scratch copy and reported which assertions still passed against the
  broken state. I adopted the same technique when fixing the flagged gaps
  (temporarily reverting to the pre-fix content, confirming the tightened
  assertion now fails, then restoring) -- a much stronger validation than
  "the assertion reads correctly" for anything checking that specific wording
  or specific logic survived a change, since a test that merely checks a
  header or keyword is present can pass on both the broken and fixed version.

## Meta-Session 2026-07-25 (session 11 continued, F011/OVI-64)
- Scope accuracy: scope held exactly as prepped (5 files); the one surprise was a
  cross-feature interaction, not a scope gap -- F006/OVI-62's harness-doctor
  commit-gate probe test assumed commit-gate.sh.template would never actually
  exist in this repo's own plugin source (it tested "shipped by the plugin but
  not yet copied to the project" using a FAKE plugin root specifically to avoid
  needing a real template). Once F011 shipped a real one, install_hooks()'s
  glob-copy-everything convention silently satisfied that fixture's "not yet
  copied" precondition. Lesson: a test fixture that depends on "this artifact
  doesn't exist yet" is inherently fragile against a LATER feature actually
  building that artifact -- worth a comment (added) flagging the coupling for
  whoever touches either feature next.
- Model calibration: single-session, correction_cycles 1 -- the same known
  TDD-red-phase false-rejection pattern (9 sessions running now). Not a real
  correction, as always.
- Discovery lineage: no new features filed.
- Approach patterns: for a security-sensitive check (secret-shaped-content
  detection), writing the "must never leak the matched value" tests FIRST
  (asserting the denial message does NOT contain the planted secret string) was
  more valuable than the usual red-then-green flow, since it's the kind of
  requirement that's easy to satisfy accidentally-wrong (e.g. an f-string that
  includes the matched group by mistake) without a dedicated negative
  assertion. Also: manually exercising known evasion/edge shapes NOT covered by
  the 8 formal test cases (combined -am flag, git commit <pathspec>'s
  documented residual hole, --amend with nothing staged) before considering the
  feature done caught nothing broken here, but is worth doing as standard
  practice for any hook whose job is denying an adversarial-ish input, per the
  same principle F005/OVI-61 established for the harness's OWN gates.
- Review value: extreme -- 6 adversarial rounds before APPROVE, each finding
  a real bug the previous round's fix introduced or missed, none of them
  hypothetical (every finding was verified end-to-end against a real hook
  invocation with a real staged secret before being reported or fixed).
  Rounds 1-3 progressively broke and fixed a regex-based git-subcommand
  detector (diff-header mis-parsing -> secret-scan total bypass; then two
  rounds of "the fix for the last regex bug introduced a new regex bug in an
  untested dimension"), ending with round 3 explicitly diagnosing this as
  "tuning a regex against a growing list of examples rather than deciding
  what the matcher's contract is" and recommending a real tokenizer, which I
  implemented immediately rather than risk a round-4 regex edge case. Rounds
  4-6 then did the same thing to the TOKENIZER: round 4 found an incomplete,
  memory-assembled flag set and an unreproducible coverage claim; round 5
  independently re-probed round 4's OWN fix and found it still wrong
  (mechanically re-probing the git binary rather than trusting a from-memory
  list caught 2 more missing flags and 2 wrongly-kept ones), plus recommended
  a fix for an "accepted" hole that turned out to be one line away from
  closed; round 6 found that round 5's OWN continuation-join fix had
  introduced a NEW fail-open bypass (an escaped backslash before a real
  separator newline), plus a missing "&" separator, plus a reserved-word
  recognition gap -- three more findings in the same "the fix for the last
  bug introduces a new one" pattern, this time in the tokenizer itself
  rather than in regexes. The pattern only broke once round 6 ran a
  systematic 96-case fuzz sweep AFTER applying its own proposed patches and
  found zero new classes, converging the surface to exactly 2 documented
  residual holes (wrapper commands, brace groups) plus one newly-added one
  (case-pattern segments). Two meta-lessons worth carrying forward: (1) a
  security-relevant matcher built by iteratively patching one adversarial
  example at a time will keep finding new bugs in new dimensions
  indefinitely -- the fix is a structural rewrite (regex -> tokenizer) that
  eliminates a whole class at once, not another patch; (2) even a
  "structural rewrite" isn't immune to the same failure mode at a smaller
  scale (the flag set, the continuation-join, the separator set all needed
  their own iteration) -- what changed the trajectory was independent
  reviewers explicitly re-deriving numbers/sets from source (probing the
  git binary, re-measuring coverage from scratch) rather than trusting the
  previous round's fix, plus a final systematic fuzz sweep to get evidence
  of convergence rather than assuming "no new finding this round" means
  "done." Also: a peer reviewer, working autonomously during idle time
  between assigned tasks, found an identical bug class in a DIFFERENT
  already-shipped hook (enforce-scope.sh's segments_of(), missing the same
  newline-in-split-regex bug commit-gate.sh's round 3 had found and fixed)
  purely from having just internalized what to look for -- filed as F023
  rather than scope-creeping into fixing it. Every fix across all 6 rounds
  was mutation-tested (by me, and independently re-verified by the round-5
  and round-6 reviewers reverting the fixes themselves in separate scratch
  copies) before being trusted.

## Meta-Session 2026-07-26 (F023/enforce-scope.sh missing-separator fix)
- Scope accuracy: scope held (2 files: the template + tests), but the review
  cycle itself fanned out via a discovery chain rather than staying contained
  -- reviewing F023's fix surfaced F024 (a different pre-existing bug in the
  same function), F025 (the same root-cause bug in a DIFFERENT already-shipped
  hook, found during the reviewer's own idle time), and F026 (yet another
  pre-existing gap, exposed under 2 new spellings by F023's own fix). None of
  these were fixed here -- each was filed and left for its own session, which
  is the right call (matches F023's own origin as a discovery from F011's
  review), but four features from one two-file fix is worth noting as a
  pattern: fixing one hook's bug class tends to surface the same class
  elsewhere, and a reviewer given room to look (idle time, or "not a blocker
  but worth flagging") will find it.
- Model calibration: single-session; correction_cycles 3 (3 review rounds,
  each finding a genuine regression the PREVIOUS round's fix introduced --
  same pattern as F011's 6-round marathon, at smaller scale). Round 1's fix
  (add \n and & to the split) introduced a continuation-handling regression
  and a quoted-& false positive, both from copying commit-gate.sh's
  prerequisites incompletely. Round 2's fix for THAT (porting strip_quotes
  verbatim) introduced a CRITICAL regression of its own: this hook's write
  target is routinely quoted (unlike commit-gate's, where quotes only ever
  wrap non-target text), so erasing quoted spans erased the target itself,
  disabling enforcement for the ordinary case of writing a quoted path --
  worse than the bug F023 existed to fix. The fix for THAT (mask-then-slice,
  quoting content preserved through segmentation, unquoted only at
  extraction) held through round 3's final confirming pass.
- Discovery lineage: F024/F025/F026 all discovered_via F023, mirroring F023's
  own discovered_via F011. This is now a recurring shape across 3 features in
  a row (F011 -> F023 -> {F024, F025, F026}) -- worth watching whether the
  chain continues when F025 (same bug class, different hook) is eventually
  fixed; it likely will surface more of the same in whatever hook comes next
  with similar segmentation logic, if any.
- Approach patterns that worked: (1) verifying a reviewer's own claim against
  REAL bash execution, not just re-reading the diff or trusting the hook's
  verdict change -- this went both ways twice: I confirmed the reviewer's
  "quote-erasure disables enforcement" finding was real by literally running
  the redirect in bash and checking which file got created, AND separately
  disproved the reviewer's own "apostrophe-pairing hazard" finding the same
  way (the flagged command never actually writes to the "forbidden" path in
  real bash -- it's swallowed into a single-quoted literal). The reviewer
  independently ran the same real-bash check on their own finding afterward,
  confirmed my correction, and retracted it -- a case of a peer catching and
  fixing their OWN error once prompted to verify against ground truth rather
  than trust a hook's before/after verdict change. (2) Testing each ported
  fix's mutation INDEPENDENTLY (not just the combined revert) to confirm
  orthogonality -- e.g. reverting only join_continuations broke exactly the
  continuation tests and nothing else, reverting only strip_quotes/mask_quotes
  broke exactly the quoting tests -- this is stronger evidence than a single
  combined mutation test, since it rules out one fix silently doing the work
  of both. (3) When a peer reviewer's fix RECOMMENDATION turns out to be
  correct in direction but the reviewer's OWN prior claim about a related
  case is wrong, correct it explicitly and specifically rather than silently
  accepting or silently ignoring it -- this surfaced the reviewer's error
  fast (one message round-trip) instead of it lingering.
- Review value: very high, same conclusion as F011's retrospective a session
  ago -- for a security-relevant hook, treat the FIRST fix as a hypothesis,
  not a conclusion, and keep reviewing until a round produces a genuine
  fuzz/mutation NEGATIVE result (nothing new found) rather than stopping at
  the first "looks good." Round 3 here was exactly that: independent
  reconfirmation of everything, a corrected error, and only new findings that
  were explicitly out-of-scope follow-ups, not blockers.

## Meta-Session 2026-07-27 (F025/commit-gate.sh quoted-token bypass fix)
- Scope accuracy: scope held (2 files), but again fanned out via discovery
  during review, same shape as F023: F027 (a 3-part residual in the same
  function, has_staging_flag) and F028 (the analogous bug in the sibling
  hook, enforce-scope.sh, low severity/not exploitable today). Neither fixed
  here. The chain is now F011 -> F023 -> {F024, F025, F026} -> F025's own
  review -> {F027, F028} -- five features deep from one original bug class
  (quote-erasure deleting content load-bearing for a gate's decision).
- Model calibration: single-session; correction_cycles 1 (2 review rounds:
  round 1 found 2 regressions the fix itself introduced -- same "the fix for
  the last bug introduces a new one" pattern as F011/F023, this time one
  level DEEPER: F025's mask-then-slice fix was correct at the SEGMENT level
  (command_segments) but left tokenization inside a segment naive (seg.split()),
  which the OLD quote-deletion design had accidentally masked by deleting the
  very message text those pseudo-tokens came from. Round 2 confirmed the
  round-1 fix and found nothing new in the code itself, only a documentation
  error IN THE REVIEWER'S OWN FIRST-PASS FILING of one of the residuals (F027
  shape 3's polarity was backwards -- called a false-positive regression a
  "genuine improvement"). The reviewer caught and corrected their own error
  on a follow-up idle-time check against real git, unprompted, before I acted
  on the wrong framing.
- Discovery lineage: F027 and F028 both discovered_via F025. Same recurring
  shape noted in F023's retrospective a session ago.
- Approach patterns that worked: (1) When a fix touches a MULTI-LEVEL
  structure (segments, then tokens within a segment), verify EACH LEVEL
  independently for the same class of bug rather than assuming a fix at one
  level generalizes -- F025's round-1 regressions were exactly this: the
  segment-level mask-then-slice fix was right, but token-level splitting
  inside a segment needed the identical treatment one level down
  (split_tokens(), added in round 1's fix, mirrors command_segments()'s own
  mask-then-slice discipline). (2) Before filing ANY "improvement" or
  "regression" characterization of a behavior change, verify against the
  REAL tool (real git, real bash) what the command actually DOES, not just
  whether the hook's verdict changed -- both the F023 and F025 review cycles
  had exactly one reviewer self-correction each, and both corrections came
  from the SAME discipline: running the actual command and checking what got
  staged/committed/written, not inferring intent from a before/after verdict
  diff. (3) When told "no code change needed, just amend the ticket," treat
  that ticket amendment with the SAME rigor as a code fix: verify the
  reviewer's claim before writing it into features.json, since a bad
  characterization in a filed ticket actively misleads whoever picks it up
  next (exactly what happened here, and exactly why the follow-up correction
  mattered enough to send unprompted).
- Review value: consistent with F011/F023 -- for this class of hook (a
  security-relevant Bash-command scanner built on regex/token pattern
  matching, not a real shell parser), the first fix is a hypothesis. Two
  rounds was enough to converge here specifically because round 2 found
  nothing new IN THE CODE and only a documentation error, which is the same
  "negative result" signal that ended F011's and F023's longer cycles.

## Meta-Session 2026-07-28 (F024/enforce-scope.sh multi-target masking fix)
- Scope accuracy: scope held (2 files), but review again fanned out via
  discovery: F029 (a -- pathspec gap in the exact function being rewritten)
  and F030 (a pre-existing /dev/null and 2>&1 denial issue) both surfaced.
  Now 6 open features (F026-F030) tracing back to the F011/F023/F025 chain,
  all in the same 2-hook family (enforce-scope.sh, commit-gate.sh).
- Model calibration: single-session; correction_cycles 3 (4 review rounds,
  the longest single-PR cycle since F011's original 6, and the first one
  in this whole chain where every regression was found and fixed WITHIN
  one PR rather than spilling into a follow-up PR). Round 1 found the
  initial fix's sed script-detection heuristic broke on 3 real shapes
  (BSD `-i ''`, multi `-e`, long-form `--expression=`/`--file=`) plus a
  cross-extractor masking gap (a real write command with an unrelated
  trailing redirect only had the redirect checked). Round 2 found the
  round-1 fix for the redirect-stripping side left a stray file-descriptor
  digit behind, misread as a bogus write target. Round 3 found the round-2
  fix over-corrected: anchoring the ENTIRE match (not just the optional
  digit) to a token boundary broke plain `>` redirects with no digit at
  all when glued directly to an argument with no space. Round 4 found
  nothing new in the code -- only a test that couldn't actually
  discriminate a truncating regex from a correct one, since it used an
  all-in-scope target where both the correct and truncated names were
  still in scope.
- Discovery lineage: F029, F030 discovered_via F024, matching the by-now-
  established pattern (F011 -> F023 -> {F024,F025,F026} -> F025's own
  review -> {F027,F028} -> F024's own review -> {F029,F030}).
- Approach patterns that worked, consistent with the whole chain's lessons:
  (1) A reviewer's OWN suggested fix ("anchor the digit run") still needs
  independent verification of exactly what gets anchored -- the fix's
  DIRECTION was right but its SCOPE (whole match vs. just the digit group)
  was wrong, and only surfaced by testing the fix against cases the
  ORIGINAL bug report never covered (a bare, un-prefixed redirect glued to
  an argument with no space). (2) When a reviewer flags a test as
  "doesn't discriminate," the fix is to run the OLD (buggy) code against
  the test and confirm it now fails for the right reason -- round 4's own
  test-quality nit was verified by mutation-testing against the naive
  regex before accepting the reviewer's diagnosis. (3) Building a small,
  precise verification matrix (5-9 concrete before/after cases run through
  the actual function directly, not just through the hook end-to-end) was
  faster and more conclusive than reasoning about regex behavior
  abstractly -- used in every round of this cycle.
- Review value: this is now the THIRD feature in a row (F011, F023, F025,
  F024) where the terminating signal was the same: a review round that
  finds nothing new in the code, only in the test suite or documentation.
  Worth treating as a general heuristic for this class of hook (regex/
  token-pattern-based Bash-command scanners): don't stop at "looks right,"
  stop at "a dedicated adversarial round found nothing new to fix."

## Meta-Session 2026-07-31 (F055-F062: TeammateIdle coordination + LEAD_OWNED family; closes the F023-originated local-discovery chain)
- Scope accuracy: 6 of 8 features held their declared scope (with the usual
  small scope_expansions for stale sibling comments -- see Discovery
  lineage). Two did NOT: F059 and F061 were both filed as candidate CODE
  fixes and resolved to pure DOCUMENTATION instead once investigated --
  a scope-TYPE pivot, not just a scope expansion, and a pattern not seen
  in any earlier session of this arc. F059 (per-teammate early release)
  turned into a "Known limitation"-style lead judgment rule in
  rules/agent-teams-protocol.md once it became clear the underlying
  coordination gap needed a documented convention, not a mechanism. F061
  (lead/teammate hook-blindness) turned into documentation after fetching
  Claude Code's own hooks/agent-teams docs directly confirmed no
  hook-facing discriminator field exists today -- confirmed with Ovidiu via
  AskUserQuestion before shipping the redirected scope into the distributed
  plugin, since a pivot from "add a mechanism" to "document a limitation"
  changes what actually ships, not just which files change.
- Model calibration: single-session throughout (all 8 features sequential,
  well-scoped, no parallelism benefit); one Opus reviewer sub-agent spawned
  per PR via the Agent tool (the same fallback pattern as every prior
  session in this arc, not native Agent Teams). correction_cycles were
  unusually high on two features -- F056 (4 rounds) and F061 (4 rounds) --
  both worth flagging as a genuinely-needs-this-many-rounds class, not a
  process failure: F056's rounds 2-4 each corrected a DIFFERENT accuracy
  claim in the fix's own documentation/tests (a non-discriminating test
  suite, then a claimed-but-unlanded comment reflow, twice); F061's rounds
  2-4 were a self-referential chain where each round's own restated
  justification became the next round's finding (round 2 disproved my
  original claim by inspecting real ~/.claude/teams/*/config.json files on
  disk; round 3 caught that my OWN correction had swapped one false claim
  for another; round 4 caught that my OWN round-3 note ABOUT round 2's fix
  was itself inaccurate -- a claim-about-a-claim mismatch).
- Discovery lineage: F059 discovered_via F055 (found live during F055's own
  review: a reviewer's TeammateIdle hook re-fired 6 times after its review
  was delivered, with no path to release before team-wide Phase 5). F058
  discovered_via F054 (a false "harness.json is lead-owned" claim, caught
  and corrected in F054, filed here as the real fix). F060 discovered_via
  F058 (review-pr91-f058 found harness.json wasn't the only unprotected
  lead-only file). F061 AND F062 both discovered_via F060 -- a single
  review round surfacing two independent siblings at once, one a platform
  research question (F061) and one a mechanical follow-up needing a new
  matching primitive (F062, the first prefix-style LEAD_OWNED entry, since
  every prior entry was a fixed path and .harness/mld/ files are
  dated/session-named).
- Approach patterns that worked: (1) Ground-truthing a reviewer's finding
  BEFORE fixing it caught real bugs every single time it was tried this
  session (never once turned out to be a false alarm) -- most notably
  F062's finding that the actual new mechanism (a hand-written python
  prefix check) had zero discriminating test coverage, reproduced as a live
  false positive (an unrelated file wrongly denied) before writing the fix.
  (2) Mutation-testing a reviewer's OWN recommended fix, not just the
  original bug, closed F062 cleanly in one round after the finding. (3)
  Filing new features the moment a review round surfaces a genuine
  follow-up (F059, F061, F062 all originated this way), rather than
  folding an unrelated behavior change into the PR under review, kept
  every PR's diff reviewable in isolation -- the F054->F058->F060->
  {F061,F062} chain is now 4 features deep and each step was still a
  small, single-concern diff.
- Plan approval: not applicable this session -- no plan-approval-required
  teammates were spawned (all sub-agents were read-only reviewers).

## Meta-Session 2026-07-31 (F012/OVI-53: portable readiness-stamp signing)
- Scope accuracy: held the declared scope (schemas/readiness-stamp.md,
  skills/harness-issue-prep/SKILL.md, skills/harness-issue-debug/SKILL.md,
  test/run-tests.sh) exactly, plus one disclosed scope_expansion:
  INSTALL.md's kickstart_label example would have gone stale once Step 8
  was generalized, so it was updated in the same pass rather than left to
  rot (the class of mistake multiple F055-F062 reviews caught -- "sibling
  doc left stale after a fix" -- avoided proactively this time instead of
  caught in review).
- Spec grounding: the local features.json `description` field is a terse
  paraphrase, not the authoritative spec. Re-fetching OVI-53 via
  `get_issue` before finalizing caught that the actual spec text specifies
  a FLAT, presence-gated `prep.kick_command` -- the first implementation
  pass had nested it as `prep.runner.kick_command` with a leftover
  `enabled` flag (a plausible-looking but wrong reading of the terse local
  summary alone). Lesson for future Linear-sourced features: when a
  feature's local description is a summary rather than the full spec
  (signaled by a `notes` field like "Full spec re-verified per-issue"),
  re-fetch the actual issue before implementing config surface details,
  not just before the initial spec-verification pass.
- Model calibration: single-session, no sub-agents spawned for
  implementation (no team needed for a scope this size); this entry
  documents implementation only -- PR review (Opus reviewer round(s)) is
  covered separately once the PR is filed and reviewed.
- Discovery lineage: none -- F012 was a pre-existing Linear-tracked
  feature (OVI-53), not discovered mid-work.
- Approach patterns: (1) test-by-extraction (pulling the actual shipped
  python snippet out of the SKILL.md via regex, rather than hand-writing a
  parallel re-implementation in run-tests.sh) proved the real instructions
  work, not a derivation that could silently drift from them. (2)
  Mutation-testing the shipped snippet itself (reverting the 0600
  permission check, confirming exactly the 2 related assertions failed,
  restoring) proved the new tests discriminate rather than being
  vacuously true -- the same discipline applied to a spec's own shipped
  artifact, not just to a bugfix diff. (3) Ground-truthing a long-repeated
  "blocked" claim before acting on it (see Active Context correction
  above) prevented relaying stale state as if it were current.
- Plan approval: not applicable -- single-session implementation, no
  teammates spawned.

## Meta-Session 2026-08-01 (F013/OVI-63: mechanical stamp for /harness-init)
- Scope accuracy: the initial implementation held the declared scope exactly
  (scripts/stamp.sh, skills/harness-init/SKILL.md,
  skills/harness-init/templates/, test/run-tests.sh). Round 1 review then
  found this PR had left two dangling pointers (INSTALL.md,
  skills/harness-doctor/doctor.py) to the Step 3.6 inline block it deleted --
  fixed in the same PR, outside the declared scope list, and recorded as a
  scope_expansion on F013 rather than left silently untracked. Explicitly
  considered and declined one adjacent change -- wiring harness-doctor's
  --fix to delegate to stamp.sh in upgrade mode, which the spec's own
  Dependencies section notes as a future consequence, not an acceptance
  criterion; filed as F063 instead of folded in.
- Design decisions made without a full spec spelling them out, each
  recorded as an assumption in F013's own notes rather than silently
  picked: team_mode drives a real settings.json toggle
  (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS "0"/"1") rather than being a
  no-op key, chosen because harness-doctor's SETTINGS_WIRING_CHECKS
  requires the key to be non-null regardless of value, and because a
  real toggle is more useful than a decorative one; harness-init's own
  answers-file-writing instructions hardcode team_mode=teams (preserving
  the pre-existing always-on behavior) rather than asking a new question,
  since "Interview/UX changes to harness-init" was explicitly out of
  scope.
- A real bug caught only by writing the SKILL.md prose out and reading it
  top-to-bottom: the "confirm the build hook" step was drafted as its own
  numbered step placed AFTER the step whose action it needed to precede,
  directly contradicting this same file's "Follow these steps in order"
  rule at the top. Folding it into the start of the step it needed to
  precede, rather than renumbering every subsequent step to reorder
  them, kept the fix local -- INSTALL.md and harness-doctor's fixes.py
  both point at "Step 3.6" by number, so renumbering would have had a
  real blast radius outside this feature's declared scope for a purely
  cosmetic reason.
- Model calibration: single-session, no sub-agents spawned for
  implementation.
- Discovery lineage: none -- F013 was a pre-existing Linear-tracked
  feature (OVI-63), not discovered mid-work.
- Approach patterns: (1) every acceptance criterion was verified by
  direct hand-execution against real fixture directories BEFORE any test
  assertion was written for it (mode=new/upgrade collision behavior,
  harness-doctor run directly against a stamped project) -- the same
  ground-truth-first discipline applied to this feature's own shipped
  artifact, not just to a reviewer's finding. (2) Mutation-testing caught
  a real test-quality gap on the first attempt: the collision-abort
  mutation initially only failed 1 of 3 related assertions, revealing
  that 2 "does the abort message list this path" checks were only weakly
  discriminating (a path substring appearing anywhere in ANY output,
  including a non-abort success message, would satisfy them) -- fixed by
  adding an explicit "says aborted" check and an mtime-unchanged check,
  after which the same mutation correctly failed all 4 related
  assertions. (3) A pre-existing test broke as a direct, expected
  consequence of this feature's own change (removing inline settings
  JSON) -- fixed by redirecting it to the new template file rather than
  deleting it, preserving the original test's intent against its new
  home.
- Plan approval: not applicable -- single-session implementation, no
  teammates spawned.

## Meta-Session 2026-08-01 (F015/OVI-55: promotion ladder + ablation pass)
- Scope accuracy: held the declared scope exactly
  (skills/harness-continue/SKILL.md, rules/context-summary.md,
  test/run-tests.sh); zero scope_expansions.
- Design decisions made without the spec spelling them out, recorded as
  assumptions in F015's own notes: P3.1 (corroborated MLD entries) has
  not shipped in this repo -- the Promotion pass instructions treat it
  as optional input, skipped gracefully when the corroboration marker
  isn't present, matching the spec's own "consumes P3.1 entries when
  present" (not a hard dependency) framing rather than blocking on an
  undelivered sibling feature.
- AC3 (dry-run producing a classified pattern + ablation verdict) was
  satisfied as a PR-description transcript, not a committed file --
  .harness/HARNESS_BACKLOG.md is a per-project runtime artifact the
  skill creates when a real retrospective actually runs, not plugin
  distribution content, so it wasn't created in this repo's own
  .harness/ as part of implementing the capability itself.
- A self-caught cross-reference bug: a "run the abbreviated ladder per
  the existing minimum-retrospective rule below" pointer was wrong --
  that rule lives in Step 5a, well ABOVE Phase 5.5 in the same file, not
  below it. Caught by reading the new content back top-to-bottom before
  finishing, the same discipline that caught F013's step-ordering bug
  last session.
- Model calibration: single-session, no sub-agents spawned for
  implementation.
- Discovery lineage: none -- F015 was a pre-existing Linear-tracked
  feature (OVI-55), not discovered mid-work.
- Approach patterns: mutation-tested the AC7 "stated exactly once" guard
  (duplicated the cap phrase, confirmed the count-based check flips from
  pass to fail) -- the same discipline applied to a prose/documentation
  assertion, not just a code assertion, confirming it generalizes.
- Plan approval: not applicable -- single-session implementation, no
  teammates spawned.

## Meta-Session 2026-08-01 (F016/OVI-57: worker epoch record + requalification)
- Scope accuracy: held the declared scope exactly (schemas/feature.schema.json,
  skills/harness-continue/SKILL.md, docs/requalification.md,
  rules/agent-teams-protocol.md, templates/CLAUDE.md, test/run-tests.sh);
  zero scope_expansions.
- Design decision made without the spec spelling it out, recorded as an
  assumption in F016's own notes: the spec's "Schema file (P1.1) extended
  accordingly" assumed a schema owner that, on inspection, only ever
  covered the features.json envelope (F004/P1.1's declared scope), not
  harness.json. Rather than creating an out-of-scope new schema file for
  harness.json, added the worker block as a second, independently-
  documented $defs entry within the same declared-scope file, with its
  own description stating plainly it's unrelated to the features.json
  envelope above it.
- Forward references to not-yet-shipped sibling features (F021's
  orientation eval, F015's ablation-pass backlog) were written to
  degrade honestly ("if F021 hasn't landed yet, note that this step
  was skipped and move on") rather than assuming delivery order.
- Model calibration: single-session, no sub-agents spawned for
  implementation.
- Discovery lineage: none -- F016 was a pre-existing Linear-tracked
  feature (OVI-57), not discovered mid-work.
- Approach patterns: mutation-tested 3 of the new checks; one attempt
  initially produced a false "no failure" result from a shell-quoting
  bug in the mutation SCRIPT itself (nested double quotes inside a
  `python3 -c "..."` invocation), not the check under test -- caught by
  noticing the absence of expected output rather than assuming a clean
  mutation meant a weak check, then redone with a heredoc to get a
  trustworthy result. A reminder that a mutation test's own tooling
  needs the same skepticism as the code it's testing.
- Plan approval: not applicable -- single-session implementation, no
  teammates spawned.

## Meta-Session 2026-08-01 (F017/OVI-65: author-blind conformance tester)
- Scope accuracy: held the declared scope exactly (agents/conformance-tester.md,
  skills/harness-continue/SKILL.md, schemas/feature.schema.json,
  test/run-tests.sh); zero scope_expansions -- schemas/feature.schema.json
  was in scope but needed no edit (see below).
- Verified-before-assuming: checked git history for the evidence_type enum
  before touching schemas/feature.schema.json, and found F010/OVI-52 had
  already added "conformance" to both the qa_binding and proof.evidence_type
  enums proactively when it shipped. Confirmed AC3 was already satisfied
  rather than making a redundant edit to an already-correct schema (which
  could have introduced a real conflict, e.g. a duplicate enum entry, if
  done carelessly).
- Model calibration: single-session, no sub-agents spawned for
  implementation.
- Discovery lineage: none -- F017 was a pre-existing Linear-tracked
  feature (OVI-65), not discovered mid-work.
- Approach patterns: mutation-tested both new lint checks (the frontmatter
  tools-set check, the blindness-rule presence check) against targeted
  defects; both caught their mutation on the first attempt.
- Plan approval: not applicable -- single-session implementation, no
  teammates spawned.

## Meta-Session 2026-08-01 (F018/OVI-66: optional dual-engine review)
- Scope accuracy: held the declared scope exactly (rules/agent-teams-protocol.md,
  agents/reviewer.md, README.md, test/run-tests.sh); zero scope_expansions.
- Grounded a "verified live" annotation in genuine, minimal live verification
  rather than either fabricating it or skipping it: checked `codex --help` and
  `codex review --help` to confirm the exact pinned flag exists, and `codex
  doctor` to confirm auth/reachability -- but deliberately did NOT run a full
  `codex review` against a real diff, since that would spend Ovidiu's Codex
  subscription usage without an explicit go-ahead for that specific action.
  The annotation states precisely what was verified (command existence + auth)
  versus what wasn't (a completed review's actual output), rather than letting
  "verified live" imply more than it means.
- Model calibration: single-session, no sub-agents spawned for implementation.
- Discovery lineage: none -- F018 was a pre-existing Linear-tracked feature
  (OVI-66), not discovered mid-work.
- Approach patterns: mutation-tested the section-scoped synthesis-rules check
  by deleting one of the four rules; caught correctly on the first attempt.
- Plan approval: not applicable -- single-session implementation, no
  teammates spawned.

## Meta-Session 2026-08-01 (F019/OVI-58: AGENTS.md routing layer)
- Scope accuracy: the initial implementation held the declared scope (AGENTS.md,
  CLAUDE.md, skills/AGENTS.md, test/AGENTS.md) exactly. Round-trip review found one
  real regression: a pre-existing test checked CLAUDE.md for the workaround-
  retirement-condition rule, which this feature moved to AGENTS.md -- fixed by
  redirecting the test outside the declared scope list, recorded as a
  scope_expansion.
- Verified-before-committing: fetched Claude Code's own official documentation
  for the `@path` import mechanism before writing CLAUDE.md around it, rather than
  trusting the spec's own claim ("documented feature, used by vv since v2.1") or
  training-data recall alone. Found it's not just supported but the explicitly
  documented, first-party recommended pattern for exactly this AGENTS.md/CLAUDE.md
  coexistence use case -- a genuinely strong verification, not a guess dressed up
  as one.
- Honest partial verification, consistent with F018's precedent: AC4 (a fresh
  Codex/Cursor session surfaces AGENTS.md guidance) was not independently
  live-verified. Confirmed via web search that AGENTS.md is a real,
  OpenAI-originated, now-widely-adopted convention Codex reads natively, looked
  for a zero-cost check (a reported `--print-instructions` flag) and found it
  doesn't exist in the actually-installed CLI version, and declined to spend a
  real paid Codex invocation just to verify further. Left the actual manual
  check for Ovidiu's next real session, same discipline as F018's Codex
  verification boundary.
- Model calibration: single-session, no sub-agents spawned for implementation.
- Discovery lineage: none -- F019 was a pre-existing Linear-tracked feature
  (OVI-58), not discovered mid-work.
- Approach patterns: manually diffed both root files side by side to confirm
  zero duplicated sentences (AC1) before considering the split done, rather than
  relying only on the full-suite green run (which wouldn't have caught a
  duplicated sentence at all, since no automated check for that exists).
- Plan approval: not applicable -- single-session implementation, no teammates
  spawned.

## Meta-Session 2026-08-01 (F020/OVI-59: harness-improve skill)
- Scope accuracy: held the declared scope exactly (skills/harness-improve/SKILL.md,
  test/run-tests.sh). No expansion needed -- F019's earlier fix already made the
  skill-frontmatter name==directory lint self-maintaining (a glob, not a hardcoded
  tuple), so AC1's prefix requirement only needed a small standalone check, not a
  lint update.
- Style consistency check: before considering the new test section done, grepped
  the whole 8000+ line test/run-tests.sh for other uses of bash's `[[ ]]` and found
  none -- the file consistently uses POSIX `[ ]`/`case`. Rewrote the AC1 prefix
  check from `[[ ... == harness-* ]]` to a `case` statement to match, rather than
  leaving the one inconsistent construct in place.
- Mutation-testing: all 7 new assertions individually mutation-tested (a missing
  step heading, an emptied gap-class owner cell, a reworded guardrail sentence, the
  attribution line removed from BOTH its occurrences -- the first attempt only
  removed the closing one and the intro-paragraph occurrence still satisfied the
  check, a real near-miss caught by checking the FAIL output actually appeared --
  and the non-harness-project early-exit text removed). Each mutation produced
  exactly the expected single FAIL, restored from a scratch backup between rounds.
- Model calibration: single-session, no sub-agents spawned for implementation.
- Discovery lineage: none -- F020 was a pre-existing Linear-tracked feature
  (OVI-59), not discovered mid-work.
- Approach patterns: adapted harness-engineering's improve-harness.md playbook
  (CC BY 4.0) into the 7-step/gap-table/guardrail shape already established by
  F017/F018 for HE-derived features in this repo -- same attribution-line
  convention, same "adapted from, not copied" framing.
- Plan approval: not applicable -- single-session implementation, no teammates
  spawned.
