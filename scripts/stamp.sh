#!/usr/bin/env bash
# scripts/stamp.sh -- deterministic file emitter for /harness-init (F013/OVI-63).
# Adapted from Setlist's two-phase bootstrap doctrine (Alex Ciortan, CC BY 4.0):
# "Never hand-write what a stamp can emit; never stamp what a decision shapes."
#
# Usage: scripts/stamp.sh <answers-file> <target-dir>
#
# Answers file: KEY=VALUE lines (blank lines and #-comments ignored).
#   project_name  - free text, used in .harness/harness.json and features.json
#   stack         - typescript | swift | python | go | rust | anything else
#                   (an unrecognized stack gets no PostToolUse build-check
#                   hook -- matches today's behavior, which only offers one
#                   for these 5 known stacks)
#   team_mode     - single | teams (sets env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
#                   to "0" or "1"; always present so a doctor/settings check
#                   can rely on the key existing)
#   mode          - new | upgrade
#
# new mode: aborts (exit 1) if ANY target file already exists, listing every
# collision, and writes NOTHING.
#
# upgrade mode: writes any target file that doesn't yet exist; for one that
# does, overwrites ONLY if it is byte-identical to what a fresh stamp would
# produce right now (a no-op refresh) -- any other difference is left alone
# and reported as a customization, never silently overwritten. Always exits
# 0 (skipping a customization is success, not failure).
#
# The .gitignore SESSION_INCOMPLETE line is appended idempotently in both
# modes, independent of collision handling for the other files.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SKILL_DIR="$PLUGIN_ROOT/skills/harness-init"
TEMPLATES_DIR="$SKILL_DIR/templates"

ANSWERS_FILE="${1:?usage: stamp.sh <answers-file> <target-dir>}"
TARGET_DIR="${2:?usage: stamp.sh <answers-file> <target-dir>}"

if [ ! -f "$ANSWERS_FILE" ]; then
  echo "stamp.sh: answers file not found: $ANSWERS_FILE" >&2
  exit 1
fi

PROJECT_NAME=""
STACK=""
TEAM_MODE=""
MODE=""
while IFS='=' read -r key value || [ -n "$key" ]; do
  case "$key" in
    ''|'#'*) continue ;;
  esac
  case "$key" in
    project_name) PROJECT_NAME="$value" ;;
    stack) STACK="$value" ;;
    team_mode) TEAM_MODE="$value" ;;
    mode) MODE="$value" ;;
  esac
done < "$ANSWERS_FILE"

if [ -z "$PROJECT_NAME" ]; then
  echo "stamp.sh: answers file missing required key: project_name" >&2
  exit 1
fi
if [ -z "$STACK" ]; then
  echo "stamp.sh: answers file missing required key: stack" >&2
  exit 1
fi
if [ -z "$TEAM_MODE" ]; then
  echo "stamp.sh: answers file missing required key: team_mode" >&2
  exit 1
fi
if [ -z "$MODE" ]; then
  echo "stamp.sh: answers file missing required key: mode" >&2
  exit 1
fi

case "$TEAM_MODE" in
  single) ENV_TEAMS_FLAG="0" ;;
  teams) ENV_TEAMS_FLAG="1" ;;
  *)
    echo "stamp.sh: team_mode must be 'single' or 'teams', got: $TEAM_MODE" >&2
    exit 1
    ;;
esac

case "$MODE" in
  new|upgrade) ;;
  *)
    echo "stamp.sh: mode must be 'new' or 'upgrade', got: $MODE" >&2
    exit 1
    ;;
esac

CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

case "$STACK" in
  typescript|swift|python|go|rust)
    POSTTOOLUSE_FRAGMENT="$TEMPLATES_DIR/posttooluse-$STACK.json"
    ;;
  *)
    POSTTOOLUSE_FRAGMENT=""
    ;;
esac

WORKDIR=$(mktemp -d) || exit 1
trap 'rm -rf "$WORKDIR"' EXIT

# Render the three templated JSON files into $WORKDIR first, entirely
# independent of $TARGET_DIR -- new mode's collision pre-flight needs every
# target's content decided before touching disk.
python3 - "$TEMPLATES_DIR" "$WORKDIR" "$PROJECT_NAME" "$STACK" "$CREATED" "$ENV_TEAMS_FLAG" "$POSTTOOLUSE_FRAGMENT" <<'PYEOF'
import json
import sys

templates_dir, workdir, project_name, stack, created, env_teams_flag, posttooluse_fragment = sys.argv[1:8]


def read(path):
    with open(path) as fh:
        return fh.read()


def substitute(text, mapping):
    for key, value in mapping.items():
        text = text.replace("{{" + key + "}}", value)
    return text


posttooluse_json = "[]"
if posttooluse_fragment:
    posttooluse_json = read(posttooluse_fragment).strip()

settings_text = substitute(
    read(f"{templates_dir}/settings.json.tmpl"),
    {"ENV_TEAMS_FLAG": env_teams_flag, "POSTTOOLUSE_HOOKS": posttooluse_json},
)
json.loads(settings_text)

