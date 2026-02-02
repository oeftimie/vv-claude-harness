# Context Graph Skill

Manages module-level locking for parallel agent coordination.

## Commands

### claim

Claim modules before starting work.

```
Use context-graph skill: claim
Modules needed: [auth, database]
Feature: F003 - Add password reset
```

**Steps:**
1. Read `.context/modules.yaml`
2. Check each module's `locked_by`
3. If all available: set locks, increment version, commit
4. If any locked: STOP, report which are unavailable

**Success:** "Claimed modules: [auth, database]. Version: abc→def"

**Failure:** "Cannot claim. auth locked by session-xyz for F002."

---

### release

Release modules when done.

```
Use context-graph skill: release
```

**Steps:**
1. Read `.context/modules.yaml`
2. Clear `locked_by`, `locked_at`, `locked_for` for your modules
3. Increment version, commit

**Response:** "Released modules: [auth, database]. Version: def→ghi"

---

### status

Check current lock state.

```
Use context-graph skill: status
```

**Response:**
```
Module Status (version: def456)

| Module   | Status | Locked By   | For                | Since     |
|----------|--------|-------------|--------------------|-----------|
| auth     | LOCKED | session-xyz | F002 - OAuth       | 5 min ago |
| payments | FREE   | -           | -                  | -         |

⚠️ No stale locks detected.
```

---

### which

Find which module a file belongs to.

```
Use context-graph skill: which
File: src/handlers/auth/login.ts
```

**Response:** "File belongs to module: auth"

---

### force-release

Force release a stale lock.

```
Use context-graph skill: force-release
Module: auth
Reason: Previous session terminated
```

Only use after verifying session is abandoned (>24h or confirmed dead).

---

## modules.yaml Format

```yaml
version: "abc123"
updated_at: "2025-02-01T10:25:00Z"

strategy: explicit

modules:
  auth:
    description: "Authentication"
    paths:
      - src/auth/
      - src/handlers/auth/
    locked_by: null
    locked_at: null
    locked_for: null
```

## Rules

1. Always claim before modifying module code
2. Always release at session end
3. Never modify unclaimed modules
4. Report locked modules to orchestrator
5. Check status if unsure
