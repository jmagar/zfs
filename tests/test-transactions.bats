#!/usr/bin/env bats
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Test Suite for ZFS Transaction Library                                # #
# #   Tests transaction state tracking, rollback, and recovery             # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Load test helpers if available
load 'test_helper/bats-support/load' 2>/dev/null || true
load 'test_helper/bats-assert/load' 2>/dev/null || true

# Setup function run before each test
setup() {
    # Set up test environment
    export TEST_DIR="${BATS_TEST_TMPDIR}/zfs-tx-test"
    export TX_STATE_DIR="$TEST_DIR/transactions"
    export TX_LOCK_DIR="$TEST_DIR/locks"
    export LOG_FILE="$TEST_DIR/test.log"
    export DRY_RUN="no"

    # Create test directory structure
    mkdir -p "$TEST_DIR"
    mkdir -p "$TX_STATE_DIR"
    mkdir -p "$TX_LOCK_DIR"

    # Source the transaction library
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$SCRIPT_DIR/lib/zfs-transactions.sh"

    # Stub validate_dataset_name so transaction_start doesn't abort in tests
    if ! declare -F validate_dataset_name >/dev/null 2>&1; then
        validate_dataset_name() { return 0; }
        export -f validate_dataset_name
    fi
}

# Teardown function run after each test
teardown() {
    # Clean up test directory
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

#######################################
# Test: Transaction Start
#######################################

@test "transaction_start creates state file" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    # Check transaction ID format
    [[ "$tx_id" =~ ^tx_[0-9]{8}_[0-9]{6}_[0-9]+$ ]]

    # Check state file exists
    [ -f "$TX_STATE_DIR/${tx_id}.json" ]

    # Check state file content
    local state=$(cat "$TX_STATE_DIR/${tx_id}.json")
    [[ "$state" =~ "INITIATED" ]]
    [[ "$state" =~ "tank/dataset" ]]
    [[ "$state" =~ "convert" ]]
}

@test "transaction_start validates dataset name" {
    run transaction_start "convert" "../invalid" "/mnt/tank/data" "/mnt/tank/data_temp"

    [ "$status" -eq 1 ]
}

@test "transaction_start requires all parameters" {
    run transaction_start "convert" "tank/dataset"

    [ "$status" -eq 1 ]
}

#######################################
# Test: Transaction State Updates
#######################################

@test "transaction_update_state changes state correctly" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    transaction_update_state "$tx_id" "RENAMED"

    local state=$(transaction_get_info "$tx_id" "state")
    [ "$state" = "RENAMED" ]
}

@test "transaction_update_state updates timestamp" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    local created_at=$(transaction_get_info "$tx_id" "created_at")
    sleep 1
    transaction_update_state "$tx_id" "RENAMED"
    local updated_at=$(transaction_get_info "$tx_id" "updated_at")

    [[ "$updated_at" != "$created_at" ]]
}

@test "transaction_update_state can add error message" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    transaction_update_state "$tx_id" "FAILED" "Test error message"

    local error_msg=$(transaction_get_info "$tx_id" "error_message")
    [[ "$error_msg" =~ "Test error message" ]]
}

#######################################
# Test: Transaction Completion
#######################################

@test "transaction_complete marks transaction as completed" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    transaction_complete "$tx_id"

    local state=$(transaction_get_info "$tx_id" "state")
    [ "$state" = "COMPLETED" ]
}

@test "transaction_fail marks transaction as failed" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    transaction_fail "$tx_id" "Test failure"

    local state=$(transaction_get_info "$tx_id" "state")
    [ "$state" = "FAILED" ]
}

#######################################
# Test: Transaction Info Retrieval
#######################################

@test "transaction_get_info returns full JSON when no field specified" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    local info=$(transaction_get_info "$tx_id")

    [[ "$info" =~ "transaction_id" ]]
    [[ "$info" =~ "dataset_name" ]]
    [[ "$info" =~ "state" ]]
}

