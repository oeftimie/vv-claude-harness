# Maintenance Log

Newest entry first. One entry per run, including no-op runs — a run that finds
nothing wrong is still logged, never skipped.

## Run #0 — 2026-07-24

- **CLI version probed**: 2.1.218 (live interactive session, not the automated
  cron path — this is the bootstrapping run required by F007/OVI-56's own
  acceptance criteria, executed manually since the cron and monthly-agent parts
  didn't exist yet before this run).
- **Trigger**: manual, during F007/OVI-56's implementation.

### Outcomes

1. **`plan_approval_response` delivery bug — INCONCLUSIVE, mechanism unavailable
   to teammates.** Could not complete the documented reproduction. Findings,
   in order:
   - `SendMessage`'s own tool schema no longer accepts a `plan_approval_request`
     type from a teammate at all — only `plan_approval_response`,
     `shutdown_request`/`shutdown_response`, or plain text are valid outgoing
     `message` shapes. Confirmed by reading the schema directly.
   - A spawned teammate (`vv-harness:researcher`, no `require_plan_approval`
     option passed at spawn — no such option exists on the `Agent` spawn tool's
     schema) confirmed via two independent `ToolSearch` lookups that neither
     `EnterPlanMode` nor `ExitPlanMode` is exposed to it, even though both tools
     exist (the lead has them; other agent definitions reference
     `ExitPlanMode` in their tool-exclusion lists).
   - Conclusion: the plan-approval round trip this workaround describes has no
     reachable path in this session's tool surface for a teammate spawned the
     way this harness currently spawns them. This is not evidence the delivery
     bug itself is fixed or still present — the precondition to trigger it
     could not be reached at all. **Workaround NOT retired.** Not acted on
     further per this issue's scope (see `docs/maintenance-runbook.md`,
     Autonomous vs Approval-Required Operations).
   - **Follow-up**: separately investigate whether `require_plan_approval` (or
     an equivalent) exists on a different spawn surface than the `Agent` tool
     schema available in this session, and whether `rules/agent-teams-protocol.md`'s
     description of teammates originating `plan_approval_request` via
     `SendMessage` needs correcting independent of the delivery-bug question.
2. **Implicit-team model assumptions — HOLD.** No `TeamCreate`/`TeamDelete`
   tool exists in this session's tool surface (`ToolSearch` for team-management
   tools returned nothing matching). Teams still form implicitly at first
   teammate spawn.
3. **Hook events fire with expected payloads — HOLD.** Observed directly across
   this session: `TaskCompleted` fired correctly on every `TaskUpdate`
   completion (including the two known TDD-red-phase false positives already
   documented in `context_summary.md`); `TeammateIdle` fired for two teammates
   spawned this session; `SessionStart` injected orientation at session start.
   `SessionEnd` was not re-tested live this run (ending the session isn't
   practical mid-implementation) — covered by `test/run-tests.sh`'s existing
   `session-end.sh` fixture suite instead.
4. **Plugin cache/update layout — HOLD.** `~/.claude/plugins/cache/vv-harness-marketplace/vv-harness/`
   contains `4.1.0/` and `4.2.2/` side by side, matching `INSTALL.md`'s claim
   of no stale-file mixing between versions.
5. **`fable` model-allowlist entry — CONFIRMED INTENT, no removal.** Fable is a
   current, real Claude model family (alongside Sonnet 5, Opus 4.8, Haiku 4.5);
   no agent in `agents/*.md` uses it yet, but it is kept for forward
   compatibility, not stale cruft.

### Follow-ups

- Investigate the `require_plan_approval` / plan-approval-round-trip gap named
  in outcome 1 above as a separate, explicit piece of work — this is a bigger
  finding than a single workaround's retirement status, since it suggests part
  of `rules/agent-teams-protocol.md`'s documented Agent Teams mechanics may not
  reflect the current platform's actual tool surface for spawned teammates.
