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
# Formatting: harness_state.py owns the write (indent=2, trailing newline,
# atomic replace via a file lock + PID-suffixed tmp + os.replace, see its
# own _with_file_lock/_write_atomic); only the targeted feature is modified.
# Failure posture: fail-closed for the core gate -- a missing .harness/init.sh or any
# smoke/full test failure rejects completion (exit 2). Fail-open/best-effort for the
# correction_cycles bookkeeping side effect: a harness_state.py write failure there is
# noted on stderr but never changes the accept/reject verdict.

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT_ROOT"

# Read hook input from stdin
INPUT=$(cat)

# Try to extract feature ID from task metadata (if TaskCreate used
# metadata.feature_id). The JSON parse is in its OWN try/except (exit 2 on
# failure); extracting/printing the field is a SEPARATE try/except that
# exits 1 instead (F050, the identical two-stage split F043 wrote for
# enforce-scope.sh.template) -- a raw lone UTF-16 surrogate in the input
# JSON parses fine but crashes the final print() with UnicodeEncodeError,
# and the old single `2>/dev/null || echo ""` swallowed that the same way
# it swallows a genuinely absent feature_id. Unlike enforce-scope.sh.template
# and commit-gate.sh.template, a crash here does NOT gain any new blocking
# power: this hook's own documented posture is fail-open/best-effort for the
# correction_cycles bookkeeping (a missing feature_id already just skips the
# update, "noted on stderr" below, never changes the accept/reject verdict),
# and the coverage gate itself is separately self-reported and already
# trivially skippable via a bogus or omitted feature_id -- closing the
# surrogate specifically here would be a false sense of soundness, not a
# real fix, without addressing that broader gap too (out of scope for this
# feature). The two-stage split is applied anyway for consistency and so a
# crash-during-extraction is distinguishable (via its own stderr note) from
# a genuinely absent feature_id, rather than because it changes the gate.
FEATURE_ID=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(2)
try:
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
except Exception:
    sys.exit(1)
" 2>/dev/null) || FEATURE_ID_RC=$?
FEATURE_ID_RC="${FEATURE_ID_RC:-0}"
if [ "$FEATURE_ID_RC" -eq 1 ]; then
    echo "verify-task-quality: feature_id could not be safely extracted from task metadata;" \
         "skipping the correction_cycles update." >&2
    FEATURE_ID=""
fi

if [ ! -f ".harness/init.sh" ]; then
    # Claude Code discards a hook's stdout entirely on exit 2 and feeds only
    # stderr back to the blocked agent as its error message
    # (code.claude.com/docs/en/hooks) -- this and the other three exit-2
    # sites below wrote their rejection message to stdout, silently
    # discarding it on every real TaskCompleted rejection (F053, the
    # identical defect F046 fixed in check-remaining-tasks.sh.template).
    echo "Task rejected: .harness/init.sh not found. Cannot verify tests pass." >&2
    echo "Run /harness-init to create the test script, or create it manually." >&2
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
    # harness_state.py now owns the entire read-modify-write-rename cycle
    # itself (file-locked, PID-suffixed tmp, os.replace) -- see its own
    # _with_file_lock/_write_atomic. This wrapper used to rm -f a shared
    # .tmp name and mv it into place after the fact, which raced under
    # parallel TaskCompleted invocations (OVI-107): one invocation could
    # delete another's in-flight tmp, or the whole-file mv could clobber a
    # concurrent edit. There is nothing left for this shell wrapper to do
    # but invoke the module and stay fail-open on its exit code, matching
    # this hook's documented posture for the correction_cycles side effect.
    python3 "$STATE_MODULE" increment-correction-cycles .harness/features.json "$FEATURE_ID" \
        2>&1 || true
}

