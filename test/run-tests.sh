#!/usr/bin/env bash
# Test runner for the vv-harness plugin: hook behavior, manifest lint, agent frontmatter.
# Dependency-free: bash 3.2+, git, python3. Run from anywhere: bash test/run-tests.sh
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
HOOKS_DIR="$REPO_ROOT/hooks"
FIXTURE_SRC="$SCRIPT_DIR/fixtures/harness-project"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vv-harness-tests.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL: $1"
}

assert_contains() {
  case "$1" in
    *"$2"*) pass "$3" ;;
    *) fail "$3 -- output missing: $2" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "$3 -- output unexpectedly contains: $2" ;;
    *) pass "$3" ;;
  esac
}

assert_empty() {
  if [ -z "$1" ]; then pass "$2"; else fail "$2 -- expected empty output, got: $1"; fi
}

assert_rc0() {
  if [ "$1" -eq 0 ]; then pass "$2"; else fail "$2 -- exit code $1"; fi
}

assert_rc2() {
  if [ "$1" -eq 2 ]; then pass "$2"; else fail "$2 -- exit code $1"; fi
}

assert_rc_nonzero() {
  if [ "$1" -ne 0 ]; then pass "$2"; else fail "$2 -- expected a nonzero exit code"; fi
}

# Copies the fixture into $1 and turns it into a committed git repo with a quiet identity.
make_fixture() {
  mkdir -p "$1"
  cp -R "$FIXTURE_SRC/." "$1/"
  git -C "$1" -c init.defaultBranch=main init -q
  git -C "$1" config user.email "fixture@example.com"
  git -C "$1" config user.name "Fixture User"
  git -C "$1" config commit.gpgsign false
  git -C "$1" add -A
  git -C "$1" commit -q -m "fixture baseline"
}

run_session_start() {
  (cd "$1" && printf '%s' "$2" | env -u CLAUDE_PLUGIN_ROOT bash "$HOOKS_DIR/session-start.sh")
}

run_session_start_with_root() {
  (cd "$1" && printf '%s' "$2" | CLAUDE_PLUGIN_ROOT="$3" bash "$HOOKS_DIR/session-start.sh")
}

run_session_end() {
  (cd "$1" && bash "$HOOKS_DIR/session-end.sh" </dev/null)
}

run_statusline() {
  printf '%s' "$1" | bash "$HOOKS_DIR/statusline.sh"
}

TEMPLATES_DIR="$REPO_ROOT/skills/harness-init"

