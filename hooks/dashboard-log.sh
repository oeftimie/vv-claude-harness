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

# Prefers CLAUDE_PROJECT_DIR, matching every gate script's own
# PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel ...)}"
# resolution (.claude/hooks/enforce-scope.sh, commit-gate.sh,
# check-remaining-tasks.sh, verify-task-quality.sh) and hooks/session-start.sh.
# Before this fix, this hook ignored CLAUDE_PROJECT_DIR entirely and always
# fell back to git-toplevel-or-pwd -- in a harness project nested inside a
# larger git repo, that resolves to the OUTER repo's root while the gate
# scripts resolve to the inner project, so this hook silently wrote to (or
# looked for) .harness/dashboard/ in the wrong directory: the dashboard ends
# up completely empty with no diagnostic anywhere.
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
H="$ROOT/.harness"
[ -d "$H" ] || exit 0

STDIN_JSON=$(cat 2>/dev/null || true)

# F089 round 2 (adversarial review): the JSON payload is fed via STDIN, never
# argv -- a large Write/Edit payload on argv can exceed the OS's exec()
# argument-list size limit (~1MB on macOS, as low as 128KB per-argument on
# Linux), which fails this whole call silently (it's `|| true`) and drops the
# event with no error surfaced anywhere -- silent event loss, not a security
# bypass (this hook only ever logs, it never gates a tool call). Only the
# small, bounded dashboard directory path stays on argv.
#
# The payload-building logic itself lives in the sibling dashboard-log.py
# (F094 round 2), not inlined here via `python3 -c "$(cat <<'PYEOF' ...)"` --
# see that file's own header for why a heredoc nested inside a double-quoted
# command substitution is a bash-3.2-specific parse hazard this hook must not
# reintroduce.
#
# /simplify cleanup: this used to spawn a SEPARATE python3 process here just
# to extract and sanitize session_id from $STDIN_JSON, then pass it as an
# argv value to a second python3 process (dashboard-log.py) that re-read and
# re-parsed that same JSON to build the log line. dashboard-log.py now does
# both -- session_id extraction/sanitization and log-line building -- in the
# one process it already runs, parsing $STDIN_JSON exactly once. This shell
# script no longer computes or checks SESSION_ID at all; an empty/absent
# session_id is now detected and silently skipped inside dashboard-log.py,
# matching the original "no directory, no write" behavior exactly.
printf '%s' "$STDIN_JSON" | python3 "$(dirname "$0")/dashboard-log.py" "$H/dashboard" \
  >/dev/null 2>/dev/null || true

exit 0
