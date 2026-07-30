#!/bin/bash
# VV Claude Code Harness - PreToolUse git identity verification hook
# Runs before Bash tool calls that contain git push/pull/clone.
# Exit code 0 = allow
# Exit code 2 = block (identity mismatch)
# Failure posture: fail-open. Missing harness.json, or a harness.json with no recorded
# git_identity, allows the command (exit 0) rather than blocking it; only an actually
# detected mismatch blocks (exit 2). Residual: an incomplete harness.json silently
# disables identity verification.

# Read hook input from stdin
INPUT=$(cat)

# Anchor to the project root so the hook works from any working directory
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT_ROOT" 2>/dev/null || exit 0

# Check if harness.json exists with git identity BEFORE extracting the
# command: this hook's own fail-open contract is "no configured identity ->
# nothing to protect, always allow" (see header), and that decision doesn't
# depend on the command at all -- checking it first means a project with no
# identity configured (the common case) never needs to worry about the
# command-extraction failure mode below, matching the existing exit-0
# posture exactly instead of introducing a new way to block a command this
# hook would never have checked in the first place.
if [ ! -f ".harness/harness.json" ]; then
    exit 0
fi

# Extract expected identity from harness.json
EXPECTED_NAME=$(python3 -c "
import json
with open('.harness/harness.json') as f:
    data = json.load(f)
print(data.get('git_identity', {}).get('user_name', ''))
" 2>/dev/null)

EXPECTED_EMAIL=$(python3 -c "
import json
with open('.harness/harness.json') as f:
    data = json.load(f)
print(data.get('git_identity', {}).get('user_email', ''))
" 2>/dev/null)

if [ -z "$EXPECTED_NAME" ] || [ -z "$EXPECTED_EMAIL" ]; then
    exit 0
fi

# Extract the command from tool input. The JSON parse itself is in its OWN
# try/except, exiting 2 on failure: a genuinely unparseable tool-input
# document is this hook's own documented fail-open contract (see the
# header). Everything AFTER a successful parse -- extracting the field and
# printing it -- is a SEPARATE try/except that exits 1 instead (F050, the
# identical two-stage split F043 already wrote and ground-truthed for
# enforce-scope.sh.template): a raw lone UTF-16 surrogate (0xD800-0xDFFF)
# arriving directly in the input JSON is perfectly valid JSON -- json.load()
# decodes it into a real Python str with no error -- but crashes the FINAL
# print(command) with UnicodeEncodeError once stdout isn't a tty. Before
# this fix, the single `2>/dev/null` on this whole command substitution
# swallowed that traceback, COMMAND came back empty, and the grep check
# below never matched "push|pull|clone|fetch" regardless of what the real
# command was, silently skipping this hook's identity check entirely
# (confirmed live: a real `git push` with a mismatched identity correctly
# denies, the identical command with a trailing surrogate exits 0 with no
# output at all). Two distinct exit codes (not "any nonzero") are required:
# an uncaught exception's default exit code is 1 regardless of which
# try/except raised it, so a single except-and-exit(1) around BOTH stages
# would make a genuinely unparseable document fail closed too, silently
# reversing this hook's own documented fail-open contract. Placed AFTER the
# "is identity even configured" checks above, so this only ever fails
# closed when there is a real identity to protect.
COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(2)
try:
    print(data.get('tool_input', {}).get('command', ''))
except Exception:
    sys.exit(1)
" 2>/dev/null)
COMMAND_RC=$?
if [ "$COMMAND_RC" -eq 1 ]; then
    echo "Git operation blocked: command could not be safely extracted from tool input (treating as a possible push/pull/clone/fetch out of caution)."
    exit 2
fi

# Only check git push, pull, clone, fetch commands
if ! echo "$COMMAND" | grep -qE 'git\s+(push|pull|clone|fetch)'; then
    exit 0
fi

# Check current git identity
CURRENT_NAME=$(git config user.name 2>/dev/null)
CURRENT_EMAIL=$(git config user.email 2>/dev/null)

if [ "$CURRENT_NAME" != "$EXPECTED_NAME" ] || [ "$CURRENT_EMAIL" != "$EXPECTED_EMAIL" ]; then
    echo "Git push blocked: identity mismatch."
    echo ""
    echo "Expected (from .harness/harness.json):"
    echo "  $EXPECTED_NAME <$EXPECTED_EMAIL>"
    echo ""
    echo "Current:"
    echo "  $CURRENT_NAME <$CURRENT_EMAIL>"
    echo ""
    echo "Fix with: git config user.name \"$EXPECTED_NAME\" && git config user.email \"$EXPECTED_EMAIL\""
    exit 2
fi

exit 0
