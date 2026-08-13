# F116 / OVI-146 — AC1 live-run evidence (2026-08-13)

One live run per capture: a headless Claude Code session (`claude -p`) in a scratch
project with hooks wired to THIS branch's `hooks/dashboard-log.sh` (the installed
vv-harness 5.7.0 plugin was disabled for the scratch project via `enabledPlugins`,
so every log line came from the new capture code only), `VV_HARNESS_DASHBOARD=1`,
spawning 2 subagents. Rendered by this branch's `hooks/dashboard/serve.py` +
`index.html`, watched live in Chromium via Playwright.

## Checklist (AC1)

- (a) **Spoke on SubagentStart, labeled agent_type**: `live-run-spoke-explore.png`
  — captured while watching session `cedee770` live: one spoke labeled `Explore`
  orbiting the lead, screenshotted between that agent's SubagentStart and
  SubagentStop. Both of the session's agents rendered their spoke this way
  (observed in successive frames).
- (b) **Pulse on PreToolUse/PostToolUse**: transient animation, not capturable in
  a still; the live session processed all 4/4 Pre/PostToolUse pairs with no
  console errors, and the pulse wiring is pinned structurally in
  test/run-tests.sh (dash-fe assertions).
- (c) **Animate out on SubagentStop**: `live-run-final-state.png` — after both
  agents' SubagentStop, the graph returns to the lead node alone (observed live
  as each spoke left).
- (d) **No-agent_id events attach to the lead**: the lead node carried the
  session's own tool activity; no `(unknown agent)` spokes appeared.
- (e) **No JavaScript console errors**: the only console entry across the whole
  watched session was a favicon.ico 404 resource line (pre-existing, not a JS
  error, unrelated to event handling).

## Logs

- `session-watched-live.jsonl` — the session captured in the screenshots
  (2 Explore agents, sequential lifetimes; 12 lines).
- `session-parallel-overlap.jsonl` — a second run (Sonnet) whose two agents ran
  concurrently (SubagentStart 04:37:48/49, SubagentStop 04:38:07/08) — proves
  the capture path under genuinely parallel agents.

Both logs carry exactly the post-trim allowlist fields (`ts`,
`hook_event_name`, `session_id`, `agent_id`, `agent_type`) — no `summary`, no
`tool_name`, no `Task*` lines.

## Disclosed limitation

No single frame shows both spokes simultaneously: in the watched run the agents'
lifetimes were sequential, and in the parallel run the watch connection attached
seconds after both agents had stopped (their replay animated in and out faster
than a screenshot round-trip). AC1's checklist binds each agent's
appear/pulse/leave behavior, not simultaneity; item (a) is evidenced per-agent.
