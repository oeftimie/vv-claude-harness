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

FEAT_DIRTY=$(git -C "$ROOT" status --porcelain -- .harness/features.json 2>/dev/null)
PROG_DIRTY=$(git -C "$ROOT" status --porcelain -- .harness/claude-progress.txt 2>/dev/null)
if [ -n "$FEAT_DIRTY" ] && [ -z "$PROG_DIRTY" ]; then
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
TODAY_LOCAL=$(date +%Y-%m-%d)
MS_PATTERNS=(-e "## Meta-Session $TODAY")
[ "$TODAY_LOCAL" != "$TODAY" ] && MS_PATTERNS+=(-e "## Meta-Session $TODAY_LOCAL")
if ! grep -q "${MS_PATTERNS[@]}" "$H/context_summary.md" 2>/dev/null; then
  add_gap "Missing '## Meta-Session $TODAY' retrospective in context_summary.md."
fi

DIRTY_META=$(git -C "$ROOT" status -s -- .harness/ 2>/dev/null \
  | grep -v '\.harness/SESSION_INCOMPLETE' || true)
if [ -n "$DIRTY_META" ]; then
  add_gap "Uncommitted .harness/ metadata - commit with a docs: prefix."
fi

if [ -n "$GAPS" ]; then
  TMP="$H/SESSION_INCOMPLETE.tmp"
  printf '%s' "$GAPS" > "$TMP" 2>/dev/null && mv "$TMP" "$H/SESSION_INCOMPLETE" 2>/dev/null
  printf '%s' "$GAPS"
else
  rm -f "$H/SESSION_INCOMPLETE" 2>/dev/null
fi

# Proof discipline note: informational only, never written to SESSION_INCOMPLETE
# (not a gap) -- a passing feature with no proof recorded is worth surfacing, not
# blocking the next session over.
PROOF_NOTES=$(python3 - "$H/features.json" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    feats = json.load(open(sys.argv[1])).get("features", [])
    for f in feats:
        if f.get("status") == "passing" and not f.get("proof"):
            print(f"{f.get('id', '?')} is passing with no proof recorded.")
except Exception:
    pass
PYEOF
)
[ -n "$PROOF_NOTES" ] && printf 'Discipline note (informational, not blocking):\n%s\n' "$PROOF_NOTES"

exit 0