# Installs the hook templates into $1/.claude/hooks/ as executable .sh files,
# plus harness_state.py which check-remaining-tasks.sh and verify-task-quality.sh consume.
install_hooks() {
  mkdir -p "$1/.claude/hooks"
  for TPL in "$TEMPLATES_DIR"/*.sh.template; do
    BASE=$(basename "$TPL" .template)
    cp "$TPL" "$1/.claude/hooks/$BASE"
    chmod +x "$1/.claude/hooks/$BASE"
  done
  cp "$TEMPLATES_DIR/harness_state.py.template" "$1/.claude/hooks/harness_state.py"
  chmod +x "$1/.claude/hooks/harness_state.py"
}

# Invokes a hook the way settings.json does: "$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh
run_hook() {
  (cd "$1" && printf '%s' "$3" | CLAUDE_PROJECT_DIR="$1" "$1/.claude/hooks/$2")
}

run_hook_from_subdir() {
  (cd "$1/sub" && printf '%s' "$3" | CLAUDE_PROJECT_DIR="$1" "$1/.claude/hooks/$2")
}

echo "== session-start.sh =="

DIR_A="$WORK/a"
make_fixture "$DIR_A"
OUT=$(run_session_start "$DIR_A" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "a: session-start exits 0 in a harness project"
assert_contains "$OUT" "## Harness orientation" "a: prints the orientation header"
assert_contains "$OUT" "1/3 passing" "a: reports 1/3 features passing"
assert_contains "$OUT" "F003" "a: names F003 as next claimable"
assert_contains "$OUT" "Currently working on: F002 hook coverage reporting" \
  "a: includes the Active Context bullets"

DIR_B="$WORK/b-plain"
mkdir -p "$DIR_B"
OUT=$(run_session_start "$DIR_B" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "b: exits 0 in a plain directory"
assert_empty "$OUT" "b: prints nothing in a plain directory"

DIR_C="$WORK/c"
make_fixture "$DIR_C"
OUT=$(run_session_start "$DIR_C" '{"source":"compact"}')
RC=$?
assert_rc0 "$RC" "c: compact source exits 0"
FIRST_LINE=$(printf '%s\n' "$OUT" | head -n 1)
if [ "$FIRST_LINE" = "## Compaction recovery" ]; then
  pass "c: compaction recovery block comes first"
else
  fail "c: expected '## Compaction recovery' as first line, got: $FIRST_LINE"
fi
assert_contains "$OUT" "## Harness orientation" "c: orientation follows the recovery block"

OUT=$(run_session_start "$DIR_A" '')
RC=$?
assert_rc0 "$RC" "d: empty stdin exits 0"
assert_contains "$OUT" "## Harness orientation" "d: empty stdin still orients"

DIR_E="$WORK/e"
make_fixture "$DIR_E"
printf '{ this is not json' > "$DIR_E/.harness/features.json"
OUT=$(run_session_start "$DIR_E" '{"source":"startup"}' 2>&1)
RC=$?
assert_rc0 "$RC" "e: malformed features.json exits 0"
assert_not_contains "$OUT" "Traceback" "e: no python traceback leaks into output"
assert_contains "$OUT" "## Harness orientation" "e: still prints the orientation header"

OUT=$(run_session_start_with_root "$DIR_A" '{"source":"startup"}' "$REPO_ROOT")
LEN=${#OUT}
if [ "$LEN" -lt 4000 ]; then
  pass "o: startup orientation stays under 4000 chars ($LEN)"
else
  fail "o: startup orientation is $LEN chars, expected under 4000"
fi
assert_contains "$OUT" "rules/code-quality.md (read before writing code)" \
  "o: orientation includes the code-quality pointer"
assert_contains "$OUT" "rules/context-summary.md" \
  "o: orientation includes the context-summary pointer"
assert_contains "$OUT" "rules/task-completion.md" \
  "o: orientation includes the task-completion pointer"

OUT=$(run_session_start "$DIR_A" '{"source":"startup"}')
assert_not_contains "$OUT" "<vv-harness plugin root>" \
  "y: no placeholder literal when CLAUDE_PLUGIN_ROOT is unset"
assert_not_contains "$OUT" "rules/code-quality.md" \
  "y: no rule-pointer lines when CLAUDE_PLUGIN_ROOT is unset"
assert_contains "$OUT" "## Harness orientation" \
  "y: orientation still prints when CLAUDE_PLUGIN_ROOT is unset"

OUT=$(run_session_start_with_root "$DIR_A" '{"source":"startup"}' "")
assert_not_contains "$OUT" "rules/code-quality.md" \
  "y: empty CLAUDE_PLUGIN_ROOT also suppresses rule-pointer lines"

DIR_Y="$WORK/y-name-mismatch"
make_fixture "$DIR_Y"
python3 - "$DIR_Y/.harness/harness.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
data["git_identity"]["user_name"] = "Someone Else"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_session_start "$DIR_Y" '{"source":"startup"}')
assert_contains "$OUT" "git identity mismatch" \
  "y: matching email with mismatched name still warns"

echo ""
echo "== spec drift =="

DIR_S="$WORK/spec-drift-clean"
make_fixture "$DIR_S"
python3 - "$DIR_S/.harness/features.json" <<'PYEOF'
import hashlib
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F003":
        digest = hashlib.sha256(feature["description"].encode("utf-8")).hexdigest()
        feature["spec"] = {"hash": digest, "verdict": "PASS", "sv_version": "1.0"}
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_session_start "$DIR_S" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "s: matching spec hash exits 0"
assert_not_contains "$OUT" "spec drift" "s: no drift warning when the hash matches"

DIR_T="$WORK/spec-drift-bogus"
make_fixture "$DIR_T"
python3 - "$DIR_T/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F003":
        feature["spec"] = {"hash": "0" * 60 + "dead", "verdict": "PASS", "sv_version": "1.0"}
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_session_start "$DIR_T" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "t: mismatched spec hash exits 0"
assert_contains "$OUT" "spec drift" "t: warns about spec drift"
assert_contains "$OUT" "F003" "t: names F003 as drifted"
LEN=${#OUT}
if [ "$LEN" -lt 4000 ]; then
  pass "t: drift-warning output stays under 4000 chars ($LEN)"
else
  fail "t: drift-warning output is $LEN chars, expected under 4000"
fi

DIR_U="$WORK/spec-drift-nondict"
make_fixture "$DIR_U"
python3 - "$DIR_U/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F003":
        feature["spec"] = "bogus"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_session_start "$DIR_U" '{"source":"startup"}' 2>&1)
RC=$?
assert_rc0 "$RC" "u: non-dict spec exits 0"
assert_not_contains "$OUT" "Traceback" "u: no python traceback leaks for a non-dict spec"
assert_contains "$OUT" "## Harness orientation" "u: orientation header still present"

echo ""
echo "== scope enforcement warning =="

DIR_W="$WORK/scope-unarmed"
make_fixture "$DIR_W"
mkdir -p "$DIR_W/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$DIR_W/.claude/hooks/enforce-scope.sh"
python3 - "$DIR_W/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F002":
        feature["assigned_to"] = "api"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_session_start "$DIR_W" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "w: unarmed-scope case exits 0"
assert_contains "$OUT" "scope enforcement unarmed" \
  "w: warns when a teammate is in-progress, the hook exists, and the scope file is missing"
assert_contains "$OUT" ".claude/teammate-scope.txt" "w: warning names the missing file"

DIR_W2="$WORK/scope-armed"
make_fixture "$DIR_W2"
mkdir -p "$DIR_W2/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$DIR_W2/.claude/hooks/enforce-scope.sh"
printf 'src/hooks/\n' > "$DIR_W2/.claude/teammate-scope.txt"
python3 - "$DIR_W2/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F002":
        feature["assigned_to"] = "api"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_session_start "$DIR_W2" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "w: armed case exits 0"
assert_not_contains "$OUT" "scope enforcement unarmed" \
  "w: no warning once the scope file exists"

DIR_W3="$WORK/scope-lead-only"
make_fixture "$DIR_W3"
mkdir -p "$DIR_W3/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$DIR_W3/.claude/hooks/enforce-scope.sh"
OUT=$(run_session_start "$DIR_W3" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "w: lead-only case exits 0"
assert_not_contains "$OUT" "scope enforcement unarmed" \
  "w: no warning when no feature has assigned_to set"

DIR_W4="$WORK/scope-no-hook"
make_fixture "$DIR_W4"
python3 - "$DIR_W4/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F002":
        feature["assigned_to"] = "api"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_session_start "$DIR_W4" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "w: hook-absent case exits 0"
assert_not_contains "$OUT" "scope enforcement unarmed" \
  "w: no warning when enforce-scope.sh itself is not installed"

DIR_W5="$WORK/scope-empty-string-assigned"
make_fixture "$DIR_W5"
mkdir -p "$DIR_W5/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$DIR_W5/.claude/hooks/enforce-scope.sh"
python3 - "$DIR_W5/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F002":
        feature["assigned_to"] = ""
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_session_start "$DIR_W5" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "w: empty-string assigned_to case exits 0"
assert_contains "$OUT" "scope enforcement unarmed" \
  "w: warns on an empty-string assigned_to too (spec says != null, not just truthy)"

echo ""
echo "== session-end.sh =="

DIR_F="$WORK/f"
make_fixture "$DIR_F"
printf '\n' >> "$DIR_F/.harness/features.json"
OUT=$(run_session_end "$DIR_F")
RC=$?
assert_rc0 "$RC" "f: session-end exits 0 even with gaps"
SI_FILE="$DIR_F/.harness/SESSION_INCOMPLETE"
if [ -f "$SI_FILE" ]; then
  pass "f: SESSION_INCOMPLETE written"
else
  fail "f: SESSION_INCOMPLETE missing"
fi
SI_TEXT=$(cat "$SI_FILE" 2>/dev/null || true)
assert_contains "$SI_TEXT" \
  "features.json changed but claude-progress.txt has no new handoff." \
  "f: records the handoff gap"
assert_contains "$SI_TEXT" "F002 is in-progress but missing test_file or coverage." \
  "f: records the F002 test_file/coverage gap"
assert_contains "$SI_TEXT" "Missing '## Meta-Session" "f: records the Meta-Session gap"

DIR_P="$WORK/p"
make_fixture "$DIR_P"
printf '\n' >> "$DIR_P/.harness/features.json"
git -C "$DIR_P" add .harness/features.json
OUT=$(run_session_end "$DIR_P")
SI_TEXT=$(cat "$DIR_P/.harness/SESSION_INCOMPLETE" 2>/dev/null || true)
assert_contains "$SI_TEXT" \
  "features.json changed but claude-progress.txt has no new handoff." \
  "p: staged features.json edit still records the handoff gap"

DIR_Q="$WORK/q"
make_fixture "$DIR_Q"
git -C "$DIR_Q" rm -q --cached .harness/claude-progress.txt
git -C "$DIR_Q" commit -q -m "untrack progress log"
printf '\n' >> "$DIR_Q/.harness/features.json"
OUT=$(run_session_end "$DIR_Q")
SI_TEXT=$(cat "$DIR_Q/.harness/SESSION_INCOMPLETE" 2>/dev/null || true)
assert_not_contains "$SI_TEXT" "no new handoff" \
  "q: new untracked claude-progress.txt counts as a fresh handoff"

DIR_G="$WORK/g"
make_fixture "$DIR_G"
TODAY=$(date -u +%Y-%m-%d)
printf '\n## Meta-Session %s\n- Scope accuracy: clean run, no expansions\n' "$TODAY" \
  >> "$DIR_G/.harness/context_summary.md"
python3 - "$DIR_G/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F001":
        # Already passing in the base fixture with no proof; give it one too so
        # this stays a genuinely clean, no-discipline-note scenario.
        feature["proof"] = {
            "claim": "pipeline parsing works",
            "evidence_type": "unit",
            "artifact": "tests/parser/test_parser.py",
            "not_established": "none",
        }
    if feature["id"] == "F002":
        feature["status"] = "passing"
        feature["coverage"] = 96
        feature["proof"] = {
            "claim": "hook coverage reporting works",
            "evidence_type": "unit",
            "artifact": "tests/hooks/test_hooks.py",
            "not_established": "none",
        }
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
git -C "$DIR_G" add -A
git -C "$DIR_G" commit -q -m "session work committed"
OUT=$(run_session_end "$DIR_G")
RC=$?
assert_rc0 "$RC" "g: clean session-end exits 0"
if [ -f "$DIR_G/.harness/SESSION_INCOMPLETE" ]; then
  fail "g: SESSION_INCOMPLETE should be absent after a clean session"
else
  pass "g: SESSION_INCOMPLETE absent after a clean session"
fi
assert_empty "$OUT" "g: clean session-end prints nothing (proof recorded, no discipline note)"

printf 'stale gap from previous run\n' > "$DIR_G/.harness/SESSION_INCOMPLETE"
OUT=$(run_session_end "$DIR_G")
RC=$?
assert_rc0 "$RC" "r: re-run with leftover SESSION_INCOMPLETE exits 0"
assert_empty "$OUT" "r: leftover SESSION_INCOMPLETE does not re-trigger the metadata gap"
if [ -f "$DIR_G/.harness/SESSION_INCOMPLETE" ]; then
  fail "r: SESSION_INCOMPLETE should be cleared when no gaps remain"
else
  pass "r: SESSION_INCOMPLETE cleared when no gaps remain"
fi

OUT=$(run_session_start "$DIR_F" '{"source":"startup"}')
RC=$?
assert_rc0 "$RC" "h: session-start after gaps exits 0"
assert_contains "$OUT" "unresolved discipline gaps" "h: warns about the incomplete session"
assert_contains "$OUT" "F002 is in-progress but missing test_file or coverage." \
  "h: surfaces the SESSION_INCOMPLETE contents"

DIR_PROOF="$WORK/session-end-proof-note"
make_fixture "$DIR_PROOF"
python3 - "$DIR_PROOF/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F002":
        feature["status"] = "passing"
        feature["coverage"] = 96
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
TODAY=$(date -u +%Y-%m-%d)
printf '\n## Meta-Session %s\n- clean\n' "$TODAY" >> "$DIR_PROOF/.harness/context_summary.md"
git -C "$DIR_PROOF" add -A
git -C "$DIR_PROOF" commit -q -m "session work committed, F002 passing, no proof"
OUT=$(run_session_end "$DIR_PROOF")
RC=$?
assert_rc0 "$RC" "pf: session-end exits 0 with a passing-no-proof feature"
assert_contains "$OUT" "F002" "pf: proof discipline note names the feature"
assert_contains "$OUT" "no proof" "pf: proof discipline note mentions no proof"
if [ -f "$DIR_PROOF/.harness/SESSION_INCOMPLETE" ]; then
  fail "pf: a missing-proof note must not write SESSION_INCOMPLETE"
else
  pass "pf: a missing-proof note does not trigger SESSION_INCOMPLETE"
fi

echo ""
echo "== statusline.sh =="

DIR_I="$WORK/i"
make_fixture "$DIR_I"
OUT=$(run_statusline "{\"workspace\": {\"project_dir\": \"$DIR_I\"}}")
RC=$?
assert_rc0 "$RC" "i: statusline exits 0"
assert_contains "$OUT" "⬡ 1/3 passing" "i: shows the passing ratio"
assert_contains "$OUT" "F002" "i: shows F002 as in-progress"
printf 'gap\n' > "$DIR_I/.harness/SESSION_INCOMPLETE"
OUT=$(run_statusline "{\"workspace\": {\"project_dir\": \"$DIR_I\"}}")
assert_contains "$OUT" "last session incomplete" "i: flags SESSION_INCOMPLETE"

DIR_J="$WORK/j-plain"
mkdir -p "$DIR_J"
OUT=$(run_statusline "{\"workspace\": {\"project_dir\": \"$DIR_J\"}}")
RC=$?
assert_rc0 "$RC" "j: exits 0 when project_dir has no harness"
assert_empty "$OUT" "j: prints nothing when project_dir has no harness"

OUT=$(run_statusline 'not json')
RC=$?
assert_rc0 "$RC" "k: garbage stdin exits 0"
assert_empty "$OUT" "k: garbage stdin prints nothing"

echo ""
echo "== manifests =="

for MANIFEST in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  if python3 -m json.tool "$REPO_ROOT/$MANIFEST" >/dev/null 2>&1; then
    pass "l: $MANIFEST is valid JSON"
  else
    fail "l: $MANIFEST is not valid JSON"
  fi
done

PLUGIN_NAME=$(python3 -c \
  'import json, sys; print(json.load(open(sys.argv[1])).get("name", ""))' \
  "$REPO_ROOT/.claude-plugin/plugin.json" 2>/dev/null)
if [ "$PLUGIN_NAME" = "vv-harness" ]; then
  pass "l: plugin.json name is vv-harness"
else
  fail "l: plugin.json name is '$PLUGIN_NAME', expected vv-harness"
fi

HOOK_REF_ERRORS=$(python3 - "$REPO_ROOT" <<'PYEOF'
import json
import os
import sys

root = sys.argv[1]
commands = []


def walk(node):
    if isinstance(node, dict):
        if node.get("type") == "command" and "command" in node:
            commands.append(node["command"])
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)


walk(json.load(open(os.path.join(root, "hooks", "hooks.json"))))
if not commands:
    print("hooks.json declares no command hooks")
for command in commands:
    path = command.replace('"', "").replace("${CLAUDE_PLUGIN_ROOT}", root)
    if not os.path.isfile(path):
        print(f"missing hook target: {command}")
    elif not os.access(path, os.X_OK):
        print(f"non-executable hook target: {command}")
PYEOF
)
if [ -z "$HOOK_REF_ERRORS" ]; then
  pass "l: hooks.json references only existing, executable files in hooks/"
else
  fail "l: hooks.json reference check -- $HOOK_REF_ERRORS"
fi

echo ""
echo "== feature schema validator =="

VALIDATE_SCRIPT="$REPO_ROOT/scripts/validate-features.py"
FEATURE_SCHEMA="$REPO_ROOT/schemas/feature.schema.json"

if python3 -m json.tool "$FEATURE_SCHEMA" >/dev/null 2>&1; then
  pass "fsv: schemas/feature.schema.json is valid JSON"
else
  fail "fsv: schemas/feature.schema.json is not valid JSON"
fi

SCHEMA_DIALECT=$(python3 -c \
  'import json, sys; print(json.load(open(sys.argv[1])).get("$schema", ""))' \
  "$FEATURE_SCHEMA" 2>/dev/null)
case "$SCHEMA_DIALECT" in
  *2020-12*) pass "fsv: feature.schema.json declares draft 2020-12" ;;
  *) fail "fsv: feature.schema.json \$schema is '$SCHEMA_DIALECT', expected draft 2020-12" ;;
esac

FSV_DIR="$WORK/fsv"
mkdir -p "$FSV_DIR"

RC=0
python3 "$VALIDATE_SCRIPT" "$FIXTURE_SRC/.harness/features.json" >/dev/null 2>&1 || RC=$?
assert_rc0 "$RC" "fsv: validator passes on the shared test fixture (pre-v3.3 fields absent)"

fsv_mutate() {
  # $1: output filename under $FSV_DIR, $2: python snippet mutating dict `d` in place
  python3 - "$FIXTURE_SRC/.harness/features.json" "$FSV_DIR/$1" <<PYEOF
import json, sys
d = json.load(open(sys.argv[1]))
$2
json.dump(d, open(sys.argv[2], "w"))
PYEOF
}

fsv_mutate "bad-status.json" 'd["features"][0]["status"] = "done"'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/bad-status.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects invalid status enum value"
assert_contains "$OUT" "features[0].status" "fsv: bad status error names the location"

fsv_mutate "missing-id.json" 'del d["features"][0]["id"]'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/missing-id.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects a feature missing 'id'"
assert_contains "$OUT" "features[0]" "fsv: missing id error names the location"

fsv_mutate "bad-type.json" 'd["features"][0]["correction_cycles"] = "three"'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/bad-type.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects wrong type for correction_cycles"
assert_contains "$OUT" "features[0].correction_cycles" \
  "fsv: bad correction_cycles error names the location"

fsv_mutate "dup-id.json" 'd["features"][1]["id"] = d["features"][0]["id"]'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/dup-id.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects a duplicate feature id"
assert_contains "$OUT" "features[1].id" "fsv: duplicate id error names the location"

fsv_mutate "dangling-dep.json" 'd["features"][1]["depends_on"] = ["F099"]'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/dangling-dep.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects a dangling depends_on reference"
assert_contains "$OUT" "features[1].depends_on" "fsv: dangling depends_on error names the location"

fsv_mutate "unknown-field.json" 'd["features"][0]["custom_metadata"] = "not a real field"'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/unknown-field.json" 2>&1)
RC=$?
assert_rc0 "$RC" "fsv: an unknown top-level feature field is a warning, not an error"
assert_contains "$OUT" "custom_metadata" "fsv: unknown field warning names the field"

fsv_mutate "bad-qa-binding.json" 'd["features"][0]["qa_binding"] = "vibes"'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/bad-qa-binding.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects an invalid qa_binding value"
assert_contains "$OUT" "features[0].qa_binding" "fsv: bad qa_binding error names the location"

fsv_mutate "good-qa-binding.json" 'd["features"][0]["qa_binding"] = "unit"'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/good-qa-binding.json" 2>&1)
RC=$?
assert_rc0 "$RC" "fsv: accepts a valid qa_binding value"

fsv_mutate "conformance-qa-binding.json" 'd["features"][0]["qa_binding"] = "conformance"'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/conformance-qa-binding.json" 2>&1)
RC=$?
assert_rc0 "$RC" "fsv: accepts qa_binding value 'conformance'"

fsv_mutate "bad-proof-missing-subfield.json" \
  'd["features"][0]["proof"] = {"claim": "x", "evidence_type": "unit", "artifact": "y"}'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/bad-proof-missing-subfield.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects a proof object missing not_established"
assert_contains "$OUT" "features[0].proof.not_established" \
  "fsv: missing proof subfield error names the location"

fsv_mutate "bad-proof-empty-subfield.json" \
  'd["features"][0]["proof"] = {"claim": "", "evidence_type": "unit",\
  "artifact": "y", "not_established": "z"}'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/bad-proof-empty-subfield.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects a proof object with an empty subfield"
assert_contains "$OUT" "features[0].proof.claim" \
  "fsv: empty proof subfield error names the location"

fsv_mutate "bad-proof-evidence-type.json" \
  'd["features"][0]["proof"] = {"claim": "x", "evidence_type": "vibes",\
  "artifact": "y", "not_established": "z"}'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/bad-proof-evidence-type.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects a proof object with a bad evidence_type"
assert_contains "$OUT" "features[0].proof.evidence_type" \
  "fsv: bad proof evidence_type error names the location"

fsv_mutate "good-proof.json" \
  'd["features"][0]["proof"] = {"claim": "x", "evidence_type": "unit",\
  "artifact": "y", "not_established": "z"}'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/good-proof.json" 2>&1)
RC=$?
assert_rc0 "$RC" "fsv: accepts a complete proof object"

fsv_mutate "bad-coverage-target-range.json" 'd["features"][0]["coverage_target"] = 150'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/bad-coverage-target-range.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects an out-of-range coverage_target"
assert_contains "$OUT" "features[0].coverage_target" \
  "fsv: bad coverage_target error names the location"

fsv_mutate "good-coverage-target.json" 'd["features"][0]["coverage_target"] = 80'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/good-coverage-target.json" 2>&1)
RC=$?
assert_rc0 "$RC" "fsv: accepts a valid coverage_target"

fsv_mutate "bad-delivered-merged-at.json" \
  'd["features"][0]["delivered"] = {"pr": "#1", "merged_at": "not-a-date", "verified": "x"}'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/bad-delivered-merged-at.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: rejects a non-ISO8601 delivered.merged_at"
assert_contains "$OUT" "features[0].delivered.merged_at" \
  "fsv: bad delivered.merged_at error names the location"

fsv_mutate "good-delivered.json" \
  'd["features"][0]["delivered"] = {"pr": "#1",\
  "merged_at": "2026-07-24T12:00:00Z", "verified": "x"}'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/good-delivered.json" 2>&1)
RC=$?
assert_rc0 "$RC" "fsv: accepts a valid delivered object with ISO8601 merged_at"

fsv_mutate "good-design-contract.json" 'd["features"][0]["design_contract"] = "docs/mock.png"'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/good-design-contract.json" 2>&1)
RC=$?
assert_rc0 "$RC" "fsv: accepts a design_contract string"

fsv_mutate "coverage-string.json" \
  'd["features"][0]["coverage"] = "n/a (shell suite, no coverage tooling)"'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/coverage-string.json" 2>&1)
RC=$?
assert_rc0 "$RC" "fsv: accepts a descriptive string for coverage (F022)"

fsv_mutate "coverage-bad-type.json" 'd["features"][0]["coverage"] = True'
OUT=$(python3 "$VALIDATE_SCRIPT" "$FSV_DIR/coverage-bad-type.json" 2>&1)
RC=$?
assert_rc_nonzero "$RC" "fsv: still rejects a boolean coverage value"
assert_contains "$OUT" "features[0].coverage" "fsv: bad coverage error names the location"

echo ""
echo "== spec gate artifacts =="

READINESS_STAMP_ERRORS=$(python3 - "$REPO_ROOT" <<'PYEOF'
import json
import os
import re
import sys

root = sys.argv[1]
path = os.path.join(root, "schemas", "readiness-stamp.md")
if not os.path.isfile(path):
    print(f"missing: {path}")
    sys.exit()
text = open(path).read()
if "stamp_version" not in text:
    print("schemas/readiness-stamp.md: missing 'stamp_version'")
match = re.search(r"```json\n(.*?)\n```", text, re.DOTALL)
if not match:
    print("schemas/readiness-stamp.md: no fenced json block found")
else:
    try:
        json.loads(match.group(1))
    except Exception as exc:
        print(f"schemas/readiness-stamp.md: first json block does not parse -- {exc}")
PYEOF
)
if [ -z "$READINESS_STAMP_ERRORS" ]; then
  pass "v: schemas/readiness-stamp.md exists, mentions stamp_version, and its first json block parses"
else
  fail "v: readiness stamp schema -- $READINESS_STAMP_ERRORS"
fi

SKILL_ERRORS=$(python3 - "$REPO_ROOT" <<'PYEOF'
import os
import sys

root = sys.argv[1]
for skill_dir in ("harness-issue-prep", "harness-issue-debug", "harness-doctor"):
    path = os.path.join(root, "skills", skill_dir, "SKILL.md")
    if not os.path.isfile(path):
        print(f"missing: {path}")
        continue
    lines = open(path).read().splitlines()
    if not lines or lines[0] != "---":
        print(f"{skill_dir}/SKILL.md: does not start with ---")
        continue
    try:
        end = lines[1:].index("---") + 1
    except ValueError:
        print(f"{skill_dir}/SKILL.md: frontmatter has no closing ---")
        continue
    name = None
    for line in lines[1:end]:
        if line.startswith("name:"):
            name = line.split(":", 1)[1].strip()
    if name != skill_dir:
        print(f"{skill_dir}/SKILL.md: name '{name}' does not match directory '{skill_dir}'")
PYEOF
)
if [ -z "$SKILL_ERRORS" ]; then
  pass "w: harness-issue-prep/-debug/-doctor SKILL.md files have sane frontmatter"
else
  fail "w: skill frontmatter -- $SKILL_ERRORS"
fi

if grep -q "QA binding" "$REPO_ROOT/skills/harness-issue-prep/SKILL.md"; then
  pass "w: harness-issue-prep's Step 5 template carries a QA binding line"
else
  fail "w: harness-issue-prep's Step 5 template is missing the QA binding line"
fi

if grep -q "QA binding" "$REPO_ROOT/agents/spec-verification.md"; then
  pass "w: spec-verification's SV-01 checklist references the QA binding requirement"
else
  fail "w: spec-verification's SV-01 checklist is missing the QA binding requirement"
fi

DIR_X="$WORK/x"
make_fixture "$DIR_X"
TODAY=$(date -u +%Y-%m-%d)
printf '\n## Meta-Session %s\n- Scope accuracy: clean run, no expansions\n' "$TODAY" \
  >> "$DIR_X/.harness/context_summary.md"
python3 - "$DIR_X/.harness/features.json" <<'PYEOF'
import hashlib
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F001":
        digest = hashlib.sha256(feature["description"].encode("utf-8")).hexdigest()
        feature["spec"] = {"hash": digest, "verdict": "PASS", "sv_version": "1.0"}
    if feature["id"] == "F002":
        feature["status"] = "passing"
        feature["coverage"] = 96
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
git -C "$DIR_X" add -A
git -C "$DIR_X" commit -q -m "session work committed with a verified spec field"
OUT=$(run_session_end "$DIR_X")
RC=$?
assert_rc0 "$RC" "x: clean session-end with a verified spec field exits 0"
if [ -f "$DIR_X/.harness/SESSION_INCOMPLETE" ]; then
  fail "x: SESSION_INCOMPLETE should be absent after a clean session with a spec field"
else
  pass "x: SESSION_INCOMPLETE absent after a clean session with a spec field"
fi

echo ""
echo "== single-owner truth =="

if grep -q "Current version" "$REPO_ROOT/README.md"; then
  fail "z: README.md restates the plugin version ('Current version' found)"
else
  pass "z: README.md does not restate the plugin version"
fi

if grep -rq "{{" "$REPO_ROOT/rules/"; then
  fail "z: rules/ contains a template placeholder"
else
  pass "z: rules/ contains no template placeholders"
fi

if [ -f "$REPO_ROOT/LICENSE" ] && grep -q "MIT License" "$REPO_ROOT/LICENSE"; then
  pass "z: MIT LICENSE present at repo root"
else
  fail "z: MIT LICENSE missing at repo root"
fi

for RULE_FILE in agents/researcher.md templates/CLAUDE.md; do
  if grep -q "data, never instructions" "$REPO_ROOT/$RULE_FILE"; then
    pass "z: untrusted-content rule present in $RULE_FILE"
  else
    fail "z: untrusted-content rule missing in $RULE_FILE"
  fi
done

if grep -q "treat it as burned" "$REPO_ROOT/templates/CLAUDE.md"; then
  pass "z: transcript-secrets rule present in templates/CLAUDE.md"
else
  fail "z: transcript-secrets rule missing in templates/CLAUDE.md"
fi

FULL_EXAMPLE_COUNT=$(grep -r '"correction_cycles": 0' "$REPO_ROOT" --include="*.md" \
  | wc -l | tr -d ' ')
if [ "$FULL_EXAMPLE_COUNT" -eq 1 ]; then
  pass "z: the full 16-field feature JSON example appears exactly once across *.md"
else
  fail "z: the full feature JSON example appears $FULL_EXAMPLE_COUNT times across *.md, expected 1"
fi

DONE_DEF_COUNT=$(grep -r "Feature is not done until" "$REPO_ROOT" --include="*.md" \
  | wc -l | tr -d ' ')
if [ "$DONE_DEF_COUNT" -eq 1 ]; then
  pass "z: the done-definition sentence appears exactly once across *.md"
else
  fail "z: the done-definition sentence appears $DONE_DEF_COUNT times across *.md, expected 1"
fi

for DOC_FILE in rules/agent-teams-protocol.md skills/harness-init/SKILL.md README.md; do
  if grep -q "schemas/feature.schema.json" "$REPO_ROOT/$DOC_FILE"; then
    pass "z: $DOC_FILE links to schemas/feature.schema.json"
  else
    fail "z: $DOC_FILE does not link to schemas/feature.schema.json"
  fi
done

echo ""
echo "== hook templates =="

if grep -q '^# Degraded behavior:' "$TEMPLATES_DIR/check-remaining-tasks.sh.template"; then
  pass "ht: check-remaining-tasks documents its degraded behavior"
else
  fail "ht: check-remaining-tasks lacks a '# Degraded behavior:' header line"
fi

if grep -q '^# Formatting:' "$TEMPLATES_DIR/verify-task-quality.sh.template"; then
  pass "ht: verify-task-quality documents its formatting ownership"
else
  fail "ht: verify-task-quality lacks a '# Formatting:' header line"
fi

if grep -q 'mv ' "$TEMPLATES_DIR/verify-task-quality.sh.template"; then
  pass "ht: verify-task-quality writes features.json atomically (.tmp + mv)"
else
  fail "ht: verify-task-quality has no mv-based atomic write"
fi

DIR_HS="$WORK/ht-scope"
make_fixture "$DIR_HS"
install_hooks "$DIR_HS"
mkdir -p "$DIR_HS/sub"
IN_SCOPE_JSON="{\"tool_input\":{\"file_path\":\"$DIR_HS/src/parser/x.py\"}}"
OUT_SCOPE_JSON="{\"tool_input\":{\"file_path\":\"$DIR_HS/src/other/y.py\"}}"
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$IN_SCOPE_JSON")
RC=$?
assert_rc0 "$RC" "ht: enforce-scope allows edits when no scope file exists"
printf 'src/parser/\n' > "$DIR_HS/.claude/teammate-scope.txt"
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$IN_SCOPE_JSON")
RC=$?
assert_rc0 "$RC" "ht: enforce-scope allows an in-scope edit"
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$OUT_SCOPE_JSON")
RC=$?
assert_rc2 "$RC" "ht: enforce-scope blocks an out-of-scope edit"
assert_contains "$OUT" "src/other/y.py" "ht: block message names the file"
assert_contains "$OUT" "scope expansion" "ht: block message names the scope-expansion repair"
OUT=$(run_hook_from_subdir "$DIR_HS" enforce-scope.sh "$OUT_SCOPE_JSON")
RC=$?
assert_rc2 "$RC" "ht: enforce-scope still blocks when cwd is a subdirectory"

echo ""
echo "== state ownership + bash write boundary =="

bash_command_json() {
  python3 -c "
import json
import sys
print(json.dumps({'tool_input': {'command': sys.argv[1]}}))
" "$1"
}

edit_json() {
  python3 -c "
import json
import sys
print(json.dumps({'tool_input': {'file_path': sys.argv[1]}}))
" "$1"
}

assert_deny_json() {
  assert_contains "$1" '"permissionDecision": "deny"' "$2"
}

# DIR_HS already has hooks installed and a scope file ("src/parser/") from the block above.

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(edit_json "$DIR_HS/.harness/features.json")")
RC=$?
assert_rc0 "$RC" "hs2: Edit to a lead-owned state file exits 0 (JSON deny, not exit 2)"
assert_deny_json "$OUT" "hs2: lead-owned Edit denial uses the JSON deny form"
assert_contains "$OUT" "permissionDecisionReason" "hs2: lead-owned Edit denial includes a reason"
assert_contains "$OUT" "verified live" "hs2: denial reason carries a verified-live annotation"
assert_contains "$OUT" "on Claude Code" "hs2: annotation names the Claude Code version"
assert_contains "$OUT" "lead-owned" \
  "hg: lead-owned Edit denial names the violated invariant (F005/OVI-61)"
assert_contains "$OUT" "SendMessage" \
  "hg: lead-owned Edit denial names the repair (F005/OVI-61)"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'echo x >> .harness/features.json')")
RC=$?
assert_rc0 "$RC" "hs2: Bash write to a lead-owned state file exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: Bash lead-owned write denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'tee src/other/escaped.txt')")
RC=$?
assert_rc0 "$RC" "hs2: Bash tee to an out-of-scope target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: out-of-scope tee denial uses JSON deny form"
assert_contains "$OUT" "outside your assigned scope" \
  "hg: out-of-scope tee denial names the invariant (F005/OVI-61)"

HEREDOC_CMD=$'cat <<\'EOF\' > src/other/escaped.txt\ncontent\nEOF'
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "$HEREDOC_CMD")")
RC=$?
assert_rc0 "$RC" "hs2: heredoc-into-redirect to an out-of-scope target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: heredoc-into-redirect denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'rm src/other/file.py')")
RC=$?
assert_rc0 "$RC" "hs2: Bash rm on an out-of-scope target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: out-of-scope rm denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'rm .harness/features.json')")
RC=$?
assert_rc0 "$RC" "hs2: Bash rm on a lead-owned state file exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: lead-owned rm denial uses JSON deny form"
assert_contains "$OUT" "lead-owned" \
  "hg: lead-owned rm denial names the violated invariant (F005/OVI-61)"
assert_contains "$OUT" "SendMessage" \
  "hg: lead-owned rm denial names the repair (F005/OVI-61)"

# Hostile case (F005/OVI-61): Bash '>>' redirect specifically out of scope, distinct
# from the lead-owned '>>' case above (which targets .harness/features.json).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'echo x >> src/other/out.txt')")
RC=$?
assert_rc0 "$RC" "hg: Bash >> redirect outside scope exits 0 (JSON deny)"
assert_deny_json "$OUT" "hg: out-of-scope >> redirect denial uses JSON deny form"
assert_contains "$OUT" "outside your assigned scope" \
  "hg: out-of-scope >> redirect denial names the invariant"

# F005/OVI-61 scope note: the commit-content gate (compound `git add && git commit`,
# secret-shaped staged addition) has no hook yet -- F011/OVI-64 is still pending.
# Those two attack cases are skip-until-S4, not part of this issue's acceptance criteria.
# check-remaining-tasks needs no new attack case either: it is a prompt-tier hook that
# never blocks, and its existing rc 0/2 contract (below) already covers it.

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'git status')")
RC=$?
assert_rc0 "$RC" "hs2: Bash git status passes through, rc 0"
assert_not_contains "$OUT" "permissionDecision" "hs2: git status has no deny fields"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp src/parser/a.py src/parser/b.py')")
RC=$?
assert_rc0 "$RC" "hs2: in-scope Bash cp passes through, rc 0"
assert_not_contains "$OUT" "permissionDecision" "hs2: in-scope cp has no deny fields"

# Regression: a '>' inside a quoted string before the real redirect must not be
# mistaken for the redirect target (found in review: first-match regex denied
# legitimate in-scope writes containing markup/arrows/blockquotes).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo "a => b" > src/parser/map.txt')")
RC=$?
assert_rc0 "$RC" "hs2: an in-scope redirect after a quoted '>' passes through, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: quoted-'>' in-scope redirect has no deny fields"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'rm src/parser/tmp.py')")
RC=$?
assert_rc0 "$RC" "hs2: in-scope Bash rm passes through, rc 0"
assert_not_contains "$OUT" "permissionDecision" "hs2: in-scope rm has no deny fields"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'cd /tmp && tee src/other/out.txt')")
RC=$?
assert_rc0 "$RC" "hs2: a compound command's out-of-scope segment is still denied"
assert_deny_json "$OUT" "hs2: compound-command denial uses JSON deny form"

DIR_HS_LEAD="$WORK/hs2-lead-context"
make_fixture "$DIR_HS_LEAD"
install_hooks "$DIR_HS_LEAD"
OUT=$(run_hook "$DIR_HS_LEAD" enforce-scope.sh "$(edit_json "$DIR_HS_LEAD/.harness/features.json")")
RC=$?
assert_rc0 "$RC" "hs2: lead context (no scope file) allows Edit to a state file"
assert_not_contains "$OUT" "permissionDecision" "hs2: lead-context Edit has no deny fields"
OUT=$(run_hook "$DIR_HS_LEAD" enforce-scope.sh "$(bash_command_json 'rm .harness/features.json')")
RC=$?
assert_rc0 "$RC" "hs2: lead context (no scope file) allows Bash rm on a state file"
assert_not_contains "$OUT" "permissionDecision" "hs2: lead-context Bash rm has no deny fields"
OUT=$(run_hook "$DIR_HS_LEAD" enforce-scope.sh "$(bash_command_json 'tee src/anywhere/out.txt')")
RC=$?
assert_rc0 "$RC" "hs2: lead context (no scope file) allows an unscoped Bash tee"
assert_not_contains "$OUT" "permissionDecision" "hs2: lead-context tee has no deny fields"

# F023: segments_of() split on \|\||&&|[|;] -- missing a literal newline and "&".
# commit-gate.sh.template hit exactly this bug (F011/OVI-64, round 3) and fixed
# it; enforce-scope.sh never did. Both missing separators let two writes glue
# into one segment; redirect_target() then returns only the LAST >/>> match on
# that merged segment, so an in-scope write masks an out-of-scope write earlier
# in the same command and the whole thing is wrongly ALLOWED.
NEWLINE_MASKED_CMD=$(printf 'echo bad > src/other/a.txt\necho good > src/parser/ok.txt')
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "$NEWLINE_MASKED_CMD")")
RC=$?
assert_rc0 "$RC" "hs2: newline-separated out-of-scope write is still scanned (JSON deny), not masked"
assert_deny_json "$OUT" "hs2: newline-masked write denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" "hs2: newline-masked denial names the actual out-of-scope target"

AMPERSAND_MASKED_CMD='echo bad > src/other/a.txt & echo good > src/parser/ok.txt'
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "$AMPERSAND_MASKED_CMD")")
RC=$?
assert_rc0 "$RC" "hs2: '&'-separated out-of-scope write is still scanned (JSON deny), not masked"
assert_deny_json "$OUT" "hs2: '&'-masked write denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" "hs2: '&'-masked denial names the actual out-of-scope target"

# Plain sanity check, not a distinguishing regression test: unlike
# commit-gate.sh (where && vs a lone "&" affects which token segment_subcommand
# sees as the leading token), this hook's redirect_target() scans the WHOLE
# segment for a write target regardless of position, so && and back-to-back
# lone "&" characters segment identically here (verified: deleting the
# distinction changes no test outcome). This just confirms a && compound is
# still denied after simplifying the split to a single character class.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/parser/ok.txt && echo y > src/other/bad.txt')")
RC=$?
assert_rc0 "$RC" "hs2: a genuine && compound out-of-scope write still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: && compound denial uses JSON deny form"

# No new false positive: an in-scope write with an unrelated "&"-backgrounded
# command elsewhere in the same line must still pass.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/parser/ok.txt & echo done')")
RC=$?
assert_rc0 "$RC" "hs2: in-scope write with an unrelated backgrounded command passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: in-scope write with a trailing '&' has no deny fields"

# F023 round 1 review: adding the newline split without joining backslash-
# newline continuations first split "sed \" + newline + "-i ..." into two
# fragments, neither of which alone carries "-i" next to "sed" --
# sed_inplace_target() never recognized it, silently allowing an
# out-of-scope sed -i edit.
CONT_SED_CMD=$(printf 'sed \\\n-i s/a/b/ src/other/a.txt')
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "$CONT_SED_CMD")")
RC=$?
assert_rc0 "$RC" "hs2: a continuation-split 'sed -i' out-of-scope write still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: continuation-split sed -i denial uses JSON deny form"

# Same review: the newline-join fix must not introduce a NEW false positive
# for cp/mv/rm split across a continuation, all writing in-scope.
for CONT_CMD_TEMPLATE in \
  'cp \\\nsrc/parser/s.txt src/parser/ok.txt' \
  'mv \\\nsrc/parser/s.txt src/parser/ok2.txt' \
  'rm \\\nsrc/parser/tmp.txt'
do
  CONT_CMD=$(printf "$CONT_CMD_TEMPLATE")
  OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "$CONT_CMD")")
  RC=$?
  assert_rc0 "$RC" "hs2: continuation-split in-scope write ('$CONT_CMD_TEMPLATE') passes, rc 0"
  assert_not_contains "$OUT" "permissionDecision" \
    "hs2: continuation-split in-scope write ('$CONT_CMD_TEMPLATE') has no deny fields"
done

# F023 round 1 review: adding "&" to the split without stripping quotes first
# would deny a legitimate in-scope sed 's/foo/[&]/' whole-match idiom, or a
# filename containing "&", by treating the quoted "&" as a separator.
SED_AMP_CMD="sed -i 's/foo/[&]/' src/parser/f.txt"
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "$SED_AMP_CMD")")
RC=$?
assert_rc0 "$RC" "hs2: sed's quoted '&' whole-match idiom (in-scope) passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: sed's quoted '&' whole-match idiom has no deny fields"

CP_AMP_CMD='cp "a & b.txt" src/parser/dest.txt'
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "$CP_AMP_CMD")")
RC=$?
assert_rc0 "$RC" "hs2: a quoted '&' inside a filename (in-scope) passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: quoted '&' filename has no deny fields"

# F023 round 2 review: erasing quoted spans (rather than masking them) fed
# quote-erased text into TARGET EXTRACTION, not just segmentation -- so a
# quoted write target (the ordinary way to write a path, not adversarial
# evasion) was erased entirely before redirect_target()/last_flagless_token()
# ran, silently ALLOWING every one of these. Fixed by masking quoted spans
# (same length, so split positions still line up) only to find separator
# positions, then slicing the ORIGINAL text so segments keep their real
# quoted content; a target is unquoted only after extraction.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'echo x > "src/other/a.txt"')")
RC=$?
assert_rc0 "$RC" "hs2: a double-quoted out-of-scope redirect target still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: double-quoted redirect denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" "hs2: double-quoted redirect denial names the real target, unquoted"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "echo x > 'src/other/a.txt'")")
RC=$?
assert_rc0 "$RC" "hs2: a single-quoted out-of-scope redirect target still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: single-quoted redirect denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'rm "src/other/a.txt"')")
RC=$?
assert_rc0 "$RC" "hs2: a double-quoted out-of-scope rm target still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: double-quoted rm denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'rm -rf "src/other/"')")
RC=$?
assert_rc0 "$RC" "hs2: a double-quoted out-of-scope 'rm -rf' target still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: double-quoted 'rm -rf' denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'echo x | tee "src/other/a.txt"')")
RC=$?
assert_rc0 "$RC" "hs2: a double-quoted out-of-scope tee target still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: double-quoted tee denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "sed -i 's/a/b/' \"src/other/a.txt\"")")
RC=$?
assert_rc0 "$RC" "hs2: a double-quoted out-of-scope 'sed -i' target still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: double-quoted 'sed -i' denial uses JSON deny form"

# Same erasure bug also defeated the lead-owned state-file guard, a separate
# invariant, not part of F023 -- quoting one of the three protected paths
# was enough to erase it before the LEAD_OWNED membership check ran.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'echo x > ".harness/features.json"')")
RC=$?
assert_rc0 "$RC" "hs2: a double-quoted lead-owned redirect still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: double-quoted lead-owned redirect denial uses JSON deny form"
assert_contains "$OUT" "lead-owned" \
  "hs2: double-quoted lead-owned redirect denial names the invariant"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json "echo x >> '.harness/features.json'")")
RC=$?
assert_rc0 "$RC" "hs2: a single-quoted lead-owned append still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: single-quoted lead-owned append denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh "$(bash_command_json 'rm ".harness/context_summary.md"')")
RC=$?
assert_rc0 "$RC" "hs2: a double-quoted lead-owned rm still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: double-quoted lead-owned rm denial uses JSON deny form"

# cp/mv with a quoted DESTINATION must be checked against the destination,
# not fall through to the source argument once the quoted text is erased.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp src/parser/source.txt "src/other/dest.txt"')")
RC=$?
assert_rc0 "$RC" "hs2: cp with a quoted out-of-scope destination still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: cp quoted-destination denial uses JSON deny form"
assert_contains "$OUT" "src/other/dest.txt" \
  "hs2: cp quoted-destination denial names the destination, not the source"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'mv src/parser/source.txt "src/other/dest.txt"')")
RC=$?
assert_rc0 "$RC" "hs2: mv with a quoted out-of-scope destination still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: mv quoted-destination denial uses JSON deny form"
assert_contains "$OUT" "src/other/dest.txt" \
  "hs2: mv quoted-destination denial names the destination, not the source"

# Bonus fix: an in-scope quoted path containing a real "&" (e.g. "R&D") was a
# PRE-EXISTING false positive even before F023 -- the quote characters were
# never stripped from the comparison, so the target's leading '"' broke the
# scope-prefix match. Masking-then-unquoting (rather than erasing) repairs it.
mkdir -p "$DIR_HS/src/parser/R&D"
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'mv f.txt "src/parser/R&D/"')")
RC=$?
assert_rc0 "$RC" "hs2: a quoted in-scope path containing a real '&' passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: quoted in-scope '&' path has no deny fields"

# F024: write_target()/redirect_target() only ever returned the LAST target
# in a segment, so a command with multiple real write targets was checked
# only against its last one -- an out-of-scope target earlier in the same
# segment was never caught. Each case below has an out-of-scope target FIRST
# and an in-scope target LAST, so the old "last match wins" logic would mask
# the out-of-scope one.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'rm src/other/a.txt src/parser/b.txt')")
RC=$?
assert_rc0 "$RC" "hs2: multi-target rm with an out-of-scope FIRST target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: multi-target rm denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" \
  "hs2: multi-target rm denial names the actual out-of-scope target, not masked"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'tee src/other/a.txt src/parser/b.txt')")
RC=$?
assert_rc0 "$RC" "hs2: multi-target tee with an out-of-scope FIRST target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: multi-target tee denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" \
  "hs2: multi-target tee denial names the actual out-of-scope target, not masked"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'sed -i s/a/b/ src/other/a.txt src/parser/b.txt')")
RC=$?
assert_rc0 "$RC" "hs2: multi-target 'sed -i' with an out-of-scope FIRST target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: multi-target 'sed -i' denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" \
  "hs2: multi-target 'sed -i' denial names the actual out-of-scope target, not masked"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/other/a.txt 2> src/parser/b.txt')")
RC=$?
assert_rc0 "$RC" "hs2: multiple redirects in one segment, out-of-scope FIRST, exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: multi-redirect denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" \
  "hs2: multi-redirect denial names the actual out-of-scope target, not masked"

# cp -t DIR / mv -t DIR (and the --target-directory= form) put the real
# destination in a flag argument, which the old write_target() didn't look
# for at all -- an out-of-scope -t destination was never checked, even
# though every source argument is only READ, never written.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp -t src/other/ src/parser/a.txt src/parser/b.txt')")
RC=$?
assert_rc0 "$RC" "hs2: 'cp -t' out-of-scope destination exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: 'cp -t' denial uses JSON deny form"
assert_contains "$OUT" "src/other/" "hs2: 'cp -t' denial names the destination, not a source"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'mv -t src/other/ src/parser/a.txt')")
RC=$?
assert_rc0 "$RC" "hs2: 'mv -t' out-of-scope destination exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: 'mv -t' denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp --target-directory=src/other/ src/parser/a.txt')")
RC=$?
assert_rc0 "$RC" "hs2: 'cp --target-directory=' out-of-scope destination exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: 'cp --target-directory=' denial uses JSON deny form"

# No new false positive: all-in-scope multi-target commands, and a -t
# destination that IS in scope, must still pass cleanly.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'rm src/parser/a.txt src/parser/b.txt')")
RC=$?
assert_rc0 "$RC" "hs2: all-in-scope multi-target rm passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: all-in-scope multi-target rm has no deny fields"

# F029: all_flagless_tokens()/last_flagless_token() treated ANY token
# starting with "-" as a flag, unconditionally, with no awareness of "--" as
# the POSIX pathspec separator. `rm -- -a.txt` (a real, literal filename
# because "--" ends flag parsing) was misread: "--" and "-a.txt" were BOTH
# excluded as flag-shaped, so no target was identified at all and the
# command was wrongly ALLOWED even when -a.txt was out of scope. Sibling
# hook commit-gate.sh.template already recognizes "--" this way
# (has_staging_flag's `if tok == "--": break`); this hook never got the
# equivalent treatment until now.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'rm -- -a.txt')")
RC=$?
assert_rc0 "$RC" "hs2 (F029): 'rm -- -a.txt' out-of-scope literal-dash target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2 (F029): 'rm -- -a.txt' denial uses JSON deny form"
assert_contains "$OUT" "-a.txt" \
  "hs2 (F029): 'rm -- -a.txt' denial names the real target, not silently allowed"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'tee -- -a.txt')")
RC=$?
assert_rc0 "$RC" "hs2 (F029): 'tee -- -a.txt' out-of-scope literal-dash target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2 (F029): 'tee -- -a.txt' denial uses JSON deny form"

# last_flagless_token() (cp/mv's no-flag-destination fallback) has the same
# gap: a destination that is itself a literal dash-prefixed filename after
# "--" must still be recognized as the real, checkable destination, not
# skipped in favor of the (in-scope) source argument before it.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'mv src/parser/a.txt -- -out.txt')")
RC=$?
assert_rc0 "$RC" "hs2 (F029): 'mv ... -- -out.txt' out-of-scope literal-dash destination exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2 (F029): 'mv ... -- -out.txt' denial uses JSON deny form"
assert_contains "$OUT" "-out.txt" \
  "hs2 (F029): 'mv ... -- -out.txt' denial names the destination, not the in-scope source"

# No new false positive: an in-scope literal-dash filename after "--" must
# still pass cleanly.
mkdir -p "$DIR_HS/src/parser"
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'rm -- src/parser/-a.txt')")
RC=$?
assert_rc0 "$RC" "hs2 (F029): 'rm -- src/parser/-a.txt' in-scope literal-dash target passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2 (F029): in-scope literal-dash target after '--' has no deny fields"

# A second "--" after the first is ordinary literal text (POSIX: only the
# FIRST "--" ends flag parsing), not another separator. The trailing "--"
# here is itself the (out-of-scope) target -- a version that treated EVERY
# "--" as a separator would just re-consume it and find no target at all,
# wrongly ALLOWING the command; this is discriminating where an earlier
# draft (two real out-of-scope paths around the second "--") was not, since
# that draft passed identically whether or not the second "--" was treated
# as literal text (found by adversarial review of PR #52, round 2).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'rm -- src/parser/a.txt --')")
RC=$?
assert_rc0 "$RC" "hs2 (F029): a second '--' is literal text, not another separator (JSON deny)"
assert_deny_json "$OUT" "hs2 (F029): trailing-'--'-as-target denial uses JSON deny form"
assert_contains "$OUT" "write to '--'" \
  "hs2 (F029): trailing-'--'-as-target denial names '--' itself, not silently allowed"

# Round-1 review of PR #52: cp_mv_targets()'s own -t/--target-directory=
# scan had the identical "--" gap, in a DIFFERENT function than
# all_flagless_tokens() -- so fixing that one alone left this one open. A
# literal filename starting with "-t" placed AFTER "--" was misread as the
# -t flag itself and string-sliced into a bogus target, while the REAL
# destination (the last positional argument) went unchecked entirely --
# found by adversarial review of PR #52 (F029).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'mv -- -tsrc/parser/decoy.txt src/other/dest.txt')")
RC=$?
assert_rc0 "$RC" "hs2 (F029): 'mv -- -tPATH ...' out-of-scope real destination exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2 (F029): 'mv -- -tPATH ...' denial uses JSON deny form"
assert_contains "$OUT" "src/other/dest.txt" \
  "hs2 (F029): 'mv -- -tPATH ...' denial names the real destination, not a bogus -t slice"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp -- --target-directory=src/parser/decoy a.txt src/other/dest.txt')")
RC=$?
assert_rc0 "$RC" "hs2 (F029): 'cp -- --target-directory=...' out-of-scope real destination exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2 (F029): 'cp -- --target-directory=...' denial uses JSON deny form"
assert_contains "$OUT" "src/other/dest.txt" \
  "hs2 (F029): 'cp -- --target-directory=...' denial names the real destination, not the decoy"

# No new false positive: a real -t/--target-directory= flag BEFORE "--"
# must still be recognized and take priority over the trailing positionals.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp -t src/parser/ -- a.txt b.txt')")
RC=$?
assert_rc0 "$RC" "hs2 (F029): a real '-t' flag before '--' still passes cleanly, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2 (F029): real '-t' before '--' has no deny fields"

# sed_inplace_targets() has the identical gap: a real, literal-dash-prefixed
# file target after "--" went unchecked, since every token starting with
# "-" (including "--" itself) was skipped as a flag unconditionally. A
# target with no leading "-" doesn't discriminate here -- it falls through
# to the target-capture branch either way, since only DASH-PREFIXED tokens
# were ever at risk of being mistaken for a flag -- so this uses the same
# literal-dash-filename shape as the rm/tee/mv cases above (found by
# adversarial review of PR #52, F029).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json "sed -i 's/a/b/' -- -out.txt")")
RC=$?
assert_rc0 "$RC" "hs2 (F029): 'sed -i ... -- -out.txt' out-of-scope literal-dash target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2 (F029): 'sed -i ... -- -out.txt' denial uses JSON deny form"
assert_contains "$OUT" "-out.txt" \
  "hs2 (F029): 'sed -i ... -- -out.txt' denial names the real target after '--'"

# Round-2 review of PR #52: the two any()-based guards above (in-place
# presence, has_explicit_script) scanned ALL of args, including tokens AFTER
# "--", not just the token-walking loop -- round 1 only fixed the loop. A
# real out-of-scope FILE target that happens to start with "-i" (but there
# is no actual -i flag anywhere before "--") wrongly triggered the in-place
# guard; a real file literally named "-e"/"-f" after "--" wrongly triggered
# has_explicit_script, misreading the SCRIPT itself as the (wrong) target
# instead of the real file (found by adversarial review of PR #52, round 2).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json "sed 's/a/b/' -- -input.txt")")
RC=$?
assert_rc0 "$RC" "hs2 (F029): sed with no real -i flag, only a post-'--' '-i'-shaped filename, passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2 (F029): no real -i flag means no false deny, even with a '-i'-shaped filename after '--'"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json "sed -i 's/a/b/' -- -e")")
RC=$?
assert_rc0 "$RC" "hs2 (F029): 'sed -i ... -- -e' (a real file literally named -e) exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2 (F029): 'sed -i ... -- -e' denial uses JSON deny form"
assert_contains "$OUT" "write to '-e'" \
  "hs2 (F029): 'sed -i ... -- -e' denial names the real file '-e', not the script text"

# Round-3 review of PR #52: round 2's pre_separator_args used a NAIVE
# first-literal-"--" index, disagreeing with the token-walking loop's own
# FLAG-AWARE walk, which skips a "--" consumed as an -e/-f/--expression/
# --file VALUE (a script file literally named "--", e.g. `sed -f -- ...`).
# The disagreement truncated the any() guards one token too early, missing
# a genuine -i flag positioned right after the value-consumed "--" -- a
# false negative wrongly ALLOWING a real in-place edit of an out-of-scope
# file (found by adversarial review of PR #52, round 3).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'sed -f -- -i src/other/f.txt')")
RC=$?
assert_rc0 "$RC" "hs2 (F029): 'sed -f -- -i FILE' (-- is -f's own value, -i is real) exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2 (F029): 'sed -f -- -i FILE' denial uses JSON deny form"
assert_contains "$OUT" "src/other/f.txt" \
  "hs2 (F029): 'sed -f -- -i FILE' denial names the real out-of-scope target"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp -t src/parser/ src/parser/a.txt src/parser/b.txt')")
RC=$?
assert_rc0 "$RC" "hs2: 'cp -t' with an in-scope destination passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: in-scope 'cp -t' has no deny fields"

# Regression: normal cp/mv (no -t) must still check only the DESTINATION
# (the last flagless argument), not the source arguments -- a source read
# from outside scope is not a write and must not be denied.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp src/other/source.txt src/parser/dest.txt')")
RC=$?
assert_rc0 "$RC" "hs2: plain cp with an out-of-scope SOURCE and in-scope dest passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: plain cp only checks the destination, not the source"

# F024 round 1 review: the sed script-skip fix (round-1 fix) broke the
# macOS/BSD sed -i idiom, which REQUIRES a backup-suffix argument (commonly
# the empty string): `sed -i '' 's/.../ ' file` is in-scope, ordinary work on
# this repo's own platform, but the round-1 fix's "skip exactly one leading
# flagless token" heuristic skipped the empty-string suffix and misread the
# real script as the file target, denying legitimate work.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json "sed -i '' 's/a/b/' src/parser/a.txt")")
RC=$?
assert_rc0 "$RC" "hs2: BSD-style 'sed -i ''' with an in-scope target passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: BSD-style 'sed -i ''' does not misread the script as the file"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json "sed -i '' 's/a/b/' src/other/a.txt")")
RC=$?
assert_rc0 "$RC" "hs2: BSD-style 'sed -i ''' with an out-of-scope target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: BSD-style 'sed -i ''' denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" \
  "hs2: BSD-style 'sed -i ''' denial names the real file, not the script"

# Multiple -e expressions: each one's value must be skipped, not misread as
# a file target.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json "sed -i -e 's/a/b/' -e 's/c/d/' src/parser/a.txt")")
RC=$?
assert_rc0 "$RC" "hs2: multi -e 'sed -i' with an in-scope target passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: multi -e 'sed -i' does not misread a later -e value as the file"

# Long-form attached script flags (--expression=/--file=): the script never
# appears as a separate flagless token at all, so there is no implicit
# script token to skip -- the sole flagless token is the real file and must
# not be dropped.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json "sed -i --expression='s/a/b/' src/other/a.txt")")
RC=$?
assert_rc0 "$RC" "hs2: 'sed -i --expression=' with an out-of-scope target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: 'sed -i --expression=' denial uses JSON deny form"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'sed -i --file=script.sed src/other/a.txt')")
RC=$?
assert_rc0 "$RC" "hs2: 'sed -i --file=' with an out-of-scope target exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: 'sed -i --file=' denial uses JSON deny form"

# F024 round 1 review: write_targets() only checked ONE extractor category
# per segment (redirect targets OR command-type targets, whichever fired
# first), so a segment with BOTH a real write command and an unrelated
# trailing redirect only ever had its redirect target checked -- the
# command's own real target (out of scope) went uncaught, the exact
# multi-target-masking shape F024 exists to close, just across extractor
# categories instead of within one.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'tee src/other/a.txt > src/parser/log.txt')")
RC=$?
assert_rc0 "$RC" "hs2: tee target masked by a trailing redirect still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: tee-plus-redirect denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" \
  "hs2: tee-plus-redirect denial names the tee target, not just the redirect"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'rm src/other/a.txt > src/parser/log.txt')")
RC=$?
assert_rc0 "$RC" "hs2: rm target masked by a trailing redirect still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: rm-plus-redirect denial uses JSON deny form"
assert_contains "$OUT" "src/other/a.txt" \
  "hs2: rm-plus-redirect denial names the rm target, not just the redirect"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp -t src/other/ src/parser/a.txt > src/parser/log.txt')")
RC=$?
assert_rc0 "$RC" "hs2: 'cp -t' destination masked by a trailing redirect still exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: 'cp -t'-plus-redirect denial uses JSON deny form"
assert_contains "$OUT" "src/other/" \
  "hs2: 'cp -t'-plus-redirect denial names the -t destination, not just the redirect"

# No new false positive: a write command plus an in-scope trailing redirect,
# both in scope, must still pass cleanly.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'tee src/parser/a.txt > src/parser/log.txt')")
RC=$?
assert_rc0 "$RC" "hs2: all-in-scope tee-plus-redirect passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: all-in-scope tee-plus-redirect has no deny fields"

# F024 round 2 review: strip_redirects()'s >>?\s*[^\s<>|&;]+ regex removed
# the operator and its target but not a preceding file-descriptor digit
# (2>, 1>), leaving a stray digit token that the command extractors (which
# now always run, per round 1's fix) misread as a real write target -- an
# all-in-scope command was wrongly denied naming the bare digit.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'rm src/parser/a.txt 2> src/parser/err.log')")
RC=$?
assert_rc0 "$RC" "hs2: fd-prefixed redirect (space form) with all in-scope targets passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: fd-prefixed redirect (space form) does not leave a stray digit target"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'rm src/parser/a.txt 2>src/parser/err.log')")
RC=$?
assert_rc0 "$RC" "hs2: fd-prefixed redirect (no-space form) with all in-scope targets passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: fd-prefixed redirect (no-space form) does not leave a stray digit target"

# Caution (per review): a naive digit-prefix strip must NOT truncate a real
# argument that merely ENDS in a digit immediately before an UNPREFIXED
# redirect operator, with NO separating space -- no fd semantics at all here
# ("src/other/version2" is one whole word, not "just digits", so per real
# bash it is NOT an fd number; `echo abc2> out` writes "abc2", not "abc").
# The fd-prefix rule only applies when the digit run is its OWN complete
# token (whitespace or start-of-segment immediately before it). Uses an
# OUT-OF-SCOPE target specifically so truncation is observable in the
# denial message: an all-in-scope version can't discriminate, since a
# naively truncated "version" is still in scope right alongside the correct
# "version2" (found by adversarial review of PR #46, round 4 -- the
# round-3 version of this test used an all-in-scope target and could not
# actually tell a truncating regex apart from a correct one).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'rm src/other/version2> src/parser/log.txt')")
RC=$?
assert_rc0 "$RC" "hs2: an out-of-scope target ending in a digit, no-space unprefixed redirect, denies"
assert_deny_json "$OUT" "hs2: out-of-scope digit-ending-target denial uses JSON deny form"
assert_contains "$OUT" "src/other/version2" \
  "hs2: the digit at the end of the real filename is not truncated off"

# F024 round 3 review: anchoring the ENTIRE match (not just the optional
# digit run) to a token boundary made a BARE ">" (no fd prefix at all) fail
# to match unless it was ALSO preceded by whitespace -- so a redirect glued
# directly onto a cp/mv destination with no separating space
# (`cp a b> log`) was never stripped, and cp/mv's destination detection fell
# through to the unstripped trailing text, picking the redirect's own target
# instead of the real destination -- reintroducing F024's own masking bug.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp src/parser/a.txt src/other/b.txt> src/parser/log.txt')")
RC=$?
assert_rc0 "$RC" "hs2: cp with a no-space '>' glued to an out-of-scope destination exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: cp no-space-'>' denial uses JSON deny form"
assert_contains "$OUT" "src/other/b.txt" \
  "hs2: cp no-space-'>' denial names the real destination, not the redirect's target"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'mv src/parser/a.txt src/other/b.txt> src/parser/log.txt')")
RC=$?
assert_rc0 "$RC" "hs2: mv with a no-space '>' glued to an out-of-scope destination exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: mv no-space-'>' denial uses JSON deny form"

# No new false positive: the same no-space-'>' shape, all in scope, must
# still pass cleanly.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'cp src/parser/a.txt src/parser/b.txt> src/parser/log.txt')")
RC=$?
assert_rc0 "$RC" "hs2: all-in-scope cp with a no-space '>' passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: all-in-scope cp no-space-'>' has no deny fields"

# F026: normalize() strips the project-root prefix but never resolves ".."
# path traversal, so a write target that escapes the allowed directory via
# traversal still matches the allowed prefix under a bare .startswith()
# check. Verified in real bash: `echo x > src/parser/../other/x.txt`
# actually writes to src/other/x.txt, outside the "src/parser/" scope.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/parser/../other/x.txt')")
RC=$?
assert_rc0 "$RC" "hs2: a '..'-traversal escaping scope exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: traversal denial uses JSON deny form"
assert_contains "$OUT" "src/other/x.txt" \
  "hs2: traversal denial names the real, resolved out-of-scope path"

# The same gap under quoting (unquote_token, added by F023, means these
# spellings now reach the traversal unresolved rather than being
# incidentally denied by un-stripped quote characters). Asserts the
# resolved path specifically, not just any deny -- without this, a fully
# broken unquote_token could still deny (for the wrong reason: un-stripped
# quote characters breaking the prefix match, the exact "incidentally
# denied" confusion this comment describes) and the assertion wouldn't
# notice (found by adversarial review of PR #48, round 1).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > "src/parser/"../other/x.txt')")
RC=$?
assert_rc0 "$RC" "hs2: a quoted-prefix '..'-traversal exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: quoted-prefix traversal denial uses JSON deny form"
assert_contains "$OUT" "src/other/x.txt" \
  "hs2: quoted-prefix traversal denial names the real, resolved path"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > "src/parser/../other/x.txt"')")
RC=$?
assert_rc0 "$RC" "hs2: a fully-quoted '..'-traversal exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: fully-quoted traversal denial uses JSON deny form"
assert_contains "$OUT" "src/other/x.txt" \
  "hs2: fully-quoted traversal denial names the real, resolved path"

# No new false positive: a "." or ".." segment that resolves back INSIDE
# the allowed scope must still pass (e.g. a round-trip through a
# subdirectory, or a redundant "./").
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/parser/sub/../ok.txt')")
RC=$?
assert_rc0 "$RC" "hs2: a '..'-traversal that resolves back in-scope passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: an in-scope-resolving traversal has no deny fields"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/parser/./ok.txt')")
RC=$?
assert_rc0 "$RC" "hs2: a redundant './' segment resolving in-scope passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: a redundant './' segment has no deny fields"

# The lead-owned state-file guard must also resolve traversal, not just the
# scope-prefix check -- both read the same normalize() output.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/parser/../../.harness/features.json')")
RC=$?
assert_rc0 "$RC" "hs2: a '..'-traversal into a lead-owned state file exits 0 (JSON deny)"
assert_contains "$OUT" "lead-owned" \
  "hs2: traversal-to-lead-owned denial names the invariant"

# F026 round 1 review: the Edit/Write/MultiEdit legacy path (FILE_PATH,
# handled entirely in bash before the Bash-command Python script ever
# runs) has the SAME missing-traversal-resolution bug as normalize() did --
# it strips the project-root prefix but never resolves ".."/"." segments,
# and it is the MORE authoritative gate (Edit/Write tool calls, not the
# best-effort Bash coverage). A teammate scoped to "src/parser/" could
# traverse out via Edit even after the Bash-side fix (found by adversarial
# review of PR #48).
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(edit_json "$DIR_HS/src/parser/../other/y.py")")
RC=$?
assert_rc2 "$RC" "hs2: Edit with a '..'-traversal escaping scope is blocked (legacy exit 2)"
assert_contains "$OUT" "src/other/y.py" \
  "hs2: Edit traversal block message names the real, resolved out-of-scope file"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(edit_json "$DIR_HS/src/parser/../../.harness/features.json")")
RC=$?
assert_rc0 "$RC" "hs2: Edit with a '..'-traversal into a lead-owned file exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: Edit traversal-to-lead-owned denial uses JSON deny form"
assert_contains "$OUT" "lead-owned" \
  "hs2: Edit traversal-to-lead-owned denial names the invariant"

OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(edit_json "$DIR_HS/src/parser/sub/../ok.py")")
RC=$?
assert_rc0 "$RC" "hs2: Edit with a '..'-traversal that resolves back in-scope passes, rc 0"

# F026 round 2 review: routing FILE_PATH's prefix-strip through Python's
# literal str.startswith() (rather than the old bash `${FILE_PATH#$PROJECT_ROOT/}`,
# which used UNQUOTED $PROJECT_ROOT in bash pattern-match position) fixed an
# unadvertised pre-existing false positive: a project root whose path
# contains a shell glob metacharacter (e.g. "[1]") broke the old bash
# substring-stripping, wrongly blocking an in-scope edit. Locking it in with
# a dedicated fixture whose path contains such a character.
DIR_HS_GLOBROOT="$WORK/ht-scope-root[1]"
make_fixture "$DIR_HS_GLOBROOT"
install_hooks "$DIR_HS_GLOBROOT"
printf 'src/parser/\n' > "$DIR_HS_GLOBROOT/.claude/teammate-scope.txt"
OUT=$(run_hook "$DIR_HS_GLOBROOT" enforce-scope.sh \
  "$(edit_json "$DIR_HS_GLOBROOT/src/parser/x.py")")
RC=$?
assert_rc0 "$RC" "hs2: an in-scope edit under a glob-metacharacter project root passes, rc 0"

# F031: unquote_token() strips quote characters from an extracted target but
# never removes shell backslash-escapes, so a backslash-escaped ".." segment
# reads as a literal directory name ("\..") rather than a real traversal
# segment -- normalize()'s os.path.normpath() only collapses the exact
# string "..", not "\..", so the scope-prefix check is fooled even though
# real bash strips the backslash and genuinely traverses out. Filed during
# F026's review.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/parser/\../other/x.txt')")
RC=$?
assert_rc0 "$RC" "hs2: a backslash-escaped '..'-traversal exits 0 (JSON deny)"
assert_deny_json "$OUT" "hs2: backslash-escaped traversal denial uses JSON deny form"
assert_contains "$OUT" "src/other/x.txt" \
  "hs2: backslash-escaped traversal denial names the real, resolved out-of-scope path"

# Not applicable to the Edit/Write/MultiEdit legacy path: file_path arrives as
# a literal JSON string parameter, never shell-parsed, so a backslash
# character in it is just part of the filename -- there is no shell to strip
# it, unlike a Bash tool_input command string.

# A backslash before an ordinary character elsewhere in an in-scope path
# must not itself trigger a false denial -- only ".." segments matter.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/parser/\ok.txt')")
RC=$?
assert_rc0 "$RC" "hs2: a backslash-escaped ordinary character in an in-scope path passes, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: backslash-escaped ordinary character has no deny fields"

# A more discriminating case than the one above: this must ALLOW under the
# correct fix (unescaping "\p" -> "p" yields "src/parser/ok.txt", in scope)
# but DENY under both no-fix (the literal "\parser" segment never matches
# the "src/parser/" prefix) and an over-broad delete-the-character mutant
# (which would yield "src/arser/ok.txt", also out of scope) -- so, unlike
# the case above, this one actually fails without the real fix.
OUT=$(run_hook "$DIR_HS" enforce-scope.sh \
  "$(bash_command_json 'echo x > src/\parser/ok.txt')")
RC=$?
assert_rc0 "$RC" "hs2: an escaped-but-ordinary path segment resolves to its in-scope form, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "hs2: escaped-but-ordinary path segment has no deny fields"

for TPL in check-remaining-tasks.sh.template enforce-scope.sh.template \
  verify-git-identity.sh.template verify-task-quality.sh.template; do
  if grep -q '^# Failure posture:' "$TEMPLATES_DIR/$TPL"; then
    pass "hs2: $TPL documents its failure posture"
  else
    fail "hs2: $TPL lacks a '# Failure posture:' header line"
  fi
done

if grep -q "Bash remains open by instruction" "$REPO_ROOT/agents/reviewer.md" \
  && grep -q "backstop" "$REPO_ROOT/agents/reviewer.md"; then
  pass "hs2: reviewer.md acknowledges the Bash backstop"
else
  fail "hs2: reviewer.md missing the Bash-backstop acknowledgment"
fi

if grep -qi "best-effort" "$REPO_ROOT/README.md" && grep -q "lead-owned" "$REPO_ROOT/README.md"; then
  pass "hs2: README's tiers table documents best-effort Bash coverage + lead-owned files"
else
  fail "hs2: README's tiers table missing the best-effort/lead-owned relabeling"
fi

DIR_HG="$WORK/ht-identity"
make_fixture "$DIR_HG"
install_hooks "$DIR_HG"
PUSH_JSON='{"tool_input":{"command":"git push origin main"}}'
OUT=$(run_hook "$DIR_HG" verify-git-identity.sh "$PUSH_JSON")
RC=$?
assert_rc0 "$RC" "ht: verify-git-identity allows git push on identity match"
OUT=$(run_hook "$DIR_HG" verify-git-identity.sh '{"tool_input":{"command":"ls -la"}}')
RC=$?
assert_rc0 "$RC" "ht: verify-git-identity ignores non-git commands"
git -C "$DIR_HG" config user.name "Impostor"
OUT=$(run_hook "$DIR_HG" verify-git-identity.sh "$PUSH_JSON")
RC=$?
assert_rc2 "$RC" "ht: verify-git-identity blocks git push on identity mismatch"
assert_contains "$OUT" "Fix with: git config user.name" "ht: mismatch message includes the fix command"

# Hostile case (F005/OVI-61): mismatched EMAIL specifically, name restored to match.
git -C "$DIR_HG" config user.name "Fixture User"
git -C "$DIR_HG" config user.email "impostor@example.com"
OUT=$(run_hook "$DIR_HG" verify-git-identity.sh "$PUSH_JSON")
RC=$?
assert_rc2 "$RC" "hg: verify-git-identity blocks git push on email mismatch alone"
assert_contains "$OUT" "Fix with: git config user.name" \
  "hg: email-mismatch message includes the fix command"
assert_contains "$OUT" "impostor@example.com" \
  "hg: email-mismatch message names the current (wrong) email"

DIR_HR="$WORK/ht-remaining"
make_fixture "$DIR_HR"
install_hooks "$DIR_HR"
OUT=$(run_hook "$DIR_HR" check-remaining-tasks.sh '{}')
RC=$?
assert_rc2 "$RC" "ht: check-remaining-tasks exits 2 when a feature is claimable"
assert_contains "$OUT" "F003" "ht: offers the claimable feature id"
python3 - "$DIR_HR/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    feature["status"] = "passing"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_hook "$DIR_HR" check-remaining-tasks.sh '{}')
RC=$?
assert_rc0 "$RC" "ht: check-remaining-tasks exits 0 when nothing is claimable"

DIR_HM="$WORK/ht-remaining-malformed"
make_fixture "$DIR_HM"
install_hooks "$DIR_HM"
python3 - "$DIR_HM/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
data["features"][0] = "not a feature object"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_hook "$DIR_HM" check-remaining-tasks.sh '{}' 2>&1)
RC=$?
assert_rc2 "$RC" "ht: a malformed feature entry does not stop idle reassignment"
assert_contains "$OUT" "F003" "ht: the valid claimable feature is still offered"
assert_contains "$OUT" "malformed feature entry" "ht: the malformed entry is noted on stderr"

DIR_HF="$WORK/ht-remaining-malformed-field"
make_fixture "$DIR_HF"
install_hooks "$DIR_HF"
python3 - "$DIR_HF/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F002":
        feature["status"] = "pending"
        feature["depends_on"] = 5
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_hook "$DIR_HF" check-remaining-tasks.sh '{}' 2>&1)
RC=$?
assert_rc2 "$RC" "ht: a malformed field inside a feature does not stop idle reassignment"
assert_contains "$OUT" "F003" "ht: the valid claimable feature is still offered past a bad field"
assert_contains "$OUT" "malformed feature entry" "ht: the bad-field entry is noted on stderr"

DIR_HQ="$WORK/ht-quality-noinit"
make_fixture "$DIR_HQ"
install_hooks "$DIR_HQ"
OUT=$(run_hook "$DIR_HQ" verify-task-quality.sh '{}')
RC=$?
assert_rc2 "$RC" "ht: verify-task-quality rejects when .harness/init.sh is missing"
assert_contains "$OUT" "init.sh not found" \
  "hg: missing-init.sh message names the violated invariant (F005/OVI-61)"
assert_contains "$OUT" "Run /harness-init" \
  "hg: missing-init.sh message names the repair (F005/OVI-61)"

DIR_HQ2="$WORK/ht-quality-targeted"
make_fixture "$DIR_HQ2"
install_hooks "$DIR_HQ2"
printf '#!/bin/bash\nexit 1\n' > "$DIR_HQ2/.harness/init.sh"
python3 - "$DIR_HQ2/.harness/features.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F003":
        feature["status"] = "in-progress"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
OUT=$(run_hook "$DIR_HQ2" verify-task-quality.sh \
  '{"task":{"metadata":{"feature_id":"F002"}}}' 2>&1)
RC=$?
assert_rc2 "$RC" "ht: smoke failure rejects the targeted completion"
assert_contains "$OUT" "smoke test failed" \
  "hg: smoke-failure message names the violated invariant (F005/OVI-61)"
assert_contains "$OUT" "Fix compilation errors before marking complete" \
  "hg: smoke-failure message names the repair (F005/OVI-61)"
METRICS=$(python3 - "$DIR_HQ2/.harness/features.json" <<'PYEOF'
import json
import sys

with open(sys.argv[1]) as fh:
    data = json.load(fh)
by_id = {f["id"]: f for f in data["features"]}
f2 = by_id["F002"].get("correction_cycles", 0)
f3 = by_id["F003"].get("correction_cycles", 0)
print(f"F002={f2} F003={f3}")
PYEOF
)
assert_contains "$METRICS" "F002=1 F003=0" \
  "ht: correction_cycles incremented only for the targeted feature"
if [ -z "$(tail -c 1 "$DIR_HQ2/.harness/features.json")" ]; then
  pass "ht: features.json keeps its trailing newline after the metrics write"
else
  fail "ht: features.json lost its trailing newline after the metrics write"
fi

DIR_HQ3="$WORK/ht-quality-untargeted"
make_fixture "$DIR_HQ3"
install_hooks "$DIR_HQ3"
printf '#!/bin/bash\nexit 1\n' > "$DIR_HQ3/.harness/init.sh"
SUM_BEFORE=$(cksum < "$DIR_HQ3/.harness/features.json")
OUT=$(run_hook "$DIR_HQ3" verify-task-quality.sh '{}' 2>&1)
RC=$?
assert_rc2 "$RC" "ht: untargeted rejection still exits 2"
SUM_AFTER=$(cksum < "$DIR_HQ3/.harness/features.json")
if [ "$SUM_BEFORE" = "$SUM_AFTER" ]; then
  pass "ht: features.json is byte-identical after an untargeted rejection"
else
  fail "ht: features.json changed on an untargeted rejection"
fi
assert_contains "$OUT" "no feature_id" "ht: untargeted rejection notes the missing feature_id"

DIR_HQ4="$WORK/ht-quality-stale-tmp"
make_fixture "$DIR_HQ4"
install_hooks "$DIR_HQ4"
printf '#!/bin/bash\nexit 1\n' > "$DIR_HQ4/.harness/init.sh"
printf 'STALE GARBAGE NOT JSON' > "$DIR_HQ4/.harness/features.json.tmp"
SUM_BEFORE=$(cksum < "$DIR_HQ4/.harness/features.json")
OUT=$(run_hook "$DIR_HQ4" verify-task-quality.sh \
  '{"task":{"metadata":{"feature_id":"F003"}}}' 2>&1)
RC=$?
assert_rc2 "$RC" "ht: rejection with a stale tmp present still exits 2"
SUM_AFTER=$(cksum < "$DIR_HQ4/.harness/features.json")
if [ "$SUM_BEFORE" = "$SUM_AFTER" ]; then
  pass "ht: a stale features.json.tmp is never promoted over features.json"
else
  fail "ht: a stale features.json.tmp clobbered features.json"
fi
if [ -f "$DIR_HQ4/.harness/features.json.tmp" ]; then
  fail "ht: the stale tmp should be cleared, not left to poison a later run"
else
  pass "ht: the stale tmp is cleared"
fi

set_f003_fields() {
  # $1: fixture dir, $2: python snippet setting fields on the F003 dict named `feature`
  python3 - "$1/.harness/features.json" <<PYEOF
import json
path = "$1/.harness/features.json"
with open(path) as fh:
    data = json.load(fh)
for feature in data["features"]:
    if feature["id"] == "F003":
        feature["status"] = "in-progress"
        $2
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF
}

DIR_HQ5="$WORK/ht-quality-coverage-target-accept"
make_fixture "$DIR_HQ5"
install_hooks "$DIR_HQ5"
printf '#!/bin/bash\nexit 0\n' > "$DIR_HQ5/.harness/init.sh"
set_f003_fields "$DIR_HQ5" 'feature["coverage_target"] = 80
        feature["coverage"] = 85'
OUT=$(run_hook "$DIR_HQ5" verify-task-quality.sh '{"task":{"metadata":{"feature_id":"F003"}}}' 2>&1)
RC=$?
assert_rc0 "$RC" "ht: coverage_target 80 with 85% coverage accepts"

DIR_HQ6="$WORK/ht-quality-coverage-target-reject"
make_fixture "$DIR_HQ6"
install_hooks "$DIR_HQ6"
printf '#!/bin/bash\nexit 0\n' > "$DIR_HQ6/.harness/init.sh"
set_f003_fields "$DIR_HQ6" 'feature["coverage"] = 85'
OUT=$(run_hook "$DIR_HQ6" verify-task-quality.sh '{"task":{"metadata":{"feature_id":"F003"}}}' 2>&1)
RC=$?
assert_rc2 "$RC" "ht: no coverage_target with 85% coverage rejects (95% default)"
assert_contains "$OUT" "coverage" "ht: coverage rejection message mentions coverage"

DIR_HQ7="$WORK/ht-quality-no-proof-warn"
make_fixture "$DIR_HQ7"
install_hooks "$DIR_HQ7"
printf '#!/bin/bash\nexit 0\n' > "$DIR_HQ7/.harness/init.sh"
set_f003_fields "$DIR_HQ7" 'pass'
OUT=$(run_hook "$DIR_HQ7" verify-task-quality.sh '{"task":{"metadata":{"feature_id":"F003"}}}' 2>&1)
RC=$?
assert_rc0 "$RC" "ht: acceptance with no proof still exits 0"
assert_contains "$OUT" "no proof recorded" "ht: no-proof acceptance warns on stdout"
assert_contains "$OUT" "F003" "ht: no-proof warning names the feature"

DIR_HQ8="$WORK/ht-quality-qa-binding-match"
make_fixture "$DIR_HQ8"
install_hooks "$DIR_HQ8"
printf '#!/bin/bash\nexit 0\n' > "$DIR_HQ8/.harness/init.sh"
set_f003_fields "$DIR_HQ8" 'feature["qa_binding"] = "unit"
        feature["proof"] = {"claim": "x", "evidence_type": "unit",
        "artifact": "y", "not_established": "z"}'
OUT=$(run_hook "$DIR_HQ8" verify-task-quality.sh '{"task":{"metadata":{"feature_id":"F003"}}}' 2>&1)
RC=$?
assert_rc0 "$RC" "ht: acceptance with matching proof/qa_binding exits 0"
assert_not_contains "$OUT" "no proof recorded" "ht: matching proof has no no-proof warning"
assert_not_contains "$OUT" "does not match" "ht: matching proof has no mismatch warning"

DIR_HQ9="$WORK/ht-quality-qa-binding-mismatch"
make_fixture "$DIR_HQ9"
install_hooks "$DIR_HQ9"
printf '#!/bin/bash\nexit 0\n' > "$DIR_HQ9/.harness/init.sh"
set_f003_fields "$DIR_HQ9" 'feature["qa_binding"] = "unit"
        feature["proof"] = {"claim": "x", "evidence_type": "journey",
        "artifact": "y", "not_established": "z"}'
OUT=$(run_hook "$DIR_HQ9" verify-task-quality.sh '{"task":{"metadata":{"feature_id":"F003"}}}' 2>&1)
RC=$?
assert_rc0 "$RC" "ht: acceptance with mismatched proof/qa_binding still exits 0"
assert_contains "$OUT" "unit" "ht: mismatch warning names the declared qa_binding"
assert_contains "$OUT" "journey" "ht: mismatch warning names the actual evidence_type"

DIR_HQ10="$WORK/ht-quality-legacy-no-binding"
make_fixture "$DIR_HQ10"
install_hooks "$DIR_HQ10"
printf '#!/bin/bash\nexit 0\n' > "$DIR_HQ10/.harness/init.sh"
set_f003_fields "$DIR_HQ10" \
  'feature["proof"] = {"claim": "x", "evidence_type": "unit",
  "artifact": "y", "not_established": "z"}'
OUT=$(run_hook "$DIR_HQ10" verify-task-quality.sh \
  '{"task":{"metadata":{"feature_id":"F003"}}}' 2>&1)
RC=$?
assert_rc0 "$RC" "ht: acceptance with proof but no declared qa_binding exits 0"
assert_not_contains "$OUT" "no proof recorded" "ht: legacy no-binding case has no no-proof warning"
assert_not_contains "$OUT" "does not match" "ht: legacy no-binding case has no mismatch warning"

SETTINGS_BLOCK_ERRORS=$(python3 - "$REPO_ROOT" <<'PYEOF'
import os
import re
import sys

root = sys.argv[1]
text = open(os.path.join(root, "skills", "harness-init", "SKILL.md")).read()
blocks = [b for b in re.findall(r"```json\n(.*?)\n```", text, re.DOTALL) if "statusLine" in b]
if len(blocks) != 1:
    print(f"expected exactly one settings block containing statusLine, found {len(blocks)}")
    sys.exit()
block = blocks[0]
if "bash .claude/hooks/" in block:
    print("settings block still invokes hooks cwd-relative (bash .claude/hooks/...)")
if block.count('\\"$CLAUDE_PROJECT_DIR\\"/.claude/hooks/') < 5:
    print("settings block lacks the CLAUDE_PROJECT_DIR-absolute invocation form")
if '"Bash(bash .claude/hooks/*.sh)"' in block:
    print("permissions allowlist still lists the cwd-relative hook form")
PYEOF
)
if [ -z "$SETTINGS_BLOCK_ERRORS" ]; then
  pass "ht: SKILL.md settings block invokes hooks via \$CLAUDE_PROJECT_DIR"
else
  fail "ht: SKILL.md settings block -- $SETTINGS_BLOCK_ERRORS"
fi

echo ""
echo "== harness_state.py =="

STATE_MODULE_TEMPLATE="$TEMPLATES_DIR/harness_state.py.template"

hs_increment() {
  python3 "$STATE_MODULE_TEMPLATE" increment-correction-cycles "$1" "$2"
}

hs_read_correction_cycles() {
  python3 -c "
import json
data = json.load(open('$1'))
print(data['features'][0]['correction_cycles'])
"
}

# "json.dump(" (not "json.dump" alone) so json.dumps(...) -- serializing to a string,
# not writing a file -- doesn't false-positive as a features.json write site.
DUMP_HITS=$(grep -l "json.dump(" "$TEMPLATES_DIR"/*.template 2>/dev/null \
  | grep -v "harness_state.py.template" || true)
if [ -z "$DUMP_HITS" ]; then
  pass "hs: zero json.dump( call sites outside harness_state.py.template"
else
  fail "hs: json.dump( found outside harness_state.py.template in: $DUMP_HITS"
fi

HS_LOAD="$WORK/hs-load"
mkdir -p "$HS_LOAD"
printf '{ not json' > "$HS_LOAD/features.json"
OUT=$(python3 "$STATE_MODULE_TEMPLATE" load "$HS_LOAD/features.json" 2>"$HS_LOAD/stderr.log")
RC=$?
assert_rc0 "$RC" "hs: load exits 0 on malformed JSON"
assert_contains "$OUT" "[]" "hs: load prints an empty result on malformed JSON"
HS_LOAD_STDERR=$(cat "$HS_LOAD/stderr.log")
assert_contains "$HS_LOAD_STDERR" "cannot parse" "hs: load notes the parse failure on stderr"

HS_MISSING="$WORK/hs-missing-fid"
mkdir -p "$HS_MISSING"
printf '{"features": [{"id": "F001", "status": "in-progress", "correction_cycles": 2}]}' \
  > "$HS_MISSING/features.json"
SUM_BEFORE=$(cksum < "$HS_MISSING/features.json")
OUT=$(hs_increment "$HS_MISSING/features.json" F099 2>&1)
RC=$?
if [ "$RC" -eq 3 ]; then
  pass "hs: increment on a missing feature id exits 3"
else
  fail "hs: increment on a missing feature id exited $RC, expected 3"
fi
SUM_AFTER=$(cksum < "$HS_MISSING/features.json")
if [ "$SUM_BEFORE" = "$SUM_AFTER" ]; then
  pass "hs: increment on a missing feature id performs no write"
else
  fail "hs: increment on a missing feature id modified features.json"
fi
if [ -f "$HS_MISSING/features.json.tmp" ]; then
  fail "hs: increment on a missing feature id left a tmp file"
else
  pass "hs: increment on a missing feature id leaves no tmp file"
fi

HS_INIT="$WORK/hs-init-cc"
mkdir -p "$HS_INIT"
printf '{"features": [{"id": "F001", "status": "in-progress"}]}' > "$HS_INIT/features.json"
OUT=$(hs_increment "$HS_INIT/features.json" F001 2>&1)
RC=$?
assert_rc0 "$RC" "hs: increment on an absent correction_cycles field exits 0"
if [ -f "$HS_INIT/features.json.tmp" ]; then
  CC=$(hs_read_correction_cycles "$HS_INIT/features.json.tmp")
  if [ "$CC" = "1" ]; then
    pass "hs: absent correction_cycles is initialized to 1"
  else
    fail "hs: correction_cycles was $CC, expected 1"
  fi
else
  fail "hs: expected increment to write a .tmp file"
fi

HS_INIT_NULL="$WORK/hs-init-cc-null"
mkdir -p "$HS_INIT_NULL"
printf '{"features": [{"id": "F001", "status": "in-progress", "correction_cycles": null}]}' \
  > "$HS_INIT_NULL/features.json"
OUT=$(hs_increment "$HS_INIT_NULL/features.json" F001 2>&1)
RC=$?
assert_rc0 "$RC" "hs: increment on a null correction_cycles field exits 0"
CC=$(hs_read_correction_cycles "$HS_INIT_NULL/features.json.tmp")
if [ "$CC" = "1" ]; then
  pass "hs: null correction_cycles is initialized to 1"
else
  fail "hs: correction_cycles was $CC, expected 1"
fi

HS_GATE="$WORK/hs-status-gate"
mkdir -p "$HS_GATE"
printf '{"features": [{"id": "F001", "status": "pending", "correction_cycles": 0}]}' \
  > "$HS_GATE/features.json"
OUT=$(hs_increment "$HS_GATE/features.json" F001 2>&1)
RC=$?
assert_rc0 "$RC" "hs: increment on a non-in-progress feature exits 0 (silent no-op)"
if [ -f "$HS_GATE/features.json.tmp" ]; then
  fail "hs: a non-in-progress feature should not produce a tmp write"
else
  pass "hs: a non-in-progress feature produces no tmp write"
fi

HS_NONE="$WORK/hs-none-claimable"
mkdir -p "$HS_NONE"
cat > "$HS_NONE/features.json" <<'JSON'
{"features": [{"id": "F001", "status": "passing", "priority": 1, "scope": [], "depends_on": []}]}
JSON
OUT=$(python3 "$STATE_MODULE_TEMPLATE" next-claimable "$HS_NONE/features.json" 2>&1)
RC=$?
assert_rc0 "$RC" "hs: next-claimable exits 0 when nothing is claimable"
if [ "$OUT" = "no claimable feature" ]; then
  pass "hs: next-claimable prints the exact literal string when empty"
else
  fail "hs: next-claimable printed '$OUT', expected 'no claimable feature'"
fi

HS_SOME="$WORK/hs-claimable"
mkdir -p "$HS_SOME"
cat > "$HS_SOME/features.json" <<'JSON'
{"features": [
  {"id": "F001", "status": "passing", "priority": 1, "scope": [], "depends_on": []},
  {"id": "F002", "status": "pending", "priority": 2, "scope": ["src/x/"], "depends_on": ["F001"]}
]}
JSON
OUT=$(python3 "$STATE_MODULE_TEMPLATE" next-claimable "$HS_SOME/features.json" 2>&1)
RC=$?
assert_rc0 "$RC" "hs: next-claimable exits 0 when a feature is claimable"
assert_contains "$OUT" '"id": "F002"' "hs: next-claimable JSON names the claimable feature"

HS_COUNTS="$WORK/hs-counts"
mkdir -p "$HS_COUNTS"
cat > "$HS_COUNTS/features.json" <<'JSON'
{"features": [
  {"id": "F001", "status": "passing"},
  {"id": "F002", "status": "in-progress"},
  {"id": "F003", "status": "pending"}
]}
JSON
OUT=$(python3 "$STATE_MODULE_TEMPLATE" counts "$HS_COUNTS/features.json" 2>&1)
RC=$?
assert_rc0 "$RC" "hs: counts exits 0"
assert_contains "$OUT" '"passing": 1' "hs: counts reports the passing count"
assert_contains "$OUT" '"total": 3' "hs: counts reports the total count"
assert_contains "$OUT" '"F002"' "hs: counts lists in-progress ids"

HS_INTERRUPT="$WORK/hs-interrupt"
mkdir -p "$HS_INTERRUPT"
printf '{"features": [{"id": "F001", "status": "in-progress", "correction_cycles": 0}]}' \
  > "$HS_INTERRUPT/features.json"
chmod 555 "$HS_INTERRUPT"
OUT=$(hs_increment "$HS_INTERRUPT/features.json" F001 2>&1)
RC=$?
chmod 755 "$HS_INTERRUPT"
assert_rc_nonzero "$RC" "hs: a write failure (permission-denied dir) exits non-zero"
assert_contains "$(cat "$HS_INTERRUPT/features.json")" '"correction_cycles": 0' \
  "hs: original features.json is unchanged after a write failure"
if [ -f "$HS_INTERRUPT/features.json.tmp" ]; then
  fail "hs: a failed write left an orphaned tmp file"
else
  pass "hs: a failed write leaves no orphaned tmp file"
fi

DIR_HS_PLAIN="$WORK/hs-delegate-plain"
make_fixture "$DIR_HS_PLAIN"
OUT_PLAIN=$(run_session_start "$DIR_HS_PLAIN" '{"source":"startup"}')
NEXT_PLAIN=$(printf '%s\n' "$OUT_PLAIN" | grep "^Next claimable:")

DIR_HS_MODULE="$WORK/hs-delegate-module"
make_fixture "$DIR_HS_MODULE"
mkdir -p "$DIR_HS_MODULE/.claude/hooks"
cp "$STATE_MODULE_TEMPLATE" "$DIR_HS_MODULE/.claude/hooks/harness_state.py"
chmod +x "$DIR_HS_MODULE/.claude/hooks/harness_state.py"
OUT_MODULE=$(run_session_start "$DIR_HS_MODULE" '{"source":"startup"}')
NEXT_MODULE=$(printf '%s\n' "$OUT_MODULE" | grep "^Next claimable:")

if [ -n "$NEXT_PLAIN" ] && [ "$NEXT_PLAIN" = "$NEXT_MODULE" ]; then
  pass "hs: next-claimable output is identical whether harness_state.py is present or not"
else
  fail "hs: next-claimable output differs -- plain: '$NEXT_PLAIN' module: '$NEXT_MODULE'"
fi

echo ""
echo "== harness-doctor =="

DOCTOR_PY="$REPO_ROOT/skills/harness-doctor/doctor.py"

run_doctor() {
  DIR="$1"; shift
  (CLAUDE_PLUGIN_ROOT="$REPO_ROOT" python3 "$DOCTOR_PY" "$@" "$DIR")
}

run_doctor_with_root() {
  DIR="$1"; ROOT="$2"; shift 2
  (CLAUDE_PLUGIN_ROOT="$ROOT" python3 "$DOCTOR_PY" "$@" "$DIR")
}

# Builds a fully v5-healthy fixture: baseline + all hooks incl. statusline.sh +
# correctly-wired settings.json + a complete .gitignore + a context_summary.md
# with every required section. The settings.json is embedded inline (not
# copied from this repo's own live .claude/settings.json) so this test does
# not depend on that file's current shape.
make_healthy_doctor_fixture() {
  make_fixture "$1"
  install_hooks "$1"
  cp "$REPO_ROOT/hooks/statusline.sh" "$1/.claude/hooks/statusline.sh"
  chmod +x "$1/.claude/hooks/statusline.sh"
  cat > "$1/.claude/settings.json" <<'SETTINGSEOF'
{
  "statusLine": {"type": "command", "command": "bash .claude/hooks/statusline.sh"},
  "env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"},
  "permissions": {"allow": ["Bash(bash .claude/hooks/*.sh)"]},
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [{"type": "command", "command": "bash .claude/hooks/enforce-scope.sh"}]
      },
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "bash .claude/hooks/verify-git-identity.sh"}]
      }
    ],
    "TaskCompleted": [
      {"hooks": [{"type": "command", "command": "bash .claude/hooks/verify-task-quality.sh"}]}
    ],
    "TeammateIdle": [
      {"hooks": [{"type": "command", "command": "bash .claude/hooks/check-remaining-tasks.sh"}]}
    ]
  }
}
SETTINGSEOF
  printf '.harness/SESSION_INCOMPLETE\n' > "$1/.gitignore"
  cat >> "$1/.harness/context_summary.md" <<'CTXEOF'

## Cross-Cutting Concerns
- none

## Meta-Patterns
- (none yet)
CTXEOF
  git -C "$1" add -A
  git -C "$1" commit -q -m "doctor fixture: v5-healthy"
}

DIR_DOC_HEALTHY="$WORK/doctor-healthy"
make_healthy_doctor_fixture "$DIR_DOC_HEALTHY"
OUT=$(run_doctor "$DIR_DOC_HEALTHY")
RC=$?
assert_rc0 "$RC" "hd: a fully healthy fixture exits 0"
if [ "$OUT" = "healthy" ]; then
  pass "hd: a fully healthy fixture prints a single 'healthy' line"
else
  fail "hd: a fully healthy fixture prints a single 'healthy' line -- got: $OUT"
fi
assert_not_contains "$OUT" "commit-gate" \
  "hd: healthy fixture has no commit-gate finding (F011/OVI-64 template not shipped)"

# AC1: seeded breakages -- non-executable hook, missing settings wiring, invalid
# features.json, gitignored .claude/. Each finding must name its repair.
DIR_DOC_SEEDED="$WORK/doctor-seeded"
make_healthy_doctor_fixture "$DIR_DOC_SEEDED"
chmod -x "$DIR_DOC_SEEDED/.claude/hooks/enforce-scope.sh"
python3 - "$DIR_DOC_SEEDED/.claude/settings.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)
del settings["env"]
with open(path, "w") as f:
    json.dump(settings, f)
PYEOF
printf '{"features": [' >> "$DIR_DOC_SEEDED/.harness/features.json"  # corrupt JSON
printf '.claude/\n' > "$DIR_DOC_SEEDED/.gitignore"
OUT=$(run_doctor "$DIR_DOC_SEEDED")
RC=$?
assert_rc_nonzero "$RC" "hd: a seeded-breakage fixture exits non-zero"
assert_contains "$OUT" "hook 'enforce-scope.sh' is not executable" \
  "hd: seeded fixture names the non-executable hook"
assert_contains "$OUT" "chmod +x .claude/hooks/enforce-scope.sh" \
  "hd: seeded fixture gives the non-executable hook's repair"
assert_contains "$OUT" "missing env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS wiring" \
  "hd: seeded fixture names the missing settings wiring"
assert_contains "$OUT" "does not parse" \
  "hd: seeded fixture names the invalid features.json"
assert_contains "$OUT" "exclude .claude/ without un-ignoring" \
  "hd: seeded fixture names the gitignored .claude/ problem"

# AC5: only an optional-v5 artifact missing -> a single "upgrade available"
# finding, not an error.
DIR_DOC_V5="$WORK/doctor-v5-only"
make_healthy_doctor_fixture "$DIR_DOC_V5"
rm "$DIR_DOC_V5/.claude/hooks/harness_state.py"
OUT=$(run_doctor "$DIR_DOC_V5")
RC=$?
assert_rc_nonzero "$RC" "hd: an optional-v5-only gap still exits non-zero (there is a finding)"
assert_contains "$OUT" "upgrade available: harness_state.py not present" \
  "hd: optional-v5-only gap is reported as upgrade-available, not a hard error"
FINDING_LINES=$(printf '%s\n' "$OUT" | grep -c '^FINDING:')
if [ "$FINDING_LINES" -eq 1 ]; then
  pass "hd: an optional-v5-only gap produces exactly one finding"
else
  fail "hd: an optional-v5-only gap produces exactly one finding -- got $FINDING_LINES"
fi

# AC7: an untracked (never-committed) broken artifact is classified as an
# uncommitted local edit, with an explicit note that no history was available.
DIR_DOC_UNTRACKED="$WORK/doctor-untracked"
make_fixture "$DIR_DOC_UNTRACKED"
mkdir -p "$DIR_DOC_UNTRACKED/.claude"
echo '{"hooks": {}}' > "$DIR_DOC_UNTRACKED/.claude/settings.json"
OUT=$(run_doctor "$DIR_DOC_UNTRACKED")
assert_contains "$OUT" \
  "missing statusLine wiring (no committed history for this file; treating as local)" \
  "hd: an untracked broken artifact is classified as an uncommitted local edit"

# Non-harness project -> exits early pointing to /harness-init.
DIR_DOC_NONE="$WORK/doctor-none"
mkdir -p "$DIR_DOC_NONE"
OUT=$(run_doctor "$DIR_DOC_NONE")
RC=$?
assert_rc2 "$RC" "hd: a non-harness project exits 2"
assert_contains "$OUT" "/harness-init" "hd: a non-harness project points to /harness-init"

# --fix applies the mechanical INSTALL.md steps and leaves only unfixable findings.
DIR_DOC_FIX="$WORK/doctor-fix"
make_healthy_doctor_fixture "$DIR_DOC_FIX"
python3 - "$DIR_DOC_FIX/.claude/settings.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)
del settings["env"]
settings["hooks"]["PostCompact"] = [{"hooks": [{"type": "command", "command": "echo stale"}]}]
with open(path, "w") as f:
    json.dump(settings, f)
PYEOF
rm "$DIR_DOC_FIX/.claude/hooks/statusline.sh"
printf '' > "$DIR_DOC_FIX/.gitignore"
rm "$DIR_DOC_FIX/.claude/hooks/harness_state.py"
printf '# stale placeholder\n' > "$DIR_DOC_FIX/.claude/hooks/verify-task-quality.sh"
chmod +x "$DIR_DOC_FIX/.claude/hooks/verify-task-quality.sh"
FIX_OUT=$(run_doctor "$DIR_DOC_FIX" --fix)
assert_not_contains "$FIX_OUT" "PostCompact" "hd: --fix removes the stale PostCompact block"
assert_not_contains "$FIX_OUT" "statusLine wiring" "hd: --fix restores missing settings wiring"
assert_not_contains "$FIX_OUT" "statusline.sh' is missing" "hd: --fix restores statusline.sh"
assert_not_contains "$FIX_OUT" "SESSION_INCOMPLETE" "hd: --fix appends the gitignore entry"
assert_not_contains "$FIX_OUT" "harness_state.py not present" \
  "hd: --fix restores harness_state.py"
if grep -q '"PostCompact"' "$DIR_DOC_FIX/.claude/settings.json"; then
  fail "hd: --fix -- settings.json still has a PostCompact block on disk"
else
  pass "hd: --fix -- settings.json no longer has a PostCompact block on disk"
fi
if [ -x "$DIR_DOC_FIX/.claude/hooks/harness_state.py" ] \
  && cmp -s "$DIR_DOC_FIX/.claude/hooks/harness_state.py" \
    "$TEMPLATES_DIR/harness_state.py.template"; then
  pass "hd: --fix -- harness_state.py on disk matches the plugin template"
else
  fail "hd: --fix -- harness_state.py on disk does not match the plugin template"
fi
if grep -q "stale placeholder" "$DIR_DOC_FIX/.claude/hooks/verify-task-quality.sh"; then
  fail "hd: --fix -- verify-task-quality.sh was not re-copied from the current template"
else
  pass "hd: --fix -- verify-task-quality.sh was re-copied from the current template"
fi

# Spec item 2's whole point: an artifact whose current state MATCHES the last
# commit is classified as committed drift, not a local edit. Commit a settings.json
# that already has the gap; the doctor sees no local modification at all.
DIR_DOC_COMMITTED="$WORK/doctor-committed-drift"
make_healthy_doctor_fixture "$DIR_DOC_COMMITTED"
python3 - "$DIR_DOC_COMMITTED/.claude/settings.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)
del settings["env"]
with open(path, "w") as f:
    json.dump(settings, f)
PYEOF
git -C "$DIR_DOC_COMMITTED" add -A
git -C "$DIR_DOC_COMMITTED" commit -q -m "commit the gap itself"
OUT=$(run_doctor "$DIR_DOC_COMMITTED")
assert_contains "$OUT" \
  "missing env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS wiring (matches the last commit; any problem here is committed, not local)" \
  "hd: an artifact matching the last commit is classified as committed drift"

# Spec item 3: settings.json must parse.
DIR_DOC_BADSETTINGS="$WORK/doctor-bad-settings"
make_healthy_doctor_fixture "$DIR_DOC_BADSETTINGS"
printf '{ not valid json' > "$DIR_DOC_BADSETTINGS/.claude/settings.json"
OUT=$(run_doctor "$DIR_DOC_BADSETTINGS")
assert_contains "$OUT" ".claude/settings.json does not parse" \
  "hd: a malformed settings.json is reported as a parse error"

# Spec item 5: context_summary.md must carry every required section heading.
DIR_DOC_CTXGAP="$WORK/doctor-context-gap"
make_healthy_doctor_fixture "$DIR_DOC_CTXGAP"
python3 - "$DIR_DOC_CTXGAP/.harness/context_summary.md" <<'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
open(path, "w").write(text.replace("## Meta-Patterns\n- (none yet)\n", ""))
PYEOF
OUT=$(run_doctor "$DIR_DOC_CTXGAP")
assert_contains "$OUT" "missing required section(s): ## Meta-Patterns" \
  "hd: context_summary.md missing a required heading is reported by name"

# Spec item 7: the mld non-injection guarantee. session-start.sh is never copied
# into a project's .claude/hooks/ -- it runs directly from CLAUDE_PLUGIN_ROOT -- so
# the check targets the plugin's own copy, via a fake plugin root here.
DIR_DOC_MLD="$WORK/doctor-mld"
make_healthy_doctor_fixture "$DIR_DOC_MLD"
mkdir -p "$DIR_DOC_MLD/.harness/mld"
FAKE_PLUGIN_ROOT="$WORK/fake-plugin-root-mld-bad"
mkdir -p "$FAKE_PLUGIN_ROOT/hooks"
printf '#!/usr/bin/env bash\ncat "$CLAUDE_PROJECT_DIR/.harness/mld/telemetry.jsonl"\n' \
  > "$FAKE_PLUGIN_ROOT/hooks/session-start.sh"
OUT=$(run_doctor_with_root "$DIR_DOC_MLD" "$FAKE_PLUGIN_ROOT")
assert_contains "$OUT" "non-injection guarantee broken" \
  "hd: the plugin's session-start.sh referencing .harness/mld/ breaks the guarantee"

DIR_DOC_MLD_OK="$WORK/doctor-mld-ok"
make_healthy_doctor_fixture "$DIR_DOC_MLD_OK"
mkdir -p "$DIR_DOC_MLD_OK/.harness/mld"
OUT=$(run_doctor "$DIR_DOC_MLD_OK")
assert_not_contains "$OUT" "non-injection" \
  "hd: .harness/mld/ present with the real (mld-free) session-start.sh is not a finding"

# mld/ present but no plugin root available at all -> can't check, no finding.
DIR_DOC_MLD_NOROOT="$WORK/doctor-mld-noroot"
make_healthy_doctor_fixture "$DIR_DOC_MLD_NOROOT"
mkdir -p "$DIR_DOC_MLD_NOROOT/.harness/mld"
OUT=$(env -u CLAUDE_PLUGIN_ROOT python3 "$DOCTOR_PY" "$DIR_DOC_MLD_NOROOT")
assert_not_contains "$OUT" "non-injection" \
  "hd: .harness/mld/ present with no CLAUDE_PLUGIN_ROOT set produces no finding"

# mld/ present, plugin root set, but that root has no hooks/session-start.sh at all.
DIR_DOC_MLD_NOFILE="$WORK/doctor-mld-nofile"
make_healthy_doctor_fixture "$DIR_DOC_MLD_NOFILE"
mkdir -p "$DIR_DOC_MLD_NOFILE/.harness/mld"
EMPTY_PLUGIN_ROOT="$WORK/empty-plugin-root"
mkdir -p "$EMPTY_PLUGIN_ROOT"
OUT=$(run_doctor_with_root "$DIR_DOC_MLD_NOFILE" "$EMPTY_PLUGIN_ROOT")
assert_not_contains "$OUT" "non-injection" \
  "hd: a plugin root with no hooks/session-start.sh produces no mld finding"

# Missing (not malformed) settings.json, harness.json, and context_summary.md.
DIR_DOC_NOSETTINGS="$WORK/doctor-no-settings"
make_healthy_doctor_fixture "$DIR_DOC_NOSETTINGS"
rm "$DIR_DOC_NOSETTINGS/.claude/settings.json"
OUT=$(run_doctor "$DIR_DOC_NOSETTINGS")
assert_contains "$OUT" ".claude/settings.json is missing" \
  "hd: a project with no settings.json at all is reported as missing"

DIR_DOC_NOHARNESSJSON="$WORK/doctor-no-harnessjson"
make_healthy_doctor_fixture "$DIR_DOC_NOHARNESSJSON"
rm "$DIR_DOC_NOHARNESSJSON/.harness/harness.json"
OUT=$(run_doctor "$DIR_DOC_NOHARNESSJSON")
assert_contains "$OUT" ".harness/harness.json is missing" \
  "hd: a project with no harness.json at all is reported as missing"

DIR_DOC_NOCTX="$WORK/doctor-no-context"
make_healthy_doctor_fixture "$DIR_DOC_NOCTX"
rm "$DIR_DOC_NOCTX/.harness/context_summary.md"
OUT=$(run_doctor "$DIR_DOC_NOCTX")
assert_contains "$OUT" ".harness/context_summary.md is missing" \
  "hd: a project with no context_summary.md at all is reported as missing"

# context_summary.md present but missing a Domain section specifically (distinct
# from the Meta-Patterns-missing case already covered).
DIR_DOC_NODOMAIN="$WORK/doctor-no-domain"
make_healthy_doctor_fixture "$DIR_DOC_NODOMAIN"
python3 - "$DIR_DOC_NODOMAIN/.harness/context_summary.md" <<'PYEOF'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r"## Domain:.*?(?=\n## )", "", text, flags=re.S)
open(path, "w").write(text)
PYEOF
OUT=$(run_doctor "$DIR_DOC_NODOMAIN")
assert_contains "$OUT" "## Domain:" \
  "hd: context_summary.md missing any Domain section is reported by name"

# harness_state.py present but not executable.
DIR_DOC_STATENOEXEC="$WORK/doctor-state-noexec"
make_healthy_doctor_fixture "$DIR_DOC_STATENOEXEC"
chmod -x "$DIR_DOC_STATENOEXEC/.claude/hooks/harness_state.py"
OUT=$(run_doctor "$DIR_DOC_STATENOEXEC")
assert_contains "$OUT" "harness_state.py is not executable" \
  "hd: a present-but-non-executable harness_state.py is reported"

# Fully-satisfied commit-gate: the plugin ships a template AND the project already
# has its own copy -> no finding at all (the "everything's fine" tail path).
DIR_DOC_GATEOK="$WORK/doctor-commit-gate-satisfied"
make_healthy_doctor_fixture "$DIR_DOC_GATEOK"
FAKE_PLUGIN_ROOT_GATE="$WORK/fake-plugin-root-gate-satisfied"
mkdir -p "$FAKE_PLUGIN_ROOT_GATE/skills/harness-init"
echo "# fake commit gate" > "$FAKE_PLUGIN_ROOT_GATE/skills/harness-init/commit-gate.sh.template"
cp "$FAKE_PLUGIN_ROOT_GATE/skills/harness-init/commit-gate.sh.template" \
  "$DIR_DOC_GATEOK/.claude/hooks/commit-gate.sh"
chmod +x "$DIR_DOC_GATEOK/.claude/hooks/commit-gate.sh"
OUT=$(run_doctor_with_root "$DIR_DOC_GATEOK" "$FAKE_PLUGIN_ROOT_GATE")
assert_not_contains "$OUT" "commit-gate" \
  "hd: a project with its own commit-gate.sh already copied has no finding"

# Mirror case: the plugin ships a commit-gate template but the project hasn't
# copied it yet -> "upgrade available", same tier as harness_state.py. F011/OVI-64
# shipped a real commit-gate.sh.template, so install_hooks() now copies it into
# every fixture automatically; remove it here to restore the "not yet copied"
# precondition this case is testing.
DIR_DOC_GATEMISSING="$WORK/doctor-commit-gate-missing"
make_healthy_doctor_fixture "$DIR_DOC_GATEMISSING"
rm -f "$DIR_DOC_GATEMISSING/.claude/hooks/commit-gate.sh"
FAKE_PLUGIN_ROOT_GATE2="$WORK/fake-plugin-root-gate-missing"
mkdir -p "$FAKE_PLUGIN_ROOT_GATE2/skills/harness-init"
echo "# fake commit gate" > "$FAKE_PLUGIN_ROOT_GATE2/skills/harness-init/commit-gate.sh.template"
OUT=$(run_doctor_with_root "$DIR_DOC_GATEMISSING" "$FAKE_PLUGIN_ROOT_GATE2")
assert_contains "$OUT" "upgrade available: commit-gate.sh not present (post-S4/OVI-64)" \
  "hd: a shipped-but-uncopied commit-gate template is reported as upgrade-available"

# git subprocess itself unavailable during drift classification -> degrades to
# "no committed history available", never crashes.
DIR_DOC_NOGIT="$WORK/doctor-no-git-binary"
make_healthy_doctor_fixture "$DIR_DOC_NOGIT"
python3 - "$DIR_DOC_NOGIT/.claude/settings.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    settings = json.load(f)
del settings["env"]
with open(path, "w") as f:
    json.dump(settings, f)
PYEOF
EMPTY_PATH_DIR="$WORK/empty-path-dir"
mkdir -p "$EMPTY_PATH_DIR"
REAL_PYTHON3=$(command -v python3)
ln -sf "$REAL_PYTHON3" "$EMPTY_PATH_DIR/python3"
OUT=$(PATH="$EMPTY_PATH_DIR" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" python3 "$DOCTOR_PY" "$DIR_DOC_NOGIT")
assert_contains "$OUT" "no committed history available for this file; treating as local" \
  "hd: git being unavailable degrades drift classification instead of crashing"

# fixes.py: the four single-purpose fixers' no-op ("already resolved" or
# "can't act") branches are unreachable through the CLI (apply_fixes only invokes
# a fix_id when a finding actually calls for it), so exercise them directly.
FIXES_ERRORS=$(python3 - "$REPO_ROOT/skills/harness-doctor" <<'PYEOF'
import json
import os
import sys
import tempfile

sys.path.insert(0, sys.argv[1])
import fixes

errors = []
with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, ".claude"))
    settings_path = os.path.join(d, ".claude", "settings.json")
    with open(settings_path, "w") as fh:
        json.dump({"hooks": {}}, fh)

    if fixes._remove_postcompact(d, None) is not False:
        errors.append("_remove_postcompact should no-op when there is no PostCompact block")
    if fixes._copy_statusline(d, None) is not False:
        errors.append("_copy_statusline should no-op when plugin_root is None")
    if fixes._copy_harness_state(d, None) is not False:
        errors.append("_copy_harness_state should no-op when plugin_root is None")

    gitignore_path = os.path.join(d, ".gitignore")
    with open(gitignore_path, "w") as fh:
        fh.write(".harness/SESSION_INCOMPLETE\n")
    if fixes._append_gitignore(d, None) is not False:
        errors.append("_append_gitignore should no-op when the line is already present")

    if fixes._load_json(os.path.join(d, "does-not-exist.json")) is not None:
        errors.append("_load_json should return None for a missing file")
    bad_path = os.path.join(d, "bad.json")
    with open(bad_path, "w") as fh:
        fh.write("{ not json")
    if fixes._load_json(bad_path) is not None:
        errors.append("_load_json should return None for invalid JSON")

    # partial hooks: TeammateIdle present, TaskCompleted missing -> only the
    # missing event should be added (exercises the per-event "changed" branch).
    partial_hooks = {"TeammateIdle": [{"hooks": [{"type": "command", "command": "x"}]}]}
    with open(settings_path, "w") as fh:
        json.dump({"hooks": partial_hooks}, fh)
    if not fixes._add_settings_wiring(d, None):
        errors.append("_add_settings_wiring should report a change when TaskCompleted is missing")
    with open(settings_path) as fh:
        merged = json.load(fh)
    if "TaskCompleted" not in merged["hooks"]:
        errors.append("_add_settings_wiring did not add the missing TaskCompleted block")
    if merged["hooks"]["TeammateIdle"] != partial_hooks["TeammateIdle"]:
        errors.append("_add_settings_wiring should not touch an already-present hook event")

for e in errors:
    print(e)
PYEOF
)
if [ -z "$FIXES_ERRORS" ]; then
  pass "hd: fixes.py's no-op and partial-merge branches behave correctly"
else
  fail "hd: fixes.py direct unit checks -- $FIXES_ERRORS"
fi

# AC2: doctor never writes without approval -- the skill text asserts it.
if grep -qi "report-first" "$REPO_ROOT/skills/harness-doctor/SKILL.md" 2>/dev/null \
  && grep -q "never writes\|without explicit approval\|without approval" \
    "$REPO_ROOT/skills/harness-doctor/SKILL.md" 2>/dev/null; then
  pass "hd: SKILL.md asserts the report-first, no-writes-without-approval rule"
else
  fail "hd: SKILL.md is missing or does not assert the report-first rule"
fi

# AC3: INSTALL.md's upgrade section points to the doctor.
if grep -q "/harness-doctor" "$REPO_ROOT/INSTALL.md"; then
  pass "hd: INSTALL.md's upgrade section points to /harness-doctor"
else
  fail "hd: INSTALL.md does not mention /harness-doctor"
fi

# harness-continue Step 2.5 suggests the doctor on smoke-test failure.
if grep -q "harness-doctor" "$REPO_ROOT/skills/harness-continue/SKILL.md"; then
  pass "hd: harness-continue Step 2.5 suggests /harness-doctor on smoke-test failure"
else
  fail "hd: harness-continue does not mention /harness-doctor"
fi

echo ""
echo "== maintenance loop =="

RUNBOOK="$REPO_ROOT/docs/maintenance-runbook.md"
if [ -f "$RUNBOOK" ]; then
  for HEADER in "Condition" "Departure Signal" "Restoration Evidence" \
    "Autonomous vs Approval-Required Operations" "Durable State" "Probe Checklist"; do
    if grep -q "^## $HEADER" "$RUNBOOK"; then
      pass "mnt: maintenance-runbook.md has a '## $HEADER' section"
    else
      fail "mnt: maintenance-runbook.md is missing a '## $HEADER' section"
    fi
  done
  if grep -q "plan_approval_response" "$RUNBOOK" \
    && grep -q "FIXED" "$RUNBOOK" && grep -q "BROKEN" "$RUNBOOK"; then
    pass "mnt: runbook's probe checklist gives a concrete FIXED/BROKEN criterion"
  else
    fail "mnt: runbook's plan_approval_response probe is missing a FIXED/BROKEN criterion"
  fi
else
  fail "mnt: docs/maintenance-runbook.md does not exist"
fi

MAINT_YML="$REPO_ROOT/.github/workflows/maintenance.yml"
if [ -f "$MAINT_YML" ]; then
  # Capture stderr too: a checker crash must surface as a failure, not
  # silently leave MAINT_YML_ERRORS empty (which would read as a false PASS).
  MAINT_YML_ERRORS=$(python3 - "$MAINT_YML" 2>&1 <<'PYEOF'
import sys

path = sys.argv[1]
text = open(path).read()
errors = []

if "\t" in text:
    errors.append("contains a literal tab character")

WEEKLY_CRON = "0 6 * * 1"  # Mondays 06:00 UTC -- once a week, not hourly/daily

try:
    import yaml
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        errors.append(f"does not parse as YAML: {exc}")
        data = None
    if isinstance(data, dict):
        on = data.get(True, data.get("on"))
        crons = [
            e.get("cron") for e in (on.get("schedule") or []) if isinstance(e, dict)
        ] if isinstance(on, dict) else []
        if not isinstance(on, dict) or "schedule" not in on:
            errors.append("'on.schedule' is missing")
        elif WEEKLY_CRON not in crons:
            errors.append(f"'on.schedule' has no weekly cron entry ({WEEKLY_CRON}); found {crons}")
        if not isinstance(on, dict) or "workflow_dispatch" not in on:
            errors.append("'on.workflow_dispatch' is missing")
        jobs = data.get("jobs") if isinstance(data, dict) else None
        if not isinstance(jobs, dict) or not jobs:
            errors.append("'jobs' is missing or empty")
        else:
            issue_step_found = False
            for job in jobs.values():
                perms = job.get("permissions") if isinstance(job, dict) else None
                if not isinstance(perms, dict) or perms.get("issues") != "write":
                    errors.append("a job is missing permissions.issues: write")
                for step in (job.get("steps") or []) if isinstance(job, dict) else []:
                    if not isinstance(step, dict):
                        continue
                    if "github-script" in (step.get("uses") or ""):
                        issue_step_found = True
                        if step.get("if") != "failure()":
                            errors.append(
                                "the github-script step is not gated on if: failure()"
                            )
            if not issue_step_found:
                errors.append("no github-script step found")
except ImportError:
    # No PyYAML in this environment: fall back to a structural check. Real
    # parsing happens for free in CI (GitHub Actions itself validates the
    # file), so this is a degrade-gracefully sanity check, not the only gate.
    if WEEKLY_CRON not in text:
        errors.append(f"no weekly cron entry ({WEEKLY_CRON}) found (structural check)")
    if "workflow_dispatch" not in text:
        errors.append("no 'workflow_dispatch' key found (structural check)")
    if "jobs:" not in text:
        errors.append("no 'jobs' key found (structural check)")
    lines = text.splitlines()
    script_idx = next((i for i, l in enumerate(lines) if "github-script" in l), None)
    if script_idx is None:
        errors.append("no github-script step found (structural check)")
    else:
        preceding = lines[max(0, script_idx - 3):script_idx]
        if not any("if: failure()" in l for l in preceding):
            errors.append(
                "the github-script step is not gated on if: failure() "
                "(structural check)"
            )
    if "issues: write" not in text:
        errors.append("no 'issues: write' permission found (structural check)")

for e in errors:
    print(e)
PYEOF
  )
  if [ -z "$MAINT_YML_ERRORS" ]; then
    pass "mnt: maintenance.yml is well-formed with weekly cron + workflow_dispatch"
  else
    fail "mnt: maintenance.yml -- $MAINT_YML_ERRORS"
  fi
  if grep -q "bash test/run-tests.sh" "$MAINT_YML"; then
    pass "mnt: maintenance.yml runs the test suite"
  else
    fail "mnt: maintenance.yml does not run bash test/run-tests.sh"
  fi
  NPM_INSTALL_COUNT=$(grep -c "npm install -g @anthropic-ai/claude-code" "$MAINT_YML")
  if [ "$NPM_INSTALL_COUNT" -ge 2 ]; then
    pass "mnt: maintenance.yml retries the npm install on flake ($NPM_INSTALL_COUNT attempts)"
  else
    fail "mnt: maintenance.yml has no real npm retry ($NPM_INSTALL_COUNT attempts)"
  fi
  if grep -q "issues.create" "$MAINT_YML"; then
    pass "mnt: maintenance.yml opens an issue"
  else
    fail "mnt: maintenance.yml does not open an issue on failure"
  fi
else
  fail "mnt: .github/workflows/maintenance.yml does not exist"
fi

MAINT_LOG="$REPO_ROOT/MAINTENANCE_LOG.md"
if [ -f "$MAINT_LOG" ]; then
  if grep -qi "run #0" "$MAINT_LOG"; then
    pass "mnt: MAINTENANCE_LOG.md is seeded with run #0"
  else
    fail "mnt: MAINTENANCE_LOG.md has no run #0 entry"
  fi
  if grep -qi "plan_approval_response" "$MAINT_LOG"; then
    pass "mnt: MAINTENANCE_LOG.md run #0 records the plan_approval_response retest outcome"
  else
    fail "mnt: MAINTENANCE_LOG.md does not record the plan_approval_response retest outcome"
  fi
else
  fail "mnt: MAINTENANCE_LOG.md does not exist"
fi

if grep -q "retirement condition" "$REPO_ROOT/CLAUDE.md"; then
  pass "mnt: CLAUDE.md has the new every-workaround-needs-a-retirement-condition rule"
else
  fail "mnt: CLAUDE.md is missing the retirement-condition rule"
fi

PROTOCOL_MD="$REPO_ROOT/rules/agent-teams-protocol.md"
PROTOCOL_RETIREMENT_PATTERN="plan_approval_response.*[Rr]etirement condition"
PROTOCOL_RETIREMENT_COUNT=$(grep -c "$PROTOCOL_RETIREMENT_PATTERN" "$PROTOCOL_MD")
if [ "$PROTOCOL_RETIREMENT_COUNT" -eq 2 ]; then
  pass "mnt: both plan_approval_response mentions have a retirement condition"
else
  fail "mnt: expected 2 retirement conditions, found $PROTOCOL_RETIREMENT_COUNT"
fi

if grep -q "Correction (\`MAINTENANCE_LOG.md\` run #0" "$PROTOCOL_MD" \
  && grep -q "could not confirm" "$PROTOCOL_MD" \
  && grep -q "open follow-up" "$PROTOCOL_MD"; then
  pass "mnt: the run-#0 correction is hedged, not a flat counter-claim"
else
  fail "mnt: the run-#0 correction is missing or reads as an unhedged counter-claim"
fi
if ! grep -q "not accurate as of the current CLI" "$PROTOCOL_MD"; then
  pass "mnt: the pre-fix overstated correction wording is gone"
else
  fail "mnt: the pre-fix overstated correction wording is still present"
fi

PROTOCOL_POINTER_COUNT=$(grep -c \
  "unverified as of \`MAINTENANCE_LOG.md\` run #0" "$PROTOCOL_MD")
if [ "$PROTOCOL_POINTER_COUNT" -eq 3 ]; then
  pass "mnt: all 3 still-instructional plan_approval_request sites carry a pointer"
else
  fail "mnt: expected 3 plan_approval_request pointer sites, found $PROTOCOL_POINTER_COUNT"
fi

if grep -q "[Rr]etirement condition" "$REPO_ROOT/README.md"; then
  pass "mnt: README.md's plan_approval_response mention carries a retirement condition"
else
  fail "mnt: README.md's plan_approval_response mention is missing a retirement condition"
fi

echo ""
echo "== commit-gate.sh =="

run_commit_gate() {
  DIR="$1"; CMD="$2"
  (cd "$DIR" && printf '%s' "$(bash_command_json "$CMD")" \
    | CLAUDE_PROJECT_DIR="$DIR" "$DIR/.claude/hooks/commit-gate.sh")
}

DIR_CG_COMPOUND="$WORK/commit-gate-compound"
make_fixture "$DIR_CG_COMPOUND"
install_hooks "$DIR_CG_COMPOUND"
OUT=$(run_commit_gate "$DIR_CG_COMPOUND" 'git add newfile.txt && git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: compound git add && git commit exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: compound form denial uses JSON deny form"
assert_contains "$OUT" "compound-stage-and-commit" \
  "cg: compound form denial names the finding class"

DIR_CG_DASHA="$WORK/commit-gate-dash-a"
make_fixture "$DIR_CG_DASHA"
install_hooks "$DIR_CG_DASHA"
OUT=$(run_commit_gate "$DIR_CG_DASHA" 'git commit -a -m "test"')
RC=$?
assert_rc0 "$RC" "cg: git commit -a exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: -a form denial uses JSON deny form"
assert_contains "$OUT" "compound-stage-and-commit" "cg: -a form denial names the finding class"

DIR_CG_SECRET="$WORK/commit-gate-secret"
make_fixture "$DIR_CG_SECRET"
install_hooks "$DIR_CG_SECRET"
echo 'api_key = "abcdefghijklmnopqrstuvwx"' > "$DIR_CG_SECRET/config.py"
git -C "$DIR_CG_SECRET" add config.py
OUT=$(run_commit_gate "$DIR_CG_SECRET" 'git commit -m "add config"')
RC=$?
assert_rc0 "$RC" "cg: staged secret-shaped addition exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: secret-assignment denial uses JSON deny form"
if printf '%s' "$OUT" | grep -qE "secret-assignment|url-credential"; then
  pass "cg: secret denial names a closed finding class"
else
  fail "cg: secret denial does not name secret-assignment or url-credential"
fi
assert_not_contains "$OUT" "abcdefghijklmnopqrstuvwx" \
  "cg: denial message does not leak the matched value"

DIR_CG_CLEAN="$WORK/commit-gate-clean"
make_fixture "$DIR_CG_CLEAN"
install_hooks "$DIR_CG_CLEAN"
echo "clean content" > "$DIR_CG_CLEAN/clean.txt"
git -C "$DIR_CG_CLEAN" add clean.txt
OUT=$(run_commit_gate "$DIR_CG_CLEAN" 'git commit -m "clean commit"')
RC=$?
assert_rc0 "$RC" "cg: clean commit exits 0"
assert_not_contains "$OUT" "permissionDecision" "cg: clean commit has no deny fields"

DIR_CG_ENVEX="$WORK/commit-gate-envexample"
make_fixture "$DIR_CG_ENVEX"
install_hooks "$DIR_CG_ENVEX"
echo 'api_key = "abcdefghijklmnopqrstuvwx"' > "$DIR_CG_ENVEX/.env.example"
git -C "$DIR_CG_ENVEX" add .env.example
OUT=$(run_commit_gate "$DIR_CG_ENVEX" 'git commit -m "add example"')
RC=$?
assert_rc0 "$RC" "cg: .env.example staged passes despite secret-shaped content"
assert_not_contains "$OUT" "permissionDecision" "cg: .env.example exemption has no deny fields"

DIR_CG_STYLEOFF="$WORK/commit-gate-style-off"
make_fixture "$DIR_CG_STYLEOFF"
install_hooks "$DIR_CG_STYLEOFF"
printf 'a sentence \xe2\x80\x94 with an em dash\n' > "$DIR_CG_STYLEOFF/prose.md"
git -C "$DIR_CG_STYLEOFF" add prose.md
OUT=$(run_commit_gate "$DIR_CG_STYLEOFF" 'git commit -m "prose"')
RC=$?
assert_rc0 "$RC" "cg: style gate off by default, em dash passes"
assert_not_contains "$OUT" "permissionDecision" "cg: default-off style gate has no deny fields"

DIR_CG_STYLEON="$WORK/commit-gate-style-on"
make_fixture "$DIR_CG_STYLEON"
install_hooks "$DIR_CG_STYLEON"
python3 - "$DIR_CG_STYLEON/.harness/harness.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["style_gate"] = {"enabled": True}
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
printf 'a sentence \xe2\x80\x94 with an em dash\n' > "$DIR_CG_STYLEON/prose.md"
git -C "$DIR_CG_STYLEON" add prose.md
OUT=$(run_commit_gate "$DIR_CG_STYLEON" 'git commit -m "prose"')
RC=$?
assert_rc0 "$RC" "cg: style gate on, em dash denied (JSON deny)"
assert_deny_json "$OUT" "cg: style-violation denial uses JSON deny form"
assert_contains "$OUT" "style-violation" "cg: style-violation denial names the finding class"

DIR_CG_FALSEPOS="$WORK/commit-gate-falsepositive"
make_fixture "$DIR_CG_FALSEPOS"
install_hooks "$DIR_CG_FALSEPOS"
echo "clean" > "$DIR_CG_FALSEPOS/clean2.txt"
git -C "$DIR_CG_FALSEPOS" add clean2.txt
OUT=$(run_commit_gate "$DIR_CG_FALSEPOS" 'git commit -m "run git add later"')
RC=$?
assert_rc0 "$RC" \
  "cg: commit message mentioning git add is not compound (false-positive regression)"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: false-positive regression has no deny fields"

# RV's non-blocking recommendation (cycle 2): a scanning exception during Check 1
# logs only the exception TYPE NAME to stderr, never the exception message/args
# (which could itself carry matched line content). Invalid-UTF8 staged bytes force
# a real UnicodeDecodeError when git diff --cached output is decoded.
DIR_CG_DECODEEXC="$WORK/commit-gate-decode-exc"
make_fixture "$DIR_CG_DECODEEXC"
install_hooks "$DIR_CG_DECODEEXC"
printf '\x80\x81\x82 invalid utf8 bytes\n' > "$DIR_CG_DECODEEXC/binaryish.txt"
git -C "$DIR_CG_DECODEEXC" add binaryish.txt
CG_STDERR_FILE=$(mktemp)
OUT=$(cd "$DIR_CG_DECODEEXC" \
  && printf '%s' "$(bash_command_json 'git commit -m "binary"')" \
  | CLAUDE_PROJECT_DIR="$DIR_CG_DECODEEXC" \
    "$DIR_CG_DECODEEXC/.claude/hooks/commit-gate.sh" 2>"$CG_STDERR_FILE")
RC=$?
CG_STDERR_CONTENT=$(cat "$CG_STDERR_FILE")
rm -f "$CG_STDERR_FILE"
assert_rc0 "$RC" "cg: invalid-UTF8 staged content exits 0 (fail-open, no crash)"
assert_not_contains "$OUT" "permissionDecision" "cg: scanning exception fails open (no deny)"
assert_contains "$CG_STDERR_CONTENT" "UnicodeDecodeError" \
  "cg: scanning exception logs the exception type name"
assert_not_contains "$CG_STDERR_CONTENT" "invalid utf8 bytes" \
  "cg: scanning exception does not leak line content to stderr"

# Non-git-commit commands must be a pure no-op (never denied, never scanned).
DIR_CG_NOOP="$WORK/commit-gate-noop"
make_fixture "$DIR_CG_NOOP"
install_hooks "$DIR_CG_NOOP"
OUT=$(run_commit_gate "$DIR_CG_NOOP" 'git status')
RC=$?
assert_rc0 "$RC" "cg: a non-commit git command exits 0"
assert_not_contains "$OUT" "permissionDecision" "cg: non-commit command has no deny fields"

# CRITICAL regressions (adversarial review of PR #40): a STAGED line that
# happens to start with "++ " was mis-parsed as a real diff file header, both
# (a) leaking the staged content into the denial message, and (b) letting a
# forged path (matching *.env.example) skip the rest of the scan entirely.
DIR_CG_HEADERLEAK="$WORK/commit-gate-fake-header-leak"
make_fixture "$DIR_CG_HEADERLEAK"
install_hooks "$DIR_CG_HEADERLEAK"
printf '++ LEAKED_ADJACENT_LINE_sk-live-9f8e7d6c5b4a3210\napi_key = "abcdefghijklmnopqrstuvwx"\n' \
  > "$DIR_CG_HEADERLEAK/leaktest.py"
git -C "$DIR_CG_HEADERLEAK" add leaktest.py
OUT=$(run_commit_gate "$DIR_CG_HEADERLEAK" 'git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: a staged '++ ' line is still scanned as content, not a fake header"
assert_deny_json "$OUT" "cg: fake-header-adjacent secret still denied (JSON deny)"
assert_not_contains "$OUT" "LEAKED_ADJACENT_LINE" \
  "cg: a staged '++ ' line's own content is never echoed into the denial"

DIR_CG_HEADERFORGE="$WORK/commit-gate-fake-header-exemption-forge"
make_fixture "$DIR_CG_HEADERFORGE"
install_hooks "$DIR_CG_HEADERFORGE"
printf '++ b/harmless.env.example\napi_key = "REALSECRETabcdefghijklmnop"\n' \
  > "$DIR_CG_HEADERFORGE/prod_config.py"
git -C "$DIR_CG_HEADERFORGE" add prod_config.py
OUT=$(run_commit_gate "$DIR_CG_HEADERFORGE" 'git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: a forged .env.example-shaped fake header cannot exempt a real secret"
assert_deny_json "$OUT" "cg: exemption-forgery attempt still denied (JSON deny)"

# 'git -C . commit' bypassed the old bash-level substring prefilter entirely
# (the flags between "git" and "commit" broke a \s+-anchored match).
DIR_CG_GITC="$WORK/commit-gate-git-c-flag"
make_fixture "$DIR_CG_GITC"
install_hooks "$DIR_CG_GITC"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_GITC/bypass.py"
git -C "$DIR_CG_GITC" add bypass.py
OUT=$(run_commit_gate "$DIR_CG_GITC" 'git -C . commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: 'git -C . commit' is still scanned, not bypassed (JSON deny)"
assert_deny_json "$OUT" "cg: 'git -C . commit' secret denial uses JSON deny form"

# 'git stage' is a real built-in alias for 'git add' and defeated Check 0.
DIR_CG_STAGE="$WORK/commit-gate-stage-alias"
make_fixture "$DIR_CG_STAGE"
install_hooks "$DIR_CG_STAGE"
OUT=$(run_commit_gate "$DIR_CG_STAGE" 'git stage newfile2.txt && git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: 'git stage' alias is treated as compound-stage-and-commit (JSON deny)"
assert_deny_json "$OUT" "cg: 'git stage' compound denial uses JSON deny form"
assert_contains "$OUT" "compound-stage-and-commit" \
  "cg: 'git stage' compound denial names the finding class"

# The keyword-boundary secret pattern missed the dominant real-world shape:
# a keyword as part of a larger SCREAMING_SNAKE_CASE identifier, or preceded
# by a JSON quote rather than a bare word boundary.
DIR_CG_SNAKE="$WORK/commit-gate-snake-case-secret"
make_fixture "$DIR_CG_SNAKE"
install_hooks "$DIR_CG_SNAKE"
echo 'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY' > "$DIR_CG_SNAKE/aws.env"
git -C "$DIR_CG_SNAKE" add aws.env
OUT=$(run_commit_gate "$DIR_CG_SNAKE" 'git commit -m "add aws config"')
RC=$?
assert_rc0 "$RC" "cg: SCREAMING_SNAKE_CASE secret exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: SCREAMING_SNAKE_CASE secret denial uses JSON deny form"
assert_not_contains "$OUT" "wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY" \
  "cg: SCREAMING_SNAKE_CASE secret denial does not leak the matched value"

DIR_CG_JSONKEY="$WORK/commit-gate-json-key-secret"
make_fixture "$DIR_CG_JSONKEY"
install_hooks "$DIR_CG_JSONKEY"
printf '{\n  "api_key": "abcdefghijklmnopqrstuvwx"\n}\n' > "$DIR_CG_JSONKEY/config.json"
git -C "$DIR_CG_JSONKEY" add config.json
OUT=$(run_commit_gate "$DIR_CG_JSONKEY" 'git commit -m "add config"')
RC=$?
assert_rc0 "$RC" "cg: JSON-quoted secret key exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: JSON-quoted secret denial uses JSON deny form"

# URL-credential detection was http(s)-only; the spec says "URL-embedded
# credentials" with no protocol narrowing.
DIR_CG_URLCRED="$WORK/commit-gate-url-credential"
make_fixture "$DIR_CG_URLCRED"
install_hooks "$DIR_CG_URLCRED"
echo 'DATABASE_URL=postgres://user:hunter2pass@db.example.com/prod' > "$DIR_CG_URLCRED/db.env"
git -C "$DIR_CG_URLCRED" add db.env
OUT=$(run_commit_gate "$DIR_CG_URLCRED" 'git commit -m "add db config"')
RC=$?
assert_rc0 "$RC" "cg: non-https URL-embedded credential exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: url-credential denial uses JSON deny form (non-https scheme)"
assert_contains "$OUT" "url-credential" \
  "cg: url-credential denial names the finding class (non-https scheme)"
assert_not_contains "$OUT" "hunter2pass" \
  "cg: url-credential denial does not leak the matched credential"

# Combined short-flag cluster (git commit -am), formalizing what was previously
# only manually verified.
DIR_CG_DASHAM="$WORK/commit-gate-dash-am"
make_fixture "$DIR_CG_DASHAM"
install_hooks "$DIR_CG_DASHAM"
OUT=$(run_commit_gate "$DIR_CG_DASHAM" 'git commit -am "test"')
RC=$?
assert_rc0 "$RC" "cg: combined -am flag exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: -am combined flag denial uses JSON deny form"
assert_contains "$OUT" "compound-stage-and-commit" \
  "cg: -am combined flag denial names the finding class"

# Not a git repo at all -> git diff --cached fails -> fail open.
DIR_CG_NOTGITREPO="$WORK/commit-gate-not-a-repo"
mkdir -p "$DIR_CG_NOTGITREPO"
cp -R "$FIXTURE_SRC/." "$DIR_CG_NOTGITREPO/"
mkdir -p "$DIR_CG_NOTGITREPO/.claude/hooks"
cp "$TEMPLATES_DIR/commit-gate.sh.template" "$DIR_CG_NOTGITREPO/.claude/hooks/commit-gate.sh"
chmod +x "$DIR_CG_NOTGITREPO/.claude/hooks/commit-gate.sh"
OUT=$(run_commit_gate "$DIR_CG_NOTGITREPO" 'git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: not-a-git-repo fails open, exits 0"
assert_not_contains "$OUT" "permissionDecision" "cg: not-a-git-repo has no deny fields"

# Corrupt harness.json must not suppress secret detection (Check 1 never reads
# harness.json; only the opt-in style gate, Check 2, does).
DIR_CG_BADHARNESS="$WORK/commit-gate-bad-harness-json"
make_fixture "$DIR_CG_BADHARNESS"
install_hooks "$DIR_CG_BADHARNESS"
printf '{ not valid json' > "$DIR_CG_BADHARNESS/.harness/harness.json"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_BADHARNESS/secret.py"
git -C "$DIR_CG_BADHARNESS" add secret.py
OUT=$(run_commit_gate "$DIR_CG_BADHARNESS" 'git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: corrupt harness.json does not suppress secret detection"
assert_deny_json "$OUT" "cg: secret still denied despite corrupt harness.json"

# The 5-second git-diff-cached timeout fails open. COMMIT_GATE_DIFF_TIMEOUT is a
# testing-only override (undocumented for production use) so this doesn't cost
# a real 5-second wait; a fake slow `git` stands in for the real binary.
DIR_CG_TIMEOUT="$WORK/commit-gate-diff-timeout"
make_fixture "$DIR_CG_TIMEOUT"
install_hooks "$DIR_CG_TIMEOUT"
echo "irrelevant" > "$DIR_CG_TIMEOUT/whatever.txt"
git -C "$DIR_CG_TIMEOUT" add whatever.txt
FAKE_GIT_DIR="$WORK/fake-git-slow-diff"
mkdir -p "$FAKE_GIT_DIR"
cat > "$FAKE_GIT_DIR/git" <<'FAKEGIT'
#!/bin/bash
if [ "$1" = "diff" ]; then
  sleep 0.5
  exit 0
fi
exit 1
FAKEGIT
chmod +x "$FAKE_GIT_DIR/git"
OUT=$(cd "$DIR_CG_TIMEOUT" \
  && printf '%s' "$(bash_command_json 'git commit -m "test"')" \
  | PATH="$FAKE_GIT_DIR:$PATH" COMMIT_GATE_DIFF_TIMEOUT=0.1 \
    CLAUDE_PROJECT_DIR="$DIR_CG_TIMEOUT" "$DIR_CG_TIMEOUT/.claude/hooks/commit-gate.sh")
RC=$?
assert_rc0 "$RC" "cg: a git diff --cached timeout fails open, exits 0"
assert_not_contains "$OUT" "permissionDecision" "cg: timeout fail-open has no deny fields"

# Second adversarial-review round: the .* between "git" and the subcommand let
# COMMIT_PATTERN/STAGE_PATTERN match "commit"/"add" as bare substrings of a
# filename or branch name, denying commands that were never staging-and-
# committing at all.
DIR_CG_FILENAMEFP="$WORK/commit-gate-filename-false-positive"
make_fixture "$DIR_CG_FILENAMEFP"
install_hooks "$DIR_CG_FILENAMEFP"
echo "x" > "$DIR_CG_FILENAMEFP/commit-gate-helper.sh"
OUT=$(run_commit_gate "$DIR_CG_FILENAMEFP" 'git add commit-gate-helper.sh')
RC=$?
assert_rc0 "$RC" "cg: 'git add' of a file whose name contains 'commit' exits 0"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: filename-substring false positive has no deny fields"

DIR_CG_BRANCHFP="$WORK/commit-gate-branch-name-false-positive"
make_fixture "$DIR_CG_BRANCHFP"
install_hooks "$DIR_CG_BRANCHFP"
OUT=$(run_commit_gate "$DIR_CG_BRANCHFP" 'git commit -m "x" && git push origin add-feature')
RC=$?
assert_rc0 "$RC" "cg: a branch name containing 'add' exits 0"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: branch-name-substring false positive has no deny fields"

# SECRET_PATTERN's prefix wildcard created polynomial-time backtracking on
# adversarially repeated keyword-shaped text with no valid terminator. Assert
# the scan completes well under the hook's own ~1s design budget even on a
# long adversarial line. `date +%s` (1-second granularity) would silently
# pass a regression up to 2.9s slower than intended; time via python3 instead
# for sub-second precision.
DIR_CG_REDOS="$WORK/commit-gate-redos-guard"
make_fixture "$DIR_CG_REDOS"
install_hooks "$DIR_CG_REDOS"
python3 -c "print('key' * 3000)" > "$DIR_CG_REDOS/adversarial.txt"
git -C "$DIR_CG_REDOS" add adversarial.txt
CG_REDOS_START=$(python3 -c "import time; print(time.monotonic())")
OUT=$(run_commit_gate "$DIR_CG_REDOS" 'git commit -m "test"')
RC=$?
CG_REDOS_ELAPSED=$(python3 -c "import time; print(time.monotonic() - $CG_REDOS_START)")
assert_rc0 "$RC" "cg: an adversarial keyword-repeated line exits 0"
# Round-6 review: a 1.0s external wall-clock bound measures process startup
# and subprocess spawn overhead on top of the actual scan, and flaked under
# CI load. Widened with real margin over SECRET_SCAN_MAX_LEN's per-line cap
# while still catching a return to the original ~18s-class regression.
if python3 -c "import sys; sys.exit(0 if $CG_REDOS_ELAPSED <= 5.0 else 1)"; then
  pass "cg: single adversarial line scan completes in bounded time (${CG_REDOS_ELAPSED}s)"
else
  fail "cg: single adversarial line scan took ${CG_REDOS_ELAPSED}s, exceeding the bound"
fi

# The per-line cap alone doesn't bound TOTAL scan time across many adversarial
# lines. Assert the aggregate SCAN_TIME_BUDGET_SECONDS circuit breaker holds
# even when many lines would each individually pass the per-line cap.
DIR_CG_REDOS_MANY="$WORK/commit-gate-redos-many-lines"
make_fixture "$DIR_CG_REDOS_MANY"
install_hooks "$DIR_CG_REDOS_MANY"
python3 -c "
line = 'key' * 700
print('\n'.join([line] * 1500))
" > "$DIR_CG_REDOS_MANY/adversarial_many.txt"
git -C "$DIR_CG_REDOS_MANY" add adversarial_many.txt
CG_REDOS_MANY_START=$(python3 -c "import time; print(time.monotonic())")
OUT=$(run_commit_gate "$DIR_CG_REDOS_MANY" 'git commit -m "test"')
RC=$?
CG_REDOS_MANY_ELAPSED=$(python3 -c "import time; print(time.monotonic() - $CG_REDOS_MANY_START)")
assert_rc0 "$RC" "cg: many adversarial lines still exits 0"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: many-adversarial-lines scan fails open (budget exceeded, no deny)"
# Round-6 review: same widening as above, and for the same reason -- this
# bound includes process/subprocess overhead on top of
# SCAN_TIME_BUDGET_SECONDS' 2.0s internal cutoff.
if python3 -c "import sys; sys.exit(0 if $CG_REDOS_MANY_ELAPSED <= 15.0 else 1)"; then
  pass "cg: many-adversarial-lines scan completes in bounded time (${CG_REDOS_MANY_ELAPSED}s)"
else
  fail "cg: many-adversarial-lines scan took ${CG_REDOS_MANY_ELAPSED}s, exceeding the bound"
fi

# Round-3 review: a multi-line command (e.g. a heredoc'd commit message body,
# or two commands separated by a literal newline rather than ;/&&) must not
# let a token on one line pair with an unrelated token on another line.
DIR_CG_MULTILINE="$WORK/commit-gate-multiline-command"
make_fixture "$DIR_CG_MULTILINE"
install_hooks "$DIR_CG_MULTILINE"
OUT=$(run_commit_gate "$DIR_CG_MULTILINE" 'git commit -m "wip"
cargo add serde')
RC=$?
assert_rc0 "$RC" "cg: a newline-separated unrelated 'add' command exits 0"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: multi-line command false positive has no deny fields"

# Round-3 review: a command separator with no surrounding whitespace
# (";","&&","|") must not bypass segmentation and let a genuine compound
# stage-and-commit through as an unrecognized single blob.
DIR_CG_NOSPACE="$WORK/commit-gate-no-space-separators"
make_fixture "$DIR_CG_NOSPACE"
install_hooks "$DIR_CG_NOSPACE"
OUT=$(run_commit_gate "$DIR_CG_NOSPACE" 'git add .;git commit;git push')
RC=$?
assert_rc0 "$RC" "cg: compound form with no-space separators exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: no-space-separator compound denial uses JSON deny form"
assert_contains "$OUT" "compound-stage-and-commit" \
  "cg: no-space-separator compound denial names the finding class"

# The other direction of the multi-line requirement: a GENUINE compound
# command spread across a bare newline (no && or ; at all) must still be
# recognized and denied, not accidentally merged into a single segment where
# only the first subcommand token is ever inspected.
DIR_CG_NEWLINE_COMPOUND="$WORK/commit-gate-newline-compound"
make_fixture "$DIR_CG_NEWLINE_COMPOUND"
install_hooks "$DIR_CG_NEWLINE_COMPOUND"
OUT=$(run_commit_gate "$DIR_CG_NEWLINE_COMPOUND" 'git add newfile.txt
git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: compound form spread across a bare newline exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: newline-separated compound denial uses JSON deny form"
assert_contains "$OUT" "compound-stage-and-commit" \
  "cg: newline-separated compound denial names the finding class"

# Round-4/5 review: GIT_FLAGS_WITH_VALUE previously only knew -C/-c, then a
# from-memory pass added 6 more flags that both missed 2 real ones
# (--config-env, --shallow-file) and kept 2 that don't actually consume a
# following argument on git 2.52 (--exec-path, --super-prefix) -- round 5
# probed the full flag set mechanically and confirmed the corrected set
# below. One regression test per flag, each with a real staged secret to
# prove the gate actually scans (not just "doesn't crash").
for CG_FLAG_CASE in \
  "--git-dir .git" \
  "--work-tree ." \
  "--namespace ns" \
  "--attr-source HEAD" \
  "--config-env u.x=MYVAR" \
  "--shallow-file /dev/null"
do
  CG_FLAG_DIR="$WORK/commit-gate-global-flag-$(echo "$CG_FLAG_CASE" | tr -c 'a-zA-Z0-9' '-')"
  make_fixture "$CG_FLAG_DIR"
  install_hooks "$CG_FLAG_DIR"
  printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$CG_FLAG_DIR/secret.py"
  git -C "$CG_FLAG_DIR" add secret.py
  OUT=$(run_commit_gate "$CG_FLAG_DIR" "git $CG_FLAG_CASE commit -m msg")
  RC=$?
  assert_rc0 "$RC" "cg: 'git $CG_FLAG_CASE commit' still scans (JSON deny), not bypassed"
  assert_deny_json "$OUT" "cg: 'git $CG_FLAG_CASE commit' secret denial uses JSON deny form"
  assert_contains "$OUT" "secret-assignment" \
    "cg: 'git $CG_FLAG_CASE commit' denial names secret-assignment specifically"
done

# A segment that IS "git" plus flags but never reaches a real subcommand
# token (e.g. the first half of "git -C . && git commit") must not be
# mistaken for a subcommand-bearing segment.
DIR_CG_FLAGSONLY="$WORK/commit-gate-flags-only-segment"
make_fixture "$DIR_CG_FLAGSONLY"
install_hooks "$DIR_CG_FLAGSONLY"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_FLAGSONLY/secret.py"
git -C "$DIR_CG_FLAGSONLY" add secret.py
OUT=$(run_commit_gate "$DIR_CG_FLAGSONLY" 'git -C . && git commit -m msg')
RC=$?
assert_rc0 "$RC" "cg: a flags-only git segment followed by a real commit still scans"
assert_deny_json "$OUT" "cg: flags-only-segment secret denial uses JSON deny form"

# Round-4 review: "sudo git"/"env FOO=1 git" wrapper prefixes remain an
# accepted, documented residual hole (open-ended wrapper-command allowlist,
# out of scope), but /usr/bin/git and a paren-wrapped "(git ..." are cheap to
# recognize and were fixed.
DIR_CG_PATHGIT="$WORK/commit-gate-path-prefixed-git"
make_fixture "$DIR_CG_PATHGIT"
install_hooks "$DIR_CG_PATHGIT"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_PATHGIT/secret.py"
git -C "$DIR_CG_PATHGIT" add secret.py
OUT=$(run_commit_gate "$DIR_CG_PATHGIT" '/usr/bin/git commit -m msg')
RC=$?
assert_rc0 "$RC" "cg: '/usr/bin/git commit' still scans (JSON deny), not bypassed"
assert_deny_json "$OUT" "cg: path-prefixed git secret denial uses JSON deny form"

DIR_CG_PARENGIT="$WORK/commit-gate-paren-wrapped-git"
make_fixture "$DIR_CG_PARENGIT"
install_hooks "$DIR_CG_PARENGIT"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_PARENGIT/secret.py"
git -C "$DIR_CG_PARENGIT" add secret.py
OUT=$(run_commit_gate "$DIR_CG_PARENGIT" '(git commit -m msg)')
RC=$?
assert_rc0 "$RC" "cg: '(git commit ...)' still scans (JSON deny), not bypassed"
assert_deny_json "$OUT" "cg: paren-wrapped git secret denial uses JSON deny form"

# Round-5 review: \git (the standard idiom for bypassing a shell alias named
# git, not adversarial evasion) was not recognized as git-shaped at all.
DIR_CG_BACKSLASHGIT="$WORK/commit-gate-backslash-prefixed-git"
make_fixture "$DIR_CG_BACKSLASHGIT"
install_hooks "$DIR_CG_BACKSLASHGIT"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_BACKSLASHGIT/secret.py"
git -C "$DIR_CG_BACKSLASHGIT" add secret.py
OUT=$(run_commit_gate "$DIR_CG_BACKSLASHGIT" '\git commit -m msg')
RC=$?
assert_rc0 "$RC" "cg: '\\git commit' still scans (JSON deny), not bypassed"
assert_deny_json "$OUT" "cg: backslash-prefixed git secret denial uses JSON deny form"

# Round-5 review (post-approval recommendation): an unquoted backslash-newline
# shell continuation split "git" and "commit" into two segments that neither
# alone tokenized as git-shaped, no-op'ing the entire gate -- a fail-open
# bypass, not merely a missed check, since the secret scan itself was
# skipped. Joining continuations before segmenting closes this at zero cost
# (verified: no other matrix entry changes).
DIR_CG_CONTINUATION="$WORK/commit-gate-backslash-newline-continuation"
make_fixture "$DIR_CG_CONTINUATION"
install_hooks "$DIR_CG_CONTINUATION"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_CONTINUATION/secret.py"
git -C "$DIR_CG_CONTINUATION" add secret.py
OUT=$(run_commit_gate "$DIR_CG_CONTINUATION" 'git \
commit -m msg')
RC=$?
assert_rc0 "$RC" "cg: backslash-newline-continued 'git commit' still scans (JSON deny), not bypassed"
assert_deny_json "$OUT" "cg: continued-command secret denial uses JSON deny form"

# The continuation join must not defeat quote-stripping: a continuation
# INSIDE a quoted commit message is already collapsed to whitespace by
# quote-stripping either way, so it must not itself trigger a denial. Stages
# a real secret and asserts a positive secret-assignment denial (not just
# "not denied") -- proving the command IS recognized as git-shaped and
# scanned, rather than merely unrecognized. A clean-index "not denied"
# assertion can't tell those two apart, which is exactly the weakness that
# let the continuation bypass go undetected for several review rounds
# (found by adversarial review of PR #40, round 6).
DIR_CG_CONTINUATION_QUOTED="$WORK/commit-gate-continuation-inside-quotes"
make_fixture "$DIR_CG_CONTINUATION_QUOTED"
install_hooks "$DIR_CG_CONTINUATION_QUOTED"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_CONTINUATION_QUOTED/secret.py"
git -C "$DIR_CG_CONTINUATION_QUOTED" add secret.py
OUT=$(run_commit_gate "$DIR_CG_CONTINUATION_QUOTED" 'git commit -m "line one \
line two"')
RC=$?
assert_rc0 "$RC" "cg: a continuation inside a quoted commit message exits 0"
assert_deny_json "$OUT" "cg: continuation-inside-quotes is recognized and scanned (secret denial)"
assert_contains "$OUT" "secret-assignment" \
  "cg: continuation-inside-quotes denial names secret-assignment, not compound"
assert_not_contains "$OUT" "compound-stage-and-commit" \
  "cg: continuation-inside-quotes is not wrongly denied as compound"

# A genuine compound command split across a continuation must still deny --
# joining continuations must not accidentally merge two real segments into
# one that dodges the compound check.
DIR_CG_CONTINUATION_COMPOUND="$WORK/commit-gate-continuation-compound"
make_fixture "$DIR_CG_CONTINUATION_COMPOUND"
install_hooks "$DIR_CG_CONTINUATION_COMPOUND"
OUT=$(run_commit_gate "$DIR_CG_CONTINUATION_COMPOUND" 'git add newfile.txt \
&& git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: compound form split across a continuation exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: continuation-split compound denial uses JSON deny form"
assert_contains "$OUT" "compound-stage-and-commit" \
  "cg: continuation-split compound denial names the finding class"

# Round-6 review: "&" (background execution, and the leading half of "|&")
# was not a segment separator, so everything before it stayed glued to
# everything after it and only the first segment's subcommand was ever
# seen -- a real, working commit path, not hypothetical.
DIR_CG_AMPERSAND="$WORK/commit-gate-ampersand-separator"
make_fixture "$DIR_CG_AMPERSAND"
install_hooks "$DIR_CG_AMPERSAND"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_AMPERSAND/secret.py"
git -C "$DIR_CG_AMPERSAND" add secret.py
for CG_AMP_CMD in \
  'git status & git commit -m x' \
  'git add . & git commit -m x' \
  'git status |& git commit -m x'
do
  OUT=$(run_commit_gate "$DIR_CG_AMPERSAND" "$CG_AMP_CMD")
  RC=$?
  assert_rc0 "$RC" "cg: '$CG_AMP_CMD' still scans (JSON deny), not bypassed"
  assert_deny_json "$OUT" "cg: '$CG_AMP_CMD' secret denial uses JSON deny form"
done

# The same missing "&" separator also hid a compound-stage-and-commit case
# on the Check 0 side: an unrelated command glued to "git add ." by "&"
# collapsed into one segment led by the unrelated command, so the "git add"
# was invisible and no compound denial fired.
DIR_CG_AMPERSAND_COMPOUND="$WORK/commit-gate-ampersand-compound"
make_fixture "$DIR_CG_AMPERSAND_COMPOUND"
install_hooks "$DIR_CG_AMPERSAND_COMPOUND"
OUT=$(run_commit_gate "$DIR_CG_AMPERSAND_COMPOUND" 'echo hi & git add . && git commit -m x')
RC=$?
assert_rc0 "$RC" "cg: '&'-glued compound form exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: '&'-glued compound denial uses JSON deny form"
assert_contains "$OUT" "compound-stage-and-commit" \
  "cg: '&'-glued compound denial names the finding class"

# Round-6 review: the continuation-join fix (b9d639a) introduced its own
# fail-open regression -- a blanket replace("\\n", " ") with no parity check
# wrongly joined an ESCAPED backslash followed by a genuine separator
# newline (an EVEN run of backslashes) into one segment, hiding the second
# command from the gate entirely. join_continuations now only joins when an
# ODD run of backslashes precedes the newline.
DIR_CG_ESCAPED_BACKSLASH="$WORK/commit-gate-escaped-backslash-real-separator"
make_fixture "$DIR_CG_ESCAPED_BACKSLASH"
install_hooks "$DIR_CG_ESCAPED_BACKSLASH"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_ESCAPED_BACKSLASH/secret.py"
git -C "$DIR_CG_ESCAPED_BACKSLASH" add secret.py
CG_ESCAPED_CMD=$(printf 'echo a\\\\\ngit commit -m x')
OUT=$(run_commit_gate "$DIR_CG_ESCAPED_BACKSLASH" "$CG_ESCAPED_CMD")
RC=$?
assert_rc0 "$RC" "cg: an escaped backslash before a real separator newline exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: escaped-backslash-then-real-newline still scans the second command"
assert_contains "$OUT" "secret-assignment" \
  "cg: escaped-backslash-then-real-newline denial names secret-assignment"

# Round-6 review: a shell reserved word ("then"/"do"/"else"/"elif") leading
# a simple command inside a control structure defeated recognition, since
# segment_subcommand only skipped VAR=value prefixes. A closed 4-word set,
# unlike the open-ended wrapper-command class, so it is enumerated and
# fixed rather than merely documented as accepted.
DIR_CG_KEYWORDS="$WORK/commit-gate-shell-leading-keywords"
make_fixture "$DIR_CG_KEYWORDS"
install_hooks "$DIR_CG_KEYWORDS"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_KEYWORDS/secret.py"
git -C "$DIR_CG_KEYWORDS" add secret.py
for CG_KEYWORD_CMD in \
  'if true; then git commit -m x; fi' \
  'for f in a; do git commit -m x; done' \
  'while true; do git commit -m x; done' \
  'until false; do git commit -m x; done'
do
  OUT=$(run_commit_gate "$DIR_CG_KEYWORDS" "$CG_KEYWORD_CMD")
  RC=$?
  assert_rc0 "$RC" "cg: '$CG_KEYWORD_CMD' still scans (JSON deny), not bypassed"
  assert_deny_json "$OUT" "cg: '$CG_KEYWORD_CMD' secret denial uses JSON deny form"
done

# Round-4/5 review: attached short-flag clusters where the flag TAKES a value
# (-m, -F, -S, ...) were wrongly denied because the rest of the cluster's
# characters were scanned for 'a'/'i' as if they were more flags. Each case
# stages a real secret and asserts a secret-assignment denial (not just "not
# denied"), proving the command was recognized as a commit and scanned --
# not merely unrecognized -- and that it wasn't ALSO wrongly flagged as
# compound-stage-and-commit.
DIR_CG_ATTACHEDFLAG="$WORK/commit-gate-attached-value-flags"
make_fixture "$DIR_CG_ATTACHEDFLAG"
install_hooks "$DIR_CG_ATTACHEDFLAG"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_ATTACHEDFLAG/secret.py"
git -C "$DIR_CG_ATTACHEDFLAG" add secret.py
for CG_ATTACHED_CMD in \
  'git commit -mfix' \
  'git commit -Fdraft.txt' \
  'git commit -S0a46826a -m x' \
  'git commit -- -a.txt'
do
  OUT=$(run_commit_gate "$DIR_CG_ATTACHEDFLAG" "$CG_ATTACHED_CMD")
  RC=$?
  assert_rc0 "$RC" "cg: '$CG_ATTACHED_CMD' exits 0"
  assert_deny_json "$OUT" "cg: '$CG_ATTACHED_CMD' is scanned and denied for the secret"
  assert_contains "$OUT" "secret-assignment" \
    "cg: '$CG_ATTACHED_CMD' denial names secret-assignment, not compound"
  assert_not_contains "$OUT" "compound-stage-and-commit" \
    "cg: '$CG_ATTACHED_CMD' is not wrongly denied as a staging flag"
done

# Coverage: a VAR=value env-assignment prefix before "git" must not prevent
# the command from being recognized and scanned.
DIR_CG_ENVPREFIX="$WORK/commit-gate-env-assignment-prefix"
make_fixture "$DIR_CG_ENVPREFIX"
install_hooks "$DIR_CG_ENVPREFIX"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_ENVPREFIX/secret.py"
git -C "$DIR_CG_ENVPREFIX" add secret.py
OUT=$(run_commit_gate "$DIR_CG_ENVPREFIX" 'GIT_AUTHOR_NAME=x GIT_AUTHOR_EMAIL=y git commit -m msg')
RC=$?
assert_rc0 "$RC" "cg: multiple VAR=value prefixes before git still scans (JSON deny)"
assert_deny_json "$OUT" "cg: env-assignment-prefixed secret denial uses JSON deny form"

# Coverage: an argument-less global flag (--no-pager) between "git" and the
# real subcommand.
DIR_CG_NOPAGER="$WORK/commit-gate-no-pager-flag"
make_fixture "$DIR_CG_NOPAGER"
install_hooks "$DIR_CG_NOPAGER"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_NOPAGER/secret.py"
git -C "$DIR_CG_NOPAGER" add secret.py
OUT=$(run_commit_gate "$DIR_CG_NOPAGER" 'git --no-pager commit -m msg')
RC=$?
assert_rc0 "$RC" "cg: 'git --no-pager commit' still scans (JSON deny)"
assert_deny_json "$OUT" "cg: --no-pager secret denial uses JSON deny form"

# Coverage: find_style_violation's own scan-time-budget-exhausted return path
# (distinct from find_secret's, which the earlier ReDoS-guard tests exercise).
DIR_CG_STYLE_BUDGET="$WORK/commit-gate-style-budget-exhausted"
make_fixture "$DIR_CG_STYLE_BUDGET"
install_hooks "$DIR_CG_STYLE_BUDGET"
python3 - "$DIR_CG_STYLE_BUDGET/.harness/harness.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["style_gate"] = {"enabled": True}
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
python3 -c "
line = 'key' * 700
print('\n'.join([line] * 1500))
" > "$DIR_CG_STYLE_BUDGET/adversarial_style.txt"
git -C "$DIR_CG_STYLE_BUDGET" add adversarial_style.txt
OUT=$(run_commit_gate "$DIR_CG_STYLE_BUDGET" 'git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: style-gate scan under budget pressure still exits 0"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: style-gate budget exhaustion fails open (no deny)"

# Coverage: find_style_violation's own clean-completion path (the loop runs to
# the end without finding an em dash), distinct from the deadline-exhausted
# return above and from the positive-match case tested elsewhere.
DIR_CG_STYLE_CLEAN="$WORK/commit-gate-style-clean-completion"
make_fixture "$DIR_CG_STYLE_CLEAN"
install_hooks "$DIR_CG_STYLE_CLEAN"
python3 - "$DIR_CG_STYLE_CLEAN/.harness/harness.json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data["style_gate"] = {"enabled": True}
with open(path, "w") as f:
    json.dump(data, f)
PYEOF
printf 'no secrets and no house-style violations here\n' > "$DIR_CG_STYLE_CLEAN/plain.txt"
git -C "$DIR_CG_STYLE_CLEAN" add plain.txt
OUT=$(run_commit_gate "$DIR_CG_STYLE_CLEAN" 'git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: style gate on, clean staged content exits 0"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: style gate on, clean staged content is not denied"

# Coverage: style_gate_enabled()'s except branch fires only when execution
# reaches that function at all, which requires find_secret to find nothing
# first (a corrupt harness.json alone, as tested above, never gets there
# because that fixture's staged content also contains a secret).
DIR_CG_STYLE_CORRUPT="$WORK/commit-gate-style-corrupt-harness-json"
make_fixture "$DIR_CG_STYLE_CORRUPT"
install_hooks "$DIR_CG_STYLE_CORRUPT"
printf 'not valid json{{{' > "$DIR_CG_STYLE_CORRUPT/.harness/harness.json"
printf 'no secrets and no house-style violations here\n' > "$DIR_CG_STYLE_CORRUPT/plain.txt"
git -C "$DIR_CG_STYLE_CORRUPT" add plain.txt
OUT=$(run_commit_gate "$DIR_CG_STYLE_CORRUPT" 'git commit -m "test"')
RC=$?
assert_rc0 "$RC" "cg: corrupt harness.json with no secret in diff exits 0"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: corrupt harness.json treats style gate as disabled, not denied"

# F025: strip_quotes() deleted quoted spans before tokenization, so quoting
# any part of the "git"/"commit" tokens erased them entirely -- parse_command
# never saw a "commit" subcommand, and main() returned before EITHER the
# compound-stage-and-commit check or the secret scan ran. Same root cause as
# F023's round-2 finding in enforce-scope.sh.template: strip_quotes() deletes
# content that is load-bearing for the gate's decision. Each case stages a
# real secret and asserts a positive secret-assignment denial, proving the
# quoted invocation is still recognized as git-shaped and scanned.
DIR_CG_QUOTED_TOKEN="$WORK/commit-gate-quoted-subcommand-token"
make_fixture "$DIR_CG_QUOTED_TOKEN"
install_hooks "$DIR_CG_QUOTED_TOKEN"
printf 'api_key = "abcdefghijklmnopqrstuvwx"\n' > "$DIR_CG_QUOTED_TOKEN/secret.py"
git -C "$DIR_CG_QUOTED_TOKEN" add secret.py
for CG_QUOTED_CMD in \
  'git "commit" -m x' \
  "git 'commit' -m x" \
  '"git" commit -m x' \
  'git com"mit" -m x'
do
  OUT=$(run_commit_gate "$DIR_CG_QUOTED_TOKEN" "$CG_QUOTED_CMD")
  RC=$?
  assert_rc0 "$RC" "cg: '$CG_QUOTED_CMD' still scans (JSON deny), not bypassed"
  assert_deny_json "$OUT" "cg: '$CG_QUOTED_CMD' secret denial uses JSON deny form"
  assert_contains "$OUT" "secret-assignment" \
    "cg: '$CG_QUOTED_CMD' denial names secret-assignment"
done

# The same erasure bug also let a quoted staging flag bypass Check 0's
# compound-stage-and-commit detection.
OUT=$(run_commit_gate "$DIR_CG_QUOTED_TOKEN" 'git commit "-a" -m x')
RC=$?
assert_rc0 "$RC" "cg: a quoted staging flag still exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: quoted staging flag denial uses JSON deny form"
assert_contains "$OUT" "compound-stage-and-commit" \
  "cg: quoted staging flag denial names the finding class"

# No new false positive: a commit message that happens to contain the word
# "commit" or "git" in quotes must not itself trigger recognition of a
# DIFFERENT segment, and quoting must not break a normal, already-correct
# invocation. Asserts BOTH secret-assignment AND not-compound: a fixture with
# a staged secret denies on ANY bug (a false compound match is also a deny),
# so asserting only assert_deny_json here cannot fail for the reason it
# claims to test -- found by adversarial review of PR #44, round 1.
OUT=$(run_commit_gate "$DIR_CG_QUOTED_TOKEN" 'git commit -m "please git commit later"')
RC=$?
assert_rc0 "$RC" "cg: a quoted commit-message mentioning git/commit still scans normally"
assert_deny_json "$OUT" "cg: quoted-message secret denial uses JSON deny form"
assert_contains "$OUT" "secret-assignment" \
  "cg: quoted-message denial names secret-assignment, not compound"
assert_not_contains "$OUT" "compound-stage-and-commit" \
  "cg: quoted-message mentioning git/commit is not wrongly denied as compound"

# F025 round 1 review: split_tokens() was added because command_segments()'s
# mask-then-slice fix preserved quoted content at the SEGMENT level but
# parse_command still tokenized with naive seg.split(), which treats
# whitespace INSIDE a quoted commit message as a real token boundary.
# Whitespace-splitting used to be masked by accident under the old
# strip_quotes()-based design (which deleted the message text these
# pseudo-tokens came from); F025's own fix exposed it. A quoted "--" ANYWHERE
# in the message shattered into its own pseudo-token, which has_staging_flag
# then misread as the pathspec separator, stopping its scan before reaching a
# REAL staging flag later in the segment -- a fail-open bypass, not merely a
# missed check, on a clean-repo command that stages and commits in one step.
DIR_CG_QUOTED_MSG_TOKENS="$WORK/commit-gate-quoted-message-token-boundaries"
make_fixture "$DIR_CG_QUOTED_MSG_TOKENS"
install_hooks "$DIR_CG_QUOTED_MSG_TOKENS"
for CG_SHADOWED_FLAG_CMD in \
  'git commit -m "see --" -a' \
  'git commit -m "a -- b" -a' \
  'git commit -m "note --" -am wip'
do
  OUT=$(run_commit_gate "$DIR_CG_QUOTED_MSG_TOKENS" "$CG_SHADOWED_FLAG_CMD")
  RC=$?
  assert_rc0 "$RC" "cg: '$CG_SHADOWED_FLAG_CMD' exits 0 (JSON deny)"
  assert_deny_json "$OUT" "cg: '$CG_SHADOWED_FLAG_CMD' is not shadowed, still denied"
  assert_contains "$OUT" "compound-stage-and-commit" \
    "cg: '$CG_SHADOWED_FLAG_CMD' denial names compound-stage-and-commit"
done

# Same root cause, opposite direction: flag-shaped words inside a quoted
# commit message (no real staging flag anywhere in the command) must not
# trigger a false compound-stage-and-commit denial on a clean repo.
for CG_FLAGWORD_MSG_CMD in \
  'git commit -m "fix: handle -a and -i staging flags"' \
  'git commit -m "add --all support"' \
  'git commit -m "support --include option"' \
  'git commit -m "docs: describe -am cluster"'
do
  OUT=$(run_commit_gate "$DIR_CG_QUOTED_MSG_TOKENS" "$CG_FLAGWORD_MSG_CMD")
  RC=$?
  assert_rc0 "$RC" "cg: '$CG_FLAGWORD_MSG_CMD' exits 0, rc 0"
  assert_not_contains "$OUT" "permissionDecision" \
    "cg: '$CG_FLAGWORD_MSG_CMD' is not wrongly denied as compound"
done

# F027: has_staging_flag() didn't know a space-separated value-taking short
# flag's VALUE token (e.g. -m's next token) is opaque data, never a flag or a
# "--" pathspec separator itself. Three shapes, one root cause:
#   (a) `-m -- -a`  : "--" (unquoted, -m's value) wrongly read as a real
#       pathspec separator, so the REAL -a flag after it was never reached --
#       a pre-existing false-negative, present before F025 too.
#   (b) `-m "--" -a`: same false negative, quoted form.
#   (c) `-m "-a"`   : -m's value is literally the text "-a" -- nothing else
#       is staged (verified against real git), but the old code read the
#       value token itself as if it were the -a flag -- a false positive.
DIR_CG_MVALUE="$WORK/commit-gate-m-value-token"
make_fixture "$DIR_CG_MVALUE"
install_hooks "$DIR_CG_MVALUE"
for CG_MVALUE_DENY_CMD in \
  'git commit -m -- -a' \
  'git commit -m "--" -a'
do
  OUT=$(run_commit_gate "$DIR_CG_MVALUE" "$CG_MVALUE_DENY_CMD")
  RC=$?
  assert_rc0 "$RC" "cg: '$CG_MVALUE_DENY_CMD' exits 0 (JSON deny)"
  assert_deny_json "$OUT" "cg: '$CG_MVALUE_DENY_CMD' -a after -m's value is still denied"
  assert_contains "$OUT" "compound-stage-and-commit" \
    "cg: '$CG_MVALUE_DENY_CMD' denial names compound-stage-and-commit"
done

OUT=$(run_commit_gate "$DIR_CG_MVALUE" 'git commit -m "-a"')
RC=$?
assert_rc0 "$RC" "cg: 'git commit -m \"-a\"' exits 0, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: -m's own value '-a' is not misread as the -a staging flag"

# F027 round-1 review: a first pass only skipped the value token for a BARE
# 2-character flag ("-m" alone), missing every multi-letter cluster ending
# on a value-taking flag, e.g. "-sm" (sign-off + message). Same 2 shapes,
# cluster form. Verified against real git: `git commit -sm -- -a` both
# signs off AND stages (via the real trailing -a), and `git commit -sm "-a"`
# stages nothing extra (-a is just message text).
OUT=$(run_commit_gate "$DIR_CG_MVALUE" 'git commit -sm -- -a')
RC=$?
assert_rc0 "$RC" "cg: 'git commit -sm -- -a' exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: cluster-form -sm's value doesn't shadow a real trailing -a"
assert_contains "$OUT" "compound-stage-and-commit" \
  "cg: 'git commit -sm -- -a' denial names compound-stage-and-commit"

OUT=$(run_commit_gate "$DIR_CG_MVALUE" 'git commit -sm "-a"')
RC=$?
assert_rc0 "$RC" "cg: 'git commit -sm \"-a\"' exits 0, rc 0"
assert_not_contains "$OUT" "permissionDecision" \
  "cg: cluster-form -sm's own value '-a' is not misread as the -a staging flag"

# Round-2 review: the round-1 fix made -S/-u position-aware TOO, treating a
# bare/clustered -S or -u as consuming the next token as its value like -m
# does. Real git parses -S/-u as optargs (PARSE_OPT_OPTARG): a BARE -S/-u
# uses its default and does NOT consume the next token, so `-u -a`/`-S -a`
# (and clustered `-nu -a`/`-vS -a`) are genuine stage-and-commit shapes that
# `main` already denied and the round-1 fix wrongly allowed -- found by
# adversarial review of PR #49, round 2, confirmed against real git 2.52.0.
OUT=$(run_commit_gate "$DIR_CG_MVALUE" 'git commit -u -a -m x')
RC=$?
assert_rc0 "$RC" "cg: 'git commit -u -a -m x' exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: bare -u does not swallow a real trailing -a"

OUT=$(run_commit_gate "$DIR_CG_MVALUE" 'git commit -S -a -m x')
RC=$?
assert_rc0 "$RC" "cg: 'git commit -S -a -m x' exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: bare -S does not swallow a real trailing -a"

OUT=$(run_commit_gate "$DIR_CG_MVALUE" 'git commit -nu -a -m x')
RC=$?
assert_rc0 "$RC" "cg: 'git commit -nu -a -m x' exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: clustered -nu does not swallow a real trailing -a"

OUT=$(run_commit_gate "$DIR_CG_MVALUE" 'git commit -vS -a -m x')
RC=$?
assert_rc0 "$RC" "cg: 'git commit -vS -a -m x' exits 0 (JSON deny)"
assert_deny_json "$OUT" "cg: clustered -vS does not swallow a real trailing -a"

echo ""
echo "== agent frontmatter =="

AGENT_ERRORS=$(python3 - "$REPO_ROOT" <<'PYEOF'
import os
import sys

root = sys.argv[1]
agents_dir = os.path.join(root, "agents")
names = sorted(n for n in os.listdir(agents_dir) if n.endswith(".md"))
if not names:
    print("no agent files found in agents/")
for fname in names:
    stem = fname[:-3]
    lines = open(os.path.join(agents_dir, fname)).read().splitlines()
    if not lines or lines[0] != "---":
        print(f"{fname}: does not start with ---")
        continue
    try:
        end = lines[1:].index("---") + 1
    except ValueError:
        print(f"{fname}: frontmatter has no closing ---")
        continue
    fm = {}
    for line in lines[1:end]:
        if line and not line[0].isspace() and ":" in line:
            key, _, value = line.partition(":")
            fm[key.strip()] = value.strip()
    for key in ("name", "description", "model"):
        if key not in fm:
            print(f"{fname}: missing {key}: key")
    if "name" in fm and fm["name"] != stem:
        print(f"{fname}: name '{fm['name']}' does not match filename stem '{stem}'")
    model = fm.get("model", "")
    if model and model not in ("sonnet", "opus", "haiku", "fable", "inherit"):
        print(f"{fname}: model '{model}' not in allowed set")
    if "tools" in fm:
        tools = fm["tools"]
        items = [t.strip() for t in tools.split(",")]
        if not tools or tools in (">", ">-", "|", "|-") or any(not t for t in items):
            print(f"{fname}: tools must be a non-empty one-line comma-separated string")
PYEOF
)
if [ -z "$AGENT_ERRORS" ]; then
  pass "m: all agents/*.md have sane frontmatter"
else
  fail "m: agent frontmatter -- $AGENT_ERRORS"
fi

echo ""
echo "== shell syntax =="

for SCRIPT in "$HOOKS_DIR"/*.sh "$SCRIPT_DIR/run-tests.sh"; do
  if bash -n "$SCRIPT"; then
    pass "n: bash -n $(basename "$SCRIPT")"
  else
    fail "n: bash -n $(basename "$SCRIPT")"
  fi
done

SYNTAX_DIR="$WORK/template-syntax"
mkdir -p "$SYNTAX_DIR"
for TPL in "$TEMPLATES_DIR"/*.sh.template; do
  BASE=$(basename "$TPL" .template)
  cp "$TPL" "$SYNTAX_DIR/$BASE"
  if bash -n "$SYNTAX_DIR/$BASE"; then
    pass "n: bash -n $BASE (template)"
  else
    fail "n: bash -n $BASE (template)"
  fi
done

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "Summary: $PASS_COUNT/$TOTAL assertions passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
