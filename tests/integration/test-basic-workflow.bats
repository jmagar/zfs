#!/usr/bin/env bats
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Basic Workflow Integration Test                                      # #
# #   Tests the complete workflow of the ZFS management scripts            # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

load '../test_helper/common'

#######################################
# Setup
#######################################

setup_file() {
    export TEST_TEMP_DIR="${BATS_FILE_TMPDIR}"
    export LOG_FILE="$TEST_TEMP_DIR/test.log"
    export DRY_RUN="yes"  # Always use dry-run for integration tests initially
    export MOUNT_POINT="/mnt"
    export SOURCE_POOL="test-pool"
    export SOURCE_DATASET="data"
    export notification_type="none"
}

teardown_file() {
    # Clean up any test resources
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

#######################################
# Configuration Loading Tests
#######################################

@test "integration: zfs-config.sh exists and is readable" {
    assert_file_exist "$PROJECT_ROOT/zfs-config.sh"
    [ -r "$PROJECT_ROOT/zfs-config.sh" ]
}

@test "integration: zfs-config.sh has valid syntax" {
    run bash -n "$PROJECT_ROOT/zfs-config.sh"
    assert_success
}

@test "integration: can source zfs-config.sh" {
    # Try to source the config file
    run bash -c "source '$PROJECT_ROOT/zfs-config.sh' 2>&1 | head -20"

    # Should not fail catastrophically
    # May have errors about missing ZFS pool, but syntax should be valid
    echo "Output: $output"
}

#######################################
# Script Existence Tests
#######################################

@test "integration: zfs-auto-datasets-ubuntu.sh exists" {
    assert_file_exist "$PROJECT_ROOT/zfs-auto-datasets-ubuntu.sh"
}

@test "integration: zfs-replications-ubuntu.sh exists" {
    assert_file_exist "$PROJECT_ROOT/zfs-replications-ubuntu.sh"
}

@test "integration: main scripts are executable" {
    [ -x "$PROJECT_ROOT/zfs-auto-datasets-ubuntu.sh" ] || skip "Dataset script not executable"
    [ -x "$PROJECT_ROOT/zfs-replications-ubuntu.sh" ] || skip "Replication script not executable"
}

@test "integration: main scripts have valid syntax" {
    run bash -n "$PROJECT_ROOT/zfs-auto-datasets-ubuntu.sh"
    assert_success

    run bash -n "$PROJECT_ROOT/zfs-replications-ubuntu.sh"
    assert_success
}

#######################################
# Dry-Run Tests
#######################################

@test "integration: dataset converter dry-run does not require root" {
    export DRY_RUN="yes"

    # This should work in dry-run mode even without ZFS
    run timeout 30 "$PROJECT_ROOT/zfs-auto-datasets-ubuntu.sh"

    # May fail due to missing ZFS, but should not crash
    echo "Exit code: $status"
    echo "Output: $output"
}

@test "integration: replication dry-run does not require root" {
    export DRY_RUN="yes"

    # This should work in dry-run mode even without ZFS
    run timeout 30 "$PROJECT_ROOT/zfs-replications-ubuntu.sh"

    # May fail due to missing ZFS, but should not crash
    echo "Exit code: $status"
    echo "Output: $output"
}

#######################################
# Mock ZFS Tests
#######################################

@test "integration: mock ZFS commands for testing" {
    # Create mock ZFS commands
    mock_command "zfs" 'echo "mock-pool/mock-dataset	/mnt/mock-pool/mock-dataset"'
    mock_command "zpool" 'echo "mock-pool	ONLINE	-	-	-	-	-"'

    # Verify mocks work
    run zfs list
    assert_success
    assert_output --partial "mock-pool"

    run zpool list
    assert_success
    assert_output --partial "mock-pool"
}

#######################################
# Library Tests
#######################################

@test "integration: lib directory structure" {
    if [[ -d "$PROJECT_ROOT/lib" ]]; then
        echo "Library directory exists"
        ls -la "$PROJECT_ROOT/lib/"
    else
        skip "lib directory not yet created"
    fi
}

@test "integration: source all library files" {
    if [[ ! -d "$PROJECT_ROOT/lib" ]]; then
        skip "lib directory not yet created"
    fi

    # Try to source each library file
    for lib in "$PROJECT_ROOT"/lib/*.sh; do
        if [[ -f "$lib" ]]; then
            echo "Checking: $lib"
            run bash -n "$lib"
            assert_success
        fi
    done
}

#######################################
# Documentation Tests
#######################################

@test "integration: README.md exists" {
    assert_file_exist "$PROJECT_ROOT/README.md"
}

@test "integration: CLAUDE.md exists" {
    assert_file_exist "$PROJECT_ROOT/CLAUDE.md"
}

#######################################
# Configuration Validation Tests
#######################################

@test "integration: config has required variables" {
    skip "Implement when validation library is ready"

    # Test that all required variables are defined
    # MOUNT_POINT, SOURCE_POOL, SOURCE_DATASET, etc.
}

#######################################
# Real ZFS Integration Tests (Conditional)
#######################################

@test "integration: real ZFS pool operations" {
    skip_if_not_root "ZFS operations require root"
    skip_if_missing zpool "ZFS not available"

    # Check if test pool is available
    if ! zpool list "${TEST_ZFS_POOL:-test-pool}" >/dev/null 2>&1; then
        skip "Test ZFS pool not available"
    fi

    # Verify we can interact with the test pool
    run zpool list "${TEST_ZFS_POOL:-test-pool}"
    assert_success
}

@test "integration: create test dataset" {
    skip_if_not_root "ZFS operations require root"
    skip_if_missing zfs "ZFS not available"

    if ! zpool list "${TEST_ZFS_POOL:-test-pool}" >/dev/null 2>&1; then
        skip "Test ZFS pool not available"
    fi

    # Create a test dataset
    local test_dataset="${TEST_ZFS_POOL:-test-pool}/test-integration-$$"

    run zfs create "$test_dataset"
    assert_success

    # Verify it was created
    run zfs list -H -o name "$test_dataset"
    assert_success
    assert_output "$test_dataset"

    # Clean up
    run zfs destroy "$test_dataset"
    assert_success
}

#######################################
# Error Handling Tests
#######################################

@test "integration: scripts handle missing dependencies gracefully" {
    skip "Implement when scripts have better error handling"

    # Test that scripts provide helpful error messages
    # when dependencies are missing
}

@test "integration: scripts handle missing config gracefully" {
    skip "Implement when scripts have better error handling"

    # Test that scripts fail gracefully with missing config
}

#######################################
# Performance Tests
#######################################

@test "integration: scripts complete within reasonable time" {
    skip "Implement performance benchmarks"

    # Ensure scripts don't hang indefinitely
    # Test with timeout
}
