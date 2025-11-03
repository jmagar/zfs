# Testing Documentation

This document provides an overview of the testing infrastructure and strategy for the ZFS management scripts.

## Quick Links

- **Detailed Testing Guide**: [tests/README.md](tests/README.md)
- **CI/CD Pipeline**: [.github/workflows/test.yml](.github/workflows/test.yml)
- **Implementation Plan**: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)

## Overview

The ZFS scripts project uses a comprehensive testing strategy with:
- **Unit Tests**: Test individual functions and components
- **Integration Tests**: Test complete workflows and interactions
- **CI/CD**: Automated testing on every push and pull request
- **Static Analysis**: ShellCheck for code quality

## Getting Started

### Setup Testing Environment

```bash
# Install BATS and test dependencies
cd tests/
./setup.sh

# Verify installation
bats --version
```

### Run Tests

```bash
# Run all tests
bats tests/

# Run specific test suite
bats tests/test-example.bats

# Run integration tests
bats tests/integration/

# Run with verbose output
bats --print-output-on-failure tests/
```

## Test Framework: BATS

We use **BATS (Bash Automated Testing System)** with the following extensions:
- `bats-support`: Enhanced test helpers
- `bats-assert`: Rich assertion library
- `bats-file`: File system assertions

### Example Test

```bash
#!/usr/bin/env bats

load 'test_helper/common'

@test "validate dataset name" {
    run validate_dataset_name "tank/data"
    assert_success
}

@test "reject invalid dataset name" {
    run validate_dataset_name "../etc/passwd"
    assert_failure
    assert_output --partial "Invalid"
}
```

## Test Structure

```
tests/
├── README.md                      # Comprehensive testing guide
├── setup.sh                       # Test environment setup
├── test_helper/                   # Helper libraries
│   ├── common.bash                # Common utilities
│   └── bats-*/                    # BATS helper libraries
├── test-*.bats                    # Unit tests
└── integration/                   # Integration tests
    └── test-*.bats
```

## Test Coverage Goals

| Component | Target Coverage | Priority |
|-----------|----------------|----------|
| Security fixes | 100% | Critical |
| Input validation | >90% | High |
| Error handling | >90% | High |
| Common functions | >80% | High |
| Integration workflows | >70% | Medium |

## CI/CD Pipeline

### Automated Testing

Tests run automatically on:
- Every push to main, develop, or feature branches
- Every pull request
- Manual workflow dispatch

### Test Jobs

1. **ShellCheck**: Static analysis of all scripts
2. **Syntax Check**: Bash syntax validation
3. **Unit Tests**: All unit test files
4. **Integration Tests (Mocked)**: Tests without real ZFS
5. **Integration Tests (Real ZFS)**: Tests with actual ZFS pool

### Viewing Results

- **GitHub Actions**: Check the "Actions" tab in the repository
- **Pull Requests**: Test results are commented automatically
- **Local**: Run tests before pushing

## Writing New Tests

### For New Functions

When adding a new function to a library:

1. Create test file: `tests/test-<library-name>.bats`
2. Write tests for:
   - Valid inputs (happy path)
   - Invalid inputs (error cases)
   - Edge cases (boundaries, empty values, etc.)
   - Error handling

### For Bug Fixes

When fixing a bug:

1. Write a test that reproduces the bug
2. Verify the test fails
3. Fix the bug
4. Verify the test passes
5. Commit both test and fix

### For New Features

When adding a new feature:

1. Write tests first (TDD approach recommended)
2. Implement the feature
3. Ensure all tests pass
4. Add integration tests for the complete workflow

## Test Helpers

Common test utilities are available in `tests/test_helper/common.bash`:

### File Operations
```bash
create_test_dir "dirname"              # Create temp directory
create_test_file "filename" "content"  # Create temp file
generate_test_data "/path" 10 5        # 10 files, 5KB each
```

### Command Mocking
```bash
mock_command "zfs" "echo 'mocked output'"
unmock_command "zfs"
```

### Conditional Execution
```bash
skip_if_not_root "Requires root"
skip_if_missing zfs "ZFS not installed"
skip_if_ci "Not suitable for CI"
```

