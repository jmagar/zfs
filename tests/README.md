# ZFS Scripts - Testing Framework

This directory contains the testing infrastructure for the ZFS management scripts, including unit tests, integration tests, and CI/CD configuration.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Test Structure](#test-structure)
- [Writing Tests](#writing-tests)
- [Running Tests](#running-tests)
- [CI/CD Pipeline](#cicd-pipeline)
- [Test Helpers](#test-helpers)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

### Testing Framework: BATS

We use **BATS (Bash Automated Testing System)** for all our tests:
- **BATS Core**: Main testing framework
- **bats-support**: Enhanced assertions and helpers
- **bats-assert**: Rich assertion library
- **bats-file**: File system assertions

### Test Types

1. **Unit Tests** (`test-*.bats`): Test individual functions and components
2. **Integration Tests** (`integration/*.bats`): Test complete workflows
3. **Syntax Tests**: Validate bash syntax (via CI/CD)
4. **ShellCheck**: Static analysis for shell scripts (via CI/CD)

## Quick Start

### Installation

```bash
# Run the setup script to install BATS and dependencies
cd tests/
chmod +x setup.sh
./setup.sh
```

### Run All Tests

```bash
# From project root
bats tests/

# Run specific test file
bats tests/test-example.bats

# Run integration tests only
bats tests/integration/
```

### Run with Verbose Output

```bash
# Show all output (including passing tests)
bats --print-output-on-failure tests/

# Tap format (for CI/CD)
bats --formatter tap tests/
```

## Test Structure

```
tests/
├── README.md                          # This file
├── setup.sh                           # Test environment setup script
├── test_helper/                       # Helper libraries
│   ├── common.bash                    # Common test utilities
│   ├── bats-support/                  # Assertion helpers (git submodule)
│   ├── bats-assert/                   # Assertion library (git submodule)
│   └── bats-file/                     # File assertions (git submodule)
├── test-example.bats                  # Example tests showing syntax
├── test-common-functions.bats         # Tests for lib/zfs-common.sh
├── test-validation.bats               # Tests for lib/zfs-validation.sh (future)
├── test-error-handling.bats           # Tests for lib/zfs-error-handling.sh (future)
├── test-security.bats                 # Security vulnerability tests (future)
├── integration/                       # Integration tests
│   ├── test-basic-workflow.bats       # End-to-end workflow tests
│   ├── test-dataset-conversion.bats   # Dataset converter integration (future)
│   └── test-replication.bats          # Replication integration (future)
├── fixtures/                          # Test data and fixtures
└── mocks/                            # Mock commands and data
```

## Writing Tests

### Basic Test Structure

```bash
#!/usr/bin/env bats

# Load common helpers
load 'test_helper/common'

@test "description of what this tests" {
    # Arrange
    local test_var="value"

    # Act
    run some_command "$test_var"

    # Assert
    assert_success
    assert_output "expected output"
}
```

### Test Lifecycle

```bash
setup_file() {
    # Run ONCE before all tests in this file
    export TEST_TEMP_DIR="${BATS_FILE_TMPDIR}"
    export LOG_FILE="$TEST_TEMP_DIR/test.log"
}

teardown_file() {
    # Run ONCE after all tests in this file
    rm -rf "$TEST_TEMP_DIR"
}

setup() {
    # Run BEFORE EACH test
    > "$LOG_FILE"  # Clear log
}

teardown() {
    # Run AFTER EACH test
    # Cleanup test-specific resources
}
```

### Common Assertions

```bash
# Status assertions
assert_success          # Command exit code = 0
assert_failure          # Command exit code ≠ 0
[ "$status" -eq 0 ]     # Explicit status check

# Output assertions
assert_output "exact"                # Exact match
assert_output --partial "substring"  # Contains substring
assert_output --regexp "pattern"     # Regex match

# File assertions
assert_file_exist "/path/to/file"
assert_dir_exist "/path/to/dir"
assert_file_not_exist "/path/to/file"

# Line assertions
[ "${#lines[@]}" -eq 3 ]           # Line count
[ "${lines[0]}" = "first line" ]   # Specific line
```

### Using Test Helpers

```bash
@test "helper functions" {
    # Create test directory
    local dir=$(create_test_dir "my-test")

    # Create test file
    local file=$(create_test_file "test.txt" "content")

    # Generate test data
    generate_test_data "$dir" 10 5  # 10 files, 5KB each

    # Mock commands
    mock_command "zfs" "echo 'mocked output'"

    # Log assertions
    assert_log_contains "pattern"
    assert_log_not_contains "error"
}
```

### Conditional Tests

```bash
@test "skip if not root" {
    skip_if_not_root "This test requires root"
    # Test continues only if root
}

@test "skip if missing command" {
    skip_if_missing zfs "ZFS not installed"
    # Test continues only if zfs available
}

@test "skip in CI" {
    skip_if_ci "Test not suitable for CI"
    # Test continues only in local environment
}
```

### Testing with Real ZFS

```bash
@test "ZFS operations" {
    skip_if_not_root
    skip_if_missing zfs

    # Check for test pool
    if ! zpool list test-pool >/dev/null 2>&1; then
        skip "Test pool not available"
    fi

    # Perform ZFS operations
    run zfs create test-pool/test-dataset
    assert_success

    # Cleanup
    run zfs destroy test-pool/test-dataset
}
```

## Running Tests

### Local Development

```bash
# Run all tests
bats tests/

# Run specific category
bats tests/test-validation.bats
bats tests/integration/

# Watch mode (requires entr)
ls tests/*.bats | entr -c bats /_

# With coverage (if using kcov)
kcov --exclude-pattern=/usr coverage/ bats tests/
```

### CI/CD Environment

Tests run automatically on:
- Push to main, develop, or feature branches
- Pull requests to main or develop
- Manual workflow dispatch

```bash
# Simulate CI locally
CI=true bats tests/

# Run with same setup as CI
./tests/setup.sh
bats tests/
```

## CI/CD Pipeline

### Workflow Overview

The GitHub Actions workflow (`.github/workflows/test.yml`) includes:

1. **ShellCheck**: Static analysis of all shell scripts
2. **Syntax Check**: Bash syntax validation
3. **Unit Tests**: Run all unit tests
4. **Integration Tests (No ZFS)**: Integration tests with mocked ZFS
5. **Integration Tests (With ZFS)**: Integration tests with real ZFS pool
6. **Test Summary**: Aggregate results and report

### Test Artifacts

Test results are uploaded as artifacts:
- `unit-test-results`: Unit test logs and results
- `integration-test-results-no-zfs`: Integration test logs (mocked)
- `integration-test-results-with-zfs`: Integration test logs (real ZFS)

Artifacts are retained for 7 days.

### Success Criteria

For a build to pass:
- ✅ ShellCheck must pass (no warnings)
- ✅ All shell scripts must have valid syntax
- ✅ All unit tests must pass
- ⚠️ Integration tests are informational (may fail if ZFS unavailable)

## Test Helpers

### Common Helpers (test_helper/common.bash)

#### File Operations
- `create_test_dir(name)`: Create temporary test directory
- `create_test_file(name, content)`: Create temporary test file
- `generate_test_data(dir, num_files, size_kb)`: Generate random test files

#### Command Mocking
- `mock_command(name, script)`: Create mock command
- `unmock_command(name)`: Remove mock command

#### Conditional Execution
- `skip_if_missing(cmd)`: Skip if command not available
- `skip_if_not_root()`: Skip if not running as root
- `skip_if_ci()`: Skip in CI environment
- `is_ci()`: Check if running in CI

#### Assertions
- `assert_log_contains(pattern, file)`: Check log contains pattern
- `assert_log_not_contains(pattern, file)`: Check log doesn't contain pattern
- `count_log_pattern(pattern, file)`: Count pattern occurrences
- `assert_directory_not_empty(dir)`: Check directory has contents
- `assert_line_count(file, count)`: Check file has exact line count

#### ZFS Helpers
- `has_zfs()`: Check if ZFS is available
- `create_mock_zfs_pool(name, size)`: Create test ZFS pool
- `destroy_mock_zfs_pool(name)`: Destroy test ZFS pool

#### Utilities
- `safe_source(path)`: Source library file safely
- `test_section(title)`: Print section header
- `debug_var(name)`: Print variable value for debugging

## Best Practices

### Test Organization

1. **One concept per test**: Each test should verify one thing
2. **Clear test names**: Use descriptive names that explain what's being tested
3. **AAA Pattern**: Arrange, Act, Assert
4. **Test isolation**: Tests should not depend on each other
5. **Clean up**: Always clean up resources in teardown

### Test Coverage

Aim for:
- **>80%** coverage for new code
- **100%** coverage for critical paths (security, data integrity)
- **Edge cases**: Test boundary conditions
- **Error paths**: Test failure scenarios

### Performance

- Keep tests fast (< 1 second per test ideally)
- Use mocks for expensive operations
- Skip slow tests in CI if needed
- Generate minimal test data

### Debugging Tests

```bash
# Run single test with debug output
bats --print-output-on-failure tests/test-example.bats

# Add debug output in test
@test "debug example" {
    echo "Debug: variable = $variable" >&3
    debug_var "variable"
}

# Check test temp files
ls -la /tmp/bats-*

# View log files
cat "$TEST_TEMP_DIR/test.log"
```

## Troubleshooting

### BATS Not Found

```bash
# Reinstall BATS
./tests/setup.sh

# Or manually
sudo apt-get install bats
```

### Test Helpers Not Loaded

```bash
# Ensure test helpers are cloned
cd tests/test_helper/
ls -la

# Re-run setup if missing
cd ..
./setup.sh
```

### Permission Denied

```bash
# Make setup script executable
chmod +x tests/setup.sh

# Run tests requiring root with sudo
sudo bats tests/integration/
```

### ZFS Not Available

```bash
# Check if ZFS is installed
which zfs zpool

# Install ZFS (Ubuntu)
sudo apt-get install zfsutils-linux

# Load ZFS module
sudo modprobe zfs
```

### Tests Timing Out

```bash
# Increase timeout in test
run timeout 60 some_long_command

# Or skip slow tests
skip "This test takes too long"
```

### Mock Commands Not Working

```bash
# Check mock directory in PATH
echo $PATH | grep -q "$TEST_TEMP_DIR/mocks" && echo "OK" || echo "NOT IN PATH"

# Verify mock is executable
ls -la "$TEST_TEMP_DIR/mocks/"

# Check mock content
cat "$TEST_TEMP_DIR/mocks/command-name"
```

## Examples

### Example 1: Testing a Validation Function

```bash
@test "validate_dataset_name accepts valid names" {
    source lib/zfs-validation.sh

    run validate_dataset_name "tank/data"
    assert_success
}

@test "validate_dataset_name rejects invalid names" {
    source lib/zfs-validation.sh

    run validate_dataset_name "../etc/passwd"
    assert_failure
    assert_output --partial "Invalid"
}
```

### Example 2: Integration Test with Mocks

```bash
@test "integration: dataset conversion workflow" {
    # Mock ZFS commands
    mock_command "zfs" "echo 'tank/data  /mnt/tank/data'"
    mock_command "docker" "echo 'container1'"

    export DRY_RUN="yes"

    # Run converter script
    run "$PROJECT_ROOT/zfs-auto-datasets-ubuntu.sh"

    assert_success
    assert_log_contains "DRY RUN"
}
```

### Example 3: Testing Error Handling

```bash
@test "script handles missing ZFS gracefully" {
    # Remove zfs from PATH
    PATH="/usr/bin:/bin"

    run "$PROJECT_ROOT/zfs-auto-datasets-ubuntu.sh"

    assert_failure
    assert_output --partial "ZFS not found"
}
```

## Contributing

When adding new functionality:

1. Write tests first (TDD approach preferred)
2. Ensure all tests pass: `bats tests/`
3. Check code quality: `shellcheck *.sh`
4. Verify CI passes on your branch
5. Aim for >80% test coverage

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [bats-core GitHub](https://github.com/bats-core/bats-core)
- [bats-assert](https://github.com/bats-core/bats-assert)
- [bats-support](https://github.com/bats-core/bats-support)
- [bats-file](https://github.com/bats-core/bats-file)
- [ShellCheck](https://www.shellcheck.net/)

## License

Same as parent project.
