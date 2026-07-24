# Maintenance Runbook

This repo rides on Claude Code's experimental Agent Teams surface (hook payload
shapes, `SendMessage` semantics, the plan-approval flow) and ships weekly. Nothing
in this repo notices platform drift on its own — this runbook is the loop that
does.

HE's continuous-maintenance thesis: a viable maintenance loop answers five
questions. Quiet no-op runs are healthy; a run that finds nothing wrong is a
successful run, not a skipped one.

## Condition

The released plugin behaves correctly on the current stable Claude Code CLI: the
five documented hooks fire with the payload shapes this repo expects, the
implicit Agent Teams model (no `TeamCreate`/`TeamDelete`) still holds, the
plugin's cache/update layout matches what `INSTALL.md` describes, and every
documented workaround's retirement condition is still accurate.

## Departure Signal

Two independent signals, either one enough to trigger a probe:

1. **Scheduled**: the weekly cron in `.github/workflows/maintenance.yml` runs
   `bash test/run-tests.sh` against the latest published
   `@anthropic-ai/claude-code` and records the probed CLI version.
2. **Manual**: reviewing Anthropic's Claude Code release notes for changes to
   Agent Teams, hooks, or `SendMessage` — this is a human judgment call, not
   automated (see Out of scope in the tracking issue).

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

1. **`plan_approval_response` delivery bug.** `rules/agent-teams-protocol.md`
   documents: `SendMessage` with `type: "plan_approval_response"` reports
   success but the message never reaches the recipient; use `type: "message"`
   for all plan approvals instead.

   **Reproduction**: spawn a teammate requiring plan approval. When it submits
   a plan for approval, the lead responds with
   `SendMessage({type: "plan_approval_response", ...})` — the exact type the
   workaround currently avoids.

   **FIXED** if the teammate demonstrably proceeds without needing a
   `type: "message"` fallback. **BROKEN** if the teammate stalls, re-submits
   the same plan request, or otherwise shows no evidence of having received
   the response. Precondition: CLI >= 2.1.207, checked at retest time.

   A FIXED result is recorded here; the removal of the workaround from
   `rules/agent-teams-protocol.md`, `README.md`, and any other file that
   documents it is a separate, explicit, approval-required follow-up — not
   automatically performed as part of a probe run.

2. **Implicit-team model assumptions** (no `TeamCreate`/`TeamDelete` tools;
   teams form implicitly when the first teammate spawns). No workaround to
   retire — this probe exists to catch the day the platform adds explicit team
   lifecycle tools, at which point the harness's implicit-team documentation
   needs updating.

3. **Hook events fire with expected payloads**: `TaskCompleted`,
   `TeammateIdle`, `SessionStart` (all sources: `startup`, `resume`, `clear`,
   `compact`), `SessionEnd`. No workaround to retire — this probe exists to
   catch a payload-shape change before a hook silently stops firing or starts
   misparsing.

4. **Plugin cache/update layout** matches `INSTALL.md`'s description
   (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, old versions
   retained side by side, no stale-file mixing between versions). No
   workaround to retire — this probe exists to catch an installer layout
   change before `INSTALL.md`'s instructions silently go stale.

5. **`fable` entry in `test/run-tests.sh`'s agent-frontmatter model
   allowlist.** No workaround — this probe exists to periodically confirm the
   entry still reflects a real, current Claude model choice (rather than a
   stale name kept out of inertia) and to remove it if it stops being one.
