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
    if feature["id"] == "F002":
        feature["status"] = "passing"
        feature["coverage"] = 96
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
assert_empty "$OUT" "g: clean session-end prints nothing"

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
for skill_dir in ("harness-issue-prep", "harness-issue-debug"):
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
  pass "w: harness-issue-prep and harness-issue-debug SKILL.md files have sane frontmatter"
else
  fail "w: skill frontmatter -- $SKILL_ERRORS"
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

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "Summary: $PASS_COUNT/$TOTAL assertions passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
