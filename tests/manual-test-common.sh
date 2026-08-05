#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Manual Test Script for ZFS Common Library                            # #
# #   Run this to validate basic functionality without BATS                # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TEMP_DIR=$(mktemp -d)
export LOG_FILE="$TEST_TEMP_DIR/test.log"
export LOG_MAX_SIZE="10M"
export LOG_MAX_FILES=5

# Counter for tests
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result function
test_result() {
    local test_name="$1"
    local status=$2

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "========================================"
echo "ZFS Common Library Manual Tests"
echo "========================================"
echo ""

# Source the library
# shellcheck disable=SC1091 # runtime-resolved library, linted separately
source "$SCRIPT_DIR/lib/zfs-common.sh"

echo "Testing log_message function..."
echo "----------------------------------------"

# Test 1: log_message creates log file
log_message "INFO" "Test message"
if [ -f "$LOG_FILE" ] && grep -q "Test message" "$LOG_FILE"; then status=0; else status=1; fi
test_result "log_message creates log file and writes message" "$status"

# Test 2: log_message handles different levels
log_message "WARNING" "Warning test"
log_message "ERROR" "Error test"
log_message "SUCCESS" "Success test"
if grep -q "\[WARNING\]" "$LOG_FILE" && grep -q "\[ERROR\]" "$LOG_FILE" && grep -q "\[SUCCESS\]" "$LOG_FILE"; then status=0; else status=1; fi
test_result "log_message handles different log levels" "$status"

echo ""
echo "Testing normalize_name function..."
echo "----------------------------------------"

# Test 3: normalize_name with umlauts
result=$(normalize_name "Müller")
if [ "$result" = "Mueller" ]; then status=0; else status=1; fi
test_result "normalize_name converts ü to ue" "$status"

result=$(normalize_name "Größe")
if [ "$result" = "Groesse" ]; then status=0; else status=1; fi
test_result "normalize_name converts ö to oe" "$status"

result=$(normalize_name "Straße")
if [ "$result" = "Strasse" ]; then status=0; else status=1; fi
test_result "normalize_name converts ß to ss" "$status"

echo ""
echo "Testing format_bytes function..."
echo "----------------------------------------"

# Test 4: format_bytes
result=$(format_bytes "512")
if [ "$result" = "512B" ]; then status=0; else status=1; fi
test_result "format_bytes handles bytes" "$status"

result=$(format_bytes "2048")
if [ "$result" = "2K" ]; then status=0; else status=1; fi
test_result "format_bytes converts to kilobytes" "$status"

result=$(format_bytes "2097152")
if [ "$result" = "2M" ]; then status=0; else status=1; fi
test_result "format_bytes converts to megabytes" "$status"

result=$(format_bytes "2147483648")
if [ "$result" = "2G" ]; then status=0; else status=1; fi
test_result "format_bytes converts to gigabytes" "$status"

echo ""
echo "Testing parse_size_to_bytes function..."
echo "----------------------------------------"

# Test 5: parse_size_to_bytes
result=$(parse_size_to_bytes "1K")
if [ "$result" = "1024" ]; then status=0; else status=1; fi
test_result "parse_size_to_bytes converts kilobytes" "$status"

result=$(parse_size_to_bytes "1M")
if [ "$result" = "1048576" ]; then status=0; else status=1; fi
test_result "parse_size_to_bytes converts megabytes" "$status"

result=$(parse_size_to_bytes "1G")
if [ "$result" = "1073741824" ]; then status=0; else status=1; fi
test_result "parse_size_to_bytes converts gigabytes" "$status"

result=$(parse_size_to_bytes "12345")
if [ "$result" = "12345" ]; then status=0; else status=1; fi
test_result "parse_size_to_bytes handles plain numbers" "$status"

echo ""
echo "Testing ensure_directory function..."
echo "----------------------------------------"

# Test 6: ensure_directory
test_dir="$TEST_TEMP_DIR/new_test_dir"
ensure_directory "$test_dir" >/dev/null 2>&1
if [ -d "$test_dir" ]; then status=0; else status=1; fi
test_result "ensure_directory creates directory" "$status"

test_dir="$TEST_TEMP_DIR/nested/path/dir"
ensure_directory "$test_dir" >/dev/null 2>&1
if [ -d "$test_dir" ]; then status=0; else status=1; fi
test_result "ensure_directory creates nested directories" "$status"

echo ""
echo "Testing require_root function..."
echo "----------------------------------------"

# Test 7: require_root (expected to report failure when not root)
if [ "$EUID" -ne 0 ]; then
    if require_root >/dev/null 2>&1; then status=1; else status=0; fi
    test_result "require_root returns error for non-root" "$status"
else
    if require_root >/dev/null 2>&1; then status=0; else status=1; fi
    test_result "require_root succeeds for root" "$status"
fi

echo ""
echo "Testing function exports..."
echo "----------------------------------------"

# Test 8: Check all functions are available
if declare -F log_message >/dev/null && \
   declare -F rotate_log >/dev/null && \
   declare -F send_notification >/dev/null && \
   declare -F is_zfs_dataset >/dev/null && \
   declare -F get_dataset_for_path >/dev/null && \
   declare -F normalize_name >/dev/null && \
   declare -F format_bytes >/dev/null && \
   declare -F parse_size_to_bytes >/dev/null && \
   declare -F require_root >/dev/null && \
   declare -F ensure_directory >/dev/null && \
   declare -F get_dataset_available_space >/dev/null && \
   declare -F get_dataset_used_space >/dev/null; then status=0; else status=1; fi
test_result "All functions are exported and available" "$status"

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit_code=0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    exit_code=1
fi

# Cleanup
rm -rf "$TEST_TEMP_DIR"

exit $exit_code