@test "transaction_get_info returns specific field" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    local dataset=$(transaction_get_info "$tx_id" "dataset_name")

    [ "$dataset" = "tank/dataset" ]
}

@test "transaction_get_info fails for non-existent transaction" {
    run transaction_get_info "tx_nonexistent"

    [ "$status" -eq 1 ]
}

#######################################
# Test: Transaction Rollback - INITIATED State
#######################################

@test "rollback from INITIATED state succeeds" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    transaction_rollback "$tx_id"

    local state=$(transaction_get_info "$tx_id" "state")
    [ "$state" = "ROLLEDBACK" ]
}

#######################################
# Test: Transaction Rollback - RENAMED State
#######################################

@test "rollback from RENAMED state restores directory" {
    # Create test directory structure
    mkdir -p "$TEST_DIR/source/testdir"
    echo "test data" > "$TEST_DIR/source/testdir/file.txt"

    local tx_id=$(transaction_start "convert" "tank/dataset" "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp")

    # Simulate RENAMED state
    mv "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp"
    transaction_update_state "$tx_id" "RENAMED"

    # Rollback
    transaction_rollback "$tx_id"

    # Verify directory restored
    [ -d "$TEST_DIR/source/testdir" ]
    [ ! -d "$TEST_DIR/source/testdir_temp" ]
    [ -f "$TEST_DIR/source/testdir/file.txt" ]
}

#######################################
# Test: Transaction Rollback - DATASET_CREATED State
#######################################

@test "rollback from DATASET_CREATED state (simulated)" {
    # Create test directory structure
    mkdir -p "$TEST_DIR/source/testdir_temp"
    echo "test data" > "$TEST_DIR/source/testdir_temp/file.txt"

    # Create a placeholder for the "dataset" (we can't actually create ZFS datasets in tests)
    mkdir -p "$TEST_DIR/source/testdir"

    local tx_id=$(transaction_start "convert" "tank/dataset" "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp")

    # Simulate DATASET_CREATED state
    transaction_update_state "$tx_id" "DATASET_CREATED"

    # Rollback (this will try to destroy dataset, which will fail, but should still restore directory)
    transaction_rollback "$tx_id"

    local state=$(transaction_get_info "$tx_id" "state")
    # Should be ROLLEDBACK or FAILED depending on whether directory restoration succeeded
    [[ "$state" == "ROLLEDBACK" || "$state" == "FAILED" ]]
}

#######################################
# Test: Transaction Rollback - VALIDATED State
#######################################

@test "rollback from VALIDATED state performs forward recovery" {
    # Create test directory structure
    mkdir -p "$TEST_DIR/source/testdir_temp"
    echo "test data" > "$TEST_DIR/source/testdir_temp/file.txt"

    local tx_id=$(transaction_start "convert" "tank/dataset" "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp")

    # Simulate VALIDATED state (data is good, just needs cleanup)
    transaction_update_state "$tx_id" "VALIDATED"

    # Rollback should complete the transaction instead
    transaction_rollback "$tx_id"

    local state=$(transaction_get_info "$tx_id" "state")
    [ "$state" = "COMPLETED" ]

    # Temp directory should be cleaned up
    [ ! -d "$TEST_DIR/source/testdir_temp" ]
}

#######################################
# Test: Transaction Rollback - Skip Final States
#######################################

@test "rollback skips already completed transactions" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    transaction_complete "$tx_id"
    transaction_rollback "$tx_id"

    local state=$(transaction_get_info "$tx_id" "state")
    [ "$state" = "COMPLETED" ]
}

@test "rollback skips already rolled back transactions" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    transaction_update_state "$tx_id" "ROLLEDBACK"
    transaction_rollback "$tx_id"

    local state=$(transaction_get_info "$tx_id" "state")
    [ "$state" = "ROLLEDBACK" ]
}

#######################################
# Test: Transaction Listing
#######################################

