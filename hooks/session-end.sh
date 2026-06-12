#!/usr/bin/env bash
# SessionEnd hook: audits session-end discipline for harness projects.
# Writes gaps to .harness/SESSION_INCOMPLETE so the next SessionStart surfaces them.
# Hard budget: must complete well under the 1.5s SessionEnd timeout. Always exits 0.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
H="$ROOT/.harness"
[ -d "$H" ] || exit 0

GAPS=""
add_gap() { GAPS="${GAPS}${1}
"; }

if ! git -C "$ROOT" diff --quiet -- .harness/features.json 2>/dev/null \
  && git -C "$ROOT" diff --quiet -- .harness/claude-progress.txt 2>/dev/null; then
  add_gap "features.json changed but claude-progress.txt has no new handoff."
fi

WIP_GAPS=$(python3 - "$H/features.json" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    feats = json.load(open(sys.argv[1])).get("features", [])
    for f in feats:
        if f.get("status") != "in-progress":
            continue
        if not f.get("test_file") or f.get("coverage") in (None, ""):
            print(f"{f.get('id', '?')} is in-progress but missing test_file or coverage.")
except Exception:
    pass
PYEOF
)
[ -n "$WIP_GAPS" ] && add_gap "$WIP_GAPS"

TODAY=$(date -u +%Y-%m-%d)
if ! grep -q "## Meta-Session $TODAY" "$H/context_summary.md" 2>/dev/null; then
  add_gap "Missing '## Meta-Session $TODAY' retrospective in context_summary.md."
fi

if [ -n "$(git -C "$ROOT" status -s -- .harness/ 2>/dev/null)" ]; then
  add_gap "Uncommitted .harness/ metadata - commit with a docs: prefix."
fi

if [ -n "$GAPS" ]; then
  TMP="$H/SESSION_INCOMPLETE.tmp"
  printf '%s' "$GAPS" > "$TMP" 2>/dev/null && mv "$TMP" "$H/SESSION_INCOMPLETE" 2>/dev/null
  printf '%s' "$GAPS"
else
  rm -f "$H/SESSION_INCOMPLETE" 2>/dev/null
fi
exit 0
