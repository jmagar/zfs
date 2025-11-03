#!/usr/bin/env bats
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Test Suite for ZFS Input Validation Library                          # #
# #   Comprehensive tests for all validation functions                     # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# This file tests the validation library (lib/zfs-validation.sh) with >90% coverage
#
# Test categories:
# - Dataset name validation
# - Path validation with traversal protection
# - Integer validation (positive, non-negative, ranges)
# - URL validation
# - Host validation (IPv4 and hostnames)
# - ZFS resource existence checks (pools, datasets)
# - Snapshot name format validation
# - Boolean and choice validation

# Load test helpers
load 'test_helper/common'

# Setup: Source the validation library
setup() {
    # Source validation library
    source "$PROJECT_ROOT/lib/zfs-validation.sh"
}

#######################################
# Dataset Name Validation Tests
#######################################

@test "validate_dataset_name: accepts valid simple pool name" {
    run validate_dataset_name "tank"
    [ "$status" -eq 0 ]
}

@test "validate_dataset_name: accepts valid pool/dataset" {
    run validate_dataset_name "tank/data"
    [ "$status" -eq 0 ]
}

@test "validate_dataset_name: accepts valid deep hierarchy" {
    run validate_dataset_name "tank/data/subfolder/deep"
    [ "$status" -eq 0 ]
}

@test "validate_dataset_name: accepts underscores" {
    run validate_dataset_name "my_pool/my_dataset"
    [ "$status" -eq 0 ]
}

@test "validate_dataset_name: accepts hyphens" {
    run validate_dataset_name "my-pool/my-dataset"
    [ "$status" -eq 0 ]
}

@test "validate_dataset_name: accepts colons" {
    run validate_dataset_name "pool:backup"
    [ "$status" -eq 0 ]
}

@test "validate_dataset_name: accepts periods" {
    run validate_dataset_name "pool.01/dataset.v2"
    [ "$status" -eq 0 ]
}

@test "validate_dataset_name: rejects empty name" {
    run validate_dataset_name ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "cannot be empty" ]]
}

@test "validate_dataset_name: rejects name starting with hyphen" {
    run validate_dataset_name "-badname"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid dataset name format" ]]
}

@test "validate_dataset_name: rejects consecutive slashes" {
    run validate_dataset_name "tank//data"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "consecutive slashes" ]]
}

@test "validate_dataset_name: rejects trailing slash" {
    run validate_dataset_name "tank/data/"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "end with slash" ]]
}

@test "validate_dataset_name: rejects reserved name .zfs" {
    run validate_dataset_name "tank/.zfs"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "reserved word" ]]
}

@test "validate_dataset_name: rejects reserved name snapshot" {
    run validate_dataset_name "tank/snapshot"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "reserved word" ]]
}

@test "validate_dataset_name: rejects reserved name bookmark" {
    run validate_dataset_name "tank/bookmark"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "reserved word" ]]
}

@test "validate_dataset_name: rejects path traversal" {
    run validate_dataset_name "../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_dataset_name: rejects special characters" {
    run validate_dataset_name "tank/data*"
    [ "$status" -eq 1 ]
}

@test "validate_dataset_name: rejects spaces" {
    run validate_dataset_name "tank/my data"
    [ "$status" -eq 1 ]
}

@test "validate_dataset_name: rejects name over 255 chars" {
    local long_name=$(printf 'a%.0s' {1..300})
    run validate_dataset_name "$long_name"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "too long" ]]
}

#######################################
# Path Validation Tests
#######################################

@test "validate_path: accepts valid absolute path" {
    run validate_path "/mnt/tank/data"
    [ "$status" -eq 0 ]
}

@test "validate_path: accepts valid relative path" {
    run validate_path "data/subfolder"
    [ "$status" -eq 0 ]
}

@test "validate_path: rejects empty path" {
    run validate_path ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "cannot be empty" ]]
}

@test "validate_path: rejects path with parent reference" {
    run validate_path "/mnt/../etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "parent directory reference" ]]
}

@test "validate_path: rejects path with double dots" {
    run validate_path "../../secret"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "parent directory reference" ]]
}

@test "validate_path: rejects path with null byte" {
    run validate_path $'/mnt/tank\0bad'
    [ "$status" -eq 1 ]
    [[ "$output" =~ "null byte" ]]
}

@test "validate_path: validates containment within base path" {
    run validate_path "/mnt/tank/data/subdir" "/mnt/tank"
    [ "$status" -eq 0 ]
}

@test "validate_path: rejects path outside base path" {
    run validate_path "/etc/passwd" "/mnt/tank"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "outside base path" ]]
}

