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
# copied it yet -> "upgrade available", same tier as harness_state.py.
DIR_DOC_GATEMISSING="$WORK/doctor-commit-gate-missing"
make_healthy_doctor_fixture "$DIR_DOC_GATEMISSING"
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
