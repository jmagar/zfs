#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR:-/tmp/bats-test-$$}"
    mkdir -p "$TEST_TEMP_DIR"
    export ZFS_ERROR_LOG="$TEST_TEMP_DIR/error.log"
    source "$SCRIPT_DIR/lib/zfs-error-handling.sh"
    reset_error_count
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

@test "error function logs and increments counter" {
    reset_error_count
    error "Test error 1" || true
    error "Test error 2" || true
    [ "$(get_error_count)" -eq 2 ]
    [ "$(get_last_error)" = "Test error 2" ]
    grep -q "Test error 1" "$ZFS_ERROR_LOG"
    grep -q "Test error 2" "$ZFS_ERROR_LOG"
}

@test "error function respects custom exit code" {
    run error "Test error" 42
    [ "$status" -eq 42 ]
}

@test "error function creates log directory if missing" {
    export ZFS_ERROR_LOG="$TEST_TEMP_DIR/nested/deep/error.log"
    error "Test error" || true
    [ -f "$ZFS_ERROR_LOG" ]
    grep -q "Test error" "$ZFS_ERROR_LOG"
}

@test "safe_execute succeeds on valid command" {
    run safe_execute echo "test"
    [ "$status" -eq 0 ]
}

@test "safe_execute fails on invalid command" {
    run safe_execute false
    [ "$status" -eq 1 ]
}

@test "safe_execute captures command output on failure" {
    run safe_execute bash -c "echo 'error output'; exit 1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"error output"* ]]
}

@test "retry_execute succeeds immediately on success" {
    run retry_execute 3 echo "test"
    [ "$status" -eq 0 ]
}

@test "retry_execute retries on failure then succeeds" {
    cat > "$TEST_TEMP_DIR/flaky.sh" <<'EOF'
#!/bin/bash
count_file="${TEST_TEMP_DIR:-/tmp}/retry-count"
count=$(cat "$count_file" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$count_file"
if [ "$count" -lt 3 ]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/flaky.sh"
    rm -f "$TEST_TEMP_DIR/retry-count"
    run retry_execute 5 "$TEST_TEMP_DIR/flaky.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_TEMP_DIR/retry-count")" -eq 3 ]
}

@test "retry_execute fails after max attempts" {
    run retry_execute 3 false
    [ "$status" -eq 1 ]
}

@test "retry_execute validates max_attempts parameter" {
    run retry_execute "invalid" echo "test"
    [ "$status" -eq 1 ]
    run retry_execute 0 echo "test"
    [ "$status" -eq 1 ]
}

@test "check_exit_code succeeds on zero" {
    run check_exit_code 0 "Should not fail"
    [ "$status" -eq 0 ]
}

@test "check_exit_code fails on non-zero" {
    run check_exit_code 1 "Test failure"
    [ "$status" -eq 1 ]
}

@test "check_exit_code validates input" {
    run check_exit_code "invalid" "Test message"
    [ "$status" -eq 1 ]
}

@test "require_command detects missing commands" {
    run require_command "this-command-does-not-exist-12345"
    [ "$status" -eq 1 ]
}

@test "require_command accepts existing commands" {
    run require_command "bash"
    [ "$status" -eq 0 ]
}

@test "require_command rejects empty input" {
    run require_command ""
    [ "$status" -eq 1 ]
}

@test "require_file detects missing files" {
    run require_file "$TEST_TEMP_DIR/nonexistent.txt"
    [ "$status" -eq 1 ]
}

@test "require_file accepts existing readable files" {
    echo "test" > "$TEST_TEMP_DIR/test.txt"
    run require_file "$TEST_TEMP_DIR/test.txt"
    [ "$status" -eq 0 ]
}

@test "require_file rejects empty input" {
    run require_file ""
    [ "$status" -eq 1 ]
}

@test "require_directory detects missing directories" {
    run require_directory "$TEST_TEMP_DIR/nonexistent"
    [ "$status" -eq 1 ]
}

@test "require_directory accepts existing writable directories" {
    mkdir -p "$TEST_TEMP_DIR/testdir"
    run require_directory "$TEST_TEMP_DIR/testdir"
    [ "$status" -eq 0 ]
}

@test "require_directory rejects empty input" {
    run require_directory ""
    [ "$status" -eq 1 ]
}

@test "dry_run_execute skips in dry-run mode" {
    export DRY_RUN="yes"
    run dry_run_execute rm -rf /nonexistent-path-12345
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY RUN" ]]
}

@test "dry_run_execute executes in normal mode" {
    export DRY_RUN="no"
    run dry_run_execute echo "test"
    [ "$status" -eq 0 ]
    [[ "$output" == "test" ]]
}

@test "dry_run_execute defaults to executing when DRY_RUN unset" {
    unset DRY_RUN
    run dry_run_execute echo "test"
    [ "$status" -eq 0 ]
    [[ "$output" == "test" ]]
}

@test "reset_error_count resets counters" {
    error "Test error 1" || true
    error "Test error 2" || true
    [ "$(get_error_count)" -eq 2 ]
    reset_error_count
    [ "$(get_error_count)" -eq 0 ]
    [ "$(get_last_error)" = "" ]
}

@test "get_error_count returns correct count" {
    reset_error_count
    [ "$(get_error_count)" -eq 0 ]
    error "Error 1" || true
    [ "$(get_error_count)" -eq 1 ]
    error "Error 2" || true
    [ "$(get_error_count)" -eq 2 ]
    error "Error 3" || true
    [ "$(get_error_count)" -eq 3 ]
}

@test "get_last_error returns last error message" {
    reset_error_count
    error "First error" || true
    [ "$(get_last_error)" = "First error" ]
    error "Second error" || true
    [ "$(get_last_error)" = "Second error" ]
    error "Third error" || true
    [ "$(get_last_error)" = "Third error" ]
}

@test "error log contains timestamp" {
    error "Test error with timestamp" || true
    grep -E "\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]" "$ZFS_ERROR_LOG"
}

@test "error log contains error code" {
    error "Test error" 42 || true
    grep -q "\[ERROR 42\]" "$ZFS_ERROR_LOG"
}

@test "multiple errors are tracked correctly" {
    reset_error_count
    for i in {1..10}; do
        error "Error $i" || true
    done
    [ "$(get_error_count)" -eq 10 ]
    [ "$(get_last_error)" = "Error 10" ]
}

@test "retry_execute uses exponential backoff" {
    cat > "$TEST_TEMP_DIR/always-fail.sh" <<'EOF'
#!/bin/bash
echo "Attempt at $(date +%s)"
exit 1
EOF
    chmod +x "$TEST_TEMP_DIR/always-fail.sh"
    start_time=$(date +%s)
    run retry_execute 4 "$TEST_TEMP_DIR/always-fail.sh"
    end_time=$(date +%s)
    [ "$status" -eq 1 ]
    elapsed=$((end_time - start_time))
    [ "$elapsed" -ge 6 ]
}

@test "safe_execute handles commands with special characters" {
    run safe_execute echo "test with spaces"
    [ "$status" -eq 0 ]
    run safe_execute bash -c "echo 'quoted string'"
    [ "$status" -eq 0 ]
}

@test "error handling respects pipefail setting" {
    run bash -c "source '$SCRIPT_DIR/lib/zfs-error-handling.sh'; echo test | false"
    [ "$status" -ne 0 ]
}

@test "error tracking works with multiple error sources" {
    reset_error_count
    error "Error A" || true
    safe_execute false || true
    check_exit_code 1 "Check failed" || true
    [ "$(get_error_count)" -eq 3 ]
}
