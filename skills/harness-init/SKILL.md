---
name: harness-init
description: Initialize a new project with the Long-Running Agent Harness (vv-harness plugin). Sets up feature tracking, git identity capture, context summary, build hooks, quality gate hooks, and optional Agent Teams structure. Use when starting a new multi-session project.
---

# Harness Initializer

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
  "harness": "vv-harness",
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

Each feature's shape (the 16 fields, which are required vs. optional, the status enum) is
defined once in `${CLAUDE_PLUGIN_ROOT}/schemas/feature.schema.json` and illustrated with the
one worked example in the Feature Schema section of
`${CLAUDE_PLUGIN_ROOT}/rules/agent-teams-protocol.md`. `scripts/validate-features.py`
enforces it in the test suite.

Feature is not done until:
- `status` is `"passing"`
- `test_file` points to a test
- `coverage` >= 95% on touched code

A feature may also carry a `spec` verification object; see the Feature Schema section of the Agent Teams protocol.

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

## Meta-Patterns
<!-- Coordination insights that apply across features — NOT domain-specific.
     Populated by the retrospective step at session end.
     These transfer to new projects: harness-init can import them as starting context. -->
- (none yet — first retrospective will populate this)
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

The script accepts one optional argument: `smoke_test` or `full_test` (default: `full_test`).
- `smoke_test` — compile/syntax check only, completes in <15s. Used by the `TaskCompleted` hook as a fast first-pass gate.
- `full_test` — complete test suite with coverage. Used by the lead at session end and synthesis phase.

When configuring for the project's stack, ensure both targets work correctly.

## Step 3.5: Configure Build Hooks

