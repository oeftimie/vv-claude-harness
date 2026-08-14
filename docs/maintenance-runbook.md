# Maintenance Runbook

This repo rides on Claude Code platform surfaces (hook payload shapes, the
Workflow tool, worktree-isolated subagents) and ships weekly. Nothing in this
repo notices platform drift on its own — this runbook is the loop that does.

HE's continuous-maintenance thesis: a viable maintenance loop answers five
questions. Quiet no-op runs are healthy; a run that finds nothing wrong is a
successful run, not a skipped one.

## Condition

The released plugin behaves correctly on the current stable Claude Code CLI: the
documented hooks fire with the payload shapes this repo expects, the plugin's
cache/update layout matches what `INSTALL.md` describes, and every documented
workaround's retirement condition is still accurate.

## Departure Signal

Two independent signals, either one enough to trigger a probe:

1. **Scheduled**: the weekly cron in `.github/workflows/maintenance.yml` runs
   `bash test/run-tests.sh` against the latest published
   `@anthropic-ai/claude-code` and records the probed CLI version.
2. **Manual**: reviewing Anthropic's Claude Code release notes for changes to
   hooks, the Workflow tool, or worktree subagents — this is a human judgment
   call, not automated (see Out of scope in the tracking issue).

## Restoration Evidence

- The mechanical signal: `bash test/run-tests.sh` green on the probed CLI
  version — this is necessary but not sufficient, since it only exercises code
  paths this repo already has fixtures for.
- The behavioral signal: the Probe Checklist below, which exercises live team
  behaviors CI fixtures can't reach (an actual spawned teammate, an actual
  plan-approval round trip). This is what the monthly agent-run part of the
  loop is for.
- A FIXED verdict on any probe is evidence for retiring its workaround; it is
  not itself the retirement — see Autonomous vs Approval-Required Operations.

## Autonomous vs Approval-Required Operations

**Autonomous** (the weekly cron and the monthly agent run may do these without
asking):
- Run the test suite against the latest CLI.
- Record the probed CLI version and outcomes in `MAINTENANCE_LOG.md`, including
  no-op runs — a run that finds nothing wrong is still logged, never skipped
  ("repeated rediscovery of the same facts signals missing state").
- Open a GitHub issue when the cron run fails.

**Approval-required** (a human must sign off before these happen):
- Any change to a file in this repo — the maintenance loop observes and
  records, it does not edit.
- Removing a documented workaround, even when its probe reports FIXED. A FIXED
  result is recorded in `MAINTENANCE_LOG.md`; the actual removal from the files
  that reference it is a separate, explicit follow-up change.

## Durable State

`MAINTENANCE_LOG.md` at the repo root, newest entry first, one entry per run —
including no-op runs. Each entry records: date, CLI version probed, the outcome
of every probe checklist item, and any follow-ups (e.g. "workaround X reported
FIXED — propose removal in a follow-up PR").

## Probe Checklist

Each item below names the workaround (if any) it can retire, and the exact
condition that retires it. Items the weekly cron can't exercise (anything
requiring a live spawned teammate) are run by the monthly `claude -p` agent
session instead, and their outcome is appended to `MAINTENANCE_LOG.md` the same
way.

1. **Hook events fire with expected payloads**: `TaskCompleted`,
   `SessionStart` (all sources: `startup`, `resume`, `clear`,
   `compact`), `SessionEnd`. No workaround to retire — this probe exists to
   catch a payload-shape change before a hook silently stops firing or starts
   misparsing.

2. **Plugin cache/update layout** matches `INSTALL.md`'s description
   (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, old versions
   retained side by side, no stale-file mixing between versions). No
   workaround to retire — this probe exists to catch an installer layout
   change before `INSTALL.md`'s instructions silently go stale.

3. **`fable` entry in `test/run-tests.sh`'s agent-frontmatter model
   allowlist.** No workaround — this probe exists to periodically confirm the
   entry still reflects a real, current Claude model choice (rather than a
   stale name kept out of inertia) and to remove it if it stops being one.

4. **Workflow `args` arrives as a JSON-encoded string** (Phase 0 / OVI-141
   Q7). Both workflow scripts route `args` through a defensive `parseArgs`
   that tolerates either marshaling (string parsed, bare object passed
   through). Retires when the earliest CLI this plugin supports delivers
   `args` as a parsed object — probe by running any workflow with an object
   `args` and logging `typeof args`; on FIXED, drop `parseArgs`'s string
   branch (approval-required, as all retirements are).

5. **`CLAUDE_PROJECT_DIR` unset in worktree workflow agents** (Phase 0 /
   OVI-141). PreToolUse gate scripts fall back to git-toplevel resolution so
   scope and secret gates still fire inside workflow worktrees; flagged
   fragile at Phase 0. Retires when the platform sets `CLAUDE_PROJECT_DIR`
   for hook invocations inside worktree subagents — probe by logging the env
   var from a hook during a worktree workflow run; on FIXED, the fallback can
   be simplified away.

Teams-era items formerly listed here (the `plan_approval_response` delivery
bug, implicit-team model assumptions, and the F061/F067/F069 teammate
blindness cluster) were retired 2026-08-12 with OVI-144 Phase 3 and delisted
at the v6.0.0 release; their retirement records live in `MAINTENANCE_LOG.md`
and this file's git history.
