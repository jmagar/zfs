#!/usr/bin/env bats
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Common Functions Test Suite                                          # #
# #   Tests for lib/zfs-common.sh                                          # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

load 'test_helper/common'

#######################################
# Setup
#######################################

setup_file() {
    export TEST_TEMP_DIR="${BATS_FILE_TMPDIR}"
    export LOG_FILE="$TEST_TEMP_DIR/test.log"
    export DRY_RUN="no"
}

setup() {
    # Try to source common library if it exists
    if [[ -f "$PROJECT_ROOT/lib/zfs-common.sh" ]]; then
        # Mock dependencies that might not exist yet
        export SCRIPT_DIR="$PROJECT_ROOT"

        # Source the library
        source "$PROJECT_ROOT/lib/zfs-common.sh" 2>/dev/null || skip "lib/zfs-common.sh not yet implemented"
    else
        skip "lib/zfs-common.sh not yet created"
    fi
}

#######################################
# Log Message Tests
#######################################

@test "log_message writes to log file" {
    log_message "INFO" "Test message"

    assert_file_exist "$LOG_FILE"
    assert_log_contains "Test message"
}

@test "log_message includes level" {
    log_message "ERROR" "Test error"

    assert_log_contains "ERROR"
    assert_log_contains "Test error"
}

@test "log_message includes timestamp" {
    log_message "INFO" "Timestamp test"

    # Check for date format YYYY-MM-DD
    assert_log_contains "[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}"
}

#######################################
# Path Validation Tests
#######################################

@test "normalize_name handles German umlauts" {
    result=$(normalize_name "Müller")
    [ "$result" = "Mueller" ]
}

@test "normalize_name handles ä" {
    result=$(normalize_name "Bär")
    [ "$result" = "Baer" ]
}

@test "normalize_name handles ö" {
    result=$(normalize_name "Köln")
    [ "$result" = "Koeln" ]
}

@test "normalize_name handles ß" {
    result=$(normalize_name "Straße")
    [ "$result" = "Strasse" ]
}

#######################################
# Size Formatting Tests
#######################################

@test "format_bytes formats bytes correctly" {
    [ "$(format_bytes 1024)" = "1K" ]
}

@test "format_bytes formats kilobytes" {
    [ "$(format_bytes 1048576)" = "1M" ]
}

@test "format_bytes formats megabytes" {
    [ "$(format_bytes 1073741824)" = "1G" ]
}

@test "format_bytes handles zero" {
    result=$(format_bytes 0)
    [ "$result" = "0B" ]
}

@test "format_bytes handles invalid input" {
    result=$(format_bytes "invalid")
    [ "$result" = "0B" ]
}

#######################################
# Parse Size Tests
#######################################

@test "parse_size_to_bytes handles bytes" {
    [ "$(parse_size_to_bytes '100B')" = "100" ]
}

@test "parse_size_to_bytes handles kilobytes" {
    [ "$(parse_size_to_bytes '10K')" = "10240" ]
}

@test "parse_size_to_bytes handles megabytes" {
    [ "$(parse_size_to_bytes '10M')" = "10485760" ]
}

@test "parse_size_to_bytes handles gigabytes" {
    result=$(parse_size_to_bytes '1G')
    [ "$result" = "1073741824" ]
}

@test "parse_size_to_bytes handles case insensitive" {
    [ "$(parse_size_to_bytes '10k')" = "10240" ]
    [ "$(parse_size_to_bytes '10m')" = "10485760" ]
}

#######################################
# Directory Management Tests
#######################################

@test "ensure_directory creates directory" {
    local test_dir="$TEST_TEMP_DIR/test-ensure-dir"

    ensure_directory "$test_dir"

    assert_dir_exist "$test_dir"
}

@test "ensure_directory succeeds if directory exists" {
    local test_dir
    test_dir=$(create_test_dir "existing-dir")

    run ensure_directory "$test_dir"
    assert_success
}

@test "ensure_directory sets permissions" {
    local test_dir="$TEST_TEMP_DIR/test-perms-dir"

    ensure_directory "$test_dir" "755"

    assert_dir_exist "$test_dir"
    # Check permissions
    local perms
    perms=$(stat -c %a "$test_dir")
    [ "$perms" = "755" ]
}

#######################################
# Root Check Tests
#######################################

@test "require_root detects non-root user" {
    if [[ $EUID -eq 0 ]]; then
        skip "Test must run as non-root"
    fi

    run require_root
    assert_failure
}

@test "require_root succeeds for root" {
    skip_if_not_root "Test requires root"

    run require_root
    assert_success
}

#######################################
# ZFS Detection Tests
#######################################

@test "is_zfs_dataset validates path format" {
    skip_if_missing zfs "ZFS not available"

    # Invalid path should fail validation
    run is_zfs_dataset "../etc/passwd"
    assert_failure
}

@test "is_zfs_dataset handles non-existent paths" {
    skip_if_missing zfs "ZFS not available"

    run is_zfs_dataset "/nonexistent/path"
    assert_failure
}

#######################################
# Notification Tests
#######################################

@test "send_notification logs message" {
    export notification_type="none"

    send_notification "Test notification" "info"

    assert_log_contains "Test notification"
}

@test "send_notification respects notification_type=none" {
    export notification_type="none"
    export GOTIFY_SERVER_URL="http://example.com"
    export GOTIFY_APP_TOKEN="test-token"

    # Should not fail even without Gotify available
    run send_notification "Test" "info"
    assert_success
}

@test "send_notification handles error level" {
    export notification_type="error"

    send_notification "Test error" "error"

    assert_log_contains "ERROR"
    assert_log_contains "Test error"
}

@test "send_notification handles success level" {
    export notification_type="all"

    send_notification "Test success" "success"

    assert_log_contains "SUCCESS"
    assert_log_contains "Test success"
}

#######################################
# Log Rotation Tests
#######################################

@test "rotate_log handles missing log file" {
    export LOG_FILE="$TEST_TEMP_DIR/nonexistent.log"

    run rotate_log
    assert_success
}

@test "rotate_log does not rotate small files" {
    export LOG_FILE="$TEST_TEMP_DIR/small.log"
    export LOG_MAX_SIZE="10M"

    echo "Small log content" > "$LOG_FILE"

    run rotate_log
    assert_success

    # Original file should still exist
    assert_file_exist "$LOG_FILE"
    # Rotated file should not exist
    [ ! -f "${LOG_FILE}.1" ]
}

@test "rotate_log creates backup file" {
    skip "Requires large file generation - implement when needed"
}
