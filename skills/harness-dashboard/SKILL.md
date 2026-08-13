---
name: harness-dashboard
description: Launch (or reuse) the live dashboard for the current harness session and open it in a browser. Checks .harness/dashboard/ for at least one session log, starts F090's SSE server (hooks/dashboard/serve.py) detached at the OS level if one isn't already running on 127.0.0.1:8765, then opens F091's node-graph view. Use when you want to visually watch an active workflow/subagent session, or review the final state of one that already ended.
---

# Harness Dashboard

Opens a live, animated view of one harness session's workflow/subagent activity:
nodes for the lead and each spoke agent (workflow agents, plain subagents --
anything that fires SubagentStart/SubagentStop), pulsing on tool use, badged for
quality-gate verdicts, judge subagents, and permission prompts. This skill only launches the viewer --
the actual event log is written by `hooks/dashboard-log.sh` (F088), and only when
the session that produced it was started with `VV_HARNESS_DASHBOARD=1` set.

The page itself picks which session to watch (F099): it lists every session log
found under the server's project and lets you choose, rather than guessing one
for you. See "Choosing which session to watch" below.

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

   Do not start a server pointed at nothing -- /events answers 404 when no log
   exists yet, and a server nobody connects to idle-exits on its own after 10
   minutes (see "Stopping / restarting the server" below), but a pointless
   launch still churns a process for no reason.

2. **Check whether a server is already serving.** Probe `127.0.0.1:8765` (e.g. a
   plain `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8765/` with a
   short timeout, or `lsof -i :8765`). If something is already listening there,
   skip straight to step 4 (open the browser) -- do not start a second server.

   **Accepted limitation**: reusing an already-running server means it may still
   be bound to a *different project* than the one you're watching from, if that
   server was launched from elsewhere (nohup+disown -- F090's servers outlive
   the session that started them, per step 3 below). This skill's own reuse
   check only probes whether port 8765 is occupied, not which project the
   listener is bound to. Unlike the older, narrower staleness this note used to
   describe (a same-project server pointed at an older session), this is no
   longer invisible: the page itself (F099) shows the bound project's path and
   its full session list on load, so a mismatched project is immediately
   obvious -- an empty or unfamiliar list means you're looking at someone
   else's server. See "Choosing which session to watch" below for the normal,
   same-project case (picking among several sessions needs no restart at all),
   and "Stopping / restarting the server" if the reused server is genuinely the
   wrong project's.

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
   available, print `http://127.0.0.1:8765/` for the user to open manually. The
   page loads with nothing connected yet -- see the next section for what happens
   there.

## Choosing which session to watch

The page never guesses (F099). On load it calls F090's `GET /sessions` and shows:

- the project path the server is bound to (so a reused, wrong-project server --
  see step 2's Accepted limitation above -- is obvious rather than silent), and
- every `*.jsonl` session log found there, most-recently-modified first.

Pick one from the dropdown and click **Watch** to connect. Nothing streams before
that click -- there is no auto-selected default the way the underlying server's
CLI/`/events`-with-no-query behavior still has (kept for non-browser callers, e.g.
`curl`, but the page itself never relies on it).

If the session you want isn't listed yet (it started after the page loaded), click
**Refresh** to re-fetch the list -- this does not restart the server or lose your
current connection. To watch a different session than the one you're already
watching, just pick it and click Watch again: this closes the old connection and
starts a fresh one against the newly selected log, with **no server restart
needed at all** -- unlike a same-project session switch, which used to require
killing and relaunching the server.

If the session you picked already ended, the dashboard shows its final state,
frozen -- no more events will arrive. This is expected, not a failure: F090's
server has no cross-session aggregation or historical replay beyond
backlog-replay-on-connect for whichever one file a connection is tailing.

If your connection drops (laptop sleep, server hiccup), the browser's
EventSource auto-reconnects and replays the selected session's log file in
full -- there is no incremental resume. That replay is bounded by the file's
size (fine up to ~10 MB; session logs are typically far smaller), so a
reconnect costs a sub-second burst, not lost data.

## Stopping / restarting the server

The server reaps itself: after 10 minutes with no connected viewer (600
seconds, `--idle-exit-seconds`; the timer runs from process start, so a server
that never gets a viewer also exits), it shuts down cleanly and frees the
port -- an orphaned server no longer squats 8765 across projects
indefinitely. Note that only a connected /events stream counts as a viewer: a
page left open on the picker without clicking Watch does not hold the server
up.

To stop it sooner, there is no shutdown endpoint and no Claude-Code-internal
stop command -- the server is a plain OS process, stopped like any other:

```bash
lsof -i :8765          # find the PID listening on the dashboard port
kill <PID>              # stop it
```

Restarting is no longer how you switch to a different session in the *same*
project -- use the picker's Refresh + Watch instead (see above). Killing and
re-running `/harness-dashboard` is still how you free the port entirely, or how
you get off a server that turned out to be bound to the *wrong project*.

## Not auto-started

This skill is the only supported entry point -- there is no `SessionStart` hook
that spawns the dashboard automatically. A hook silently launching a long-running
background server on every session was judged too large a behavioral change to a
hook every harness session already goes through.
