#!/usr/bin/env bats
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Test Suite for ZFS Common Library (lib/zfs-common.sh)                # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Setup for each test file
setup_file() {
    export TEST_TEMP_DIR="$(mktemp -d)"
    export LOG_FILE="$TEST_TEMP_DIR/test.log"
    export LOG_MAX_SIZE="1K"
    export LOG_MAX_FILES=3
    export DRY_RUN="no"
}

# Teardown for each test file
teardown_file() {
    rm -rf "$TEST_TEMP_DIR"
}

# Setup for each test
setup() {
    # Source the common library
    export SCRIPT_DIR="${BATS_TEST_DIRNAME%/*}"
    source "$SCRIPT_DIR/lib/zfs-common.sh"

    # Reset log file and any rotated copies for each test
    rm -f "$LOG_FILE" "${LOG_FILE}".* 2>/dev/null
    touch "$LOG_FILE"
}

# Teardown for each test
teardown() {
    # Clean up any test files
    rm -f "$TEST_TEMP_DIR"/*.test 2>/dev/null || true
}

#######################################
# Tests for log_message function
#######################################

@test "log_message writes to log file with timestamp" {
    log_message "INFO" "Test message"

    [ -f "$LOG_FILE" ]
    grep -q "Test message" "$LOG_FILE"
    grep -q "\[INFO\]" "$LOG_FILE"
    grep -q "^\\[.*\\]" "$LOG_FILE"  # Check for timestamp
}

@test "log_message handles different log levels" {
    log_message "INFO" "Info message"
    log_message "WARNING" "Warning message"
    log_message "ERROR" "Error message"
    log_message "SUCCESS" "Success message"

    grep -q "\[INFO\].*Info message" "$LOG_FILE"
    grep -q "\[WARNING\].*Warning message" "$LOG_FILE"
    grep -q "\[ERROR\].*Error message" "$LOG_FILE"
    grep -q "\[SUCCESS\].*Success message" "$LOG_FILE"
}

@test "log_message creates log directory if missing" {
    export LOG_FILE="$TEST_TEMP_DIR/subdir/new.log"

    log_message "INFO" "Test"

    [ -f "$LOG_FILE" ]
    [ -d "$TEST_TEMP_DIR/subdir" ]
}

@test "log_message works without LOG_FILE set" {
    unset LOG_FILE

    run log_message "INFO" "Test without file"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Test without file" ]]
}

#######################################
# Tests for rotate_log function
#######################################

@test "rotate_log does nothing if log file doesn't exist" {
    rm -f "$LOG_FILE"

    run rotate_log

    [ "$status" -eq 0 ]
}

@test "rotate_log rotates when file exceeds size limit" {
    # Create a log file larger than LOG_MAX_SIZE (1K)
    # Avoid yes|head which triggers SIGPIPE under pipefail in CI
    local i
    for i in $(seq 1 100); do
        echo "This is a test log line that will be repeated many times"
    done > "$LOG_FILE"

    rotate_log

    # Original file should be moved to .1
    [ -f "${LOG_FILE}.1" ]
    # New log file should exist and be smaller
    [ -f "$LOG_FILE" ]
    [ $(stat -c%s "$LOG_FILE") -lt $(stat -c%s "${LOG_FILE}.1") ]
}

@test "rotate_log maintains multiple rotated files" {
    # Create multiple rotated logs
    echo "log 1" > "${LOG_FILE}.1"
    echo "log 2" > "${LOG_FILE}.2"

    # Create large current log (avoid yes|head — SIGPIPE under pipefail)
    local i
    for i in $(seq 1 300); do echo "test line for rotation testing"; done > "$LOG_FILE"

    rotate_log

    # Logs should be shifted
    [ -f "${LOG_FILE}.1" ]
    [ -f "${LOG_FILE}.2" ]
    [ -f "${LOG_FILE}.3" ]
}

@test "rotate_log handles different size suffixes" {
    # Test with M suffix
    export LOG_MAX_SIZE="1M"
    echo "small log" > "$LOG_FILE"

    run rotate_log

    [ "$status" -eq 0 ]
    # Should not rotate a small file
    [ ! -f "${LOG_FILE}.1" ]
}

#######################################
# Tests for send_notification function
#######################################

@test "send_notification logs message" {
    run send_notification "Test notification" "info"

    [ "$status" -eq 0 ]
    grep -q "Test notification" "$LOG_FILE"
}

@test "send_notification respects notification_type none" {
    export notification_type="none"
    export GOTIFY_SERVER_URL="http://localhost:8080"
    export GOTIFY_APP_TOKEN="test_token"

    run send_notification "Should not send" "success"

    [ "$status" -eq 0 ]
    # Message should still be logged
    grep -q "Should not send" "$LOG_FILE"
}

@test "send_notification respects notification_type error" {
    export notification_type="error"

    run send_notification "Success message" "success"

    [ "$status" -eq 0 ]
    # Should skip sending but still log
    grep -q "Success message" "$LOG_FILE"
}

@test "send_notification handles missing Gotify config gracefully" {
    unset GOTIFY_SERVER_URL
    unset GOTIFY_APP_TOKEN

    run send_notification "Test" "info"

    [ "$status" -eq 0 ]
}

@test "send_notification sets correct log level" {
    send_notification "Success msg" "success"
    send_notification "Error msg" "error"
    send_notification "Info msg" "info"

    grep -q "\[SUCCESS\].*Success msg" "$LOG_FILE"
    grep -q "\[ERROR\].*Error msg" "$LOG_FILE"
    grep -q "\[INFO\].*Info msg" "$LOG_FILE"
}

#######################################
# Tests for is_zfs_dataset function
#######################################

@test "is_zfs_dataset returns 1 for empty input" {
    run is_zfs_dataset ""

    [ "$status" -eq 1 ]
}

@test "is_zfs_dataset returns 1 for non-existent path" {
    run is_zfs_dataset "/nonexistent/path"

    [ "$status" -eq 1 ]
}

# Note: Testing actual ZFS datasets requires ZFS to be installed and configured
# These tests would be run in integration tests with actual ZFS pools

#######################################
# Tests for get_dataset_for_path function
#######################################

@test "get_dataset_for_path returns 1 for empty input" {
    run get_dataset_for_path ""

    [ "$status" -eq 1 ]
}

@test "get_dataset_for_path returns 1 for non-ZFS path" {
    run get_dataset_for_path "/tmp"

    [ "$status" -eq 1 ]
}

#######################################
# Tests for normalize_name function
#######################################

@test "normalize_name converts German umlauts" {
    result=$(normalize_name "Müller")
    [ "$result" = "Mueller" ]

    result=$(normalize_name "Größe")
    [ "$result" = "Groesse" ]

    result=$(normalize_name "Bäcker")
    [ "$result" = "Baecker" ]
}

@test "normalize_name converts ß to ss" {
    result=$(normalize_name "Straße")
    [ "$result" = "Strasse" ]
}

@test "normalize_name handles uppercase umlauts" {
    result=$(normalize_name "MÜLLER")
    [ "$result" = "MUELLER" ]
}

@test "normalize_name leaves regular ASCII unchanged" {
    result=$(normalize_name "regular_name")
    [ "$result" = "regular_name" ]
}

#######################################
# Tests for format_bytes function
#######################################

@test "format_bytes handles bytes" {
    result=$(format_bytes "512")
    [ "$result" = "512B" ]
}

@test "format_bytes converts to kilobytes" {
    result=$(format_bytes "2048")
    [ "$result" = "2K" ]
}

@test "format_bytes converts to megabytes" {
    result=$(format_bytes "2097152")
    [ "$result" = "2M" ]
}

@test "format_bytes converts to gigabytes" {
    result=$(format_bytes "2147483648")
    [ "$result" = "2G" ]
}

@test "format_bytes handles invalid input" {
    result=$(format_bytes "invalid")
    [ "$result" = "0B" ]
}

@test "format_bytes handles zero" {
    result=$(format_bytes "0")
    [ "$result" = "0B" ]
}

#######################################
# Tests for parse_size_to_bytes function
#######################################

@test "parse_size_to_bytes handles bytes" {
    result=$(parse_size_to_bytes "100B")
    [ "$result" = "100" ]

    result=$(parse_size_to_bytes "100b")
    [ "$result" = "100" ]
}

@test "parse_size_to_bytes handles kilobytes" {
    result=$(parse_size_to_bytes "1K")
    [ "$result" = "1024" ]

    result=$(parse_size_to_bytes "2k")
    [ "$result" = "2048" ]
}

@test "parse_size_to_bytes handles megabytes" {
    result=$(parse_size_to_bytes "1M")
    [ "$result" = "1048576" ]

    result=$(parse_size_to_bytes "2m")
    [ "$result" = "2097152" ]
}

@test "parse_size_to_bytes handles gigabytes" {
    result=$(parse_size_to_bytes "1G")
    [ "$result" = "1073741824" ]
}

@test "parse_size_to_bytes handles terabytes" {
    result=$(parse_size_to_bytes "1T")
    [ "$result" = "1099511627776" ]
}

@test "parse_size_to_bytes handles plain numbers" {
    result=$(parse_size_to_bytes "12345")
    [ "$result" = "12345" ]
}

#######################################
# Tests for require_root function
#######################################

@test "require_root returns 1 for non-root user" {
    # Most tests run as non-root
    if [ $EUID -ne 0 ]; then
        run require_root
        [ "$status" -eq 1 ]
    else
        skip "Running as root, cannot test non-root case"
    fi
}

@test "require_root returns 0 for root user" {
    # This test only runs if we're root
    if [ $EUID -eq 0 ]; then
        run require_root
        [ "$status" -eq 0 ]
    else
        skip "Not running as root, cannot test root case"
    fi
}

#######################################
# Tests for ensure_directory function
#######################################

@test "ensure_directory creates directory" {
    local test_dir="$TEST_TEMP_DIR/new_directory"

    ensure_directory "$test_dir"

    [ -d "$test_dir" ]
}

@test "ensure_directory creates nested directories" {
    local test_dir="$TEST_TEMP_DIR/path/to/nested/dir"

    ensure_directory "$test_dir"

    [ -d "$test_dir" ]
}

@test "ensure_directory succeeds if directory exists" {
    local test_dir="$TEST_TEMP_DIR/existing"
    mkdir -p "$test_dir"

    run ensure_directory "$test_dir"

    [ "$status" -eq 0 ]
}

@test "ensure_directory sets permissions" {
    local test_dir="$TEST_TEMP_DIR/perms_test"

    ensure_directory "$test_dir" "700"

    [ -d "$test_dir" ]
    # Check permissions (may not work perfectly on all systems)
    perms=$(stat -c %a "$test_dir" 2>/dev/null || stat -f %Lp "$test_dir" 2>/dev/null)
    [ "$perms" = "700" ]
}

#######################################
# Tests for get_dataset_available_space function
#######################################

@test "get_dataset_available_space returns 1 for empty input" {
    run get_dataset_available_space ""

    [ "$status" -eq 1 ]
}

@test "get_dataset_available_space returns 1 for non-existent dataset" {
    run get_dataset_available_space "nonexistent/dataset"

    [ "$status" -eq 1 ]
}

# Note: Actual ZFS dataset tests would be in integration tests

#######################################
# Tests for get_dataset_used_space function
#######################################

@test "get_dataset_used_space returns 1 for empty input" {
    run get_dataset_used_space ""

    [ "$status" -eq 1 ]
}

@test "get_dataset_used_space returns 1 for non-existent dataset" {
    run get_dataset_used_space "nonexistent/dataset"

    [ "$status" -eq 1 ]
}

#######################################
# Integration tests
#######################################

@test "all functions are exported" {
    # Check that functions are available for export
    declare -F log_message >/dev/null
    declare -F rotate_log >/dev/null
    declare -F send_notification >/dev/null
    declare -F is_zfs_dataset >/dev/null
    declare -F get_dataset_for_path >/dev/null
    declare -F normalize_name >/dev/null
    declare -F format_bytes >/dev/null
    declare -F parse_size_to_bytes >/dev/null
    declare -F require_root >/dev/null
    declare -F ensure_directory >/dev/null
    declare -F get_dataset_available_space >/dev/null
    declare -F get_dataset_used_space >/dev/null
}

@test "library can be sourced multiple times" {
    source "$SCRIPT_DIR/lib/zfs-common.sh"
    source "$SCRIPT_DIR/lib/zfs-common.sh"

    # Should not cause errors
    run log_message "INFO" "Test"
    [ "$status" -eq 0 ]
}
