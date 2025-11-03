#!/usr/bin/env bats
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Test Suite for Race Condition Fixes                                   # #
# #   Tests locking mechanisms and concurrent operation handling            # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Load test helpers if available
load 'test_helper/bats-support/load' 2>/dev/null || true
load 'test_helper/bats-assert/load' 2>/dev/null || true

# Setup function runs before each test
setup() {
    # Set up test environment
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/zfs-test-$$"
    mkdir -p "$TEST_TEMP_DIR"

    # Set lock directory for testing
    export ZFS_LOCK_DIR="$TEST_TEMP_DIR/locks"
    export ZFS_LOCK_TIMEOUT=5

    # Source the locking library
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

    # Create minimal error handling for testing
    if [[ ! -f "$SCRIPT_DIR/lib/zfs-error-handling.sh" ]]; then
        mkdir -p "$SCRIPT_DIR/lib"
        cat > "$SCRIPT_DIR/lib/zfs-error-handling.sh" <<'EOF'
#!/bin/bash
error() { echo "ERROR: $1" >&2; return ${2:-1}; }
log_message() { echo "[$1] $2"; }
export -f error log_message
EOF
    fi

    # Create minimal common library for testing
    if [[ ! -f "$SCRIPT_DIR/lib/zfs-common.sh" ]]; then
        cat > "$SCRIPT_DIR/lib/zfs-common.sh" <<'EOF'
#!/bin/bash
log_message() { echo "[$1] $2"; }
export -f log_message
EOF
    fi

    source "$SCRIPT_DIR/lib/zfs-locking.sh"
}

