#!/bin/bash
# Harness - TaskCompleted quality gate hook
# Runs when a teammate marks a task as complete.
# Exit code 0 = accept completion
# Exit code 2 = reject completion, send feedback to teammate
#
# Staged evaluation (inspired by HyperAgents):
#   Stage 1: smoke_test — fast compile/syntax check
#   Stage 2: full_test  — complete suite with coverage
# Failing at Stage 1 avoids the cost of a full test run.
# correction_cycles is incremented in features.json on any rejection.
# Formatting: this hook's features.json writes own indent=2, a trailing
# newline, and atomic replacement (.tmp + mv); only the targeted feature
# is modified.
# Failure posture: fail-closed for the core gate -- a missing .harness/init.sh or any
# smoke/full test failure rejects completion (exit 2). Fail-open/best-effort for the
# correction_cycles bookkeeping side effect: a harness_state.py write failure there is
# noted on stderr but never changes the accept/reject verdict.

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT_ROOT"

# Read hook input from stdin
INPUT=$(cat)

# Try to extract feature ID from task metadata (if TaskCreate used metadata.feature_id)
FEATURE_ID=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Check task metadata first, then fall back to parsing task subject for 'FXXX:'
metadata = data.get('task', {}).get('metadata', {})
feature_id = metadata.get('feature_id', '')
if not feature_id:
    subject = data.get('task', {}).get('subject', '')
    if ':' in subject:
        candidate = subject.split(':')[0].strip()
        if candidate.startswith('F') and candidate[1:].isdigit():
            feature_id = candidate
print(feature_id)
" 2>/dev/null || echo "")

if [ ! -f ".harness/init.sh" ]; then
    echo "Task rejected: .harness/init.sh not found. Cannot verify tests pass."
    echo "Run /harness-init to create the test script, or create it manually."
    exit 2
fi

# Increment correction_cycles for the targeted in-progress feature via the
# shared state module. This tracks how many times the quality gate rejected
# completion — useful for retrospectives and dynamic model selection.
STATE_MODULE=".claude/hooks/harness_state.py"
increment_correction_cycles() {
    if [ -z "$FEATURE_ID" ]; then
        echo "verify-task-quality: no feature_id in task metadata or subject;" \
             "skipping the correction_cycles update." >&2
        return 0
    fi
    if [ ! -f ".harness/features.json" ]; then
        return 0
    fi
    # Clear any tmp orphaned by an earlier killed run: the guarded mv below
    # must only ever promote a tmp that THIS invocation wrote.
    rm -f .harness/features.json.tmp
    python3 "$STATE_MODULE" increment-correction-cycles .harness/features.json "$FEATURE_ID" \
        2>&1 || true
    if [ -f ".harness/features.json.tmp" ]; then
        mv .harness/features.json.tmp .harness/features.json
    fi
}

# Stage 1: Smoke test (fast compile/syntax check)
echo "Stage 1: Smoke test..." >&2
SMOKE_OUTPUT=$(bash .harness/init.sh smoke_test 2>&1) || {
    echo "Task rejected: smoke test failed. Fix compilation errors before marking complete."
    echo ""
    echo "Smoke test output:"
    echo "$SMOKE_OUTPUT" | tail -20
    increment_correction_cycles
    exit 2
}

# Stage 2: Full test suite
echo "Stage 2: Full test suite..." >&2
FULL_OUTPUT=$(bash .harness/init.sh full_test 2>&1) || {
    echo "Task rejected: tests are failing. Fix the failures before marking complete."
    echo ""
    echo "Test output (last 20 lines):"
    echo "$FULL_OUTPUT" | tail -20
    increment_correction_cycles
    exit 2
}

# Coverage target gate: compare the targeted feature's own recorded `coverage`
# number against its `coverage_target` (falls back to 95). Skipped entirely when
# coverage isn't a number yet (e.g. this repo's own descriptive strings) --
# proportional: don't punish projects without numeric coverage tooling.
if [ -n "$FEATURE_ID" ] && [ -f ".harness/features.json" ]; then
    COVERAGE_RESULT=$(python3 - ".harness/features.json" "$FEATURE_ID" <<'PYEOF'
import json
import sys

path, feature_id = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)
match = next((f for f in data.get("features", []) if f.get("id") == feature_id), None)
if match is None:
    sys.exit(0)
coverage = match.get("coverage")
if not isinstance(coverage, (int, float)) or isinstance(coverage, bool):
    sys.exit(0)
target = match.get("coverage_target")
if not isinstance(target, int) or isinstance(target, bool):
    target = 95
if coverage < target:
    print(f"{coverage}|{target}")
PYEOF
)
    if [ -n "$COVERAGE_RESULT" ]; then
        ACHIEVED="${COVERAGE_RESULT%%|*}"
        TARGET="${COVERAGE_RESULT##*|}"
        echo "Task rejected: coverage $ACHIEVED% is below the target $TARGET%."
        increment_correction_cycles
        exit 2
    fi
fi

# Claim-matched proof: warn (never block) when this feature accepts with no
# proof recorded, or with proof whose evidence_type doesn't match its declared
# qa_binding. Reads both fields directly off the feature object -- no external
# lookup, no re-parsing of prose.
if [ -n "$FEATURE_ID" ] && [ -f ".harness/features.json" ]; then
    PROOF_WARNING=$(python3 - ".harness/features.json" "$FEATURE_ID" <<'PYEOF'
import json
import sys

path, feature_id = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)
match = next((f for f in data.get("features", []) if f.get("id") == feature_id), None)
if match is None:
    sys.exit(0)
proof = match.get("proof")
qa_binding = match.get("qa_binding")
if not proof:
    print(f"WARN: {feature_id} accepted with no proof recorded.")
elif qa_binding and proof.get("evidence_type") != qa_binding:
    print(
        f"WARN: {feature_id}'s proof.evidence_type "
        f"'{proof.get('evidence_type')}' does not match its declared "
        f"qa_binding '{qa_binding}'. Fix the proof or the binding."
    )
PYEOF
)
    [ -n "$PROOF_WARNING" ] && echo "$PROOF_WARNING"
fi

# Remind about stale in-progress features
if [ -f ".harness/features.json" ]; then
    IN_PROGRESS=$(python3 -c "
import json, sys
with open('.harness/features.json') as f:
    data = json.load(f)
in_progress = [f for f in data.get('features', []) if f['status'] == 'in-progress']
print(len(in_progress))
" 2>/dev/null || echo "0")
    if [ "$IN_PROGRESS" -gt 0 ]; then
        echo "Note: $IN_PROGRESS feature(s) still marked in-progress. Update features.json if your feature is complete."
    fi
fi

# All checks passed
exit 0
