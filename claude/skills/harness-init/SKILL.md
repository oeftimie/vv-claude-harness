---
name: harness-init
description: Initialize a new project with the Long-Running Agent Harness v3.7.0. Sets up feature tracking, git identity capture, context summary, build hooks, quality gate hooks, optional OpenSpec spec traceability, and optional Agent Teams structure. Use when starting a new multi-session project.
---

# Harness Initializer v3.7.0

Follow these steps in order. Do not skip steps. Ask the user when indicated.

## Step 1: Gather Requirements

Ask the user (if not already provided):
- What are you building? (brief description)
- What's the tech stack? (language, framework, build tool)
- Any existing code to preserve?

If the user provided this information in their initial message, proceed without asking.

## Step 1.5: Offer OpenSpec Spec Traceability

Ask the user whether to enable OpenSpec integration for this project:

```
Optional: enable OpenSpec spec traceability for this project?

OpenSpec is a lightweight spec-driven framework that pairs with the harness.
When enabled:
- Each feature points at an authoritative spec via the spec_path field.
- Agents read the spec before writing code (instead of inventing intent
  from a one-line description).
- Specs are checked into git as living documentation.
- The harness invokes OpenSpec via the .harness/openspec.sh shim — when
  OpenSpec changes, only the shim updates.

Recommended for: projects spanning >2 weeks, multi-developer projects, projects
where intent fidelity matters (security, compliance, public APIs).
Skip for: throwaway prototypes, single-session work, formatting-only repos.

If you enable it, you'll also need OpenSpec installed (`npm i -g @openspec/cli`
or per OpenSpec's current install instructions) and run `openspec init` in the
project. The harness will not run those for you.

Enable OpenSpec? (yes/no — default: no)
```

Record the answer. The rest of this skill branches on this choice:
- If `yes`: include the `openspec` block in `harness.json` (Step 3), create the
  `.harness/openspec.sh` shim (Step 3.1), default new features to
  `spec_required: true`.
- If `no`: omit the `openspec` block, skip Step 3.1 entirely, default new
  features to `spec_required: false` (which makes the field a no-op).

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
  "version": "3.7.0",
  "git_identity": {
    "user_name": "DETECTED_NAME",
    "user_email": "DETECTED_EMAIL",
    "ssh_key": "KEY_FILE_OR_HOST_ALIAS",
    "ssh_host": "github.com OR ALIAS"
  },
  "team_structure": null
}
```

If the user said yes to OpenSpec in Step 1.5, also include an `openspec` block:

```json
{
  "openspec": {
    "enabled": true,
    "cli_required": true,
    "specs_dir": "openspec/specs",
    "changes_dir": "openspec/changes",
    "config_synced_at": null
  }
}
```

**Field ownership:**
- `enabled` and `cli_required` are user-chosen settings (recorded once at init).
- `specs_dir`, `changes_dir`, and `config_synced_at` are **not hand-edited**. They are populated and refreshed by `.harness/openspec.sh sync-config` (created in Step 3.1). The values shown above are placeholder defaults; the shim overwrites them with OpenSpec's actual configured paths on first sync.
- `cli_required: true` means `harness-continue` Phase 0 fails loudly if `openspec` is not on PATH. Set to `false` for file-only workflows.

If the user said no, omit the `openspec` block entirely. All spec-related logic in `harness-continue` no-ops when this block is missing or `enabled: false`.

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
  "notes": null,
  "correction_cycles": 0,
  "scope_expansions": [],
  "approaches_tried": [],
  "failure_reason": null,
  "discovered_via": null,
  "spec_path": null,
  "spec_required": true
}
```

**Status values** (exhaustive enum): `pending`, `in-progress`, `blocked`, `passing`, `failed`.

**Operational metrics** (updated automatically or by the lead — used in retrospectives and for dynamic model selection):
- `correction_cycles`: incremented by the `verify-task-quality.sh` hook each time a TaskCompleted is rejected. High values signal the feature was harder than expected.
- `scope_expansions`: array of file/directory strings added to scope after initial assignment. Frequent expansions mean the initial scope was too narrow.
- `approaches_tried`: brief notes on approaches attempted before the passing implementation. Populated by the teammate in the task-complete message to lead.
- `failure_reason`: why the feature reached `status: "failed"`. Essential for understanding root cause without re-reading conversation history.
- `discovered_via`: ID of the feature whose implementation revealed the need for this feature (discovery lineage). Different from `depends_on`, which is a technical dependency.