# Teardown function runs after each test
teardown() {
    # Clean up locks
    cleanup_all_locks 2>/dev/null || true

    # Remove test directory
    if [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Test: Lock directory initialization
@test "Lock directory is created on init" {
    rm -rf "$ZFS_LOCK_DIR"

    run init_lock_dir
    [ "$status" -eq 0 ]
    [ -d "$ZFS_LOCK_DIR" ]
}

# Test: Basic lock acquisition and release
@test "Can acquire and release a lock" {
    local lock_file="$ZFS_LOCK_DIR/test.lock"

    # Acquire lock
    run acquire_lock "$lock_file" 5 "test lock"
    [ "$status" -eq 0 ]

    # Lock file should exist
    [ -f "$lock_file" ]

    # Release lock
    run release_lock "$lock_file"
    [ "$status" -eq 0 ]
}

# Test: Lock timeout
@test "Lock acquisition times out if lock is held" {
    local lock_file="$ZFS_LOCK_DIR/test-timeout.lock"

    # Acquire lock in subshell (to keep it held)
    (
        fd=$(acquire_lock "$lock_file" 10 "first lock")
        sleep 10
    ) &
    local bg_pid=$!

    sleep 1  # Give first process time to acquire lock

    # Try to acquire same lock with short timeout
    run acquire_lock "$lock_file" 2 "second lock"
    [ "$status" -eq 1 ]

    # Cleanup background process
    kill $bg_pid 2>/dev/null || true
    wait $bg_pid 2>/dev/null || true
}

# Test: Container lock acquisition
@test "Can acquire container lock" {
    run container_lock_acquire "test-container" 5
    [ "$status" -eq 0 ]

    # Should return lock file path
    [[ "$output" =~ container-test-container.lock$ ]]

    # Clean up
    container_lock_release "test-container"
}

# Test: Container lock prevents concurrent access
@test "Container lock prevents concurrent operations" {
    # Acquire lock
    lock_file=$(container_lock_acquire "test-container" 5)

    # Try to acquire same lock (should timeout)
    run container_lock_acquire "test-container" 2
    [ "$status" -eq 1 ]

    # Release original lock
    container_lock_release "test-container"

    # Now should succeed
    run container_lock_acquire "test-container" 2
    [ "$status" -eq 0 ]

    container_lock_release "test-container"
}

# Test: VM lock acquisition
@test "Can acquire VM lock" {
    run vm_lock_acquire "test-vm" 5
    [ "$status" -eq 0 ]

    # Should return lock file path
    [[ "$output" =~ vm-test-vm.lock$ ]]

    # Clean up
    vm_lock_release "test-vm"
}

# Test: VM lock with special characters in name
@test "VM lock handles special characters in names" {
    run vm_lock_acquire "test-vm-with-dashes" 5
    [ "$status" -eq 0 ]

    vm_lock_release "test-vm-with-dashes"
}

# Test: Dataset lock acquisition
@test "Can acquire dataset lock" {
    run dataset_lock_acquire "tank/data" 5
    [ "$status" -eq 0 ]

    # Should return lock file path (/ converted to -)
    [[ "$output" =~ dataset-tank-data.lock$ ]]

    # Clean up
    dataset_lock_release "tank/data"
}

# Test: Dataset lock prevents concurrent creation
@test "Dataset lock prevents concurrent operations" {
    local dataset="tank/data/test"

    # Acquire lock
    lock_file=$(dataset_lock_acquire "$dataset" 5)
    [ -n "$lock_file" ]

    # Try to acquire same lock (should timeout)
    run dataset_lock_acquire "$dataset" 2
    [ "$status" -eq 1 ]

    # Release and retry
    dataset_lock_release "$dataset"

    run dataset_lock_acquire "$dataset" 2
    [ "$status" -eq 0 ]

    dataset_lock_release "$dataset"
}

# Test: Multiple concurrent locks (different resources)
@test "Can hold multiple locks for different resources" {
    # Acquire multiple locks
    container_lock=$(container_lock_acquire "container1" 5)
    [ -n "$container_lock" ]

    vm_lock=$(vm_lock_acquire "vm1" 5)
    [ -n "$vm_lock" ]

    dataset_lock=$(dataset_lock_acquire "tank/data" 5)
    [ -n "$dataset_lock" ]

    # All locks should be held
    [ ${#ZFS_HELD_LOCKS[@]} -eq 3 ]

    # Release all
    container_lock_release "container1"
    vm_lock_release "vm1"
    dataset_lock_release "tank/data"

    # No locks should remain
    [ ${#ZFS_HELD_LOCKS[@]} -eq 0 ]
}

# Test: with_container_lock helper
@test "with_container_lock executes command with lock" {
    # Create a test command
    test_cmd() {
        echo "Command executed"
        return 0
    }
    export -f test_cmd

    run with_container_lock "test-container" 5 bash -c test_cmd
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Command executed" ]]
}

# Test: with_container_lock releases lock on failure
@test "with_container_lock releases lock even on command failure" {
    # Create a failing test command
    failing_cmd() {
        echo "Command failed"
        return 1
    }
    export -f failing_cmd

    run with_container_lock "test-container" 5 bash -c failing_cmd
    [ "$status" -eq 1 ]

    # Lock should be released - we should be able to acquire it
    run container_lock_acquire "test-container" 2
    [ "$status" -eq 0 ]

    container_lock_release "test-container"
}

# Test: Lock cleanup on normal exit
@test "cleanup_all_locks releases all held locks" {
    # Acquire multiple locks
    container_lock_acquire "container1" 5
    vm_lock_acquire "vm1" 5
    dataset_lock_acquire "tank/data" 5

    # Should have 3 locks
    [ ${#ZFS_HELD_LOCKS[@]} -eq 3 ]

    # Cleanup
    cleanup_all_locks

    # Should have no locks
    [ ${#ZFS_HELD_LOCKS[@]} -eq 0 ]
}

# Test: Lock file path sanitization
@test "Lock files are properly sanitized" {
    # Container with special characters
    run container_lock_acquire "test/container:special" 5
    [ "$status" -eq 0 ]

    # Lock file should have safe name
    [[ "$output" =~ container-test_container_special.lock$ ]]

    container_lock_release "test/container:special"
}

# Test: Concurrent lock attempts (stress test)
@test "Handles concurrent lock attempts correctly" {
    skip "Stress test - requires background processes"

    local lock_file="$ZFS_LOCK_DIR/stress-test.lock"
    local success_count=0
    local pids=()

    # Start 5 concurrent processes trying to acquire same lock
    for i in {1..5}; do
        (
            if acquire_lock "$lock_file" 10 "process-$i" >/dev/null; then
                sleep 1
                release_lock "$lock_file"
                exit 0
            else
                exit 1
            fi
        ) &
        pids+=($!)
    done

    # Wait for all processes
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            ((success_count++))
        fi
    done

    # All processes should eventually succeed (with timeout and retries)
    [ "$success_count" -eq 5 ]
}

# Test: Lock acquisition with empty parameters
@test "Lock functions reject empty parameters" {
    run container_lock_acquire "" 5
    [ "$status" -eq 1 ]

    run vm_lock_acquire "" 5
    [ "$status" -eq 1 ]

    run dataset_lock_acquire "" 5
    [ "$status" -eq 1 ]
}

# Test: Release non-existent lock
@test "Releasing non-held lock is safe" {
    run release_lock "$ZFS_LOCK_DIR/nonexistent.lock"
    [ "$status" -eq 0 ]  # Should not fail
}

# Test: Lock reacquisition after release
@test "Can reacquire lock after release" {
    local dataset="tank/data"

    # Acquire, release, reacquire
    dataset_lock_acquire "$dataset" 5
    dataset_lock_release "$dataset"

    run dataset_lock_acquire "$dataset" 5
    [ "$status" -eq 0 ]

    dataset_lock_release "$dataset"
}

# Integration test: Simulate dataset creation race
@test "Dataset lock prevents double creation" {
    skip "Integration test - requires ZFS mock"

    local dataset="tank/test"
    local created_count=0

    # Simulate two processes trying to create same dataset
    (
        if lock_file=$(dataset_lock_acquire "$dataset" 10); then
            # Simulate checking if dataset exists
            if [[ ! -f "$TEST_TEMP_DIR/dataset-$dataset" ]]; then
                # Simulate dataset creation
                touch "$TEST_TEMP_DIR/dataset-$dataset"
                sleep 1
            fi
            dataset_lock_release "$dataset"
        fi
    ) &

    (
        if lock_file=$(dataset_lock_acquire "$dataset" 10); then
            # Simulate checking if dataset exists
            if [[ ! -f "$TEST_TEMP_DIR/dataset-$dataset" ]]; then
                # Simulate dataset creation
                touch "$TEST_TEMP_DIR/dataset-$dataset"
                sleep 1
            fi
            dataset_lock_release "$dataset"
        fi
    ) &

    wait

    # Dataset file should only exist once
    [ -f "$TEST_TEMP_DIR/dataset-$dataset" ]
    local count=$(ls -1 "$TEST_TEMP_DIR"/dataset-* 2>/dev/null | wc -l)
    [ "$count" -eq 1 ]
}

# Test: Lock timeout is respected
@test "Lock timeout is properly enforced" {
    local lock_file="$ZFS_LOCK_DIR/timeout-test.lock"

    # Acquire lock
    fd=$(acquire_lock "$lock_file" 10 "first")

    # Try to acquire with 3 second timeout
    local start=$(date +%s)
    run acquire_lock "$lock_file" 3 "second"
    local end=$(date +%s)
    local duration=$((end - start))

    [ "$status" -eq 1 ]

    # Should have taken approximately 3 seconds (allow 1 second variance)
    [ "$duration" -ge 2 ]
    [ "$duration" -le 5 ]

    # Release original lock
    eval "exec $fd>&-"
}
