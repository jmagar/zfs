#!/usr/bin/env bats
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Example Test File                                                     # #
# #   Demonstrates BATS syntax and testing patterns                        # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Load common test helpers
load 'test_helper/common'

#######################################
# Basic Assertions
#######################################

@test "example: basic arithmetic" {
    result=$((2 + 2))
    [ "$result" -eq 4 ]
}

@test "example: string comparison" {
    local greeting="hello"
    [ "$greeting" = "hello" ]
}

@test "example: command success" {
    run echo "test"
    assert_success
}

@test "example: command failure" {
    run false
    assert_failure
}

#######################################
# Output Assertions
#######################################

@test "example: exact output match" {
    run echo "hello world"
    assert_output "hello world"
}

@test "example: partial output match" {
    run echo "hello world"
    assert_output --partial "world"
}

@test "example: regex output match" {
    run echo "test123"
    assert_output --regexp "test[0-9]+"
}

#######################################
# Line Assertions
#######################################

@test "example: line count" {
    run printf "line1\nline2\nline3"
    [ "${#lines[@]}" -eq 3 ]
}

@test "example: specific line check" {
    run printf "first\nsecond\nthird"
    [ "${lines[0]}" = "first" ]
    [ "${lines[1]}" = "second" ]
    [ "${lines[2]}" = "third" ]
}

#######################################
# File Assertions
#######################################

@test "example: file exists" {
    local test_file
    test_file=$(create_test_file "example.txt" "content")
    assert_file_exist "$test_file"
}

@test "example: file contains text" {
    local test_file
    test_file=$(create_test_file "example.txt" "hello world")
    run cat "$test_file"
    assert_output "hello world"
}

@test "example: directory creation" {
    local test_dir
    test_dir=$(create_test_dir "example-dir")
    assert_dir_exist "$test_dir"
}

#######################################
# Mock Commands
#######################################

@test "example: mock command success" {
    mock_command "test-cmd" "echo 'mocked output'"
    run test-cmd
    assert_success
    assert_output "mocked output"
}

@test "example: mock command failure" {
    mock_command "failing-cmd" "exit 1"
    run failing-cmd
    assert_failure
}

#######################################
# Conditional Test Execution
#######################################

@test "example: skip if missing command" {
    skip_if_missing "nonexistent-command" "Command not available"
    # This test will be skipped
    run echo "This won't run"
}

@test "example: CI detection" {
    if is_ci; then
        echo "Running in CI environment"
    else
        echo "Running locally"
    fi
}

#######################################
# Test Data Generation
#######################################

@test "example: generate test data" {
    local test_dir
    test_dir=$(create_test_dir "data-test")

    # Generate 3 files of 1KB each
    generate_test_data "$test_dir" 3 1

    # Verify files were created
    [ "$(ls -1 "$test_dir" | wc -l)" -eq 3 ]
}

#######################################
# Log Assertions
#######################################

@test "example: log file contains pattern" {
    echo "INFO: Test message" > "$LOG_FILE"
    echo "ERROR: Test error" >> "$LOG_FILE"

    assert_log_contains "INFO"
    assert_log_contains "ERROR"
    assert_log_contains "Test message"
}

@test "example: count log patterns" {
    echo "ERROR: First error" > "$LOG_FILE"
    echo "INFO: Information" >> "$LOG_FILE"
    echo "ERROR: Second error" >> "$LOG_FILE"

    local error_count
    error_count=$(count_log_pattern "ERROR")
    [ "$error_count" -eq 2 ]
}

#######################################
# Setup/Teardown Examples
#######################################

@test "example: test isolation" {
    # Each test runs in isolation with fresh setup
    local test_var="test-specific-value"
    [ "$test_var" = "test-specific-value" ]
}

@test "example: temporary directory exists" {
    # TEST_TEMP_DIR is available to all tests
    [ -d "$TEST_TEMP_DIR" ]
}

@test "example: log file exists" {
    # LOG_FILE is set by setup
    [ -n "$LOG_FILE" ]
}
