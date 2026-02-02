#!/bin/bash
# Harness Init Script v2.1
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo_status() { echo -e "${GREEN}[harness]${NC} $1"; }
echo_error() { echo -e "${RED}[harness]${NC} $1"; }

get_custom_command() {
    local key=$1
    if [ -f ".harness/harness.json" ]; then
        local cmd=$(grep -o "\"$key\": *\"[^\"]*\"" .harness/harness.json | cut -d'"' -f4)
        if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then
            echo "$cmd"
            return 0
        fi
    fi
    return 1
}

detect_stack() {
    if [ -f "Package.swift" ] || ls *.xcodeproj 1>/dev/null 2>&1; then echo "swift"
    elif [ -f "package.json" ]; then echo "nodejs"
    elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then echo "python"
    elif [ -f "go.mod" ]; then echo "go"
    elif [ -f "Cargo.toml" ]; then echo "rust"
    else echo "unknown"; fi
}

run_build() {
    local custom=$(get_custom_command "build_command")
    if [ -n "$custom" ]; then eval "$custom"; return; fi

    local stack=$(detect_stack)
    echo_status "Stack: $stack"

    case $stack in
        swift) swift build 2>/dev/null || xcodebuild build ;;
        nodejs) npm install && npm run build 2>/dev/null || true ;;
        python) pip install -e . --quiet 2>/dev/null || pip install -r requirements.txt --quiet 2>/dev/null || true ;;
        go) go build ./... ;;
        rust) cargo build ;;
    esac
}

run_tests() {
    local custom=$(get_custom_command "test_command")
    if [ -n "$custom" ]; then eval "$custom"; return; fi

    local stack=$(detect_stack)

    case $stack in
        swift) swift test 2>/dev/null || xcodebuild test ;;
        nodejs) npm test ;;
        python) pytest --cov --cov-report=term-missing || python -m pytest ;;
        go) go test -cover ./... ;;
        rust) cargo test ;;
    esac
}

echo_status "=== BUILD ==="
run_build

echo_status "=== TEST ==="
run_tests

echo_status "=== DONE ==="