harness_text = substitute(
    read(f"{templates_dir}/harness.json.tmpl"),
    {"PROJECT_NAME": project_name, "STACK": stack, "CREATED": created},
)
json.loads(harness_text)

features_text = substitute(
    read(f"{templates_dir}/features.json.tmpl"),
    {"PROJECT_NAME": project_name, "CREATED": created},
)
json.loads(features_text)

with open(f"{workdir}/settings.json", "w") as fh:
    fh.write(settings_text)
with open(f"{workdir}/harness.json", "w") as fh:
    fh.write(harness_text)
with open(f"{workdir}/features.json", "w") as fh:
    fh.write(features_text)
PYEOF
if [ $? -ne 0 ]; then
  echo "stamp.sh: failed to render templated JSON" >&2
  exit 1
fi

# Byte-verbatim files: the 4 gate hook templates, harness_state.py,
# commit-gate.sh, and the plugin's shared statusline.sh.
mkdir -p "$WORKDIR/hooks"
cp "$SKILL_DIR/verify-task-quality.sh.template" "$WORKDIR/hooks/verify-task-quality.sh"
cp "$SKILL_DIR/check-remaining-tasks.sh.template" "$WORKDIR/hooks/check-remaining-tasks.sh"
cp "$SKILL_DIR/enforce-scope.sh.template" "$WORKDIR/hooks/enforce-scope.sh"
cp "$SKILL_DIR/verify-git-identity.sh.template" "$WORKDIR/hooks/verify-git-identity.sh"
cp "$SKILL_DIR/commit-gate.sh.template" "$WORKDIR/hooks/commit-gate.sh"
cp "$SKILL_DIR/harness_state.py.template" "$WORKDIR/hooks/harness_state.py"
cp "$PLUGIN_ROOT/hooks/statusline.sh" "$WORKDIR/hooks/statusline.sh"

MANIFEST="settings.json:.claude/settings.json
harness.json:.harness/harness.json
features.json:.harness/features.json
hooks/verify-task-quality.sh:.claude/hooks/verify-task-quality.sh
hooks/check-remaining-tasks.sh:.claude/hooks/check-remaining-tasks.sh
hooks/enforce-scope.sh:.claude/hooks/enforce-scope.sh
hooks/verify-git-identity.sh:.claude/hooks/verify-git-identity.sh
hooks/commit-gate.sh:.claude/hooks/commit-gate.sh
hooks/harness_state.py:.claude/hooks/harness_state.py
hooks/statusline.sh:.claude/hooks/statusline.sh"

COLLISIONS=""
while IFS=: read -r src dest; do
  [ -z "$src" ] && continue
  if [ -f "$TARGET_DIR/$dest" ]; then
    COLLISIONS="$COLLISIONS$dest
"
  fi
done <<EOF
$MANIFEST
EOF

if [ "$MODE" = "new" ] && [ -n "$COLLISIONS" ]; then
  echo "stamp.sh: mode=new aborted -- the following files already exist:" >&2
  printf '%s' "$COLLISIONS" | sed 's/^/  /' >&2
  echo "stamp.sh: nothing was written. Use mode=upgrade to update an existing project." >&2
  exit 1
fi

WRITTEN=""
REFRESHED=""
SKIPPED=""
while IFS=: read -r src dest; do
  [ -z "$src" ] && continue
  DEST_DIR=$(dirname "$TARGET_DIR/$dest")
  mkdir -p "$DEST_DIR"
  if [ -f "$TARGET_DIR/$dest" ]; then
    if cmp -s "$WORKDIR/$src" "$TARGET_DIR/$dest"; then
      cp "$WORKDIR/$src" "$TARGET_DIR/$dest"
      REFRESHED="$REFRESHED$dest
"
    else
      SKIPPED="$SKIPPED$dest
"
      continue
    fi
  else
    cp "$WORKDIR/$src" "$TARGET_DIR/$dest"
    WRITTEN="$WRITTEN$dest
"
  fi
  case "$dest" in
    .claude/hooks/*) chmod +x "$TARGET_DIR/$dest" ;;
  esac
done <<EOF
$MANIFEST
EOF

GITIGNORE="$TARGET_DIR/.gitignore"
touch "$GITIGNORE"
if ! grep -qxF '.harness/SESSION_INCOMPLETE' "$GITIGNORE"; then
  echo '.harness/SESSION_INCOMPLETE' >> "$GITIGNORE"
fi

echo "stamp.sh: mode=$MODE complete"
if [ -n "$WRITTEN" ]; then
  echo "written:"
  printf '%s' "$WRITTEN" | sed 's/^/  /'
fi
if [ -n "$REFRESHED" ]; then
  echo "refreshed (byte-identical to a fresh stamp):"
  printf '%s' "$REFRESHED" | sed 's/^/  /'
fi
if [ -n "$SKIPPED" ]; then
  echo "skipped (differs from a fresh stamp -- treated as a customization, left untouched):"
  printf '%s' "$SKIPPED" | sed 's/^/  /'
fi

exit 0
