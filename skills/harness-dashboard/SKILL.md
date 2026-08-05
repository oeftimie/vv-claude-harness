---
name: harness-dashboard
description: Launch (or reuse) the live dashboard for the current harness session and open it in a browser. Checks .harness/dashboard/ for at least one session log, starts F090's SSE server (hooks/dashboard/serve.py) detached at the OS level if one isn't already running on 127.0.0.1:8765, then opens F091's node-graph view. Use when you want to visually watch an active Agent Teams session, or review the final state of one that already ended.
---

# Harness Dashboard

Opens a live, animated view of one harness session's Agent Teams activity: nodes
for the lead and each spoke, pulsing on tool use, badged for quality-gate verdicts,
judge subagents, and permission prompts. This skill only launches the viewer --
the actual event log is written by `hooks/dashboard-log.sh` (F088), and only when
the session that produced it was started with `VV_HARNESS_DASHBOARD=1` set.

## Precondition: the session must have opted in

The dashboard has nothing to show unless the session being watched set the env
var *before* it started:

```bash
export VV_HARNESS_DASHBOARD=1
claude
```

Then, from a second terminal (or after that session ends), run `/harness-dashboard`.
Setting the variable after the session has already started has no effect.

## Steps

1. **Check for a log file.** Look under `.harness/dashboard/` for at least one
   `*.jsonl` file. If the directory doesn't exist or is empty, stop here and print:

   ```
   No dashboard log found under .harness/dashboard/.
   Set VV_HARNESS_DASHBOARD=1 before starting the Claude Code session you want
   to watch, then run /harness-dashboard again once it's running.
   ```

   Do not start a server pointed at nothing -- F090's server will happily wait/poll
   for a log file that will never appear, which just leaves a useless process running.

2. **Check whether a server is already serving.** Probe `127.0.0.1:8765` (e.g. a
   plain `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8765/` with a
   short timeout, or `lsof -i :8765`). If something is already listening there,
   skip straight to step 4 (open the browser) -- do not start a second server.

   **Accepted limitation**: reusing an already-running server means it may still
   be pointed at an older session if a newer one has started since that server
   launched (F090's server resolves the most-recently-modified log once per
   `/events` connection, not on a timer). This skill does not re-target a running
   server at a newer session -- see "Stopping / restarting the server" below if
   you need to point it at a different session.

3. **Start the server, detached at the OS level.** From the project root:

   ```bash
   nohup python3 "${CLAUDE_PLUGIN_ROOT}/hooks/dashboard/serve.py" > /tmp/harness-dashboard.log 2>&1 & disown
   ```

   No `session_id` argument is passed -- F090's server defaults to the
   most-recently-modified `*.jsonl` under `.harness/dashboard/`. `nohup` plus
   `disown` detaches the process at the OS level so it survives past this Claude
   Code session's own exit; this is deliberately not Claude Code's own
   `run_in_background` task mechanism, which is only verified to keep a process
   alive across turns/idle periods within one still-running session -- a weaker
   guarantee than what a dashboard meant to be checked back on later needs.
   Because the launch is OS-level, the server process is independent of the
   invoking session by construction: it keeps running after that session ends,
   until it is explicitly killed or the machine restarts.

4. **Open the page.** Run `open http://127.0.0.1:8765/` (macOS's `open` command --
   this repo's documented environment is macOS-specific). If `open` fails or isn't
   available, print `http://127.0.0.1:8765/` for the user to open manually.

## If the most-recently-modified session already ended

The dashboard will show that session's final state, frozen -- no more events will
arrive. This is expected behavior under the most-recently-modified selection rule,
not a failure: F090's server has no cross-session aggregation or historical replay
beyond backlog-replay-on-connect for the one file it picked.

## Stopping / restarting the server

There is no shutdown endpoint and no Claude-Code-internal stop command -- the
server is a plain OS process, stopped like any other:

```bash
lsof -i :8765          # find the PID listening on the dashboard port
kill <PID>              # stop it
```

To point the dashboard at a newer session, kill the old server first, then run
`/harness-dashboard` again so it starts a fresh one (which will auto-select the
now-most-recent log file).

## Not auto-started

This skill is the only supported entry point -- there is no `SessionStart` hook
that spawns the dashboard automatically. A hook silently launching a long-running
background server on every session was judged too large a behavioral change to a
hook every harness session already goes through.
