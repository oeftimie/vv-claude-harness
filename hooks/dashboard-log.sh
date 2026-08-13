#!/usr/bin/env bash
# Dashboard event-log hook (F088): opt-in, near-zero-overhead JSON-line log of
# harness activity for external dashboard tooling (F090+). This is the
# CONTRACT's reference implementation, not a shared callable -- project-level
# gate scripts (F089) cannot reach a plugin-root file, so they independently
# duplicate this same JSON-line schema inline. Wired in hooks/hooks.json for
# PreToolUse, PostToolUse, SubagentStart, SubagentStop, PermissionRequest,
# and PermissionDenied -- exactly the events the dashboard page renders
# (OVI-146: TaskCreated/TaskCompleted routing removed; the render layer never
# used those lines).
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
#   hook_event_name  -- one of the six wired event names above
#   session_id       -- sanitized, matches the log file name
#   agent_id         -- when present (subagent/--agent mode only)
#   agent_type       -- when present (subagent/--agent mode only)
# This is the COMPLETE schema (OVI-146): a fixed allowlist with no field
# derived from tool_input or any other free-text payload content, so no
# secret riding in a command, URL, or file path can reach the log -- there is
# nothing to redact because nothing free-form is written.
#
# A log write failure (unwritable directory, disk full, a malformed stdin
# payload, or anything else) NEVER blocks the tool call or alters gate
# behavior -- this hook always exits 0 regardless of write outcome. A missing
# python3 is the one failure that gets a diagnostic: one stderr line, at most
# once per project (gated by the .harness/dashboard/.python3-missing
# sentinel; if the sentinel itself cannot be written -- read-only .harness/ --
# the hook stays silent rather than repeating the line every tool call),
# then silence -- see below.
set -uo pipefail

[ "${VV_HARNESS_DASHBOARD:-}" = "1" ] || exit 0

# Prefers CLAUDE_PROJECT_DIR, matching every gate script's own
# PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel ...)}"
# resolution (.claude/hooks/enforce-scope.sh, commit-gate.sh,
# verify-task-quality.sh) and hooks/session-start.sh.
# Before this fix, this hook ignored CLAUDE_PROJECT_DIR entirely and always
# fell back to git-toplevel-or-pwd -- in a harness project nested inside a
# larger git repo, that resolves to the OUTER repo's root while the gate
# scripts resolve to the inner project, so this hook silently wrote to (or
# looked for) .harness/dashboard/ in the wrong directory: the dashboard ends
# up completely empty with no diagnostic anywhere.
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
H="$ROOT/.harness"
[ -d "$H" ] || exit 0

# python3 is the only runtime this hook cannot degrade around: without it no
# event line can be built and every event is dropped. Surface that once per
# project instead of fully silently -- the sentinel file gates a single
# stderr diagnostic; every later invocation stays silent and still exits 0.
if ! command -v python3 >/dev/null 2>&1; then
  SENTINEL="$H/dashboard/.python3-missing"
  if [ ! -e "$SENTINEL" ]; then
    # The diagnostic fires only when the sentinel is actually created: on an
    # unwritable .harness/ the guard could never close, and at-most-once
    # (here: zero) beats repeating the line on every tool call (OVI-146
    # review).
    if mkdir -p "$H/dashboard" 2>/dev/null && touch "$SENTINEL" 2>/dev/null; then
      echo "vv-harness dashboard-log: python3 not found; dashboard logging disabled" >&2
    fi
  fi
  exit 0
fi

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

# F089 round 2 (adversarial review): the JSON payload is fed via STDIN, never
# argv -- a large Write/Edit payload on argv can exceed the OS's exec()
# argument-list size limit (~1MB on macOS, as low as 128KB per-argument on
# Linux), which fails this whole call silently (it's `|| true`) and drops the
# event with no error surfaced anywhere -- silent event loss, not a security
# bypass (this hook only ever logs, it never gates a tool call). Only small,
# bounded values (the log path, session id) stay on argv.
#
# The payload-building logic itself lives in the sibling dashboard-log.py
# (F094 round 2), not inlined here via `python3 -c "$(cat <<'PYEOF' ...)"` --
# see that file's own header for why a heredoc nested inside a double-quoted
# command substitution is a bash-3.2-specific parse hazard this hook must not
# reintroduce.
printf '%s' "$STDIN_JSON" | python3 "$(dirname "$0")/dashboard-log.py" \
  "$DASHBOARD_DIR/$SESSION_ID.jsonl" "$SESSION_ID" \
  >/dev/null 2>/dev/null || true

exit 0
