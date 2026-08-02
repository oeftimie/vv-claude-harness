#!/usr/bin/env bash
# SessionStart hook: injects harness orientation into model context for harness projects.
# Plain stdout reaches the model (capped at 10,000 chars). Always exits 0; never blocks.
# Hard invariant, enforced mechanically: this file must NEVER contain the literal
# lowercase substring naming the per-session telemetry directory under .harness/
# (checked by /harness-doctor's non-injection check and a permanent regression
# test in test/run-tests.sh; see harness-continue's Session End step and its
# linked review-cadence rule for what that directory is and why).
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
H="$ROOT/.harness"
[ -d "$H" ] || exit 0

STDIN_JSON=$(cat 2>/dev/null || true)
SOURCE=$(printf '%s' "$STDIN_JSON" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("source", ""))
except Exception:
    pass
' 2>/dev/null || true)

SESSION_ID=$(printf '%s' "$STDIN_JSON" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("session_id") or "")
except Exception:
    pass
' 2>/dev/null || true)
# session_id is externally supplied and echoed into the orientation block below --
# never trust it raw. Unfiltered, a newline lets it inject arbitrary lines into the
# most authoritative position in this hook's output (directly under the orientation
# header, indistinguishable from harness-authored content), and a "/" or ".." lets
# it escape its intended directory once the lead uses it verbatim in a later
# filename (see the header comment above for what that directory is and why it
# is deliberately not named here). Restricting to a safe charset closes both
# at once; the length cap keeps a maliciously long value from bloating the context
# injection (found by adversarial review of PR #62).
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-' | cut -c1-64)

if [ "$SOURCE" = "compact" ]; then
  echo "## Compaction recovery"
  echo "Context was just compacted. Re-read the Active Context section of"
  echo ".harness/context_summary.md and the task list (TaskList) before continuing work."
  echo ""
fi

echo "## Harness orientation (auto-injected)"

[ -n "$SESSION_ID" ] && echo "Session: $SESSION_ID"

if [ -f "$H/SESSION_INCOMPLETE" ]; then
  echo ""
  echo "WARNING: the previous session ended with unresolved discipline gaps:"
  head -15 "$H/SESSION_INCOMPLETE" 2>/dev/null | sed 's/^/    /' || true
  echo "Resolve these before starting new work."
fi

echo ""
python3 - "$H/features.json" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    feats = json.load(open(sys.argv[1])).get("features", [])
    passing = sum(1 for f in feats if f.get("status") == "passing")
    print(f"Features: {passing}/{len(feats)} passing")
except Exception:
    pass
PYEOF

# next-claimable: delegate the algorithm to harness_state.py when a per-project
# copy exists (v5+ projects); fall back to the inline computation otherwise
# (older projects initialized before this module existed).
STATE_MODULE="$ROOT/.claude/hooks/harness_state.py"
# OVI-105: a feature's description is free text with no length cap
# (.harness/features.json has carried descriptions past 13,000 chars in real
# use), and this whole script's stdout is what's capped at 10,000 chars
# reaching the model (line 3 above). Truncating this one field to 200 chars
# protects everything that prints AFTER it -- the git-identity mismatch
# warning and every rule pointer below -- from being silently pushed past
# the cap by one long description. The full text is never lost; it's still
# in features.json, just not echoed whole into every session's orientation.
if [ -f "$STATE_MODULE" ] && [ -f "$H/features.json" ]; then
  RESULT=$(python3 "$STATE_MODULE" next-claimable "$H/features.json" 2>/dev/null || true)
  if [ "$RESULT" = "no claimable feature" ]; then
    echo "Next claimable: none (no pending or failed features)"
  elif [ -n "$RESULT" ]; then
    python3 - "$RESULT" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    data = json.loads(sys.argv[1])
    f = data["next"]
    scope = ", ".join(f.get("scope") or [])
    desc = f.get("description", "")
    DESC_LIMIT = 200
    if len(desc) > DESC_LIMIT:
        full_len = len(desc)
        desc = desc[:DESC_LIMIT] + f"... ({full_len} chars total, see .harness/features.json for the full description)"
    print(f"Next claimable: {f.get('id', '?')} - {desc} (scope: {scope})")
except Exception:
    pass
PYEOF
  fi
else
  python3 - "$H/features.json" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    feats = json.load(open(sys.argv[1])).get("features", [])
    status = {f.get("id"): f.get("status") for f in feats}
    claimable = [f for f in feats if f.get("status") in ("pending", "failed")
                 and all(status.get(d) == "passing" for d in (f.get("depends_on") or []))]
    claimable.sort(key=lambda f: f.get("priority", 999))
    if claimable:
        f = claimable[0]
        scope = ", ".join(f.get("scope") or [])
        desc = f.get("description", "")
        DESC_LIMIT = 200
        if len(desc) > DESC_LIMIT:
            full_len = len(desc)
            desc = desc[:DESC_LIMIT] + f"... ({full_len} chars total, see .harness/features.json for the full description)"
        print(f"Next claimable: {f.get('id', '?')} - {desc} (scope: {scope})")
    else:
        print("Next claimable: none (no pending or failed features)")
except Exception:
    pass
PYEOF
fi

