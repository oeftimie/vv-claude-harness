#!/usr/bin/env python3
"""Dashboard event-log line builder for hooks/dashboard-log.sh (F088).

Split out of dashboard-log.sh into this sibling file (F094 round 2) rather
than embedded as `python3 -c "$(cat <<'PYEOF' ... PYEOF)"`: a heredoc nested
inside a DOUBLE-QUOTED command substitution parses fine under bash 5.x but
fails `bash -n` outright under real bash 3.2.57 (this repo's own declared
minimum, test/run-tests.sh's header) whenever the heredoc body's own single-
quote count happens to be odd -- bash 3.2's lexer still scans the heredoc
BODY for quote balance while looking for the closing double-quote of the
substitution, even though heredoc content is not supposed to be subject to
quote-parity rules at all. This is invisible under Homebrew bash (5.x) on
PATH, which is exactly why it shipped uncaught. dashboard-log.sh is a
plugin-root hook (not a project-level template that must stay self-
contained/inlined per F089's "duplicate, don't source" architecture, unlike
the four gate scripts' own copies of this same schema), so it CAN reach a
sibling file -- this sidesteps the whole heredoc-quoting hazard rather than
working around it.

The logged line is a fixed field allowlist -- ts, hook_event_name,
session_id, and (when present) agent_id/agent_type. No field is ever derived
from tool_input or any other free-text payload content, so no secret riding
in a command, URL, or file path can reach the log (OVI-146): there is
nothing to redact because nothing free-form is written.

Invoked as: dashboard-log.py <log_path> <session_id>, with the raw hook
stdin JSON piped to this process's own stdin.
"""
import json
import sys
import time

log_path, session_id = sys.argv[1], sys.argv[2]
stdin_json = sys.stdin.read()

try:
    try:
        data = json.loads(stdin_json)
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}

    line = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "hook_event_name": data.get("hook_event_name", ""),
        "session_id": session_id,
    }
    for key in ("agent_id", "agent_type"):
        value = data.get(key)
        if value:
            line[key] = value

    with open(log_path, "a") as fh:
        fh.write(json.dumps(line) + "\n")
except Exception:
    pass
