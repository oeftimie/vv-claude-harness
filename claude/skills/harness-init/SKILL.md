---
name: harness-init
description: Initialize a new project with the Long-Running Agent Harness v3.2.1. Sets up feature tracking, git identity capture, context summary, build hooks, quality gate hooks, and optional Agent Teams structure. Use when starting a new multi-session project.
---

# Harness Initializer v3.2.1

Follow these steps in order. Do not skip steps. Ask the user when indicated.

## Step 1: Gather Requirements

Ask the user (if not already provided):
- What are you building? (brief description)
- What's the tech stack? (language, framework, build tool)
- Any existing code to preserve?

If the user provided this information in their initial message, proceed without asking.

## Step 2: Capture Git Identity

```bash
git config user.name
git config user.email
ssh -T git@github.com 2>&1 || true
cat ~/.ssh/config 2>/dev/null | head -30
```

Record the active identity. Ask the user to confirm:

```
I detected:
- Git user: [name] <[email]>
- SSH identity: [key file or host alias]

Is this correct for this project? If you use multiple GitHub accounts, tell me which one this project belongs to.
```

Store the confirmed identity in `.harness/harness.json`.

## Step 3: Create .harness/ Directory

Create `.harness/` with these files:

**`.harness/harness.json`**:

```json
{
  "project": "PROJECT_NAME",
  "stack": "DETECTED_OR_SPECIFIED_STACK",
  "created": "ISO_DATE",
  "version": "3.2.1",
  "git_identity": {
    "user_name": "DETECTED_NAME",
    "user_email": "DETECTED_EMAIL",
    "ssh_key": "KEY_FILE_OR_HOST_ALIAS",
    "ssh_host": "github.com OR ALIAS"
  },
  "team_structure": null
}
```

**`.harness/features.json`**:

```json
{
  "project": "PROJECT_NAME",
  "created": "ISO_DATE",
  "total_features": 0,
  "passing": 0,
  "features": []
}
```

Each feature has this shape:

```json
{
  "id": "F001",
  "description": "FEATURE_DESCRIPTION",
  "priority": 1,
  "status": "pending",
  "scope": ["src/feature/", "tests/feature/"],
  "depends_on": [],
  "assigned_to": null,
  "test_file": null,
  "coverage": null,
  "notes": null
}
```

**Status values** (exhaustive enum): `pending`, `in-progress`, `blocked`, `passing`, `failed`.

Feature is not done until:
- `status` is `"passing"`
- `test_file` points to a test
- `coverage` >= 95% on touched code

**`.harness/context_summary.md`**:

```markdown
# Context Summary

Persistent record of architectural decisions, discovered patterns, gotchas, and active context.
This file is referenced in CLAUDE.md and loaded every session.

## Active Context
- Currently working on: project initialization
- Next up: first feature implementation

## Cross-Cutting Concerns
- Stack: [stack]
- Architecture: [brief description]
- Key constraints: [any constraints mentioned by user]

## Domain: [Primary Domain]

### Decisions
- [Stack] chosen: [rationale] (ISO_DATE)

### Patterns
- (none yet)

### Gotchas
- (none yet)
```

**`.harness/claude-progress.txt`**:

```
# Claude Progress Log
# Project: PROJECT_NAME
# Created: ISO_DATE

## Session 1 - Initialization
- Created harness scaffolding
- Detected stack: [stack]
- Git identity: [user] <[email]>
- [List what you set up]
```

**`.harness/init.sh`**: Read the `init.sh.template` file in this skill's directory. Copy it into `.harness/init.sh`, configure for the detected stack, and make executable with `chmod +x`.

## Step 3.5: Configure Build Hooks

Based on the detected stack, offer to add a PostToolUse hook to the project's `.claude/settings.json`. This catches type errors immediately after edits.

Create `.claude/settings.json` (or merge into existing) with the appropriate hook:

**TypeScript/Node.js**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"ts\" ] || [ \"$ext\" = \"tsx\" ]; then npx tsc --noEmit 2>&1 | head -20; fi; fi"
          }
        ]
      }
    ]
  }
}
```

**Swift/iOS/macOS**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"swift\" ]; then swift build 2>&1 | tail -10; fi; fi"
          }
        ]
      }
    ]
  }
}
```

**Python**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"py\" ]; then python -m py_compile \"$FILE\" 2>&1; fi; fi"
          }
        ]
      }
    ]
  }
}
```

**Go**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"go\" ]; then go build ./... 2>&1 | tail -10; fi; fi"
          }
        ]
      }
    ]
  }
}
```

