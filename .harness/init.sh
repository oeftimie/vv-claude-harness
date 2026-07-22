#!/bin/bash
# Harness init.sh - build/test runner for vv-claude-harness (stack: custom)
# Usage: .harness/init.sh [smoke_test|full_test]
# Default: full_test
#
# smoke_test — fast syntax/manifest check (<15s). Used by the
#              TaskCompleted hook as a first-pass rejection gate.
# full_test  — complete fixture-based test suite. Used by the lead's
#              synthesis step and session-end validation.

set -e

TARGET=${1:-full_test}

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== Harness ${TARGET} ==="
echo "Project: $PROJECT_ROOT"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

case "$TARGET" in
    smoke_test)
        echo "--- Shell Syntax Check (hooks/) ---"
        for f in hooks/*.sh; do
            bash -n "$f"
            echo "OK: $f"
        done
        echo ""
        echo "--- Plugin Manifest JSON Check ---"
        python3 -m json.tool .claude-plugin/plugin.json > /dev/null
        echo "OK: .claude-plugin/plugin.json"
        python3 -m json.tool .claude-plugin/marketplace.json > /dev/null
        echo "OK: .claude-plugin/marketplace.json"
        ;;
    full_test)
        echo "--- Test Suite ---"
        bash test/run-tests.sh
        ;;
    *)
        echo "ERROR: unknown target '$TARGET' (expected smoke_test or full_test)" >&2
        exit 1
        ;;
esac

echo ""
echo "=== ${TARGET} Complete ==="
