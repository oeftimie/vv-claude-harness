#!/usr/bin/env bash
# SessionStart hook: injects harness orientation into model context for harness projects.
# Plain stdout reaches the model (capped at 10,000 chars). Always exits 0; never blocks.
# Hard invariant, enforced mechanically: this file must NEVER contain the literal
# lowercase substring naming the per-session telemetry directory under .harness/
# (checked by /harness-doctor's non-injection check and a permanent regression
# test in test/run-tests.sh; see harness-continue's Session End step and its
# linked review-cadence rule for what that directory is and why).
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
H="$ROOT/.harness"
[ -d "$H" ] || exit 0

STDIN_JSON=$(cat 2>/dev/null || true)
# One parse of STDIN_JSON for both fields, separated by an ASCII Record
# Separator (0x1e) rather than a newline: session_id is untrusted and may
# itself carry embedded newlines (see the sanitization comment below), so a
# newline-delimited split would silently truncate it at its own first
# embedded newline.
FIELD_SEP=$'\x1e'
PARSED=$(printf '%s' "$STDIN_JSON" | python3 -c '
import json, sys
source, session_id = "", ""
try:
    data = json.load(sys.stdin)
    source = data.get("source", "")
    session_id = data.get("session_id") or ""
except Exception:
    pass
sys.stdout.write(f"{source}\x1e{session_id}")
' 2>/dev/null || true)
SOURCE=${PARSED%%$FIELD_SEP*}
SESSION_ID=${PARSED#*$FIELD_SEP}
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

# F097: the per-section budgets below (print_budgeted_block, the description/
# scope truncation in print_next_claimable_line) each bound one block in
# isolation, but nothing ever measured their SUM against the platform's
# 10,000-char cap (line 3) -- three PR #128 commits chased that sum by hand
# (2000 -> broke on real content -> recalibrated to 2600 -> a later review
# found even that constant was a judgment call, not a derived bound) and the
# rule-pointer block's own comment admits its length still varies 1800-2900
# chars with CLAUDE_PLUGIN_ROOT's install path. Buffering the whole body in
# this subshell and measuring $ORIENTATION's actual length below turns "we
# hope the sum of hand-tuned constants stays under 10,000" into a mechanically
# guaranteed invariant, additive to (not a replacement for) the per-section
# budgets kept for readability/prioritization.
ORIENTATION=$(
if [ "$SOURCE" = "compact" ]; then
  echo "## Compaction recovery"
  echo "Context was just compacted. Re-read the Active Context section of"
  echo ".harness/context_summary.md and the task list (TaskList) before continuing work."
  echo ""
fi

echo "## Harness orientation (auto-injected)"

[ -n "$SESSION_ID" ] && echo "Session: $SESSION_ID"

# OVI-105 (total output budget): SESSION_INCOMPLETE, claude-progress.txt, and
# context_summary.md's Active Context are each capped by LINE count (head -15,
# tail -12, head -20), which bounds nothing if the lines themselves are long --
# a single pathological or just-unusually-verbose line can still push the whole
# script's stdout toward the 10,000-char platform cap (line 3 above). This
# truncates each block's CHARACTER count too, same truncate-and-point pattern
# already used for a feature's description below, so no single section can
# consume the budget the sections after it need.
#
# Round-1 review (review-pr128-f079) caught the first value (2000) truncating
# THIS repo's own real Active Context (measured at 2422 chars) on ordinary,
# already-shipped content -- not a pathological case, an active regression.
# Recalibrated against a direct measurement of "everything else" (features
# count, next-claimable, git-identity check, all 6 rule pointers): roughly
# 1800-2900 chars depending on the installed CLAUDE_PLUGIN_ROOT path length
# (echoed 6 times, once per rule pointer) and whether any of the several
# optional WARNING blocks fire. Round-2 review measured the deployed-path
# margin at ~480 chars in the ordinary case, not a fixed number -- this
# constant is a judgment call sized to comfortably fit today's real Active
# Context (2422) with room for near-term growth, not a value with an exact
# derived margin against the platform's 10,000-char hard cap.
BLOCK_CHAR_BUDGET=2600
print_budgeted_block() {
  local content
  content=$(cat)
  local len=${#content}
  if [ "$len" -gt "$BLOCK_CHAR_BUDGET" ]; then
    printf '%s\n' "${content:0:$BLOCK_CHAR_BUDGET}"
    echo "    ... ($len chars total, truncated to fit the orientation budget; see $1 for the full text)"
  else
    printf '%s\n' "$content"
  fi
}

if [ -f "$H/SESSION_INCOMPLETE" ]; then
  echo ""
  echo "WARNING: the previous session ended with unresolved discipline gaps:"
  head -15 "$H/SESSION_INCOMPLETE" 2>/dev/null | sed 's/^/    /' \
    | print_budgeted_block ".harness/SESSION_INCOMPLETE" || true
  echo "Resolve these before starting new work."
fi

echo ""
# STATE_MODULE is the delegate-when-available switch for both blocks below:
# a per-project harness_state.py (v5+ projects) owns the counting/claimable
# algorithms; older projects initialized before that module existed fall back
# to the inline computation.
STATE_MODULE="$ROOT/.claude/hooks/harness_state.py"

# Features passing-count: delegate to harness_state.py's own `counts` verb
# when available instead of reimplementing the same sum-of-passing here.
if [ -f "$STATE_MODULE" ] && [ -f "$H/features.json" ]; then
  COUNTS_RESULT=$(python3 "$STATE_MODULE" counts "$H/features.json" 2>/dev/null || true)
  if [ -n "$COUNTS_RESULT" ]; then
    python3 - "$COUNTS_RESULT" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    data = json.loads(sys.argv[1])
    print(f"Features: {data['passing']}/{data['total']} passing")
except Exception:
    pass
PYEOF
  fi
else
  python3 - "$H/features.json" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    feats = json.load(open(sys.argv[1])).get("features", [])
    passing = sum(1 for f in feats if f.get("status") == "passing")
    print(f"Features: {passing}/{len(feats)} passing")
except Exception:
    pass
PYEOF
fi

# OVI-105: a feature's description is free text with no length cap
# (.harness/features.json has carried descriptions past 13,000 chars in real
# use), and this whole script's stdout is what's capped at 10,000 chars
# reaching the model (line 3 above). Truncating this one field to 200 chars
# protects everything that prints AFTER it -- the git-identity mismatch
# warning and every rule pointer below -- from being silently pushed past
# the cap by one long description. The full text is never lost; it's still
# in features.json, just not echoed whole into every session's orientation.
#
# print_next_claimable_line is the single formatter shared by both the
# harness_state.py-delegated path and the inline fallback below -- each path
# only has to produce a feature's JSON (or the literal "no claimable
# feature") into RESULT; the truncation and "Next claimable: ..." line are
# written once here, not copy-pasted per path.
print_next_claimable_line() {
  python3 - "$1" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    f = json.loads(sys.argv[1])
    scope_list = f.get("scope") or []
    scope = ", ".join(scope_list)
    # F085: scope is the same unbounded-field class as description (382 chars
    # real on this repo, 711 in the suite's 12-path adversarial fixture) --
    # cap it with the same truncate-and-point treatment, marker naming the
    # path count since the full value is a list, not prose.
    SCOPE_LIMIT = 150
    if len(scope) > SCOPE_LIMIT:
        noun = "path" if len(scope_list) == 1 else "paths"
        scope = scope[:SCOPE_LIMIT] + f"... ({len(scope_list)} {noun} total, see .harness/features.json)"
    desc = f.get("description", "")
    DESC_LIMIT = 200
    if len(desc) > DESC_LIMIT:
        full_len = len(desc)
        desc = desc[:DESC_LIMIT] + f"... ({full_len} chars total, see .harness/features.json for the full description)"
    print(f"Next claimable: {f.get('id', '?')} - {desc} (scope: {scope})")
except Exception:
    pass
PYEOF
}

# next-claimable: delegate the algorithm to harness_state.py when a per-project
# copy exists (v5+ projects); fall back to the inline computation otherwise
# (older projects initialized before this module existed).
if [ -f "$STATE_MODULE" ] && [ -f "$H/features.json" ]; then
  RESULT=$(python3 "$STATE_MODULE" next-claimable "$H/features.json" 2>/dev/null || true)
  if [ -n "$RESULT" ] && [ "$RESULT" != "no claimable feature" ]; then
    # unwrap harness_state.py's {"next": {...}, "count": N} down to just the
    # feature, so the fallback branch below and this one feed the same shape
    # into the shared formatter.
    RESULT=$(python3 -c 'import json, sys; print(json.dumps(json.loads(sys.argv[1])["next"]))' \
      "$RESULT" 2>/dev/null || true)
  fi
else
  RESULT=$(python3 - "$H/features.json" <<'PYEOF' 2>/dev/null || true
import json, sys
try:
    feats = json.load(open(sys.argv[1])).get("features", [])
    status = {f.get("id"): f.get("status") for f in feats}
    claimable = [f for f in feats if f.get("status") in ("pending", "failed")
                 and all(status.get(d) == "passing" for d in (f.get("depends_on") or []))]
    claimable.sort(key=lambda f: f.get("priority", 999))
    if claimable:
        print(json.dumps(claimable[0]))
    else:
        print("no claimable feature")
except Exception:
    pass
PYEOF
)
fi

if [ "$RESULT" = "no claimable feature" ]; then
  echo "Next claimable: none (no pending or failed features)"
elif [ -n "$RESULT" ]; then
  print_next_claimable_line "$RESULT"
fi

# F098: spec-drift, scope-armed, and test_file-existence each used to open and
# json.load .harness/features.json in their own python3 process; one load here
# feeds all three, each still in its OWN try/except (not one shared one) so a
# crash in one check can't silently skip the other two the way a single shared
# try/except would -- matching the original's per-block failure isolation.
python3 - "$ROOT" "$H/features.json" <<'PYEOF' 2>/dev/null || true
import hashlib, json, os, sys

root, features_path = sys.argv[1], sys.argv[2]
feats = json.load(open(features_path)).get("features", [])

try:
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

try:
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

# F066: a passing/in-progress feature's test_file is a claim, not a fact -- this
# reproduces doctor.py's check_feature_test_files at session-start scope (cheap,
# same os.path.isfile cost as the spec-drift hash check above) so faithful
# orientation can't hand the session a fabricated picture.
try:
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
  tail -12 "$H/claude-progress.txt" 2>/dev/null | sed 's/^/    /' \
    | print_budgeted_block ".harness/claude-progress.txt" || true
fi

if [ -f "$H/context_summary.md" ]; then
  echo ""
  echo "Active Context (context_summary.md):"
  awk '/## Active Context/{p=1;next} /^## /{p=0} p' "$H/context_summary.md" 2>/dev/null \
    | head -20 | sed 's/^/    /' \
    | print_budgeted_block ".harness/context_summary.md" || true
fi

# One parse of harness.json for both fields.
GIT_IDENTITY=$(python3 -c '
import json, sys
try:
    identity = json.load(open(sys.argv[1])).get("git_identity", {})
    print(identity.get("user_name", ""))
    print(identity.get("user_email", ""))
except Exception:
    pass
' "$H/harness.json" 2>/dev/null || true)
EXPECTED_NAME=$(printf '%s\n' "$GIT_IDENTITY" | sed -n '1p')
EXPECTED_EMAIL=$(printf '%s\n' "$GIT_IDENTITY" | sed -n '2p')
# One git-config call for both fields. --get-regexp lists a match from every
# scope that defines it (system/global/local), lowest priority first, so the
# LAST matching line per key is the effective value -- same as plain
# `git config user.name` -- and must be picked with an END-block, not just
# filtered.
ACTUAL_IDENTITY=$(git config --get-regexp '^user\.(name|email)$' 2>/dev/null || true)
ACTUAL_NAME=$(printf '%s\n' "$ACTUAL_IDENTITY" | awk '$1 == "user.name" {$1=""; sub(/^ /, ""); v=$0} END{print v}')
ACTUAL_EMAIL=$(printf '%s\n' "$ACTUAL_IDENTITY" | awk '$1 == "user.email" {$1=""; sub(/^ /, ""); v=$0} END{print v}')
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
  echo "TDD process: $CLAUDE_PLUGIN_ROOT/rules/tdd.md (read before implementing a feature or bugfix)."
fi
echo "Run /harness-continue for the full interactive flow (mode choice, smoke test, team plan)."
)

ORIENTATION_CHAR_CAP=9800
ORIENTATION_LEN=${#ORIENTATION}
if [ "$ORIENTATION_LEN" -gt "$ORIENTATION_CHAR_CAP" ]; then
  printf '%s\n' "${ORIENTATION:0:$ORIENTATION_CHAR_CAP}"
  echo "... (orientation truncated: $ORIENTATION_LEN chars total, exceeds the ${ORIENTATION_CHAR_CAP}-char safety cap; see .harness/ files directly for full context)"
else
  printf '%s\n' "$ORIENTATION"
fi
exit 0