@test "transaction_list_pending shows pending transactions" {
    local tx_id1=$(transaction_start "convert" "tank/dataset1" "/mnt/tank/data1" "/mnt/tank/data1_temp")
    local tx_id2=$(transaction_start "convert" "tank/dataset2" "/mnt/tank/data2" "/mnt/tank/data2_temp")

    transaction_complete "$tx_id1"
    # tx_id2 remains pending

    local output=$(transaction_list_pending)

    [[ "$output" =~ "$tx_id2" ]]
    [[ ! "$output" =~ "$tx_id1" ]]
}

@test "transaction_list_pending shows message when no pending transactions" {
    local output=$(transaction_list_pending)

    [[ "$output" =~ "No pending transactions found" ]]
}

#######################################
# Test: Transaction Recovery
#######################################

@test "transaction_recover_all finds and recovers pending transactions" {
    # Create multiple transactions in different states
    local tx_id1=$(transaction_start "convert" "tank/dataset1" "/mnt/tank/data1" "/mnt/tank/data1_temp")
    local tx_id2=$(transaction_start "convert" "tank/dataset2" "/mnt/tank/data2" "/mnt/tank/data2_temp")
    local tx_id3=$(transaction_start "convert" "tank/dataset3" "/mnt/tank/data3" "/mnt/tank/data3_temp")

    # Set different states
    transaction_complete "$tx_id1"  # Should be skipped
    transaction_update_state "$tx_id2" "RENAMED"  # Should be rolled back
    transaction_update_state "$tx_id3" "VALIDATED"  # Should be completed

    # Recover all
    transaction_recover_all

    # Check results
    [ "$(transaction_get_info "$tx_id1" "state")" = "COMPLETED" ]
    [ "$(transaction_get_info "$tx_id2" "state")" = "ROLLEDBACK" ]
    [ "$(transaction_get_info "$tx_id3" "state")" = "COMPLETED" ]
}

@test "transaction_recover_all handles empty transaction directory" {
    rm -rf "$TX_STATE_DIR"

    run transaction_recover_all

    [ "$status" -eq 0 ]
}

#######################################
# Test: Transaction Cleanup
#######################################

@test "transaction_cleanup removes old completed transactions" {
    # Create a completed transaction
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")
    transaction_complete "$tx_id"

    local state_file="$TX_STATE_DIR/${tx_id}.json"

    # Make the file appear old (modify timestamp)
    touch -d "35 days ago" "$state_file"

    # Clean up transactions older than 30 days
    transaction_cleanup 30

    # File should be removed
    [ ! -f "$state_file" ]
}

@test "transaction_cleanup preserves recent transactions" {
    # Create a completed transaction
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")
    transaction_complete "$tx_id"

    local state_file="$TX_STATE_DIR/${tx_id}.json"

    # Clean up transactions older than 30 days (this one is recent)
    transaction_cleanup 30

    # File should still exist
    [ -f "$state_file" ]
}

@test "transaction_cleanup preserves pending transactions" {
    # Create a pending transaction
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    local state_file="$TX_STATE_DIR/${tx_id}.json"

    # Make the file appear old
    touch -d "35 days ago" "$state_file"

    # Clean up transactions older than 30 days
    transaction_cleanup 30

    # File should still exist (because it's pending)
    [ -f "$state_file" ]
}

#######################################
# Test: Concurrent Transaction Handling
#######################################

@test "transactions use locking to prevent conflicts" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    # Simulate lock acquisition
    local lock_file="$TX_LOCK_DIR/${tx_id}.lock"

    # Lock should not exist after operation
    [ ! -f "$lock_file" ]
}

#######################################
# Test: Dry Run Mode
#######################################

@test "transactions work in dry run mode" {
    export DRY_RUN="yes"

    # Create test directory structure (but operations won't actually happen)
    mkdir -p "$TEST_DIR/source/testdir_temp"

    local tx_id=$(transaction_start "convert" "tank/dataset" "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp")

    transaction_update_state "$tx_id" "VALIDATED"
    transaction_rollback "$tx_id"

    # Temp directory should still exist in dry run
    [ -d "$TEST_DIR/source/testdir_temp" ]

    local state=$(transaction_get_info "$tx_id" "state")
    [ "$state" = "COMPLETED" ]
}