@test "validate_path: accepts path equal to base path" {
    run validate_path "/mnt/tank" "/mnt/tank"
    [ "$status" -eq 0 ]
}

#######################################
# Integer Validation Tests
#######################################

@test "validate_positive_integer: accepts 1" {
    run validate_positive_integer "1" "test"
    [ "$status" -eq 0 ]
}

@test "validate_positive_integer: accepts large number" {
    run validate_positive_integer "9999999" "test"
    [ "$status" -eq 0 ]
}

@test "validate_positive_integer: rejects 0" {
    run validate_positive_integer "0" "test"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "greater than 0" ]]
}

@test "validate_positive_integer: rejects negative number" {
    run validate_positive_integer "-5" "test"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "positive integer" ]]
}

@test "validate_positive_integer: rejects decimal" {
    run validate_positive_integer "3.14" "test"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "positive integer" ]]
}

@test "validate_positive_integer: rejects non-numeric" {
    run validate_positive_integer "abc" "test"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "positive integer" ]]
}

@test "validate_positive_integer: rejects empty string" {
    run validate_positive_integer "" "test"
    [ "$status" -eq 1 ]
}

@test "validate_non_negative_integer: accepts 0" {
    run validate_non_negative_integer "0" "test"
    [ "$status" -eq 0 ]
}

@test "validate_non_negative_integer: accepts positive number" {
    run validate_non_negative_integer "100" "test"
    [ "$status" -eq 0 ]
}

@test "validate_non_negative_integer: rejects negative number" {
    run validate_non_negative_integer "-1" "test"
    [ "$status" -eq 1 ]
}

@test "validate_non_negative_integer: rejects decimal" {
    run validate_non_negative_integer "1.5" "test"
    [ "$status" -eq 1 ]
}

@test "validate_integer_range: accepts value in range" {
    run validate_integer_range "50" "0" "100" "percent"
    [ "$status" -eq 0 ]
}

@test "validate_integer_range: accepts minimum value" {
    run validate_integer_range "0" "0" "100" "percent"
    [ "$status" -eq 0 ]
}

@test "validate_integer_range: accepts maximum value" {
    run validate_integer_range "100" "0" "100" "percent"
    [ "$status" -eq 0 ]
}

@test "validate_integer_range: rejects value below minimum" {
    run validate_integer_range "5" "10" "20" "test"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "between 10 and 20" ]]
}

@test "validate_integer_range: rejects value above maximum" {
    run validate_integer_range "25" "10" "20" "test"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "between 10 and 20" ]]
}

@test "validate_integer_range: rejects non-integer" {
    run validate_integer_range "abc" "0" "100" "test"
    [ "$status" -eq 1 ]
}

#######################################
# URL Validation Tests
#######################################

@test "validate_url: accepts http URL" {
    run validate_url "http://localhost:8080"
    [ "$status" -eq 0 ]
}

@test "validate_url: accepts https URL" {
    run validate_url "https://example.com"
    [ "$status" -eq 0 ]
}

@test "validate_url: accepts URL with path" {
    run validate_url "https://example.com/path/to/resource"
    [ "$status" -eq 0 ]
}

@test "validate_url: accepts URL with port" {
    run validate_url "http://192.168.1.1:3000"
    [ "$status" -eq 0 ]
}

@test "validate_url: accepts subdomain" {
    run validate_url "https://api.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_url: rejects empty URL" {
    run validate_url ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "cannot be empty" ]]
}

@test "validate_url: rejects URL without protocol" {
    run validate_url "example.com"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid URL format" ]]
}

@test "validate_url: rejects invalid protocol" {
    run validate_url "ftp://example.com"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid URL format" ]]
}

@test "validate_url: rejects URL with spaces" {
    run validate_url "http://bad url.com"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "contains spaces" ]]
}

@test "validate_url: rejects URL with path traversal" {
    run validate_url "http://example.com/../etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "path traversal" ]]
}

@test "validate_url: rejects malformed URL" {
    run validate_url "http://"
    [ "$status" -eq 1 ]
}

#######################################
# Host Validation Tests
#######################################

