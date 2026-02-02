---
paths:
  - ".harness/**"
---

# Feature Scheduling Rules (Orchestrator)

When orchestrating parallel work on a harness project.

## Scheduling Algorithm

### 1. Read State

```bash
cat .harness/features.json
cat .context/modules.yaml
```

### 2. Build Availability Matrix

```
Feature | Modules Required | Locked? | Assignable?
--------|------------------|---------|------------
F001    | [auth, db]       | auth:Y  | BLOCKED
F002    | [payments]       | No      | YES
F003    | [api]            | No      | YES
```

### 3. Assign Non-Conflicting Work

Prioritize by:
1. Priority field (lower = higher)
2. Fewer dependencies (simpler = faster)
3. No overlap with assigned work

**Rule**: Never assign features sharing a module to different agents.

### 4. Track Assignments

```json
{
  "id": "F002",
  "assigned_to": "session-abc",
  "modules_claimed": ["payments"]
}
```

## Handling Blocked Agents

When agent reports "modules unavailable":
1. Check if blocking agent is active
2. If active: queue feature, assign different work
3. If stale (>2 hours): consider force-release
4. Never let agent wait idle

## Handling Stale Locks

Locks >24 hours with no progress:
1. Verify no active session
2. Force-release via context-graph skill
3. Log the action
4. Reassign blocked features

## Convergence Intervention

If agent reports repeated failures:
1. After 2: review feature definition
2. After 3: break into smaller pieces
3. After 4: escalate to Ovidiu

## Progress Report

At natural breakpoints:

```
## Harness Status Report

Progress: X/Y features passing (Z%)

Active:
- Agent A: F002 (payments)
- Agent B: F003 (api)

Blocked:
- F001: waiting on auth

Completed:
- F004: User profile endpoint

Issues:
- [Any concerns]
```