**OpenSpec linkage fields** (only meaningful when `harness.json` has `openspec.enabled: true`):
- `spec_path`: path to the spec materials for this feature. During drafting/implementation it points at the change folder under OpenSpec's `changes_dir`. After PR-merge archive (v3.8.0+), it points at the archived capability spec under OpenSpec's `specs_dir`. The path structure follows OpenSpec's conventions — the harness does not define it. `null` until a spec is drafted.
- `spec_required`: whether implementation may proceed without a spec. Default `true` when OpenSpec is enabled. Set to `false` per-feature for trivial work (dep bumps, formatting, tiny refactors). Setting to `false` must be a deliberate edit.

Feature is not done until:
- `status` is `"passing"`
- `test_file` points to a test
- `coverage` >= 95% on touched code
- If OpenSpec is enabled and `spec_required` is `true`: `spec_path` is set

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

## Step 3.1: Create OpenSpec Shim (only if openspec.enabled)

Skip this step if the user said no to OpenSpec in Step 1.5.

`.harness/openspec.sh` is the single integration boundary between the harness and OpenSpec. All OpenSpec invocations from harness code go through it. When OpenSpec ships a breaking change, only this file changes — harness logic, prompts, and hooks are unaffected.

Create `.harness/openspec.sh` with the following content, then `chmod +x` it:

```bash
#!/usr/bin/env bash
# .harness/openspec.sh — integration boundary between the harness and OpenSpec.
# All OpenSpec invocations from harness code go through this script.
# When OpenSpec ships a breaking change, only this file changes.
#
# Verbs (v3.7.0):
#   sync-config    Query OpenSpec for its configured paths; write them
#                  into harness.json's openspec block. Idempotent.
#
# Future verbs (added in v3.8.0+):
#   archive <name>   Delegate to OpenSpec's archive flow.
#   validate <name>  Delegate to OpenSpec's validator.
#   verify <name>    Delegate to OpenSpec's /opsx:verify equivalent.

set -euo pipefail

HARNESS_JSON=".harness/harness.json"

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "openspec.sh: jq is required but not installed" >&2
    exit 1
  }
}

require_openspec_cli() {
  if command -v openspec >/dev/null 2>&1; then
    return 0
  fi
  local cli_required
  cli_required=$(jq -r '.openspec.cli_required // true' "$HARNESS_JSON" 2>/dev/null || echo "true")
  if [ "$cli_required" = "true" ]; then
    echo "openspec.sh: 'openspec' CLI not on PATH (cli_required: true)" >&2
    echo "Install OpenSpec or set openspec.cli_required to false in harness.json." >&2
    exit 1
  fi
}

cmd_sync_config() {
  require_jq
  require_openspec_cli

  # Resolve specs_dir and changes_dir.
  # OpenSpec's current default layout uses openspec/specs and openspec/changes.
  # If OpenSpec exposes a config-show command in a future release, replace
  # this block with a parse of that output. For now we detect by directory
  # existence and fall back to defaults.
  local specs_dir="openspec/specs"
  local changes_dir="openspec/changes"

  [ -d "openspec/specs" ] && specs_dir="openspec/specs"
  [ -d "openspec/changes" ] && changes_dir="openspec/changes"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local tmp="${HARNESS_JSON}.tmp"
  jq --arg specs "$specs_dir" \
     --arg changes "$changes_dir" \
     --arg now "$now" \
     '.openspec.specs_dir = $specs |
      .openspec.changes_dir = $changes |
      .openspec.config_synced_at = $now' \
     "$HARNESS_JSON" > "$tmp"
  mv "$tmp" "$HARNESS_JSON"

  echo "openspec.sh: synced — specs_dir=$specs_dir, changes_dir=$changes_dir"
}

case "${1:-}" in
  sync-config)
    cmd_sync_config
    ;;
  validate|verify|archive)
    echo "openspec.sh: verb '$1' not yet implemented (added in v3.8.0+)" >&2
    exit 64
    ;;
  *)
    echo "Usage: .harness/openspec.sh <verb> [args]" >&2
    echo "Verbs (v3.7.0): sync-config" >&2
    echo "Future verbs: validate, verify, archive (v3.8.0+)" >&2
    exit 64
    ;;
esac
```