Based on the detected stack, offer to add a PostToolUse hook to the project's `.claude/settings.json`. This catches type errors after edits without blocking the agent (hooks run async).

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
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"ts\" ] || [ \"$ext\" = \"tsx\" ]; then npx tsc --noEmit 2>&1 | head -20; fi; fi",
            "async": true
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
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"swift\" ]; then swift build 2>&1 | tail -10; fi; fi",
            "async": true
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
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"py\" ]; then python -m py_compile \"$FILE\" 2>&1; fi; fi",
            "async": true
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
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"go\" ]; then go build ./... 2>&1 | tail -10; fi; fi",
            "async": true
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
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then ext=\"${FILE##*.}\"; if [ \"$ext\" = \"rs\" ]; then cargo check 2>&1 | tail -10; fi; fi",
            "async": true
          }
        ]
      }
    ]
  }
}
```

Present the hook to the user and wait for confirmation before creating or modifying the file.

## Step 3.6: Configure Quality Gate Hooks

Set up Agent Teams quality enforcement hooks. Read the `.sh.template` files in this skill's directory and install them:

1. Create `.claude/hooks/` directory: `mkdir -p .claude/hooks`
2. Copy `harness_state.py.template` to `.claude/hooks/harness_state.py` — the shared,
   stdlib-only `features.json` read/write module that `verify-task-quality.sh` and
   `check-remaining-tasks.sh` consume (schema in
   `${CLAUDE_PLUGIN_ROOT}/schemas/feature.schema.json`).
3. Copy `verify-task-quality.sh.template` to `.claude/hooks/verify-task-quality.sh`
4. Copy `check-remaining-tasks.sh.template` to `.claude/hooks/check-remaining-tasks.sh`
5. Copy `enforce-scope.sh.template` to `.claude/hooks/enforce-scope.sh`
6. Copy `verify-git-identity.sh.template` to `.claude/hooks/verify-git-identity.sh`
7. Copy the plugin's status line script into the project:
   `cp "${CLAUDE_PLUGIN_ROOT}/hooks/statusline.sh" .claude/hooks/statusline.sh`
   — the plugin cache path changes on every plugin update, so the project keeps its own copy.
8. Make all executable: `chmod +x .claude/hooks/*.sh .claude/hooks/harness_state.py`
9. Append `.harness/SESSION_INCOMPLETE` to the project's `.gitignore` (create it if missing).
   It is transient session state written by the plugin's SessionEnd hook.
10. Add to `.claude/settings.json` (merge with the PostToolUse hooks from Step 3.5):

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/statusline.sh"
  },
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "Bash(bash .harness/init.sh*)",
      "Bash(\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/*.sh*)",
      "Bash(git config user.name)",
      "Bash(git config user.email)",
      "Bash(git rev-parse*)",
      "Bash(git log*)",
      "Bash(git status*)",
      "Read(./.harness/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/enforce-scope.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/verify-git-identity.sh"
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/verify-task-quality.sh"
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-remaining-tasks.sh"
          }
        ]
      }
    ]
  }
}
```

Do NOT wire a per-project PostCompact hook. The plugin's SessionStart hook (which fires
with a `compact` source after compaction) already injects post-compaction recovery
directly into the model's context, so a separate PostCompact hook would be redundant.

### Step 3.7: Verify Hooks

After installing hooks, verify they execute correctly:

```bash
echo '{}' | "$CLAUDE_PROJECT_DIR"/.claude/hooks/verify-task-quality.sh
echo "Exit code: $?"

echo '{}' | "$CLAUDE_PROJECT_DIR"/.claude/hooks/check-remaining-tasks.sh
echo "Exit code: $?"
```

Expected results:
- `verify-task-quality.sh`: exit 0 if tests pass, exit 2 if tests fail
- `check-remaining-tasks.sh`: exit 0 if no pending features, exit 2 if pending features exist

If either script fails to execute (permission denied, syntax error, missing dependency), fix the issue before proceeding. Silent hook failures mean quality gates don't enforce anything.

Tell the user:

```
I've set up four hooks plus a status line:
- PreToolUse (scope): blocks edits to files outside the teammate's assigned scope. Only active when .claude/teammate-scope.txt exists.
- PreToolUse (git identity): blocks git push/pull/clone if identity doesn't match .harness/harness.json.
- TaskCompleted: runs tests when a teammate marks work done. Rejects if tests fail.
- TeammateIdle: checks for remaining features when a teammate finishes. Prompts teammate to pick up next task.
- Status line: live feature progress (N/M passing, in-progress IDs, incomplete-session flag).

Session orientation and post-compaction recovery are injected by the vv-harness
plugin's SessionStart hook; no per-project PostCompact hook is needed.

Quality gate hooks verified: [pass/fail status for each].

These enforce TDD and context recovery mechanically instead of relying on instructions alone.
```

## Step 4: Update Project CLAUDE.md

If the project already has a CLAUDE.md, append the harness reference. If not, create one:

```markdown
# [PROJECT_NAME]

[Brief description from user]

## Tech Stack

[Stack details]

## Harness

This project uses the Long-Running Agent Harness (vv-harness plugin).

- Feature tracking: `.harness/features.json`
- Context and decisions: `.harness/context_summary.md` (READ THIS at session start)
- Progress handoff: `.harness/claude-progress.txt`
- Build/test: `.harness/init.sh`
- Quality gates: `.claude/hooks/` (TaskCompleted, TeammateIdle, scope, git identity)

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

Wait for confirmation of the feature list. Then, BEFORE writing anything to
`.harness/features.json`, run the spec gate (Step 5.1).

### Step 5.1: Verify the proposal (spec gate)

Spawn the spec-verification agent as a read-only subagent over the ENTIRE confirmed
proposal in one call:

```
Agent({
  description: "Spec-verify proposed features",
  subagent_type: "vv-harness:spec-verification",
  model: "opus",
  prompt: "[the full proposal: every feature's id, description, scope, depends_on,
            plus the user's project description. Ask for a per-feature verdict line
            in the report.]"
})
```

Route on the report's VERDICT:
- **PASS**: write `features.json`. For each feature, populate `spec` with
  `{"hash": sha256(description), "verdict": "PASS", "sv_version": "1.0",
  "verified_at": ISO8601-UTC, "source": "conversation"}` (canonical hash recipe:
  `${CLAUDE_PLUGIN_ROOT}/schemas/readiness-stamp.md`).
- **ASK**: relay the numbered OPEN QUESTIONS to the user verbatim; iterate the feature
  descriptions with their answers; re-run the gate on the amended proposal. Do not
  write `features.json` until the gate passes.
- **BLOCK**: present the grounds; the user amends or drops the contradicted features;
  re-run.

If the user explicitly waives the gate ("skip verification"), write the features with
`"spec": null` and note the waiver in `claude-progress.txt`. Never fill `spec` for a
feature the gate did not pass.

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
git add .harness/ .claude/ CLAUDE.md .gitignore
git commit -m "chore: initialize vv-harness scaffolding"
```

Report:

```
Harness (vv-harness plugin) initialized:
- .harness/ created with [N] features (scope, dependencies, spec gate: [passed | waived])
- Git identity captured: [user] <[email]>
- Build hook: [installed | skipped] for [STACK]
- Quality gates: TaskCompleted + TeammateIdle hooks installed and verified
- CLAUDE.md updated
- Team structure: [single-session | Agent Teams with N teammates]

Next: run /harness-continue to start working.
```
