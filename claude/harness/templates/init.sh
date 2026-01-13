#!/bin/bash
# init.sh - Multi-language project initialization
# Supports: iOS/Swift, Node.js, Python, Go, Rust
# 
# Configuration:
#   - .harness.json: Full config (preferred)
#   - .harness-local.sh: Project-specific overrides
#   - Auto-detection: Fallback when no config
#
# Exit codes:
#   0 = Success
#   1 = Dependency installation failed
#   2 = Build failed
#   3 = Tests failed

set -e

CONFIG_FILE=".harness.json"
LOCAL_OVERRIDES=".harness-local.sh"

echo "=== Session Initialization ==="

#######################################
# Language-specific functions
#######################################

init_ios() {
    local scheme="${1:-}"
    local simulator="${2:-iPhone 15}"
    
    echo "[iOS] Installing dependencies..."
    [ -f "Podfile" ] && pod install
    [ -f "Package.swift" ] && swift package resolve
    
    # Auto-detect scheme if not provided
    if [ -z "$scheme" ]; then
        scheme=$(xcodebuild -list -json 2>/dev/null | jq -r '.project.schemes[0] // .workspace.schemes[0]' || echo "")
    fi
    
    if [ -z "$scheme" ]; then
        echo "[iOS] Warning: Could not detect scheme. Skipping build/test."
        return 0
    fi
    
    echo "[iOS] Building scheme: $scheme..."
    xcodebuild -scheme "$scheme" -destination "platform=iOS Simulator,name=$simulator" build 2>&1 | xcpretty || exit 2
    
    echo "[iOS] Running tests..."
    xcodebuild -scheme "$scheme" -destination "platform=iOS Simulator,name=$simulator" test 2>&1 | xcpretty || exit 3
}

init_node() {
    local path="${1:-.}"
    
    pushd "$path" > /dev/null
    
    echo "[Node] Installing dependencies..."
    if [ -f "package-lock.json" ]; then
        npm ci
    else
        npm install
    fi
    
    echo "[Node] Building..."
    npm run build --if-present
    
    echo "[Node] Running tests..."
    npm test --if-present || true
    
    popd > /dev/null
}

init_python() {
    local path="${1:-.}"
    
    pushd "$path" > /dev/null
    
    echo "[Python] Setting up environment..."
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt --quiet
    elif [ -f "pyproject.toml" ]; then
        pip install -e . --quiet
    elif [ -f "setup.py" ]; then
        pip install -e . --quiet
    fi
    
    echo "[Python] Running tests..."
    if [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
        pytest --tb=short || exit 3
    else
        python -m unittest discover || exit 3
    fi
    
    popd > /dev/null
}

init_go() {
    local path="${1:-.}"
    
    pushd "$path" > /dev/null
    
    echo "[Go] Downloading dependencies..."
    go mod download
    
    echo "[Go] Building..."
    go build ./... || exit 2
    
    echo "[Go] Running tests..."
    go test ./... || exit 3
    
    popd > /dev/null
}

init_rust() {
    local path="${1:-.}"
    
    pushd "$path" > /dev/null
    
    echo "[Rust] Building..."
    cargo build || exit 2
    
    echo "[Rust] Running tests..."
    cargo test || exit 3
    
    popd > /dev/null
}

#######################################
# Config-based initialization
#######################################

run_from_config() {
    echo "Using config: $CONFIG_FILE"
    
    # Process each stack
    local stack_count=$(jq '.stacks | length' "$CONFIG_FILE")
    
    for ((i=0; i<stack_count; i++)); do
        local name=$(jq -r ".stacks[$i].name" "$CONFIG_FILE")
        local path=$(jq -r ".stacks[$i].path // \".\"" "$CONFIG_FILE")
        
        echo ""
        echo "--- Stack: $name (path: $path) ---"
        
        case "$name" in
            ios|swift)
                local scheme=$(jq -r ".stacks[$i].scheme // empty" "$CONFIG_FILE")
                local simulator=$(jq -r ".stacks[$i].simulator // \"iPhone 15\"" "$CONFIG_FILE")
                pushd "$path" > /dev/null
                init_ios "$scheme" "$simulator"
                popd > /dev/null
                ;;
            node|nodejs|javascript|typescript)
                init_node "$path"
                ;;
            python)
                init_python "$path"
                ;;
            go|golang)
                init_go "$path"
                ;;
            rust)
                init_rust "$path"
                ;;
            *)
                echo "Unknown stack: $name (skipping)"
                ;;
        esac
    done
    
    # Run custom smoke test if defined
    local smoke_test=$(jq -r '.smoke_test // empty' "$CONFIG_FILE")
    if [ -n "$smoke_test" ] && [ -f "$smoke_test" ]; then
        echo ""
        echo "--- Running custom smoke test ---"
        bash "$smoke_test" || exit 3
    fi
}

#######################################
# Auto-detection initialization
#######################################

run_auto_detect() {
    echo "No config found. Auto-detecting project type..."
    
    local detected=false
    
    # iOS/Swift
    if ls *.xcodeproj 1> /dev/null 2>&1 || ls *.xcworkspace 1> /dev/null 2>&1 || [ -f "Package.swift" ]; then
        echo ""
        echo "--- Detected: iOS/Swift ---"
        init_ios
        detected=true
    fi
    
    # Node.js
    if [ -f "package.json" ]; then
        echo ""
        echo "--- Detected: Node.js ---"
        init_node
        detected=true
    fi
    
    # Python
    if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
        echo ""
        echo "--- Detected: Python ---"
        init_python
        detected=true
    fi
    
    # Go
    if [ -f "go.mod" ]; then
        echo ""
        echo "--- Detected: Go ---"
        init_go
        detected=true
    fi
    
    # Rust
    if [ -f "Cargo.toml" ]; then
        echo ""
        echo "--- Detected: Rust ---"
        init_rust
        detected=true
    fi
    
    if [ "$detected" = false ]; then
        echo "Warning: No recognized project type detected."
        echo "Consider creating a .harness.json config file."
    fi
}

#######################################
# Main
#######################################

# Source local overrides if present
if [ -f "$LOCAL_OVERRIDES" ]; then
    echo "Loading local overrides: $LOCAL_OVERRIDES"
    source "$LOCAL_OVERRIDES"
fi

# Run initialization
if [ -f "$CONFIG_FILE" ]; then
    run_from_config
else
    run_auto_detect
fi

echo ""
echo "=== Initialization Complete ==="