After creating the file:

```bash
chmod +x .harness/openspec.sh
```

Then run `sync-config` once to populate the placeholder values in `harness.json`:

```bash
.harness/openspec.sh sync-config
```

Verify the result: `jq '.openspec' .harness/harness.json` should show real `specs_dir` and `changes_dir` values plus a `config_synced_at` timestamp.

If the user has not yet run `openspec init` in this project (the openspec/ directory doesn't exist), the shim will fall back to default paths. That's fine — the values get refreshed automatically on the next `harness-continue` Phase 0 once OpenSpec is initialized.

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

Set up Agent Teams quality enforcement hooks. Read the two `.sh.template` files in this skill's directory and install them:

1. Create `.claude/hooks/` directory: `mkdir -p .claude/hooks`
2. Copy `verify-task-quality.sh.template` to `.claude/hooks/verify-task-quality.sh`
3. Copy `check-remaining-tasks.sh.template` to `.claude/hooks/check-remaining-tasks.sh`
4. Copy `enforce-scope.sh.template` to `.claude/hooks/enforce-scope.sh`
5. Copy `verify-git-identity.sh.template` to `.claude/hooks/verify-git-identity.sh`
6. Make all executable: `chmod +x .claude/hooks/*.sh`
7. Add to `.claude/settings.json` (merge with the PostToolUse hooks from Step 3.5):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/enforce-scope.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/verify-git-identity.sh"
          }
        ]
      }
    ],
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
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Context was just compacted. Immediately re-read .harness/context_summary.md and run TaskList to recover your current state before continuing work. If this is the third or more compaction in rapid succession and you are losing context each time, STOP: write your current progress and known state to .harness/context_summary.md, message the lead with SendMessage({ type: 'message', recipient: 'team-lead', content: 'Context collapse: repeated compaction losing state. Current feature [ID] progress saved to context_summary.md. Need intervention.' }), then wait for instructions."
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
I've set up five hooks:
- PreToolUse (scope): blocks edits to files outside the teammate's assigned scope. Only active when .claude/teammate-scope.txt exists.
- PreToolUse (git identity): blocks git push/pull/clone if identity doesn't match .harness/harness.json.
- TaskCompleted: runs tests when a teammate marks work done. Rejects if tests fail.
- TeammateIdle: checks for remaining features when a teammate finishes. Prompts teammate to pick up next task.
- PostCompact: reminds the agent to re-read context_summary.md and task list after compaction.

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

This project uses the Long-Running Agent Harness v3.7.0.

- Feature tracking: `.harness/features.json`
- Context and decisions: `.harness/context_summary.md` (READ THIS at session start)
- Progress handoff: `.harness/claude-progress.txt`
- Build/test: `.harness/init.sh`
- Quality gates: `.claude/hooks/` (TaskCompleted, TeammateIdle, PostCompact)
- OpenSpec shim: `.harness/openspec.sh` (only if openspec.enabled in harness.json)

## Git Identity

This project uses: [user_name] <[user_email]> with SSH key [ssh_key].
Always verify identity before push/pull/clone operations.
```

If OpenSpec was enabled in Step 1.5, also append a `## Spec Discipline` section pointing at the global rule:

```markdown
## Spec Discipline

This project uses OpenSpec for spec traceability. Every feature with
`spec_required: true` must have a `spec_path` set before implementation
begins. Read the spec materials at `spec_path` before writing any code on
that feature. See the global `## Spec Discipline` section in
`~/.claude/CLAUDE.md` for the full protocol.
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
git commit -m "chore: initialize harness v3.7.0 scaffolding"
```

Report:

```
Harness v3.7.0 initialized:
- .harness/ created with [N] features (scope and dependencies defined)
- Git identity captured: [user] <[email]>
- OpenSpec: [enabled (shim created, sync-config run) | disabled]
- Build hook: [installed | skipped] for [STACK]
- Quality gates: TaskCompleted + TeammateIdle hooks installed and verified
- CLAUDE.md updated
- Team structure: [single-session | Agent Teams with N teammates]

Next: run /harness-continue to start working.
```