@test "validate_host: accepts valid IPv4" {
    run validate_host "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "validate_host: accepts valid hostname" {
    run validate_host "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_host: accepts hostname with hyphen" {
    run validate_host "my-server.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_host: accepts single label hostname" {
    run validate_host "localhost"
    [ "$status" -eq 0 ]
}

@test "validate_host: accepts subdomain" {
    run validate_host "api.v2.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_host: rejects empty host" {
    run validate_host ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "cannot be empty" ]]
}

@test "validate_host: rejects invalid IPv4 (octet > 255)" {
    run validate_host "192.168.1.256"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid IPv4" ]]
}

@test "validate_host: rejects invalid IPv4 (999.999.999.999)" {
    run validate_host "999.999.999.999"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid IPv4" ]]
}

@test "validate_host: rejects hostname starting with hyphen" {
    run validate_host "-badhost.com"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid hostname" ]]
}

@test "validate_host: rejects hostname with special characters" {
    run validate_host "bad_host.com"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid hostname" ]]
}

@test "validate_host: rejects hostname ending with hyphen" {
    run validate_host "badhost-.com"
    [ "$status" -eq 1 ]
}

@test "validate_host: rejects hostname over 253 chars" {
    local long_host=$(printf 'a%.0s' {1..300})".com"
    run validate_host "$long_host"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "too long" ]]
}

#######################################
# Pool/Dataset Existence Tests
#######################################

@test "validate_pool_exists: validates name format first" {
    run validate_pool_exists "../bad-pool"
    [ "$status" -eq 1 ]
}

@test "validate_pool_exists: reports non-existent pool" {
    skip_if_missing zpool "ZFS not installed"
    run validate_pool_exists "nonexistent-pool-12345"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "does not exist" ]]
}

@test "validate_dataset_exists: validates name format first" {
    run validate_dataset_exists "-bad/dataset"
    [ "$status" -eq 1 ]
}

@test "validate_dataset_exists: reports non-existent dataset" {
    skip_if_missing zfs "ZFS not installed"
    run validate_dataset_exists "nonexistent-pool/nonexistent-dataset"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "does not exist" ]]
}

#######################################
# Snapshot Name Validation Tests
#######################################

@test "validate_snapshot_name: accepts valid snapshot name" {
    run validate_snapshot_name "tank/data@snapshot1"
    [ "$status" -eq 0 ]
}

@test "validate_snapshot_name: accepts snapshot with hyphen" {
    run validate_snapshot_name "tank/data@auto-2024-11-03"
    [ "$status" -eq 0 ]
}

@test "validate_snapshot_name: accepts snapshot with underscore" {
    run validate_snapshot_name "tank/data@backup_daily"
    [ "$status" -eq 0 ]
}

@test "validate_snapshot_name: accepts snapshot with colon" {
    run validate_snapshot_name "tank/data@sanoid:hourly"
    [ "$status" -eq 0 ]
}

@test "validate_snapshot_name: accepts snapshot with period" {
    run validate_snapshot_name "tank/data@v1.0.0"
    [ "$status" -eq 0 ]
}

@test "validate_snapshot_name: rejects empty name" {
    run validate_snapshot_name ""
    [ "$status" -eq 1 ]
    [[ "$output" =~ "cannot be empty" ]]
}

@test "validate_snapshot_name: rejects missing @ symbol" {
    run validate_snapshot_name "tank/data/snapshot"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "expected dataset@snapshot" ]]
}

@test "validate_snapshot_name: rejects multiple @ symbols" {
    run validate_snapshot_name "tank/data@snap@shot"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid snapshot name format" ]]
}

@test "validate_snapshot_name: rejects invalid dataset part" {
    run validate_snapshot_name "-bad/dataset@snapshot"
    [ "$status" -eq 1 ]
}

@test "validate_snapshot_name: rejects invalid snapshot part" {
    run validate_snapshot_name "tank/data@bad/snapshot"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid snapshot name format" ]]
}

@test "validate_snapshot_name: rejects snapshot starting with hyphen" {
    run validate_snapshot_name "tank/data@-snapshot"
    [ "$status" -eq 1 ]
}

@test "validate_snapshot_name: rejects snapshot name over 255 chars" {
    local long_snap=$(printf 'a%.0s' {1..300})
    run validate_snapshot_name "tank/data@$long_snap"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "too long" ]]
}

#######################################
# Boolean Validation Tests
#######################################

@test "validate_boolean: accepts 'yes'" {
    run validate_boolean "yes" "test"
    [ "$status" -eq 0 ]
}

@test "validate_boolean: accepts 'no'" {
    run validate_boolean "no" "test"
    [ "$status" -eq 0 ]
}

@test "validate_boolean: rejects 'true'" {
    run validate_boolean "true" "test"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "must be 'yes' or 'no'" ]]
}

@test "validate_boolean: rejects 'false'" {
    run validate_boolean "false" "test"
    [ "$status" -eq 1 ]
}

@test "validate_boolean: rejects '1'" {
    run validate_boolean "1" "test"
    [ "$status" -eq 1 ]
}

@test "validate_boolean: rejects '0'" {
    run validate_boolean "0" "test"
    [ "$status" -eq 1 ]
}

