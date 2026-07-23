#!/usr/bin/env bash
# SessionStart hook: injects harness orientation into model context for harness projects.
# Plain stdout reaches the model (capped at 10,000 chars). Always exits 0; never blocks.
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

if [ "$SOURCE" = "compact" ]; then
  echo "## Compaction recovery"
  echo "Context was just compacted. Re-read the Active Context section of"
  echo ".harness/context_summary.md and the task list (TaskList) before continuing work."
  echo ""
fi

echo "## Harness orientation (auto-injected)"

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
    status = {f.get("id"): f.get("status") for f in feats}
    claimable = [f for f in feats if f.get("status") in ("pending", "failed")
                 and all(status.get(d) == "passing" for d in (f.get("depends_on") or []))]
    claimable.sort(key=lambda f: f.get("priority", 999))
    if claimable:
        f = claimable[0]
        scope = ", ".join(f.get("scope") or [])
        desc = f.get("description", "")
        print(f"Next claimable: {f.get('id', '?')} - {desc} (scope: {scope})")
    else:
        print("Next claimable: none (no pending or failed features)")
except Exception:
    pass
PYEOF

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
fi
echo "Run /harness-continue for the full interactive flow (mode choice, smoke test, team plan)."
exit 0
