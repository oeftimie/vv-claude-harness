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

EXPECTED=$(python3 -c '
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("git_identity", {}).get("user_email", ""))
except Exception:
    pass
' "$H/harness.json" 2>/dev/null || true)
ACTUAL=$(git config user.email 2>/dev/null || true)
if [ -n "$EXPECTED" ] && [ "$EXPECTED" != "$ACTUAL" ]; then
  echo ""
  echo "WARNING: git identity mismatch."
  echo "harness.json expects <$EXPECTED> but git config user.email is <${ACTUAL:-unset}>."
  echo "Fix the identity before any push/pull/clone."
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-<vv-harness plugin root>}"
echo ""
echo "Agent Teams protocol: read $PLUGIN_ROOT/rules/agent-teams-protocol.md" \
  "before spawning teammates."
echo "Code-quality limits: $PLUGIN_ROOT/rules/code-quality.md (read before writing code)."
echo "Run /harness-continue for the full interactive flow (mode choice, smoke test, team plan)."
exit 0
