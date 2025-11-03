#!/usr/bin/env bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Common Test Helper Functions                                          # #
# #   Shared utilities for BATS tests                                       # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Get the directory containing this helper file
TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$TEST_HELPER_DIR")"
PROJECT_ROOT="$(dirname "$TESTS_DIR")"

# Load BATS helper libraries
load "$TEST_HELPER_DIR/bats-support/load"
load "$TEST_HELPER_DIR/bats-assert/load"
load "$TEST_HELPER_DIR/bats-file/load"

#######################################
# Setup function run once per test file
# Globals:
#   TEST_TEMP_DIR
#   LOG_FILE
#   BATS_FILE_TMPDIR
# Arguments:
#   None
#######################################
setup_file() {
    # Create temporary directory for this test file
    export TEST_TEMP_DIR="${BATS_FILE_TMPDIR:-/tmp/bats-$$}"
    mkdir -p "$TEST_TEMP_DIR"

    # Set up test log file
    export LOG_FILE="$TEST_TEMP_DIR/test.log"
    export ZFS_ERROR_LOG="$TEST_TEMP_DIR/error.log"

    # Default test configuration
    export DRY_RUN="no"
    export MOUNT_POINT="/mnt"
    export SOURCE_POOL="test-pool"
    export SOURCE_DATASET="data"

    # Notification settings for tests
    export notification_type="none"
    export GOTIFY_SERVER_URL=""
    export GOTIFY_APP_TOKEN=""
}