**Rust**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"rs\" ]; then cargo check 2>&1 | tail -10; fi; fi"
          }
        ]
      }
    ]
  }
}
```

Present the hook to the user and wait for confirmation before creating or modifying the file.

## Step 3.6: Configure Quality Gate Hooks

Set up Agent Teams quality enforcement hooks. Read the two `.sh.template` files in this skill's directory and install them:

1. Create `.claude/hooks/` directory: `mkdir -p .claude/hooks`
2. Copy `verify-task-quality.sh.template` to `.claude/hooks/verify-task-quality.sh`
3. Copy `check-remaining-tasks.sh.template` to `.claude/hooks/check-remaining-tasks.sh`
4. Make both executable: `chmod +x .claude/hooks/*.sh`
5. Add to `.claude/settings.json` (merge with the PostToolUse hooks from Step 3.5):

```json
{
  "hooks": {
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/verify-task-quality.sh"
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/check-remaining-tasks.sh"
          }
        ]
      }
    ]
  }
}
```

### Step 3.7: Verify Hooks

After installing hooks, verify they execute correctly:

```bash
echo '{}' | bash .claude/hooks/verify-task-quality.sh
echo "Exit code: $?"

echo '{}' | bash .claude/hooks/check-remaining-tasks.sh
echo "Exit code: $?"
```

Expected results:
- `verify-task-quality.sh`: exit 0 if tests pass, exit 2 if tests fail
- `check-remaining-tasks.sh`: exit 0 if no pending features, exit 2 if pending features exist

If either script fails to execute (permission denied, syntax error, missing dependency), fix the issue before proceeding. Silent hook failures mean quality gates don't enforce anything.

Tell the user:

```
I've set up two quality gate hooks:
- TaskCompleted: runs tests when a teammate marks work done. Rejects if tests fail.
- TeammateIdle: checks for remaining features when a teammate finishes. Auto-assigns next task.

Both hooks verified: [pass/fail status for each].

These enforce TDD mechanically instead of relying on instructions alone.
```

## Step 4: Update Project CLAUDE.md

If the project already has a CLAUDE.md, append the harness reference. If not, create one:

```markdown
# [PROJECT_NAME]

[Brief description from user]

## Tech Stack

[Stack details]

## Harness

This project uses the Long-Running Agent Harness v3.2.

- Feature tracking: `.harness/features.json`
- Context and decisions: `.harness/context_summary.md` (READ THIS at session start)
- Progress handoff: `.harness/claude-progress.txt`
- Build/test: `.harness/init.sh`
- Quality gates: `.claude/hooks/` (TaskCompleted, TeammateIdle)

## Git Identity

This project uses: [user_name] <[user_email]> with SSH key [ssh_key].
Always verify identity before push/pull/clone operations.
```

## Step 5: Propose Initial Features

Based on the project description, propose 3-5 initial features. Include scope for each:

```
Based on your description, here are the initial features I suggest:

F001: [Core feature 1] - Priority 1
  Scope: [directories]
  Depends on: (none)

F002: [Core feature 2] - Priority 2
  Scope: [directories]
  Depends on: (none)

F003: [Supporting feature] - Priority 3
  Scope: [directories]
  Depends on: F001

Should I add these to features.json?
```

Wait for confirmation, then populate `.harness/features.json` with full schema (including `scope` and `depends_on`).

## Step 6: Assess Team Structure

If the features have independent components, suggest a team structure:

```
Looking at the features, I think Agent Teams would work well here:

Teammate A (Sonnet): [scope] for F001
Teammate B (Sonnet): [scope] for F002
Reviewer (Opus): reviews both after completion

Or we can work through these one at a time in single-session mode.

Which approach do you prefer?
```

If the user chooses Agent Teams, store the team structure in `harness.json` under `team_structure`:

```json
{
  "team_structure": {
    "mode": "agent-teams",
    "teammates": [
      {
        "role": "ROLE_NAME",
        "scope": ["src/auth/", "tests/auth/"],
        "features": ["F001"],
        "model": "sonnet",
        "require_plan_approval": false
      }
    ]
  }
}
```

The team_structure is a starting suggestion. The lead may restructure during /harness-continue based on current project state.

## Step 7: Commit and Report

```bash
git add .harness/ .claude/ CLAUDE.md
git commit -m "chore: initialize harness v3.2.1 scaffolding"
```

Report:

```
Harness v3.2.1 initialized:
- .harness/ created with [N] features (scope and dependencies defined)
- Git identity captured: [user] <[email]>
- Build hook: [installed | skipped] for [STACK]
- Quality gates: TaskCompleted + TeammateIdle hooks installed and verified
- CLAUDE.md updated
- Team structure: [single-session | Agent Teams with N teammates]

Next: run /harness-continue to start working.
```
