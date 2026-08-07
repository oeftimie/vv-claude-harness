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

# F089: opt-in dashboard event log for this gate's block/allow verdicts.
# Duplicates hooks/dashboard-log.sh's (F088) JSON-line schema and
# redaction/atomicity conventions inline -- a project-level hook installed
# into .claude/hooks/ cannot reach a plugin-root file. Never aborts the
# gate: every risky step below is guarded, and every call site is itself
# suffixed with `|| true` -- critical under this script's own
# `set -euo pipefail`.
_dashboard_log() {
    [ "${VV_HARNESS_DASHBOARD:-}" = "1" ] || return 0
    [ -d ".harness" ] || return 0
    local verdict="$1" finding="${2:-}" session_id
    session_id=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("session_id") or "")
except Exception:
    pass
' 2>/dev/null || true)
    session_id=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9._-' | cut -c1-64)
    [ -n "$session_id" ] || return 0
    mkdir -p ".harness/dashboard" 2>/dev/null || return 0
    # F089 round 2 (adversarial review): the JSON payload is fed via STDIN,
    # never argv -- a large payload on argv can exceed the OS's exec()
    # argument-list size limit (~1MB on macOS, as low as 128KB per-argument
    # on Linux), which fails this whole call silently (it's `|| true`) and
    # drops the event with no error surfaced anywhere. Only small, bounded
    # values (the log path, session id, verdict, finding) stay on argv.
    #
    # The python source is read into a variable via a TOP-LEVEL heredoc
    # (F094 round 2), NOT `python3 -c "$(cat <<'PYEOF' ...)"` -- a heredoc
    # nested inside a DOUBLE-QUOTED command substitution parses fine under
    # bash 5.x but fails `bash -n` outright under real bash 3.2.57 (this
    # repo's own declared minimum) whenever the heredoc body's own single-
    # quote count is odd: bash 3.2's lexer still scans the heredoc BODY for
    # quote balance while looking for the closing double-quote of the
    # substitution, even though heredoc content isn't supposed to be
    # subject to quote-parity rules at all. Invisible under Homebrew bash
    # (5.x) on PATH, which is exactly why it shipped uncaught -- and because
    # this function is defined at file-load time, unconditionally, a parse
    # failure here breaks the ENTIRE gate script for every stock-bash user,
    # not just one gated behind VV_HARNESS_DASHBOARD (bash must successfully
    # PARSE the whole file before any runtime check, including that env-var
    # gate, ever executes).
    IFS= read -r -d '' _DASHBOARD_LOG_PY <<'PYEOF' || true
import json
import sys
import time

log_path, session_id, verdict, finding = sys.argv[1:5]
stdin_json = sys.stdin.read()
try:
    try:
        data = json.loads(stdin_json)
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    line = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "hook_event_name": data.get("hook_event_name", ""),
        "session_id": session_id,
        "gate": "verify-task-quality",
        "verdict": verdict,
    }
    if finding:
        line["finding"] = finding
    for key in ("agent_id", "agent_type"):
        value = data.get(key)
        if value:
            line[key] = value
    with open(log_path, "a") as fh:
        fh.write(json.dumps(line) + "\n")
except Exception:
    pass
PYEOF
    printf '%s' "$INPUT" | python3 -c "$_DASHBOARD_LOG_PY" \
        ".harness/dashboard/$session_id.jsonl" "$session_id" "$verdict" "$finding" \
        >/dev/null 2>/dev/null || true
}

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
    _dashboard_log "block" "missing-init-script" || true
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
    # No `2>&1` here (PR #120 round-1 review, NIT-2): harness_state.py
    # already writes every diagnostic to its own stderr; merging that onto
    # this function's stdout would bury it, since Claude Code discards a
    # hook's stdout entirely on exit 2 (see the header comment above) and
    # every call site of this function is on the exit-2 rejection path.
    python3 "$STATE_MODULE" increment-correction-cycles .harness/features.json "$FEATURE_ID" \
        || true
}

