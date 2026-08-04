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
    python3 - ".harness/dashboard/$session_id.jsonl" "$session_id" "$INPUT" "$verdict" "$finding" \
        >/dev/null 2>/dev/null <<'PYEOF' || true
import json
import sys
import time

log_path, session_id, stdin_json, verdict, finding = sys.argv[1:6]
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
    with open(log_path, "a") as fh:
        fh.write(json.dumps(line) + "\n")
except Exception:
    pass
PYEOF
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

data = json.load(sys.stdin)
f = data['next']
status_note = ' (retry)' if f.get('status') == 'failed' else ''
scope = ', '.join(f.get('scope') or []) or 'no scope defined'
print(f\"{data['count']} claimable feature(s). Next: {f.get('id')}: \"
      f\"{f.get('description')} (priority {f.get('priority', 'unset')})\"
      f\"{status_note} [scope: {scope}]\")
")

echo "$NEXT" >&2
echo "Read .harness/features.json for full details, then claim it via TaskUpdate." >&2
echo "If your role has no Edit/Write tools (e.g. a review-only teammate), or your assignment was an explicit, already-delivered scoped task (a single review, a single read-only investigation, one eval run) rather than open-ended implementation work, this does not apply to you -- decline once, then stay idle; do not keep responding to repeated nudges. See your own agent definition, or ask the lead to shut you down." >&2
_dashboard_log "block" "claimable-feature-pending" || true
exit 2