python3 - "$H/features.json" <<'PYEOF' 2>/dev/null || true
import hashlib, json, sys
try:
    feats = json.load(open(sys.argv[1])).get("features", [])
    drifted = []
    for f in feats:
        spec = f.get("spec") or {}
        expected = spec.get("hash")
        if not expected:
            continue
        current = hashlib.sha256((f.get("description") or "").encode("utf-8")).hexdigest()
        if current != expected:
            drifted.append(f.get("id", "?"))
    if drifted:
        print("")
        print("WARNING: spec drift: description changed after verification for "
              + ", ".join(drifted[:5]) + ".")
        print("Re-run the spec gate (harness-issue-prep) before implementing these.")
except Exception:
    pass
PYEOF

python3 - "$ROOT" "$H/features.json" <<'PYEOF' 2>/dev/null || true
import json, os, sys
try:
    root, features_path = sys.argv[1], sys.argv[2]
    feats = json.load(open(features_path)).get("features", [])
    armed_needed = any(
        f.get("status") == "in-progress" and f.get("assigned_to") is not None
        for f in feats
    )
    if armed_needed:
        hook_exists = os.path.isfile(os.path.join(root, ".claude", "hooks", "enforce-scope.sh"))
        scope_file_exists = os.path.isfile(os.path.join(root, ".claude", "teammate-scope.txt"))
        if hook_exists and not scope_file_exists:
            print("")
            print("WARNING: scope enforcement unarmed: .claude/teammate-scope.txt missing;")
            print("write it before spawning teammates or use worktree isolation.")
except Exception:
    pass
PYEOF

# F066: a passing/in-progress feature's test_file is a claim, not a fact -- this
# reproduces doctor.py's check_feature_test_files at session-start scope (cheap,
# same os.path.isfile cost as the spec-drift hash check above) so faithful
# orientation can't hand the session a fabricated picture.
python3 - "$ROOT" "$H/features.json" <<'PYEOF' 2>/dev/null || true
import json, os, sys
try:
    root, features_path = sys.argv[1], sys.argv[2]
    feats = json.load(open(features_path)).get("features", [])
    missing = []
    for f in feats:
        if f.get("status") not in ("passing", "in-progress"):
            continue
        test_file = f.get("test_file")
        if not test_file:
            continue
        if not os.path.isfile(os.path.join(root, test_file)):
            missing.append(f.get("id", "?"))
    if missing:
        shown = ", ".join(missing[:5])
        more = f" (+{len(missing) - 5} more)" if len(missing) > 5 else ""
        print("")
        print(f"WARNING: test_file does not exist for {shown}{more} despite a "
              "passing/in-progress status.")
        print("Run /harness-doctor for details, or correct the status/test_file field.")
except Exception:
    pass
PYEOF

if [ -f "$H/claude-progress.txt" ]; then
  echo ""
  echo "Last handoff (claude-progress.txt, last 12 lines):"
  tail -12 "$H/claude-progress.txt" 2>/dev/null | sed 's/^/    /' || true
fi

if [ -f "$H/context_summary.md" ]; then
  echo ""
  echo "Active Context (context_summary.md):"
  awk '/## Active Context/{p=1;next} /^## /{p=0} p' "$H/context_summary.md" 2>/dev/null \
    | head -20 | sed 's/^/    /' || true
fi

EXPECTED_NAME=$(python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("git_identity", {}).get("user_name", ""))
except Exception:
    pass
' "$H/harness.json" 2>/dev/null || true)
EXPECTED_EMAIL=$(python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("git_identity", {}).get("user_email", ""))
except Exception:
    pass
' "$H/harness.json" 2>/dev/null || true)
ACTUAL_NAME=$(git config user.name 2>/dev/null || true)
ACTUAL_EMAIL=$(git config user.email 2>/dev/null || true)
MISMATCH=""
if [ -n "$EXPECTED_NAME" ] && [ "$EXPECTED_NAME" != "$ACTUAL_NAME" ]; then MISMATCH=1; fi
if [ -n "$EXPECTED_EMAIL" ] && [ "$EXPECTED_EMAIL" != "$ACTUAL_EMAIL" ]; then MISMATCH=1; fi
if [ -n "$MISMATCH" ]; then
  echo ""
  echo "WARNING: git identity mismatch."
  echo "harness.json expects $EXPECTED_NAME <$EXPECTED_EMAIL> but git config has" \
    "${ACTUAL_NAME:-unset} <${ACTUAL_EMAIL:-unset}>."
  echo "Fix the identity before any push/pull/clone."
fi

echo ""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  echo "Agent Teams protocol: read $CLAUDE_PLUGIN_ROOT/rules/agent-teams-protocol.md" \
    "before spawning teammates."
  echo "Code-quality limits: $CLAUDE_PLUGIN_ROOT/rules/code-quality.md (read before writing code)."
  echo "Context summary format: $CLAUDE_PLUGIN_ROOT/rules/context-summary.md" \
    "(read before editing context_summary.md)."
  echo "Completion checklist: $CLAUDE_PLUGIN_ROOT/rules/task-completion.md" \
    "(read before declaring work complete)."
  echo "Debugging discipline: $CLAUDE_PLUGIN_ROOT/rules/debugging.md (read before debugging a failure)."
fi
echo "Run /harness-continue for the full interactive flow (mode choice, smoke test, team plan)."
exit 0