#######################################
# Teardown function run once per test file
# Globals:
#   TEST_TEMP_DIR
# Arguments:
#   None
#######################################
teardown_file() {
    # Clean up temporary directory
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

#######################################
# Setup function run before each test
# Globals:
#   SCRIPT_DIR
# Arguments:
#   None
#######################################
setup() {
    # Set script directory for sourcing libraries
    export SCRIPT_DIR="$PROJECT_ROOT"

    # Reset error counters if using error handling library
    if declare -F reset_error_count >/dev/null 2>&1; then
        reset_error_count
    fi

    # Create fresh log file for each test
    > "$LOG_FILE" 2>/dev/null || true
    > "$ZFS_ERROR_LOG" 2>/dev/null || true
}

#######################################
# Teardown function run after each test
# Arguments:
#   None
#######################################
teardown() {
    # Clean up any test-specific temporary files
    # Individual tests can define their own cleanup
    :
}

#######################################
# Create a temporary test directory
# Arguments:
#   $1 - Directory name (relative to TEST_TEMP_DIR)
# Returns:
#   Prints absolute path to created directory
#######################################
create_test_dir() {
    local dir_name="${1:-test-dir}"
    local dir="$TEST_TEMP_DIR/$dir_name"
    mkdir -p "$dir"
    echo "$dir"
}

#######################################
# Create a temporary test file
# Arguments:
#   $1 - File name (relative to TEST_TEMP_DIR)
#   $2 - Content (optional)
# Returns:
#   Prints absolute path to created file
#######################################
create_test_file() {
    local file_name="${1:-test-file}"
    local content="${2:-}"
    local file="$TEST_TEMP_DIR/$file_name"

    # Create parent directory if needed
    mkdir -p "$(dirname "$file")"

    if [[ -n "$content" ]]; then
        echo "$content" > "$file"
    else
        touch "$file"
    fi

    echo "$file"
}

#######################################
# Generate test data with random content
# Arguments:
#   $1 - Directory path
#   $2 - Number of files (default: 5)
#   $3 - File size in KB (default: 1)
# Returns:
#   0 on success
#######################################
generate_test_data() {
    local dir="$1"
    local num_files="${2:-5}"
    local size_kb="${3:-1}"

    mkdir -p "$dir"

    for i in $(seq 1 "$num_files"); do
        dd if=/dev/urandom of="$dir/file-$i.bin" bs=1024 count="$size_kb" 2>/dev/null
    done

    return 0
}

#######################################
# Mock a command for testing
# Arguments:
#   $1 - Command name
#   $2 - Mock script content
# Returns:
#   0 on success
#######################################
mock_command() {
    local cmd_name="$1"
    local mock_content="$2"
    local mock_dir="$TEST_TEMP_DIR/mocks"
    local mock_file="$mock_dir/$cmd_name"

    mkdir -p "$mock_dir"

    cat > "$mock_file" <<EOF
#!/bin/bash
$mock_content
EOF

    chmod +x "$mock_file"

    # Add mock directory to PATH
    export PATH="$mock_dir:$PATH"

    return 0
}

#######################################
# Unmock a command
# Arguments:
#   $1 - Command name
# Returns:
#   0 on success
#######################################
unmock_command() {
    local cmd_name="$1"
    local mock_dir="$TEST_TEMP_DIR/mocks"
    local mock_file="$mock_dir/$cmd_name"

    if [[ -f "$mock_file" ]]; then
        rm -f "$mock_file"
    fi

    return 0
}

#######################################
# Check if running in CI environment
# Returns:
#   0 if CI, 1 if not
#######################################
is_ci() {
    [[ -n "${CI:-}" ]]
}

#######################################
# Skip test if command not available
# Arguments:
#   $1 - Command name
#   $2 - Optional reason message
#######################################
skip_if_missing() {
    local cmd="$1"
    local reason="${2:-$cmd not available}"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        skip "$reason"
    fi
}

#######################################
# Skip test if not running as root
# Arguments:
#   $1 - Optional reason message
#######################################
skip_if_not_root() {
    local reason="${1:-This test requires root privileges}"

    if [[ $EUID -ne 0 ]]; then
        skip "$reason"
    fi
}

#######################################
# Skip test if in CI environment
# Arguments:
#   $1 - Optional reason message
#######################################
skip_if_ci() {
    local reason="${1:-Test not suitable for CI environment}"

    if is_ci; then
        skip "$reason"
    fi
}

#######################################
# Check if ZFS is available
# Returns:
#   0 if available, 1 if not
#######################################
has_zfs() {
    command -v zfs >/dev/null 2>&1 && command -v zpool >/dev/null 2>&1
}

#######################################
# Check if Docker is available
# Returns:
#   0 if available, 1 if not
#######################################
has_docker() {
    command -v docker >/dev/null 2>&1
}

#######################################
# Check if libvirt is available
# Returns:
#   0 if available, 1 if not
#######################################
has_libvirt() {
    command -v virsh >/dev/null 2>&1
}

#######################################
# Assert that a log file contains a pattern
# Arguments:
#   $1 - Pattern to search for
#   $2 - Log file path (default: $LOG_FILE)
#######################################
assert_log_contains() {
    local pattern="$1"
    local log="${2:-$LOG_FILE}"

    if [[ ! -f "$log" ]]; then
        echo "Log file does not exist: $log" >&2
        return 1
    fi

    if ! grep -q "$pattern" "$log"; then
        echo "Pattern not found in log: $pattern" >&2
        echo "Log contents:" >&2
        cat "$log" >&2
        return 1
    fi

    return 0
}

#######################################
# Assert that a log file does not contain a pattern
# Arguments:
#   $1 - Pattern to search for
#   $2 - Log file path (default: $LOG_FILE)
#######################################
assert_log_not_contains() {
    local pattern="$1"
    local log="${2:-$LOG_FILE}"

    if [[ ! -f "$log" ]]; then
        # If log doesn't exist, pattern can't be in it
        return 0
    fi

    if grep -q "$pattern" "$log"; then
        echo "Pattern found in log (should not be): $pattern" >&2
        echo "Log contents:" >&2
        cat "$log" >&2
        return 1
    fi

    return 0
}

#######################################
# Count occurrences of pattern in log
# Arguments:
#   $1 - Pattern to search for
#   $2 - Log file path (default: $LOG_FILE)
# Returns:
#   Number of occurrences
#######################################
count_log_pattern() {
    local pattern="$1"
    local log="${2:-$LOG_FILE}"

    if [[ ! -f "$log" ]]; then
        echo "0"
        return
    fi

    grep -c "$pattern" "$log" || echo "0"
}

#######################################
# Source a library file safely
# Arguments:
#   $1 - Library file path (relative to project root or absolute)
# Returns:
#   0 on success, 1 on failure
#######################################
safe_source() {
    local lib_path="$1"

    # Try as absolute path first
    if [[ -f "$lib_path" ]]; then
        source "$lib_path"
        return 0
    fi

    # Try relative to project root
    if [[ -f "$PROJECT_ROOT/$lib_path" ]]; then
        source "$PROJECT_ROOT/$lib_path"
        return 0
    fi

    echo "Cannot find library: $lib_path" >&2
    return 1
}

#######################################
# Create a mock ZFS pool for testing
# Arguments:
#   $1 - Pool name (default: test-pool)
#   $2 - Size in MB (default: 100)
# Returns:
#   0 on success, 1 on failure
#######################################
create_mock_zfs_pool() {
    skip_if_not_root "Creating ZFS pool requires root"
    skip_if_missing zpool "ZFS not installed"

    local pool_name="${1:-test-pool}"
    local size_mb="${2:-100}"
    local pool_file="$TEST_TEMP_DIR/${pool_name}.img"

    # Create sparse file
    truncate -s "${size_mb}M" "$pool_file"

    # Create ZFS pool
    if zpool create "$pool_name" "$pool_file" 2>/dev/null; then
        echo "Mock ZFS pool created: $pool_name"
        return 0
    else
        echo "Failed to create mock ZFS pool" >&2
        return 1
    fi
}

#######################################
# Destroy a mock ZFS pool
# Arguments:
#   $1 - Pool name (default: test-pool)
# Returns:
#   0 on success
#######################################
destroy_mock_zfs_pool() {
    skip_if_not_root "Destroying ZFS pool requires root"
    skip_if_missing zpool "ZFS not installed"

    local pool_name="${1:-test-pool}"
    local pool_file="$TEST_TEMP_DIR/${pool_name}.img"

    # Destroy pool if it exists
    if zpool list "$pool_name" >/dev/null 2>&1; then
        zpool destroy "$pool_name" 2>/dev/null || true
    fi

    # Remove pool file
    rm -f "$pool_file"

    return 0
}

#######################################
# Pretty print test section header
# Arguments:
#   $1 - Section title
#######################################
test_section() {
    local title="$1"
    echo ""
    echo "=== $title ==="
    echo ""
}

#######################################
# Debug helper - print variable value
# Arguments:
#   $1 - Variable name
#######################################
debug_var() {
    local var_name="$1"
    local var_value="${!var_name}"
    echo "[DEBUG] $var_name = '$var_value'" >&2
}

#######################################
# Assert directory exists and is not empty
# Arguments:
#   $1 - Directory path
#######################################
assert_directory_not_empty() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        echo "Directory does not exist: $dir" >&2
        return 1
    fi

    if [[ -z "$(ls -A "$dir")" ]]; then
        echo "Directory is empty: $dir" >&2
        return 1
    fi

    return 0
}

#######################################
# Assert file contains exactly N lines
# Arguments:
#   $1 - File path
#   $2 - Expected line count
#######################################
assert_line_count() {
    local file="$1"
    local expected="$2"

    if [[ ! -f "$file" ]]; then
        echo "File does not exist: $file" >&2
        return 1
    fi

    local actual
    actual=$(wc -l < "$file")

    if [[ "$actual" -ne "$expected" ]]; then
        echo "Line count mismatch: expected $expected, got $actual" >&2
        return 1
    fi

    return 0
}

# Export helper functions
export -f create_test_dir
export -f create_test_file
export -f generate_test_data
export -f mock_command
export -f unmock_command
export -f is_ci
export -f skip_if_missing
export -f skip_if_not_root
export -f skip_if_ci
export -f has_zfs
export -f has_docker
export -f has_libvirt
export -f assert_log_contains
export -f assert_log_not_contains
export -f count_log_pattern
export -f safe_source
export -f create_mock_zfs_pool
export -f destroy_mock_zfs_pool
export -f test_section
export -f debug_var
export -f assert_directory_not_empty
export -f assert_line_count
