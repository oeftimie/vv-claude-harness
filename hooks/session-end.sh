#!/usr/bin/env bash
# SessionEnd hook: audits session-end discipline for harness projects.
# Writes gaps to .harness/SESSION_INCOMPLETE so the next SessionStart surfaces them.
# Hard budget: must complete well under the 1.5s SessionEnd timeout. Always exits 0.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
H="$ROOT/.harness"
[ -d "$H" ] || exit 0

GAPS=""
add_gap() { GAPS="${GAPS}${1}
"; }

# add_note prints an informational, non-blocking discipline note (never written to
# SESSION_INCOMPLETE): a shared prefix line followed by the note's own message.
add_note() { printf 'Discipline note (informational, not blocking):\n%s\n' "$1"; }

# Single git status scan of .harness/ -- FEAT_DIRTY, PROG_DIRTY, and DIRTY_META below
# all derive from this one call instead of each re-scanning overlapping scope.
META_STATUS=$(git -C "$ROOT" status --porcelain -- .harness/ 2>/dev/null)
FEAT_DIRTY=$(printf '%s\n' "$META_STATUS" | grep -F '.harness/features.json' || true)
PROG_DIRTY=$(printf '%s\n' "$META_STATUS" | grep -F '.harness/claude-progress.txt' || true)
if [ -n "$FEAT_DIRTY" ] && [ -z "$PROG_DIRTY" ]; then
  add_gap "features.json changed but claude-progress.txt has no new handoff."
fi

# Single features.json load feeding both the in-progress WIP gap (blocking) and the
# passing-no-proof note (informational) below -- the two blocks stay logically
# distinct, they just share one python3 process and one json.load. The two blocks are
# joined by a record-separator (0x1e) that can't appear in our own generated text.
FEATURE_NOTES=$(python3 - "$H/features.json" <<'PYEOF' 2>/dev/null || true
import json, sys

try:
    feats = json.load(open(sys.argv[1])).get("features", [])
except Exception:
    feats = []
wip = []
proof = []
for f in feats:
    if f.get("status") == "in-progress" and (
        not f.get("test_file") or f.get("coverage") in (None, "")
    ):
        wip.append(f"{f.get('id', '?')} is in-progress but missing test_file or coverage.")
    if f.get("status") == "passing" and not f.get("proof"):
        proof.append(f"{f.get('id', '?')} is passing with no proof recorded.")
print("\n".join(wip) + "\x1e" + "\n".join(proof))
PYEOF
)
WIP_GAPS="${FEATURE_NOTES%%$'\x1e'*}"
PROOF_NOTES="${FEATURE_NOTES#*$'\x1e'}"
[ -n "$WIP_GAPS" ] && add_gap "$WIP_GAPS"

TODAY=$(date -u +%Y-%m-%d)
TODAY_LOCAL=$(date +%Y-%m-%d)
MS_PATTERNS=(-e "## Meta-Session $TODAY")
[ "$TODAY_LOCAL" != "$TODAY" ] && MS_PATTERNS+=(-e "## Meta-Session $TODAY_LOCAL")
if ! grep -q "${MS_PATTERNS[@]}" "$H/context_summary.md" 2>/dev/null; then
  add_gap "Missing '## Meta-Session $TODAY' retrospective in context_summary.md."
fi

DIRTY_META=$(printf '%s\n' "$META_STATUS" | grep -v '\.harness/SESSION_INCOMPLETE' || true)
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

# MLD discipline note: informational only, never written to SESSION_INCOMPLETE (not a
# gap) -- newer and softer than the Meta-Session retrospective check above, reviewed on
# its own cadence (rules/mld-review.md) rather than gated every session.
MLD_DIR="$H/mld"
MLD_FOUND=""
if [ -d "$MLD_DIR" ]; then
  if find "$MLD_DIR" -maxdepth 1 -name "${TODAY}-*.md" -print -quit 2>/dev/null \
      | grep -q .; then
    MLD_FOUND=1
  elif [ "$TODAY_LOCAL" != "$TODAY" ] \
      && find "$MLD_DIR" -maxdepth 1 -name "${TODAY_LOCAL}-*.md" -print -quit \
        2>/dev/null | grep -q .; then
    MLD_FOUND=1
  fi
fi
if [ -z "$MLD_FOUND" ]; then
  MLD_MSG="no .harness/mld/ entry found for today ($TODAY) -- see"
  MLD_MSG="$MLD_MSG /harness-continue's Session End step to write one."
  add_note "$MLD_MSG"
fi

# Proof discipline note: informational only, never written to SESSION_INCOMPLETE
# (not a gap) -- a passing feature with no proof recorded is worth surfacing, not
# blocking the next session over.
[ -n "$PROOF_NOTES" ] && add_note "$PROOF_NOTES"

exit 0
