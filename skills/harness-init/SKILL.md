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

Never hand-transcribe the framework-fixed files below into a project -- run
`${CLAUDE_PLUGIN_ROOT}/scripts/stamp.sh`, which emits every one of them deterministically
from an answers file. Adapted from Setlist's two-phase bootstrap doctrine (Alex Ciortan,
CC BY 4.0): "Never hand-write what a stamp can emit; never stamp what a decision shapes."

**First, confirm the build hook.** If the detected stack is one of `typescript`,
`swift`, `python`, `go`, or `rust`, show the user the exact PostToolUse hook the stamp
is about to wire in (the content of `skills/harness-init/templates/posttooluse-<stack>.json`
-- it catches type/build errors after edits without blocking the agent, since hooks run
async) and wait for confirmation before continuing. Any other stack: say plainly that no
PostToolUse hook is available for it, and proceed.

Write the answers file:

```bash
mkdir -p /tmp/vv-harness-stamp
cat > /tmp/vv-harness-stamp/answers.txt <<EOF
project_name=PROJECT_NAME
stack=DETECTED_OR_SPECIFIED_STACK
team_mode=teams
mode=new
EOF
```

`team_mode=teams` unconditionally enables the experimental Agent Teams env flag for every
new project (matches this skill's existing behavior; Step 6 still decides per-project
whether `team_structure` is actually populated -- this key does not add a new question).
`mode=new` is correct here; `mode=upgrade` exists in `stamp.sh` for re-stamping an
existing project and is not used by this skill.

Run the stamp from the project root:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/stamp.sh" /tmp/vv-harness-stamp/answers.txt .
```

If it aborts (mode=new found an existing file), stop and show the user exactly what it
reported; do not work around the abort by deleting their files.

On success this writes, byte-verbatim or rendered from a template in
`skills/harness-init/templates/` -- never hand-transcribed:
- `.claude/settings.json`: statusLine, env, permissions, and the full hook wiring
  (PreToolUse scope/git-identity/commit-gate, TaskCompleted, TeammateIdle), plus the
  stack-appropriate PostToolUse build-check block selected from
  `templates/posttooluse-<stack>.json` when `stack` is `typescript`, `swift`, `python`,
  `go`, or `rust`; any other stack gets no PostToolUse hook.
- `.claude/hooks/{verify-task-quality.sh, check-remaining-tasks.sh, enforce-scope.sh,
  verify-git-identity.sh, commit-gate.sh, harness_state.py, statusline.sh}`, all
  executable. `harness_state.py` is the shared, stdlib-only `features.json` read/write
  module that `verify-task-quality.sh` and `check-remaining-tasks.sh` consume (schema in
  `${CLAUDE_PLUGIN_ROOT}/schemas/feature.schema.json`). `commit-gate.sh` is a PreToolUse
  Bash hook that fires only on `git commit`, denying compound stage-and-commit forms and
  staged secret-shaped content (see the template's own header for the full check list).
- `.harness/harness.json` and `.harness/features.json` skeletons with `project`/`stack`/
  `created` filled in; `git_identity` and `team_structure` are left `null` here (this
  step and Step 6, respectively, are the decisions that fill them).
- `.gitignore` gains `.harness/SESSION_INCOMPLETE`, appended idempotently.

Then finish the pieces the stamp deliberately leaves to a decision:

**1. Fill in `git_identity`** with the identity confirmed in Step 2:

```bash
python3 - <<'PYEOF'
import json

with open(".harness/harness.json") as f:
    data = json.load(f)
data["git_identity"] = {
    "user_name": "DETECTED_NAME",
    "user_email": "DETECTED_EMAIL",
    "ssh_key": "<key file or host alias>",
    "ssh_host": "github.com OR ALIAS",
}
with open(".harness/harness.json", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
```

Each feature's shape (the 16 fields, which are required vs. optional, the status enum) is
defined once in `${CLAUDE_PLUGIN_ROOT}/schemas/feature.schema.json` and illustrated with the
one worked example in the Feature Schema section of
`${CLAUDE_PLUGIN_ROOT}/rules/agent-teams-protocol.md`. `scripts/validate-features.py`
enforces it in the test suite.

The done-definition (passing / done / shipped) and the optional claim-matched-proof
fields (`qa_binding`, `proof`, `coverage_target`, `delivered`, `design_contract`) are
defined once, in the Feature Schema section of
`${CLAUDE_PLUGIN_ROOT}/rules/agent-teams-protocol.md` — see that section rather than
this one for the current definition.

A feature may also carry a `spec` verification object; see the Feature Schema section of the Agent Teams protocol.

**2. Write `.harness/context_summary.md`** -- this carries real project judgment (domain,
constraints, architecture), never zero-decision content, so it stays hand-authored:

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

**3. Write `.harness/claude-progress.txt`**:

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

**4. Configure `.harness/init.sh`** for the detected stack -- the one genuinely
decision-shaped file in this set, so the stamp does not touch it. Read the
`init.sh.template` file in this skill's directory, copy it to `.harness/init.sh`,
configure for the detected stack, and make it executable with `chmod +x`.

The script accepts one optional argument: `smoke_test` or `full_test` (default: `full_test`).
- `smoke_test` — compile/syntax check only, completes in <15s. Used by the `TaskCompleted` hook as a fast first-pass gate.
- `full_test` — complete test suite with coverage. Used by the lead at session end and synthesis phase.

When configuring for the project's stack, ensure both targets work correctly.

## Step 3.6: Quality Gate Hooks (via the Stamp)

The stamp run in Step 3 already wrote and `chmod +x`'d every quality gate hook
(`verify-task-quality.sh`, `check-remaining-tasks.sh`, `enforce-scope.sh`,
`verify-git-identity.sh`, `commit-gate.sh`, `harness_state.py`, `statusline.sh`) and
wired the full `.claude/settings.json` block (statusLine, env, permissions, and the
PreToolUse/TaskCompleted/TeammateIdle hooks) -- there is nothing left to do here beyond
the verification in Step 3.7.

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
I've set up five hooks plus a status line:
- PreToolUse (scope): blocks edits to files outside the teammate's assigned scope. Only active when .claude/teammate-scope.txt exists.
- PreToolUse (git identity): blocks git push/pull/clone if identity doesn't match .harness/harness.json.
- PreToolUse (commit gate): blocks git commit if it stages-and-commits in one step, or if staged content looks like a secret.
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