### Assertions
```bash
assert_log_contains "pattern"
assert_directory_not_empty "/path"
assert_line_count "file.txt" 10
```

## Running Tests Locally

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get install bats git curl jq

# For ZFS integration tests (optional)
sudo apt-get install zfsutils-linux
```

### Basic Usage

```bash
# From project root
bats tests/

# Specific test file
bats tests/test-validation.bats

# With verbose output
bats --print-output-on-failure tests/

# Run as TAP format
bats --formatter tap tests/
```

### With Real ZFS

```bash
# Create test pool
sudo truncate -s 1G /tmp/test-pool.img
sudo zpool create test-pool /tmp/test-pool.img

# Run tests
sudo -E bats tests/integration/

# Cleanup
sudo zpool destroy test-pool
sudo rm /tmp/test-pool.img
```

## Debugging Tests

### View Test Output

```bash
# Show all output including from passing tests
bats --show-output-of-passing-tests tests/

# Show output only on failure
bats --print-output-on-failure tests/
```

### Debug Specific Test

```bash
# Run single test
bats tests/test-example.bats --filter "specific test name"

# Add debug output in test
@test "debug example" {
    echo "Debug info: $variable" >&3
    debug_var "variable"
}
```

### Check Test Artifacts

```bash
# View temp directories
ls -la /tmp/bats-*

# View log files
cat /tmp/bats-*/test.log

# View generated test data
ls -la /tmp/bats-*/test-data/
```

## Common Issues

### BATS Not Found

```bash
# Reinstall
cd tests && ./setup.sh
```

### Permission Denied

```bash
# Make scripts executable
chmod +x tests/*.bats tests/integration/*.bats

# Run with sudo if needed
sudo bats tests/integration/
```

### Tests Fail in CI but Pass Locally

- Check if test depends on local environment
- Use `skip_if_ci` for tests not suitable for CI
- Mock external dependencies

### ZFS Tests Skipped

- ZFS may not be available in all environments
- Tests will skip gracefully with appropriate message
- Install ZFS for full test coverage

## Best Practices

1. **One assertion per test**: Keep tests focused
2. **Descriptive names**: Test names should explain what they test
3. **Arrange-Act-Assert**: Follow this pattern
4. **Test isolation**: Tests should not depend on each other
5. **Fast tests**: Keep tests under 1 second when possible
6. **Mock expensive operations**: Use mocks for ZFS, Docker, etc.
7. **Clean up**: Always clean up in teardown functions

## Contributing

### Before Submitting PR

```bash
# Run all tests
bats tests/

# Run ShellCheck
shellcheck *.sh lib/*.sh

# Check syntax
bash -n *.sh lib/*.sh
```

### PR Requirements

- ✅ All tests must pass
- ✅ New code must have tests
- ✅ Coverage should not decrease
- ✅ ShellCheck warnings addressed
- ✅ Documentation updated

## Test Metrics

### Current Status

- **Total Tests**: 73 tests across 3 test files
- **Test Execution Time**: ~5 seconds
- **Test Success Rate**: 100% (with appropriate skips)

### Coverage Goals

- Stream 1 (Security): 100% coverage required
- Stream 2 (Validation): 90% coverage required
- Stream 3 (Error Handling): 90% coverage required
- Stream 4 (Common Library): 80% coverage required
- Stream 5 (Testing Infrastructure): Complete ✅

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [BATS GitHub](https://github.com/bats-core/bats-core)
- [ShellCheck](https://www.shellcheck.net/)
- [Test Helper Libraries](tests/test_helper/)
- [Detailed Testing Guide](tests/README.md)

## Support

For testing questions:
1. Check [tests/README.md](tests/README.md) for detailed documentation
2. Review example tests in `tests/test-example.bats`
3. Check CI logs in GitHub Actions
4. Review implementation plan for test requirements

## Future Enhancements

- [ ] Code coverage reporting with kcov
- [ ] Performance benchmarking
- [ ] Mutation testing
- [ ] Fuzz testing for input validation
- [ ] Load testing for large datasets
- [ ] Docker container for test environment
- [ ] Test result dashboard
