#!/bin/bash
# Harness init.sh - Multi-language build/test runner
# Usage: .harness/init.sh [smoke_test|full_test]
# Default: full_test
#
# smoke_test — fast compile/syntax check only (<15s). Used by the
#              TaskCompleted hook as a first-pass rejection gate.
# full_test  — complete test suite with coverage. Used by the lead's
#              synthesis step and session-end validation.

set -e

TARGET=${1:-full_test}

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== Harness ${TARGET} ==="
echo "Project: $PROJECT_ROOT"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

detect_stack() {
    if [ -f "Package.swift" ] || ls *.xcodeproj 1>/dev/null 2>&1; then
        echo "swift"
    elif [ -f "package.json" ]; then
        echo "node"
    elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "setup.py" ]; then
        echo "python"
    elif [ -f "go.mod" ]; then
        echo "go"
    elif [ -f "Cargo.toml" ]; then
        echo "rust"
    else
        echo "unknown"
    fi
}

if [ -f ".harness/harness.json" ]; then
    STACK=$(python3 -c "
import json
with open('.harness/harness.json') as f:
    data = json.load(f)
print(data.get('stack', ''))
" 2>/dev/null)
fi

if [ -z "$STACK" ] || [ "$STACK" = "null" ]; then
    STACK=$(detect_stack)
fi

echo "Stack: $STACK"
echo "Target: $TARGET"
echo ""

case "$STACK" in
    swift|ios|macos)
        if [ "$TARGET" = "smoke_test" ]; then
            echo "--- Swift Compile Check ---"
            if [ -f "Package.swift" ]; then
                swift build 2>&1 | tail -5
            elif ls *.xcodeproj 1>/dev/null 2>&1; then
                SCHEME=$(xcodebuild -list 2>/dev/null | grep -A 100 "Schemes:" | tail -n +2 | head -1 | xargs)
                if [ -n "$SCHEME" ]; then
                    xcodebuild build -scheme "$SCHEME" -destination 'platform=macOS' 2>&1 | tail -10
                else
                    echo "WARNING: No scheme detected. Run xcodebuild -list to check."
                fi
            fi
        else
            echo "--- Swift/Xcode Build ---"
            if [ -f "Package.swift" ]; then
                swift build 2>&1 | tail -5
                echo ""
                echo "--- Swift Tests ---"
                swift test 2>&1 | tail -20
            elif ls *.xcodeproj 1>/dev/null 2>&1; then
                SCHEME=$(xcodebuild -list 2>/dev/null | grep -A 100 "Schemes:" | tail -n +2 | head -1 | xargs)
                if [ -n "$SCHEME" ]; then
                    xcodebuild test -scheme "$SCHEME" -destination 'platform=macOS' 2>&1 | tail -20
                else
                    echo "WARNING: No scheme detected. Run xcodebuild -list to check."
                fi
            fi
        fi
        ;;
    node|nodejs|javascript|typescript)
        echo "--- Node.js Dependencies ---"
        if [ -f "package-lock.json" ]; then
            npm ci 2>&1 | tail -5
        elif [ -f "yarn.lock" ]; then
            yarn install --frozen-lockfile 2>&1 | tail -5
        elif [ -f "pnpm-lock.yaml" ]; then
            pnpm install --frozen-lockfile 2>&1 | tail -5
        else
            npm install 2>&1 | tail -5
        fi
        if [ -f "tsconfig.json" ]; then
            echo ""
            echo "--- TypeScript Check ---"
            npx tsc --noEmit 2>&1 | tail -10
        fi
        if [ "$TARGET" = "full_test" ]; then
            echo ""
            echo "--- Tests ---"
            npm test 2>&1 | tail -20
        fi
        ;;
    python)
        echo "--- Python Setup ---"
        if [ -f "pyproject.toml" ]; then
            pip install -e ".[dev]" --quiet 2>&1 | tail -5
        elif [ -f "requirements.txt" ]; then
            pip install -r requirements.txt --quiet 2>&1 | tail -5
        fi
        if [ "$TARGET" = "smoke_test" ]; then
            echo ""
            echo "--- Python Syntax Check ---"
            find . -name "*.py" -not -path "./.git/*" -not -path "./venv/*" -not -path "./.venv/*" | head -50 | while read f; do
                python3 -m py_compile "$f" 2>&1 && true
            done
            echo "Syntax check complete."
        else
            echo ""
            echo "--- Python Tests ---"
            if command -v pytest &>/dev/null; then
                pytest --tb=short --cov 2>&1 | tail -20
            elif [ -f "manage.py" ]; then
                python manage.py test 2>&1 | tail -20
            else
                python -m unittest discover 2>&1 | tail -20
            fi
        fi
        ;;
    go|golang)
        echo "--- Go Build ---"
        go build ./... 2>&1 | tail -5
        if [ "$TARGET" = "full_test" ]; then
            echo ""
            echo "--- Go Tests ---"
            go test -cover ./... 2>&1 | tail -20
        fi
        ;;
    rust)
        if [ "$TARGET" = "smoke_test" ]; then
            echo "--- Rust Check ---"
            cargo check 2>&1 | tail -10
        else
            echo "--- Rust Build ---"
            cargo build 2>&1 | tail -5
            echo ""
            echo "--- Rust Tests ---"
            cargo test 2>&1 | tail -20
        fi
        ;;
    *)
        echo "WARNING: Unknown stack '$STACK'"
        if [ -f "Makefile" ] && grep -q "test" Makefile; then
            echo "Found Makefile with test target"
            if [ "$TARGET" = "smoke_test" ]; then
                make build 2>&1 | tail -10 || echo "No build target found, skipping smoke check."
            else
                make test 2>&1 | tail -20
            fi
        elif [ -f "Justfile" ] && grep -q "test" Justfile; then
            echo "Found Justfile with test target"
            if [ "$TARGET" = "smoke_test" ]; then
                just build 2>&1 | tail -10 || echo "No build target found, skipping smoke check."
            else
                just test 2>&1 | tail -20
            fi
        else
            echo "No test runner detected. Skipping tests."
            echo "Configure stack in .harness/harness.json to enable."
        fi
        ;;
esac

echo ""
echo "=== ${TARGET} Complete ==="