# Stage 1: Smoke test (fast compile/syntax check)
echo "Stage 1: Smoke test..." >&2
SMOKE_OUTPUT=$(bash .harness/init.sh smoke_test 2>&1) || {
    echo "Task rejected: smoke test failed. Fix compilation errors before marking complete." >&2
    echo "" >&2
    echo "Smoke test output:" >&2
    echo "$SMOKE_OUTPUT" | tail -20 >&2
    increment_correction_cycles
    _dashboard_log "block" "smoke-test-failed" || true
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
    _dashboard_log "block" "tests-failing" || true
    exit 2
}

# Coverage target gate, claim-matched proof warning, and stale-in-progress
# reminder all read .harness/features.json -- one load, one process, feeding
# all three checks below, instead of three independent python3 subprocesses
# each re-opening and re-parsing the same file.
COVERAGE_RESULT=""
PROOF_WARNING=""
IN_PROGRESS=0
if [ -f ".harness/features.json" ]; then
    _CHECKS=$(python3 - ".harness/features.json" "$FEATURE_ID" <<'PYEOF'
import json
import sys

path, feature_id = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)
features = data.get("features", [])
match = next((f for f in features if f.get("id") == feature_id), None) if feature_id else None

# Coverage target gate: compare the targeted feature's own recorded `coverage`
# number against its `coverage_target` (falls back to 95). Skipped entirely when
# coverage isn't a number yet (e.g. this repo's own descriptive strings) --
# proportional: don't punish projects without numeric coverage tooling.
coverage_result = ""
if match is not None:
    coverage = match.get("coverage")
    if isinstance(coverage, (int, float)) and not isinstance(coverage, bool):
        target = match.get("coverage_target")
        if not isinstance(target, int) or isinstance(target, bool):
            target = 95
        if coverage < target:
            coverage_result = f"{coverage}|{target}"
print(coverage_result)

# Claim-matched proof: warn (never block) when this feature accepts with no
# proof recorded, or with proof whose evidence_type doesn't match its declared
# qa_binding. Reads both fields directly off the feature object -- no external
# lookup, no re-parsing of prose.
proof_warning = ""
if match is not None:
    proof = match.get("proof")
    qa_binding = match.get("qa_binding")
    if not proof:
        proof_warning = f"WARN: {feature_id} accepted with no proof recorded."
    elif qa_binding and proof.get("evidence_type") != qa_binding:
        proof_warning = (
            f"WARN: {feature_id}'s proof.evidence_type "
            f"'{proof.get('evidence_type')}' does not match its declared "
            f"qa_binding '{qa_binding}'. Fix the proof or the binding."
        )
print(proof_warning)

# Remind about stale in-progress features. Matches the original's exact
# f['status'] indexing (not .get) and its own fallback: any exception here
# (e.g. a feature missing "status" entirely) defaults the count to 0, same
# as the previous "python3 ... 2>/dev/null || echo 0" bash-level fallback.
try:
    in_progress = len([f for f in features if f['status'] == 'in-progress'])
except Exception:
    in_progress = 0
print(in_progress)
PYEOF
)
    COVERAGE_RESULT=$(printf '%s\n' "$_CHECKS" | sed -n '1p')
    PROOF_WARNING=$(printf '%s\n' "$_CHECKS" | sed -n '2p')
    IN_PROGRESS=$(printf '%s\n' "$_CHECKS" | sed -n '3p')
    [ -n "$IN_PROGRESS" ] || IN_PROGRESS=0
fi

if [ -n "$COVERAGE_RESULT" ]; then
    ACHIEVED="${COVERAGE_RESULT%%|*}"
    TARGET="${COVERAGE_RESULT##*|}"
    echo "Task rejected: coverage $ACHIEVED% is below the target $TARGET%." >&2
    increment_correction_cycles
    _dashboard_log "block" "coverage-below-target" || true
    exit 2
fi

IN_PROGRESS_NOTE=""
if [ "$IN_PROGRESS" -gt 0 ]; then
    IN_PROGRESS_NOTE="Note: $IN_PROGRESS feature(s) still marked in-progress. Update features.json if your feature is complete."
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

_dashboard_log "allow" || true
exit 0
