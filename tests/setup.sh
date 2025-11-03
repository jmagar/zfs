#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   BATS Testing Framework Setup Script                                   # #
# #   Installs BATS and required test helpers                               # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=================================================="
echo "  ZFS Scripts - Testing Framework Setup"
echo "=================================================="
echo ""

# Check if running in CI environment
if [[ -n "${CI:-}" ]]; then
    echo "Running in CI environment"
    IS_CI=true
else
    echo "Running in local environment"
    IS_CI=false
fi

#######################################
# Install BATS Core
#######################################
install_bats() {
    echo "Checking BATS installation..."

    if command -v bats >/dev/null 2>&1; then
        echo "  ✓ BATS already installed: $(bats --version)"
        return 0
    fi

    echo "  Installing BATS..."

    # Try package manager first
    if command -v apt-get >/dev/null 2>&1; then
        echo "  Using apt-get..."
        if $IS_CI; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq bats
        else
            sudo apt-get update
            sudo apt-get install -y bats
        fi

        if command -v bats >/dev/null 2>&1; then
            echo "  ✓ BATS installed via apt-get"
            return 0
        fi
    fi

    # Fallback to source installation
    echo "  Installing BATS from source..."
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    git clone --depth 1 https://github.com/bats-core/bats-core.git "$TEMP_DIR/bats-core"
    cd "$TEMP_DIR/bats-core"
    sudo ./install.sh /usr/local
    cd "$PROJECT_ROOT"

    if command -v bats >/dev/null 2>&1; then
        echo "  ✓ BATS installed from source"
        return 0
    else
        echo "  ✗ Failed to install BATS"
        return 1
    fi
}

#######################################
# Install BATS Support Libraries
#######################################
install_bats_helpers() {
    echo ""
    echo "Installing BATS helper libraries..."

    local test_helper="$SCRIPT_DIR/test_helper"

    # Install bats-support
    if [[ ! -d "$test_helper/bats-support" ]]; then
        echo "  Installing bats-support..."
        git clone --depth 1 https://github.com/bats-core/bats-support.git "$test_helper/bats-support"
        echo "  ✓ bats-support installed"
    else
        echo "  ✓ bats-support already installed"
    fi

    # Install bats-assert
    if [[ ! -d "$test_helper/bats-assert" ]]; then
        echo "  Installing bats-assert..."
        git clone --depth 1 https://github.com/bats-core/bats-assert.git "$test_helper/bats-assert"
        echo "  ✓ bats-assert installed"
    else
        echo "  ✓ bats-assert already installed"
    fi

    # Install bats-file
    if [[ ! -d "$test_helper/bats-file" ]]; then
        echo "  Installing bats-file..."
        git clone --depth 1 https://github.com/bats-core/bats-file.git "$test_helper/bats-file"
        echo "  ✓ bats-file installed"
    else
        echo "  ✓ bats-file already installed"
    fi
}

#######################################
# Check Dependencies
#######################################
check_dependencies() {
    echo ""
    echo "Checking dependencies..."

    local missing=()

    # Required for tests
    for cmd in git bash awk sed grep; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "  ✗ Missing required commands: ${missing[*]}"
        return 1
    fi

    echo "  ✓ All required dependencies present"

    # Optional but recommended
    echo ""
    echo "Checking optional dependencies..."

    local optional=(shellcheck jq curl docker virsh zfs zpool)
    local missing_optional=()

    for cmd in "${optional[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "  ✓ $cmd: available"
        else
            echo "  ⚠ $cmd: not available (some tests may be skipped)"
            missing_optional+=("$cmd")
        fi
    done

    return 0
}

#######################################
# Create Test Directories
#######################################
setup_test_directories() {
    echo ""
    echo "Setting up test directories..."

    mkdir -p "$SCRIPT_DIR/integration"
    mkdir -p "$SCRIPT_DIR/fixtures"
    mkdir -p "$SCRIPT_DIR/mocks"
    mkdir -p "$PROJECT_ROOT/.test-results"

    echo "  ✓ Test directories created"
}

#######################################
# Create Example Test
#######################################
create_example_test() {
    echo ""
    echo "Creating example test..."

    if [[ ! -f "$SCRIPT_DIR/test-example.bats" ]]; then
        cat > "$SCRIPT_DIR/test-example.bats" <<'EOF'
#!/usr/bin/env bats

# Example test file demonstrating BATS syntax

load 'test_helper/common'

@test "example: addition works" {
    result=$((2 + 2))
    [ "$result" -eq 4 ]
}

@test "example: bats-assert works" {
    run echo "hello world"
    assert_success
    assert_output "hello world"
}

@test "example: bats-support works" {
    run false
    assert_failure
}
EOF
        echo "  ✓ Example test created: tests/test-example.bats"
    else
        echo "  ✓ Example test already exists"
    fi
}

#######################################
# Verify Installation
#######################################
verify_installation() {
    echo ""
    echo "Verifying installation..."

    # Test BATS
    if ! command -v bats >/dev/null 2>&1; then
        echo "  ✗ BATS not found in PATH"
        return 1
    fi

    echo "  ✓ BATS: $(bats --version)"

    # Test helpers
    if [[ ! -f "$SCRIPT_DIR/test_helper/bats-support/load.bash" ]]; then
        echo "  ✗ bats-support not properly installed"
        return 1
    fi
    echo "  ✓ bats-support: installed"

    if [[ ! -f "$SCRIPT_DIR/test_helper/bats-assert/load.bash" ]]; then
        echo "  ✗ bats-assert not properly installed"
        return 1
    fi
    echo "  ✓ bats-assert: installed"

    if [[ ! -f "$SCRIPT_DIR/test_helper/bats-file/load.bash" ]]; then
        echo "  ✗ bats-file not properly installed"
        return 1
    fi
    echo "  ✓ bats-file: installed"

    # Test common helpers
    if [[ ! -f "$SCRIPT_DIR/test_helper/common.bash" ]]; then
        echo "  ✗ common.bash not found"
        return 1
    fi
    echo "  ✓ common.bash: installed"

    return 0
}

#######################################
# Run Example Tests
#######################################
run_example_tests() {
    echo ""
    echo "Running example tests..."

    if [[ -f "$SCRIPT_DIR/test-example.bats" ]]; then
        if bats "$SCRIPT_DIR/test-example.bats"; then
            echo "  ✓ Example tests passed"
            return 0
        else
            echo "  ✗ Example tests failed"
            return 1
        fi
    else
        echo "  ⚠ No example tests to run"
        return 0
    fi
}

#######################################
# Main Installation
#######################################
main() {
    install_bats || exit 1
    install_bats_helpers || exit 1
    check_dependencies || exit 1
    setup_test_directories || exit 1
    create_example_test || exit 1
    verify_installation || exit 1

    echo ""
    echo "=================================================="
    echo "  Testing Framework Setup Complete!"
    echo "=================================================="
    echo ""
    echo "Run tests with:"
    echo "  bats tests/                    # Run all tests"
    echo "  bats tests/test-example.bats   # Run specific test file"
    echo "  bats tests/integration/        # Run integration tests"
    echo ""
    echo "For more information, see:"
    echo "  https://github.com/bats-core/bats-core"
    echo ""

    # Optionally run example tests
    if [[ "${RUN_TESTS:-}" == "yes" ]]; then
        run_example_tests
    fi
}

main "$@"
