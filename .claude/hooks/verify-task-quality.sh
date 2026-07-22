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

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
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

# Increment correction_cycles for all in-progress features.
# This tracks how many times the quality gate rejected completion —
# useful for retrospectives and dynamic model selection.
increment_correction_cycles() {
    if [ -f ".harness/features.json" ]; then
        python3 - "$FEATURE_ID" <<'PYEOF'
import json, sys
target_id = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
try:
    with open('.harness/features.json', 'r') as f:
        data = json.load(f)
    changed = False
    for feature in data.get('features', []):
        if feature.get('status') == 'in-progress':
            if target_id is None or feature.get('id') == target_id:
                feature['correction_cycles'] = feature.get('correction_cycles', 0) + 1
                changed = True
    if changed:
        with open('.harness/features.json', 'w') as f:
            json.dump(data, f, indent=2)
except Exception as e:
    pass  # Don't fail the hook on JSON errors
PYEOF
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
