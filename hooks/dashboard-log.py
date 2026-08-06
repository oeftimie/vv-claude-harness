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

Invoked as: dashboard-log.py <dashboard_dir>, with the raw hook stdin JSON
piped to this process's own stdin. session_id extraction and sanitization
(same `[^A-Za-z0-9._-]` strip + 64-char cap as every other _dashboard_log()
in this repo) and the resulting log path now all happen HERE, in the same
process that already parses the JSON to build the log line (/simplify
cleanup) -- dashboard-log.sh used to spawn a SEPARATE python3 process first
just to extract session_id from the same stdin payload this file re-reads
and re-parses a moment later. One process, one JSON parse, per event.
"""
import json
import os
import re
import sys
import time

dashboard_dir = sys.argv[1]
stdin_json = sys.stdin.read()
SUMMARY_LIMIT = 200

# Reused verbatim from commit-gate.sh's own SECRET_PATTERN (~line 446-449):
# a redacted summary is still built from raw tool_input (url, description,
# etc.), unlike the field-allowlist redaction this hook otherwise relies on,
# so a real secret riding along in one of those fields -- e.g. a WebFetch url
# with an embedded `?api_key=...` query param -- reached the log verbatim.
# This closes the concrete key=value-shaped case the pattern already
# recognizes, applied to this new surface; it is not a general secret
# scanner (a bare token or unlabeled bearer string in free text still isn't
# caught, the same documented residual as commit-gate.sh's own copy).
SECRET_KEYWORDS = "key|secret|password|passwd|pwd|token"
SECRET_PATTERN = re.compile(
    r"(?i)(?:" + SECRET_KEYWORDS + r")[A-Za-z0-9_.\-]*['\"]?\s*[:=]\s*"
    r"['\"]?([A-Za-z0-9+/_.\-]{16,})"
)


def redact(tool_name, tool_input):
    if not isinstance(tool_input, dict):
        tool_input = {}
    if tool_name == "Bash":
        return tool_input.get("description") or "(no description)"
    if tool_name in ("Edit", "Write"):
        return tool_input.get("file_path", "")
    if tool_name in ("Read", "Glob", "Grep"):
        return (tool_input.get("file_path") or tool_input.get("pattern")
                 or tool_input.get("path") or "")
    if tool_name in ("WebFetch", "WebSearch"):
        return tool_input.get("url") or tool_input.get("query") or ""
    if tool_name == "Agent":
        return tool_input.get("subagent_type") or tool_input.get("description") or ""
    return None


def build_and_write():
    try:
        data = json.loads(stdin_json)
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}

    session_id = re.sub(r"[^A-Za-z0-9._-]", "", str(data.get("session_id") or ""))[:64]
    if not session_id:
        return

    line = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "hook_event_name": data.get("hook_event_name", ""),
        "session_id": session_id,
    }
    for key in ("agent_id", "agent_type", "tool_name", "teammate_name", "team_name"):
        value = data.get(key)
        if value:
            line[key] = value

    tool_name = data.get("tool_name")
    if tool_name:
        summary = redact(tool_name, data.get("tool_input"))
        if summary is not None:
            summary = SECRET_PATTERN.sub("[redacted]", summary)
            if len(summary) > SUMMARY_LIMIT:
                summary = summary[:SUMMARY_LIMIT] + f"... ({len(summary)} chars total)"
            line["summary"] = summary

    os.makedirs(dashboard_dir, exist_ok=True)
    with open(os.path.join(dashboard_dir, f"{session_id}.jsonl"), "a") as fh:
        fh.write(json.dumps(line) + "\n")


try:
    build_and_write()
except Exception:
    pass
