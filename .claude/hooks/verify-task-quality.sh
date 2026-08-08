#!/bin/bash
# Harness - TaskCompleted quality gate hook
# Runs when a teammate marks a task as complete.
# Exit code 0 = accept completion
# Exit code 2 = reject completion, send feedback to teammate
#
# Staged evaluation (inspired by HyperAgents):
#   Stage 1: smoke_test   — fast compile/syntax check, always runs
#   Stage 2: focused_test — the targeted feature's own recorded test_file,
#            run only when the feature records one AND the project's init.sh
#            supports the focused_test target (detected by grepping init.sh
#            for the string; older init.sh scripts stay smoke-only)
# full_test does NOT run here (F101): per-task full suites cost minutes per
# checkpoint and let unrelated red (e.g. an aggregate coverage bar owned by a
# sibling feature) jam every completion. The full suite is enforced where it
# decides something: the passing-flip commit gate (commit-gate.sh, F102) and
# the lead's session-end/synthesis runs.
# correction_cycles is incremented in features.json only when the failing
# stage was green on the previous recorded run (F103 -- see _gate_baseline).
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

# F103: correction_cycles counts only green-to-red transitions. Every stage
# outcome is recorded in .harness/last_gate.json (advisory baseline state,
# gitignored; deliberately PERSISTS across sessions and is never cleared by
# any hook -- a red gate left at session end must not charge the next
# session's first completer); a failure increments only when that same
# stage's previously recorded outcome was "pass". An unknown baseline -- first run, missing or
# corrupt file -- records the verdict but never increments: a red gate
# inherited from earlier work is not a correction cycle, and manufactured
# attribution is worse than missing attribution (four false increments
# observed live in portage-curator before this rule). Every key is
# per-feature -- "smoke:<feature>", "focused:<feature>",
# "coverage:<feature>" -- because the smoke stage tests the whole project:
# a green smoke recorded by feature A's run must not arm the counter for
# feature B, whose later smoke failure may be inherited breakage rather
# than its own (PR #154 review, finding 3; under Agent Teams the
# multi-feature interleave is the common case). An untargeted run (no
# feature_id) keys plain "smoke", which no feature-targeted run consults.
# Best-effort like the rest of the bookkeeping: the write is a single
# atomic os.replace with no cross-process lock (a lost update between two
# concurrent TaskCompleted hooks costs at most one advisory count, never a
# verdict), and any failure here is noted on stderr without changing the
# accept/reject decision.
GATE_BASELINE_FILE=".harness/last_gate.json"
SMOKE_KEY="smoke${FEATURE_ID:+:$FEATURE_ID}"
_gate_baseline() {
    # Args: one or more "key=outcome" pairs (outcome: pass|fail|drop).
    # Records pass/fail pairs; "drop" DELETES the key (F105: a baseline
    # entry exists only while its stage is genuinely being exercised --
    # a stage the hook reached and found unconfigured must not leave an
    # arbitrarily old pass behind to arm a future increment). Prints
    # "increment" when any fail pair transitioned from a recorded "pass".
    python3 - "$GATE_BASELINE_FILE" "$@" <<'PYEOF'
import json
import os
import sys

path = sys.argv[1]
pairs = sys.argv[2:]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
increment = False
for pair in pairs:
    key, _, outcome = pair.rpartition("=")
    if not key or outcome not in ("pass", "fail", "drop"):
        continue
    if outcome == "drop":
        data.pop(key, None)
        continue
    if outcome == "fail" and data.get(key) == "pass":
        increment = True
    data[key] = outcome
tmp = f"{path}.{os.getpid()}.tmp"
try:
    # Serializes to a string first, never json.dump-to-file: the hs suite
    # pins that direct-to-file dumping appears only in
    # harness_state.py.template (features.json's single write path); this
    # writes last_gate.json, a different file, but stays legible to that pin.
    with open(tmp, "w") as fh:
        fh.write(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, path)
except OSError as exc:
    print(f"verify-task-quality: could not write {path}: {exc}", file=sys.stderr)
    try:
        os.remove(tmp)
    except OSError:
        pass
if increment:
    print("increment")
PYEOF
}

