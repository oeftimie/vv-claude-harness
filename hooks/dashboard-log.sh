#!/usr/bin/env bash
# Dashboard event-log hook (F088): opt-in, near-zero-overhead JSON-line log of
# harness activity for external dashboard tooling (F090+). This is the
# CONTRACT's reference implementation, not a shared callable -- project-level
# gate scripts (F089) cannot reach a plugin-root file, so they independently
# duplicate this same JSON-line schema inline. Wired in hooks/hooks.json for
# PreToolUse, PostToolUse, SubagentStart, SubagentStop, PermissionRequest,
# PermissionDenied, TaskCreated, TaskCompleted, and TeammateIdle.
#
# Enablement: VV_HARNESS_DASHBOARD must equal exactly "1" (unset, empty, "0",
# or any other value is disabled). This check is the very first operation --
# one env var read, no file I/O, no subprocess -- so the disabled path stays
# near-zero-overhead (test/run-tests.sh asserts wall-clock under a generous
# 50ms bound as a regression guard, not a benchmarked SLA).
#
# When enabled: exits 0 immediately if no .harness/ directory exists (same
# `[ -d "$H" ] || exit 0` pattern as hooks/session-start.sh:13). session_id is
# sanitized with the same `tr -cd 'A-Za-z0-9._-' | cut -c1-64` pattern as
# hooks/session-start.sh:40; an empty/absent session_id silently skips the
# write (no error, no partial file).
#
# Log path: .harness/dashboard/<session_id>.jsonl -- one JSON line per event,
# appended with a single write() syscall per line (atomic for concurrent
# appends under the line's size cap).
#
# Logged fields, per code.claude.com/docs/en/hooks.md (quoted verbatim in this
# repo's .harness/features.json F088 notes field, the canonical grounding
# record -- cite THAT, not this comment, for the platform doc text itself):
#   ts               -- UTC timestamp this hook produced the line (not a
#                        platform-supplied field)
#   hook_event_name  -- one of the nine wired event names above
#   session_id       -- sanitized, matches the log file name
#   agent_id         -- when present (subagent/--agent mode only)
#   agent_type       -- when present (subagent/--agent mode only)
#   tool_name        -- when present (PreToolUse/PostToolUse/PermissionRequest/
#                        PermissionDenied)
#   teammate_name    -- when present (TeammateIdle)
#   team_name        -- when present (TeammateIdle; platform accepts but
#                        ignores this argument at spawn time per
#                        rules/agent-teams-protocol.md, logged here anyway
#                        since the hook payload still carries it)
#   summary          -- for tool-bearing events only: a per-tool-type redacted
#                        summary capped at 200 chars, reusing this repo's
#                        truncate-and-point convention (F071/F079). NEVER the
#                        raw command, file content, prompt, or transcript --
#                        matching commit-gate.sh:57's "never log matched
#                        content" policy applied to this new surface:
#                          Bash             -> tool_input.description,
#                                               or "(no description)"
#                          Edit/Write       -> tool_input.file_path only
#                          Read/Glob/Grep   -> file_path, else pattern,
#                                               else path
#                          WebFetch/WebSearch -> url, else query
#                          Agent            -> subagent_type, else description
#                          (any other tool) -> no summary field
#
# A log write failure (unwritable directory, disk full, python3 missing, a
# malformed stdin payload, or anything else) NEVER blocks the tool call or
# alters gate behavior -- this hook always exits 0 regardless of write
# outcome.
set -uo pipefail

[ "${VV_HARNESS_DASHBOARD:-}" = "1" ] || exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
H="$ROOT/.harness"
[ -d "$H" ] || exit 0

STDIN_JSON=$(cat 2>/dev/null || true)

SESSION_ID=$(printf '%s' "$STDIN_JSON" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("session_id") or "")
except Exception:
    pass
' 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-' | cut -c1-64)
[ -n "$SESSION_ID" ] || exit 0

DASHBOARD_DIR="$H/dashboard"
mkdir -p "$DASHBOARD_DIR" 2>/dev/null || exit 0

python3 - "$DASHBOARD_DIR/$SESSION_ID.jsonl" "$SESSION_ID" "$STDIN_JSON" \
  >/dev/null 2>/dev/null <<'PYEOF' || true
import json
import sys
import time

log_path, session_id, stdin_json = sys.argv[1], sys.argv[2], sys.argv[3]
SUMMARY_LIMIT = 200


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
    for key in ("agent_id", "agent_type", "tool_name", "teammate_name", "team_name"):
        value = data.get(key)
        if value:
            line[key] = value

    tool_name = data.get("tool_name")
    if tool_name:
        summary = redact(tool_name, data.get("tool_input"))
        if summary is not None:
            if len(summary) > SUMMARY_LIMIT:
                summary = summary[:SUMMARY_LIMIT] + f"... ({len(summary)} chars total)"
            line["summary"] = summary

    with open(log_path, "a") as fh:
        fh.write(json.dumps(line) + "\n")
except Exception:
    pass
PYEOF

exit 0
