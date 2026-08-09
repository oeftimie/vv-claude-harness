#!/bin/bash
# VV Claude Code Harness - TeammateIdle hook
# Runs when a teammate is about to go idle.
# Exit code 0 = allow idle (no more work)
# Exit code 2 = send feedback, keep teammate working
# Degraded behavior: a malformed feature entry is skipped with a stderr note;
# the remaining features are still evaluated for claimable work.
# Failure posture: fail-open. A missing or malformed features.json, or an unexpected
# harness_state.py output, results in exit 0 (idle allowed) rather than blocking.
# Residual: the reformatting step assumes harness_state.py's documented contract (the
# literal string "no claimable feature" or valid JSON) and is not independently
# validated -- an out-of-contract module output would raise rather than fall back.
# Guidance text (which feature to pick up next) goes to stderr, not stdout: Claude
# Code discards a hook's stdout entirely on exit 2 and feeds only stderr back to the
# blocked agent as its error message (code.claude.com/docs/en/hooks). A stdout-only
# message left an idle teammate with no visible guidance at all (F046, reported by a
# teammate stuck in a re-prompt loop with "No stderr output"). This was the first
# hook in this repo to get the channel right -- enforce-scope.sh.template's two
# legacy `exit 2` sites and verify-task-quality.sh.template's four all still write
# their blocking message to stdout, the same defect, not yet fixed (see F046 notes).
# Correction (F067 round-1 review): F055 originally claimed the TeammateIdle payload
# carries no teammate identity at all. That was WRONG -- confirmed via raw curl of
# code.claude.com/docs/en/hooks.md (a WebFetch-based check during F055 truncated
# before reaching the TeammateIdle section, ~line 2310 of a 2900+ line page, and
# silently answered from the common-fields table instead): the payload DOES carry
# `teammate_name` (plus deprecated `team_name`). This script still does not use it --
# INPUT is read and discarded below -- so it stays role-blind IN PRACTICE, but that is
# now a design choice, not a platform limitation. Investigated and declined (F069):
# `teammate_name` is caller-chosen free text with no enforced naming contract, and a
# wrong guess (silently suppressing a nudge for a teammate that legitimately has more
# work) is worse than the current bounded, visible cost of one extra decline per
# nudge. See "Considered and declined" in rules/agent-teams-protocol.md.
# The guidance text below still applies uniformly to every teammate; the reviewer-
# specific half of the original mitigation (declining once instead of re-messaging
# the lead on every repeat) lives in agents/reviewer.md.

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT_ROOT"

# Read hook input from stdin
INPUT=$(cat)

# F089: opt-in dashboard event log for this gate's block/allow verdicts.
# Duplicates hooks/dashboard-log.sh's (F088) JSON-line schema and
# redaction/atomicity conventions inline -- a project-level hook installed
# into .claude/hooks/ cannot reach a plugin-root file. Never aborts the
# gate: every risky step below is guarded, and every call site is itself
# suffixed with `|| true` -- critical under this script's own
# `set -euo pipefail`.
_dashboard_log() {
    [ "${VV_HARNESS_DASHBOARD:-}" = "1" ] || return 0
    [ -d ".harness" ] || return 0
    local verdict="$1" finding="${2:-}" session_id
    session_id=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("session_id") or "")
except Exception:
    pass
' 2>/dev/null || true)
    session_id=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9._-' | cut -c1-64)
    [ -n "$session_id" ] || return 0
    mkdir -p ".harness/dashboard" 2>/dev/null || return 0
    # F089 round 2 (adversarial review): the JSON payload is fed via STDIN,
    # never argv -- a large payload on argv can exceed the OS's exec()
    # argument-list size limit (~1MB on macOS, as low as 128KB per-argument
    # on Linux), which fails this whole call silently (it's `|| true`) and
    # drops the event with no error surfaced anywhere. Only small, bounded
    # values (the log path, session id, verdict, finding) stay on argv.
    #
    # The python source is read into a variable via a TOP-LEVEL heredoc
    # (F094 round 2), NOT `python3 -c "$(cat <<'PYEOF' ...)"` -- a heredoc
    # nested inside a DOUBLE-QUOTED command substitution parses fine under
    # bash 5.x but fails `bash -n` outright under real bash 3.2.57 (this
    # repo's own declared minimum) whenever the heredoc body's own single-
    # quote count is odd: bash 3.2's lexer still scans the heredoc BODY for
    # quote balance while looking for the closing double-quote of the
    # substitution, even though heredoc content isn't supposed to be
    # subject to quote-parity rules at all. Invisible under Homebrew bash
    # (5.x) on PATH, which is exactly why it shipped uncaught -- and because
    # this function is defined at file-load time, unconditionally, a parse
    # failure here breaks the ENTIRE gate script for every stock-bash user,
    # not just one gated behind VV_HARNESS_DASHBOARD (bash must successfully
    # PARSE the whole file before any runtime check, including that env-var
    # gate, ever executes).
    IFS= read -r -d '' _DASHBOARD_LOG_PY <<'PYEOF' || true