# Shared rejection bookkeeping: records the failing stage's verdict, notes a
# missing feature_id (diagnostics for the blocked teammate -- their task
# metadata or subject should carry one), and increments correction_cycles
# only on a green-to-red transition for a targeted feature.
_reject_bookkeeping() {
    if [ -z "$FEATURE_ID" ]; then
        echo "verify-task-quality: no feature_id in task metadata or subject;" \
             "skipping the correction_cycles update." >&2
    fi
    BASELINE=$(_gate_baseline "$@" || true)
    if [ "$BASELINE" = "increment" ] && [ -n "$FEATURE_ID" ]; then
        increment_correction_cycles
    fi
}

# Coverage target gate, claim-matched proof warning, stale-in-progress
# reminder, and the focused-test lookup all read .harness/features.json --
# one load, one process, feeding all four consumers, instead of independent
# python3 subprocesses each re-opening and re-parsing the same file. Runs
# BEFORE the test stages (F101) because Stage 2 needs the targeted feature's
# test_file; nothing here mutates the file, so the early read changes no
# behavior for the later checks.
COVERAGE_RESULT=""
PROOF_WARNING=""
IN_PROGRESS=0
TEST_FILE=""
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
# Prints "pass" when the gate was evaluated and met (F103 needs "evaluated
# and green" as a distinct outcome from "not evaluated" to record the
# coverage baseline), "achieved|target" when evaluated and missed, "" when
# not evaluated at all.
coverage_result = ""
if match is not None:
    coverage = match.get("coverage")
    if isinstance(coverage, (int, float)) and not isinstance(coverage, bool):
        target = match.get("coverage_target")
        if not isinstance(target, int) or isinstance(target, bool):
            target = 95
        coverage_result = "pass" if coverage >= target else f"{coverage}|{target}"
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

# Focused-test lookup (F101): the targeted feature's own recorded test_file,
# consumed by Stage 2. Empty when the feature is unmatched or records none.
test_file = ""
if match is not None:
    candidate = match.get("test_file")
    if isinstance(candidate, str):
        test_file = candidate
print(test_file)
PYEOF
)
    COVERAGE_RESULT=$(printf '%s\n' "$_CHECKS" | sed -n '1p')
    PROOF_WARNING=$(printf '%s\n' "$_CHECKS" | sed -n '2p')
    IN_PROGRESS=$(printf '%s\n' "$_CHECKS" | sed -n '3p')
    TEST_FILE=$(printf '%s\n' "$_CHECKS" | sed -n '4p')
    [ -n "$IN_PROGRESS" ] || IN_PROGRESS=0
fi

# Stage 1: Smoke test (fast compile/syntax check)
echo "Stage 1: Smoke test..." >&2
SMOKE_OUTPUT=$(bash .harness/init.sh smoke_test 2>&1) || {
    echo "Task rejected: smoke test failed. Fix compilation errors before marking complete." >&2
    echo "" >&2
    echo "Smoke test output:" >&2
    echo "$SMOKE_OUTPUT" | tail -20 >&2
    _reject_bookkeeping "$SMOKE_KEY=fail"
    _dashboard_log "block" "smoke-test-failed" || true
    exit 2
}

# Stage 2: the targeted feature's own focused test. Support is detected by
# grepping init.sh's NON-COMMENT lines for the target name rather than
# probing an invocation -- an older init.sh answers an unknown target with
# its own error exit, which would be indistinguishable from a real test
# failure here. Comment lines are stripped first (PR #154 review, follow-up
# 3): a script that only MENTIONS focused_test in a header comment would
# otherwise be probed and have its unknown-target error read as a failure,
# recreating exactly the confusion this detection exists to avoid.
# FOCUSED_BASELINE_ARG carries this run's verdict for the focused stage
# into the later _gate_baseline calls: pass when it ran green, drop (F105)
# when the hook reached this point and found the stage unconfigured for the
# targeted feature (no test_file, or no focused_test support). A drop only
# happens HERE -- an earlier-stage failure exits before this point, so a
# baseline is never erased by mere ordering. Empty when there is no
# targeted feature to key.
FOCUSED_BASELINE_ARG=""
if [ -n "$FEATURE_ID" ]; then
    FOCUSED_BASELINE_ARG="focused:$FEATURE_ID=drop"
