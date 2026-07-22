# Context Summary

Persistent record of architectural decisions, discovered patterns, gotchas, and active context.
This file is referenced in CLAUDE.md and loaded every session.

## Active Context
- Currently working on: F001 / OVI-47 prepped (spec verified, normalized, written to features.json 2026-07-22)
- Next up: F001 implementation via /harness-continue (per-issue loop: TDD → tests green → PR + CI → review → merge)

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
- Custom stack targets: full_test = `bash test/run-tests.sh`; smoke_test = `bash -n hooks/*.sh` + `python3 -m json.tool` over both .claude-plugin/*.json manifests (2026-07-22, per OVI-44)
- Features F001–F021 mirror the 21 OVI-44 sub-issues; depends_on mirrors the epic's dependency graph; "independent after P0" encoded as depends_on the three P0 features (2026-07-22)
- Fixture harness.json version stays frozen at 4.0.0 with a "_note" key — bumping it to the live plugin version would recreate the copied-fact drift OVI-47 removes (2026-07-22)
- LICENSE: MIT, owner decision recorded in the OVI-47 assumptions ledger (2026-07-22)

### Patterns
- Tests must pin env vars the hooks read: run_session_start forces CLAUDE_PLUGIN_ROOT unset (env -u), run_session_start_with_root sets it — never inherit the test shell's env for hook behavior assertions (2026-07-22)

### Gotchas
- Baseline before any change: 66/66 assertions passing on main @ d3661ff (2026-07-22)
- README's v2.x date repeats live under the "## The evolution: v2.0 to v4.2" heading, not a section literally named "Evolution" as OVI-47 claimed (2026-07-22)

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