# Stage 1: Smoke test (fast compile/syntax check)
echo "Stage 1: Smoke test..." >&2
SMOKE_OUTPUT=$(bash .harness/init.sh smoke_test 2>&1) || {
    echo "Task rejected: smoke test failed. Fix compilation errors before marking complete." >&2
    echo "" >&2
    echo "Smoke test output:" >&2
    echo "$SMOKE_OUTPUT" | tail -20 >&2
    increment_correction_cycles
    exit 2
}

# Stage 2: Full test suite
echo "Stage 2: Full test suite..." >&2
FULL_OUTPUT=$(bash .harness/init.sh full_test 2>&1) || {
    echo "Task rejected: tests are failing. Fix the failures before marking complete." >&2
    echo "" >&2
    echo "Test output (last 20 lines):" >&2
    echo "$FULL_OUTPUT" | tail -20 >&2
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
        echo "Task rejected: coverage $ACHIEVED% is below the target $TARGET%." >&2
        increment_correction_cycles
        exit 2
    fi
fi

# Claim-matched proof: warn (never block) when this feature accepts with no
# proof recorded, or with proof whose evidence_type doesn't match its declared
# qa_binding. Reads both fields directly off the feature object -- no external
# lookup, no re-parsing of prose.
PROOF_WARNING=""
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
fi

# Remind about stale in-progress features
IN_PROGRESS_NOTE=""
if [ -f ".harness/features.json" ]; then
    IN_PROGRESS=$(python3 -c "
import json, sys
with open('.harness/features.json') as f:
    data = json.load(f)
in_progress = [f for f in data.get('features', []) if f['status'] == 'in-progress']
print(len(in_progress))
" 2>/dev/null || echo "0")
    if [ "$IN_PROGRESS" -gt 0 ]; then
        IN_PROGRESS_NOTE="Note: $IN_PROGRESS feature(s) still marked in-progress. Update features.json if your feature is complete."
    fi
fi

# All checks passed. Claude Code's own hooks docs (code.claude.com/docs/en/hooks)
# say TaskCompleted is not one of the three exit-0 exceptions (UserPromptSubmit,
# UserPromptExpansion, SessionStart) where stdout is shown as context -- "for
# most events, stdout is written to the debug log but not shown in the
# transcript," confirmed via direct fetch for TaskCompleted specifically before
# writing this fix (F057, raised as a sibling investigation to F046/F053's
# identical exit-2 stdout-discard defect, but on this exit-0 accept path
# instead). The two warnings above used to reach this point via plain `echo`
# (stdout), which this docs page says lands only in the debug log for
# TaskCompleted -- a teammate accepting a task with no proof recorded, or with
# a stale in-progress sibling feature, never actually saw either warning. The
# same docs page documents `systemMessage` as a universal JSON output field
# ("warning message shown to the user") that IS surfaced regardless of event
# or exit code -- unlike `additionalContext`, which is delivered via
# hookSpecificOutput and is documented only for a specific set of events
# (SessionStart, Setup, SubagentStart, UserPromptSubmit, UserPromptExpansion,
# PreToolUse, PostToolUse, PostToolUseFailure, PostToolBatch, Stop,
# SubagentStop) that does not include TaskCompleted -- it would silently
# no-op here. Both warnings are combined into ONE systemMessage (not two
# separate echoes) since only a single JSON object can be emitted per hook
# invocation.
SYSTEM_MESSAGE=""
if [ -n "$PROOF_WARNING" ] && [ -n "$IN_PROGRESS_NOTE" ]; then
    SYSTEM_MESSAGE="$PROOF_WARNING"$'\n'"$IN_PROGRESS_NOTE"
elif [ -n "$PROOF_WARNING" ]; then
    SYSTEM_MESSAGE="$PROOF_WARNING"
elif [ -n "$IN_PROGRESS_NOTE" ]; then
    SYSTEM_MESSAGE="$IN_PROGRESS_NOTE"
fi

if [ -n "$SYSTEM_MESSAGE" ]; then
    python3 -c "
import json
import sys

print(json.dumps({\"systemMessage\": sys.argv[1]}))
" "$SYSTEM_MESSAGE"
fi

exit 0