fi
if [ -n "$TEST_FILE" ]; then
    if grep -v '^[[:space:]]*#' .harness/init.sh 2>/dev/null | grep -q "focused_test"; then
        echo "Stage 2: Focused test ($TEST_FILE)..." >&2
        FOCUSED_RC=0
        FOCUSED_OUTPUT=$(bash .harness/init.sh focused_test "$TEST_FILE" 2>&1) || FOCUSED_RC=$?
        if [ "$FOCUSED_RC" -eq 3 ]; then
            # F106 skip protocol: exit 3 means init.sh skipped the stage
            # (no per-file runner for the stack, or the test file doesn't
            # exist) -- not-run, never a fake green. FOCUSED_BASELINE_ARG
            # stays at its F105 drop default, so no baseline is recorded
            # and a later real failure has nothing stale to charge against.
            # init.sh's own output is surfaced (PR #156 review): if a skip
            # is ever wrong, the operator sees the runner's real output
            # instead of only this hook's explanation.
            echo "verify-task-quality: focused test skipped by init.sh (exit 3);" \
                 "accepting on smoke alone, no focused baseline recorded." >&2
            echo "Skip output (last 5 lines):" >&2
            echo "$FOCUSED_OUTPUT" | tail -5 >&2
        elif [ "$FOCUSED_RC" -ne 0 ]; then
            echo "Task rejected: focused test failed ($TEST_FILE). Fix the failures before marking complete." >&2
            echo "" >&2
            echo "Focused test output (last 20 lines):" >&2
            echo "$FOCUSED_OUTPUT" | tail -20 >&2
            _reject_bookkeeping "$SMOKE_KEY=pass" "focused:$FEATURE_ID=fail"
            _dashboard_log "block" "focused-test-failed" || true
            exit 2
        else
            FOCUSED_BASELINE_ARG="focused:$FEATURE_ID=pass"
        fi
    else
        echo "verify-task-quality: this project's .harness/init.sh does not support focused_test;" \
             "skipping the focused stage ($TEST_FILE). Adopt the focused_test target to enable it." >&2
    fi
fi

# COVERAGE_BASELINE_ARG mirrors FOCUSED_BASELINE_ARG: pass when evaluated
# and met, drop (F105) when the gate was reached but coverage is not
# numeric for the targeted feature -- the stage stopped existing, so its
# old baseline must not linger.
COVERAGE_BASELINE_ARG=""
if [ -n "$FEATURE_ID" ]; then
    COVERAGE_BASELINE_ARG="coverage:$FEATURE_ID=drop"
fi
if [ "$COVERAGE_RESULT" = "pass" ]; then
    COVERAGE_BASELINE_ARG="coverage:$FEATURE_ID=pass"
elif [ -n "$COVERAGE_RESULT" ]; then
    ACHIEVED="${COVERAGE_RESULT%%|*}"
    TARGET="${COVERAGE_RESULT##*|}"
    echo "Task rejected: coverage $ACHIEVED% is below the target $TARGET%." >&2
    _reject_bookkeeping "$SMOKE_KEY=pass" \
        ${FOCUSED_BASELINE_ARG:+"$FOCUSED_BASELINE_ARG"} \
        "coverage:$FEATURE_ID=fail"
    _dashboard_log "block" "coverage-below-target" || true
    exit 2
fi

# Accept path: record every stage that actually ran as green (re-arming the
# green-to-red attribution) and drop the keys of stages that turned out to
# be unconfigured this run.
_gate_baseline "$SMOKE_KEY=pass" \
    ${FOCUSED_BASELINE_ARG:+"$FOCUSED_BASELINE_ARG"} \
    ${COVERAGE_BASELINE_ARG:+"$COVERAGE_BASELINE_ARG"} >/dev/null || true

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
