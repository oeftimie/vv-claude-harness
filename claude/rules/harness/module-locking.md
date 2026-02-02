---
paths:
  - ".context/**"
---

# Module Locking Rules

One agent per module at a time. Locks prevent parallel conflicts.

## Lock State

```yaml
# .context/modules.yaml
modules:
  auth:
    locked_by: "session-xyz"    # or null if available
    locked_at: "2025-02-01..."
    locked_for: "F003: Rate limiting"
```

## Claiming Modules

Before modifying code in any module:

```
Use context-graph skill: claim
Modules needed: [auth, database]
Feature: F003 - Add rate limiting
```

If claim fails (modules locked):
- STOP
- Report which modules are unavailable
- Wait for orchestrator guidance

## Releasing Modules

At session end, ALWAYS release:

```
Use context-graph skill: release
```

This clears your locks so other agents can proceed.

## Checking Status

```
Use context-graph skill: status
```

Shows all modules and their lock state.

## Stale Locks

Locks older than 24 hours with no activity may be stale. To force-release:

```
Use context-graph skill: force-release
Module: auth
Reason: Previous session terminated
```

Only use force-release after verifying the session is truly abandoned.

## Rules

1. **Always claim before modifying** code in a module
2. **Always release at session end** even if work is incomplete
3. **Never modify unclaimed modules** even for "small fixes"
4. **Report locked modules** to orchestrator immediately
5. **Check status** if unsure about current state