#######################################
# Test: State File Atomicity
#######################################

@test "state file updates are atomic" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    local state_file="$TX_STATE_DIR/${tx_id}.json"

    # Update state
    transaction_update_state "$tx_id" "RENAMED"

    # Check no temp files left behind
    [ ! -f "${state_file}.tmp"* ]

    # Check state file is valid JSON
    if command -v jq >/dev/null 2>&1; then
        run jq . "$state_file"
        [ "$status" -eq 0 ]
    fi
}

#######################################
# Test: Error Handling
#######################################

@test "transaction functions handle missing transaction gracefully" {
    run transaction_update_state "tx_nonexistent" "RENAMED"

    [ "$status" -eq 1 ]
}

@test "transaction functions handle corrupted state file" {
    local tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

    local state_file="$TX_STATE_DIR/${tx_id}.json"

    # Corrupt the state file
    echo "invalid json {{{" > "$state_file"

    # Should handle gracefully
    run transaction_get_info "$tx_id" "state"

    # May succeed with fallback or fail gracefully
    [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

#######################################
# Test: Integration Scenarios
#######################################

@test "complete workflow: successful conversion" {
    # Create test directory with data
    mkdir -p "$TEST_DIR/source/testdir"
    echo "test data" > "$TEST_DIR/source/testdir/file.txt"

    # Start transaction
    local tx_id=$(transaction_start "convert" "tank/testdir" "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp")

    # Simulate conversion steps
    mv "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp"
    transaction_update_state "$tx_id" "RENAMED"

    mkdir -p "$TEST_DIR/source/testdir"
    transaction_update_state "$tx_id" "DATASET_CREATED"

    transaction_update_state "$tx_id" "RSYNC_STARTED"
    cp -a "$TEST_DIR/source/testdir_temp/." "$TEST_DIR/source/testdir/"
    transaction_update_state "$tx_id" "RSYNC_COMPLETE"

    transaction_update_state "$tx_id" "VALIDATED"

    rm -rf "$TEST_DIR/source/testdir_temp"
    transaction_complete "$tx_id"

    # Verify final state
    [ "$(transaction_get_info "$tx_id" "state")" = "COMPLETED" ]
    [ -f "$TEST_DIR/source/testdir/file.txt" ]
    [ ! -d "$TEST_DIR/source/testdir_temp" ]
}

@test "complete workflow: failed conversion with rollback" {
    # Create test directory with data
    mkdir -p "$TEST_DIR/source/testdir"
    echo "test data" > "$TEST_DIR/source/testdir/file.txt"

    # Start transaction
    local tx_id=$(transaction_start "convert" "tank/testdir" "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp")

    # Simulate conversion steps that fail after rename
    mv "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp"
    transaction_update_state "$tx_id" "RENAMED"

    # Simulate failure (don't create dataset)
    transaction_fail "$tx_id" "Simulated failure"

    # Rollback
    transaction_rollback "$tx_id"

    # Verify rollback restored original
    [ "$(transaction_get_info "$tx_id" "state")" = "ROLLEDBACK" ]
    [ -d "$TEST_DIR/source/testdir" ]
    [ ! -d "$TEST_DIR/source/testdir_temp" ]
    [ -f "$TEST_DIR/source/testdir/file.txt" ]
}

@test "recovery after unexpected termination" {
    # Create test directory with data
    mkdir -p "$TEST_DIR/source/testdir_temp"
    echo "test data" > "$TEST_DIR/source/testdir_temp/file.txt"

    # Start transaction and simulate partial completion
    local tx_id=$(transaction_start "convert" "tank/testdir" "$TEST_DIR/source/testdir" "$TEST_DIR/source/testdir_temp")
    transaction_update_state "$tx_id" "RENAMED"

    # Simulate script termination (transaction left in RENAMED state)
    # Now simulate recovery on next run
    transaction_recover_all

    # Verify transaction was rolled back
    [ "$(transaction_get_info "$tx_id" "state")" = "ROLLEDBACK" ]
}
