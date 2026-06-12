# Context Summary

## Active Context
- Currently working on: F002 hook coverage reporting
- Blocking issues: none
- Next up: F003 status badges

## Domain: Hooks

### Decisions
- Hooks always exit 0: a broken hook must never block a session (2026-01-15)

### Gotchas
- features.json must stay valid JSON; the hooks parse it with python3

## Meta-Session 2026-01-15
- Scope accuracy: F001 scope held with no expansions
- Model calibration: sonnet sufficient for parser work