import json
import sys
import time

log_path, session_id, verdict, finding = sys.argv[1:5]
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
        "gate": "check-remaining-tasks",
        "verdict": verdict,
    }
    if finding:
        line["finding"] = finding
    for key in ("agent_id", "agent_type"):
        value = data.get(key)
        if value:
            line[key] = value
    with open(log_path, "a") as fh:
        fh.write(json.dumps(line) + "\n")
except Exception:
    pass
PYEOF
    printf '%s' "$INPUT" | python3 -c "$_DASHBOARD_LOG_PY" \
        ".harness/dashboard/$session_id.jsonl" "$session_id" "$verdict" "$finding" \
        >/dev/null 2>/dev/null || true
}

if [ ! -f ".harness/features.json" ]; then
    exit 0
fi

# Check features.json for remaining work via the shared state module.
# Status enum: pending, in-progress, blocked, passing, failed
# Claimable statuses: pending (ready for work), failed (needs re-attempt)
STATE_MODULE=".claude/hooks/harness_state.py"
RESULT=$(python3 "$STATE_MODULE" next-claimable .harness/features.json || true)

if [ -z "$RESULT" ] || [ "$RESULT" = "no claimable feature" ]; then
    _dashboard_log "allow" || true
    exit 0
fi

NEXT=$(printf '%s' "$RESULT" | python3 -c "
import json
import sys

# The whole formatter is guarded: a malformed feature entry (e.g. an explicit
# null description, which f.get('description', '') passes through as None)
# must degrade to a minimal nudge, never crash the substitution -- under
# set -euo pipefail a crash here would suppress the exit-2 block verdict
# entirely (silent fail-open). Mirrors session-start.sh's own try/except
# around the identical cap logic.
data = json.load(sys.stdin)
f = data['next']
try:
    status_note = ' (retry)' if f.get('status') == 'failed' else ''
    scope_list = [str(p) for p in (f.get('scope') or [])]
    scope = ', '.join(scope_list) or 'no scope defined'
    # F107: description and scope are the same unbounded-field class F071 and
    # F085 already closed for session-start.sh's orientation -- this line goes
    # straight to stderr, into a blocked agent's context, on exit 2. Same
    # truncate-and-point caps and marker wording, so the two hooks stay
    # consistent.
    SCOPE_LIMIT = 150
    if len(scope) > SCOPE_LIMIT:
        noun = 'path' if len(scope_list) == 1 else 'paths'
        scope = scope[:SCOPE_LIMIT] + f\"... ({len(scope_list)} {noun} total, see .harness/features.json)\"
    desc = f.get('description') or ''
    DESC_LIMIT = 200
    if len(desc) > DESC_LIMIT:
        full_len = len(desc)
        desc = desc[:DESC_LIMIT] + f\"... ({full_len} chars total, see .harness/features.json for the full description)\"
    print(f\"{data['count']} claimable feature(s). Next: {f.get('id')}: \"
          f\"{desc} (priority {f.get('priority', 'unset')})\"
          f\"{status_note} [scope: {scope}]\")
except Exception:
    print(f\"{data.get('count', '?')} claimable feature(s). Next: {f.get('id', 'unknown')}\"
          \" (details unavailable; see .harness/features.json)\")
")

echo "$NEXT" >&2
echo "Read .harness/features.json for full details, then claim it via TaskUpdate." >&2
echo "If your role has no Edit/Write tools (e.g. a review-only teammate), or your assignment was an explicit, already-delivered scoped task (a single review, a single read-only investigation, one eval run) rather than open-ended implementation work, this does not apply to you -- decline once, then stay idle; do not keep responding to repeated nudges. See your own agent definition, or ask the lead to shut you down." >&2
_dashboard_log "block" "claimable-feature-pending" || true
exit 2
