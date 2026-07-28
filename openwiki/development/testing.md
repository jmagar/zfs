---
type: development-process
title: Testing Strategy and Framework
description: Comprehensive testing approach using BATS framework with unit tests, integration tests, and CI/CD automation
tags: [testing, bats, ci-cd, automation, quality-assurance]
---

# Testing Strategy

The ZFS management scripts use a comprehensive testing strategy based on the BATS (Bash Automated Testing System) framework, covering unit tests, integration tests, and automated CI/CD pipelines.

## Test Framework

### BATS (Bash Automated Testing System)

BATS is the primary testing framework, chosen for:
- Native bash testing (same language as scripts)
- readable test syntax
- Good integration with CI/CD
- Easy to write and maintain

### Test Organization

```
tests/
├── README.md                    # Testing documentation
├── setup.sh                     # Test environment setup
├── test-common-functions.bats   # Common library tests
├── test-error-handling.bats     # Error handling tests
├── test-race-conditions.bats    # Locking and race condition tests
├── test-security.bats           # Security and validation tests
├── test-transactions.bats       # Transaction system tests
├── test-validation.bats         # Validation function tests
├── test-example.bats            # Example test template
├── integration/
│   └── test-basic-workflow.bats # End-to-end workflow test
└── test_helper/
    └── common.bash              # Test helpers and fixtures
```

## Running Tests

### Setup Test Environment

```bash
cd tests/
./setup.sh
```

This installs:
- BATS framework
- Required test dependencies
- Test helper files

### Run All Tests

```bash
# From repository root
bats tests/

# With verbose output
bats --print-output-on-failure tests/

# Specific test file
bats tests/test-example.bats

# Integration tests only
bats tests/integration/
```

### CI/CD Pipeline

Automated testing runs on:
- Every push to main branch
- Every pull request
- Scheduled runs (if configured)

See **[.github/workflows/test.yml](/.github/workflows/test.yml)** for pipeline configuration.

## Test Categories

### Unit Tests

Individual function and component testing:

**test-common-functions.bats**
- Logging functions (`log_message`, `rotate_log`)
- Notification functions (`send_notification`)
- ZFS helpers (`is_zfs_dataset`, `get_dataset_for_path`)
- Utility functions (`format_bytes`, `parse_size_to_bytes`)

**test-validation.bats**
- Path validation (`validate_path`)
- URL validation (`validate_url`)
- Dataset name validation (`validate_dataset_name`)
- Integer and choice validation

**test-error-handling.bats**
- Error tracking (`track_error`, `get_error_count`)
- Cleanup callbacks
- Exit trap behavior

**test-transactions.bats**
- Transaction lifecycle (start, update, complete, rollback)
- State transitions
- Forward recovery
- Transaction storage

**test-race-conditions.bats**
- Lock acquisition and release
- Lock timeout behavior
- Concurrent operation safety

**test-security.bats**
- Path traversal prevention
- Command injection prevention
- Input sanitization

### Integration Tests

Complete workflow testing:

**integration/test-basic-workflow.bats**
- End-to-end dataset conversion
- Transaction completion
- Service management
- Notification delivery

## Writing Tests

### Test File Template

```bats
#!/usr/bin/env bats
# Test file description

setup() {
    # Setup code (runs before each test)
    source "$SCRIPT_DIR/lib/zfs-common.sh"
}

teardown() {
    # Cleanup code (runs after each test)
}

@test "Example test case" {
    # Arrange
    local input="test_value"

    # Act
    local result=$(some_function "$input")

    # Assert
    [ "$result" = "expected_value" ]
}

@test "Another test case" {
    # Test code here
    run some_command
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "expected output" ]
}
```

### Test Helper Functions

Available in `test_helper/common.bash`:

```bash
# Mock ZFS dataset
mock_zfs_dataset "tank/data" "/mnt/tank/data"

# Mock docker container
mock_docker_container "plex" "/mnt/tank/appdata/plex"

# Create test directory
create_test_directory "/tmp/test_data"

# Cleanup test resources
cleanup_test_resources
```

### Best Practices

1. **Isolation** - Each test should be independent
2. **Cleanup** - Use `teardown()` for cleanup
3. **Mocking** - Mock external dependencies (ZFS, Docker)
4. **Assertions** - Use clear, specific assertions
5. **Documentation** - Comment complex test scenarios

## CI/CD Configuration

### GitHub Actions Workflow

The `.github/workflows/test.yml` defines:

```yaml
name: Test Suite

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: sudo apt-get install bats zfsutils-linux
      - name: Run tests
        run: bats tests/
```

### Test Environments

- **Unit tests** - Run in standard Ubuntu environment
- **Integration tests** - May require ZFS pool (can be mocked)
- **Security tests** - Run in isolated environment

### Status Badges

Add to README.md:

```markdown
![Test Status](https://github.com/user/repo/actions/workflows/test.yml/badge.svg)
```

## Coverage

### Current Coverage Areas

- ✅ Common library functions
- ✅ Validation functions
- ✅ Error handling
- ✅ Transaction system
- ✅ Locking mechanism
- ✅ Security inputs
- ⚠️ Integration workflows (in progress)

### Coverage Goals

- **Libraries**: >90% coverage target
- **Main Scripts**: >70% coverage target
- **Error Paths**: All error paths tested
- **Edge Cases**: Common edge cases covered

## Debugging Failed Tests

### Verbose Output

```bash
bats --print-output-on-failure tests/test-example.bats
```

### Trace Execution

```bash
bats --trace tests/test-example.bats
```

### Single Test

```bash
bats --filter "test name" tests/test-example.bats
```

### Inspect Test Environment

```bash
# List test files
find tests/ -name "*.bats"

# Check test helper
cat tests/test_helper/common.bash

# Run setup manually
cd tests && ./setup.sh
```

## Test Data Management

### Fixtures

Test fixtures stored in `tests/fixtures/`:

```bash
tests/fixtures/
├── sample-config.sh       # Sample configuration
├── test-dataset-data/     # Mock ZFS data
└── expected-outputs/      # Expected test results
```

### Temporary Files

Tests use `/tmp/bats-test-$$` for temporary files:

```bash
TMP_DIR="/tmp/bats-test-$$"
mkdir -p "$TMP_DIR"
# Use $TMP_DIR in tests
```

## Continuous Improvement

### Adding Tests

When adding new functionality:

1. Write tests first (TDD approach when possible)
2. Ensure all edge cases covered
3. Test error paths
4. Document test purpose in comments

### Test Maintenance

- Update tests when functionality changes
- Remove tests for deprecated features
- Keep tests readable and maintainable
- Review and refactor test code

## Documentation

- **[TESTING.md](/TESTING.md)** - Detailed testing guide
- **[tests/README.md](/tests/README.md)** - Test suite documentation
- **[BATS Documentation](https://bats-core.readthedocs.io/)** - Official BATS docs

## Source Files

- **[.github/workflows/test.yml](/.github/workflows/test.yml)** - CI/CD pipeline
- **[tests/setup.sh](/tests/setup.sh)** - Test environment setup
- **[tests/test_helper/common.bash](/tests/test_helper/common.bash)** - Test helpers
- **Test files** - `tests/test-*.bats`

## Related Documentation

- [Code Quality](../development/code-quality.md) - Code review findings
- [Library Overview](../libraries/overview.md) - Tested library components