@test "validate_boolean: rejects empty string" {
    run validate_boolean "" "test"
    [ "$status" -eq 1 ]
}

@test "validate_boolean: includes variable name in error" {
    run validate_boolean "maybe" "MY_VAR"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "MY_VAR" ]]
}

#######################################
# Choice Validation Tests
#######################################

@test "validate_choice: accepts valid choice from list" {
    run validate_choice "zfs" "REPLICATION" "zfs" "rsync" "none"
    [ "$status" -eq 0 ]
}

@test "validate_choice: accepts first choice" {
    run validate_choice "option1" "VAR" "option1" "option2" "option3"
    [ "$status" -eq 0 ]
}

@test "validate_choice: accepts last choice" {
    run validate_choice "option3" "VAR" "option1" "option2" "option3"
    [ "$status" -eq 0 ]
}

@test "validate_choice: rejects invalid choice" {
    run validate_choice "invalid" "VAR" "opt1" "opt2" "opt3"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "must be one of" ]]
}

@test "validate_choice: error message lists all valid choices" {
    run validate_choice "bad" "VAR" "good1" "good2" "good3"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "good1" ]]
    [[ "$output" =~ "good2" ]]
    [[ "$output" =~ "good3" ]]
}

@test "validate_choice: is case-sensitive" {
    run validate_choice "ZFS" "VAR" "zfs" "rsync"
    [ "$status" -eq 1 ]
}

#######################################
# Edge Cases and Error Handling
#######################################

@test "validation functions handle special regex characters safely" {
    # Test that regex special chars don't cause issues
    run validate_dataset_name "pool*"
    [ "$status" -eq 1 ]

    run validate_dataset_name "pool[test]"
    [ "$status" -eq 1 ]

    run validate_dataset_name "pool.{1,2}"
    [ "$status" -eq 1 ]
}

@test "validation functions produce stderr output on error" {
    run validate_dataset_name ""
    [ "$status" -eq 1 ]
    [[ "$output" != "" ]]
}

@test "validation functions handle missing optional parameters" {
    run validate_positive_integer "5"
    [ "$status" -eq 0 ]

    run validate_path "/valid/path"
    [ "$status" -eq 0 ]
}

@test "validation functions handle very long inputs" {
    # Test with very long but valid input
    local long_path=""
    for i in {1..50}; do
        long_path="${long_path}/dir${i}"
    done
    run validate_path "$long_path"
    [ "$status" -eq 0 ]
}

@test "validate_dataset_name handles complex valid names" {
    run validate_dataset_name "pool_01-backup.v2:snapshot/data_2024/subfolder-test.001"
    [ "$status" -eq 0 ]
}

@test "validate_url handles edge cases in port numbers" {
    run validate_url "http://example.com:1"
    [ "$status" -eq 0 ]

    run validate_url "http://example.com:65535"
    [ "$status" -eq 0 ]

    run validate_url "http://example.com:99999"
    [ "$status" -eq 1 ]
}

@test "validate_host handles valid edge cases" {
    # Single character labels
    run validate_host "a.b.c"
    [ "$status" -eq 0 ]

    # IPv4 with zeros
    run validate_host "0.0.0.0"
    [ "$status" -eq 0 ]

    # Maximum valid IPv4
    run validate_host "255.255.255.255"
    [ "$status" -eq 0 ]
}

#######################################
# Integration Tests
#######################################

@test "all validation functions can be called in sequence without conflicts" {
    validate_dataset_name "tank"
    validate_path "/mnt/tank"
    validate_positive_integer "5" "test"
    validate_non_negative_integer "0" "test"
    validate_integer_range "50" "0" "100" "test"
    validate_url "http://example.com"
    validate_host "192.168.1.1"
    validate_snapshot_name "tank/data@snap"
    validate_boolean "yes" "test"
    validate_choice "opt1" "test" "opt1" "opt2"

    # All should succeed
    [ "$?" -eq 0 ]
}

@test "validation library exports all functions" {
    # Check that functions are exported
    type validate_dataset_name >/dev/null 2>&1
    type validate_path >/dev/null 2>&1
    type validate_positive_integer >/dev/null 2>&1
    type validate_non_negative_integer >/dev/null 2>&1
    type validate_integer_range >/dev/null 2>&1
    type validate_url >/dev/null 2>&1
    type validate_host >/dev/null 2>&1
    type validate_pool_exists >/dev/null 2>&1
    type validate_dataset_exists >/dev/null 2>&1
    type validate_snapshot_name >/dev/null 2>&1
    type validate_boolean >/dev/null 2>&1
    type validate_choice >/dev/null 2>&1
}
