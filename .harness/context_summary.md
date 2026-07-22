# Context Summary

Persistent record of architectural decisions, discovered patterns, gotchas, and active context.
This file is referenced in CLAUDE.md and loaded every session.

## Active Context
- Currently working on: project initialization (OVI-44 step 0, dogfood bootstrap)
- Next up: F001 / OVI-47 (P0.2 single-owner truth fixes) — first issue in the epic's execution order

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

### Patterns
- (none yet)

### Gotchas
- Baseline before any change: 66/66 assertions passing on main @ d3661ff (2026-07-22)

## Meta-Patterns
<!-- Coordination insights that apply across features — NOT domain-specific.
     Populated by the retrospective step at session end.
     These transfer to new projects: harness-init can import them as starting context. -->
- (none yet — first retrospective will populate this)
