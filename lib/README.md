# ZFS Management Libraries

This directory contains shared libraries used by the ZFS management scripts.

## Libraries Overview

| Library | Stream | Purpose | Functions |
|---------|--------|---------|-----------|
| `zfs-common.sh` | 4 | Common shared functions | 12 functions |
| `zfs-validation.sh` | 2 | Input validation | 12 validation functions |
| `zfs-error-handling.sh` | 3 | Error handling & recovery | 13 error functions |
| `zfs-locking.sh` | 6 | Race condition prevention | 15 locking functions |
| `zfs-transactions.sh` | 7 | Rollback & recovery | 9 transaction functions |

## zfs-common.sh

**Primary Owner:** Stream 4 - Architecture Specialist

**Purpose:** Common functions shared across all ZFS management scripts

**Functions Provided:**

| Function | Description | Arguments | Returns |
|----------|-------------|-----------|---------|
| `log_message` | Log messages with timestamp to file and stdout | `$1`: Level (INFO/WARNING/ERROR/SUCCESS)<br>`$2`: Message | 0 on success |
| `rotate_log` | Rotate log files when size exceeds limit | None (uses LOG_FILE, LOG_MAX_SIZE, LOG_MAX_FILES) | 0 on success, 1 on error |
| `send_notification` | Send Gotify notifications | `$1`: Message<br>`$2`: Level (success/error/info) | 0 on success, 1 on error |
| `is_zfs_dataset` | Check if path is a mounted ZFS dataset | `$1`: Mount point path | 0 if dataset, 1 if not |
| `get_dataset_for_path` | Get dataset name for a given path | `$1`: Path | Outputs dataset name; returns 0 if found, 1 if not |
| `normalize_name` | Convert German umlauts to ASCII | `$1`: String to normalize | Outputs normalized string |
| `format_bytes` | Convert bytes to human-readable format | `$1`: Size in bytes | Outputs formatted size (e.g., "1.5G") |
| `parse_size_to_bytes` | Parse size string to bytes | `$1`: Size string (e.g., "10M") | Outputs size in bytes |
| `require_root` | Check if running as root | None | 0 if root, 1 if not |
| `ensure_directory` | Create directory with parents if needed | `$1`: Directory path<br>`$2`: Permissions (optional, default 755) | 0 on success, 1 on error |
| `get_dataset_available_space` | Get available space for dataset | `$1`: Dataset name | Outputs bytes available; returns 0 on success, 1 on error |
| `get_dataset_used_space` | Get used space for dataset | `$1`: Dataset name | Outputs bytes used; returns 0 on success, 1 on error |

**Dependencies:**
- Optional: `zfs-validation.sh` (for enhanced validation)
- Optional: `zfs-error-handling.sh` (for enhanced error handling)

**Usage Example:**

```bash
#!/bin/bash

# Source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/zfs-common.sh"

# Set up logging
export LOG_FILE="/var/log/my-zfs-script.log"
export LOG_MAX_SIZE="10M"
export LOG_MAX_FILES=5

# Use the functions
log_message "INFO" "Script started"

# Check if running as root
if ! require_root; then
    exit 1
fi

# Normalize a name
normalized=$(normalize_name "Größe")
log_message "INFO" "Normalized name: $normalized"

# Format bytes
size=$(format_bytes "2147483648")
log_message "INFO" "Size: $size"

# Send notification
send_notification "Script completed successfully" "success"
```

**Documentation:** See `QUICKSTART_COMMON_LIBRARY.md` and `STREAM_4_REPORT.md`

## zfs-validation.sh

**Primary Owner:** Stream 2 - Validation Specialist

**Purpose:** Input validation functions for ZFS scripts

**Functions Provided:**

| Function | Description |
|----------|-------------|
| `validate_dataset_name` | Validate ZFS dataset name format |
| `validate_path` | Validate filesystem path (prevents traversal) |
| `validate_positive_integer` | Validate positive integer values |
| `validate_non_negative_integer` | Validate non-negative integer values |
| `validate_integer_range` | Validate integer within range |
| `validate_url` | Validate HTTP/HTTPS URL format |
| `validate_host` | Validate hostname or IP address |
| `validate_pool_exists` | Verify ZFS pool exists |
| `validate_dataset_exists` | Verify ZFS dataset exists |
| `validate_snapshot_name` | Validate snapshot name format |
| `validate_boolean` | Validate boolean values |
| `validate_choice` | Validate value from allowed list |

**Usage Example:**

```bash
source "$SCRIPT_DIR/lib/zfs-validation.sh"

# Validate user input
if ! validate_dataset_name "$USER_DATASET"; then
    echo "ERROR: Invalid dataset name" >&2
    exit 1
fi

# Validate path containment
if ! validate_path "$USER_PATH" "/mnt/tank"; then
    echo "ERROR: Path must be within /mnt/tank" >&2
    exit 1
fi
```

**Documentation:** See `STREAM_2_VALIDATION_REPORT.md`

## zfs-error-handling.sh

**Primary Owner:** Stream 3 - Reliability Specialist

**Purpose:** Error handling and recovery functions

**Functions Provided:**

| Function | Description |
|----------|-------------|
| `error` | Log error and increment counter |
| `safe_execute` | Execute command with error handling |
| `retry_execute` | Retry with exponential backoff |
| `check_exit_code` | Validate command exit codes |
| `require` | Fatal if command fails |
| `dry_run_execute` | Execute in dry-run mode |
| `require_file` | Verify file exists and is readable |
| `require_directory` | Verify directory exists and is writable |
| `require_command` | Verify command exists in PATH |
| `cleanup_on_exit` | Automatic cleanup on exit |
| `reset_error_count` | Reset error counter |
| `get_error_count` | Get current error count |
| `get_last_error` | Get last error message |

**Usage Example:**

```bash
source "$SCRIPT_DIR/lib/zfs-error-handling.sh"

# Execute with error handling
safe_execute zfs create tank/dataset

# Retry on failure
retry_execute 3 zfs snapshot tank/dataset@snap

# Require critical commands
require zfs list tank
```

**Documentation:** See `lib/ERROR_HANDLING.md` and `STREAM_3_ERROR_HANDLING_REPORT.md`

## zfs-locking.sh

**Primary Owner:** Stream 6 - Concurrency Specialist

**Purpose:** Provides locking mechanisms to prevent race conditions

**Functions Provided:**

| Function | Description |
|----------|-------------|
| `container_lock_acquire` | Acquire lock for Docker container |
| `container_lock_release` | Release container lock |
| `vm_lock_acquire` | Acquire lock for VM |
| `vm_lock_release` | Release VM lock |
| `dataset_lock_acquire` | Acquire lock for dataset |
| `dataset_lock_release` | Release dataset lock |
| `with_container_lock` | Helper for container operations |
| `with_vm_lock` | Helper for VM operations |
| `with_dataset_lock` | Helper for dataset operations |
| `acquire_lock` | Low-level lock acquisition |
| `release_lock` | Low-level lock release |
| `is_locked` | Check if resource is locked |
| `list_locks` | List all active locks |
| `cleanup_stale_locks` | Remove stale lock files |
| `cleanup_all_locks` | Cleanup on exit |

**Usage Example:**

```bash
source "$SCRIPT_DIR/lib/zfs-locking.sh"

# Acquire lock, perform operation, release lock
if lock_file=$(container_lock_acquire "$container_id" 10); then
    # Verify state after lock (TOCTOU protection)
    state=$(docker inspect --format '{{.State.Status}}' "$container_id")

    if [[ "$state" == "running" ]]; then
        # Perform operation
        docker stop "$container_id"
    fi

    # Release lock
    container_lock_release "$container_id"
else
    echo "Could not acquire lock for container $container_id"
fi
```

**Documentation:** See `LOCKING_STRATEGY.md` and `STREAM_6_REPORT.md`

## zfs-transactions.sh

**Primary Owner:** Stream 7 - Transaction Specialist

**Purpose:** Transaction state tracking and rollback capabilities

**Functions Provided:**

| Function | Description |
|----------|-------------|
| `transaction_start` | Start new transaction |
| `transaction_update_state` | Update transaction state |
| `transaction_complete` | Mark transaction complete |
| `transaction_fail` | Mark transaction failed |
| `transaction_rollback` | Rollback transaction |
| `transaction_get_info` | Query transaction details |
| `transaction_list_pending` | List pending transactions |
| `transaction_recover_all` | Automatic recovery |
| `transaction_cleanup` | Remove old transactions |

**Transaction States:**
```
INITIATED → RENAMED → DATASET_CREATED → RSYNC_STARTED →
RSYNC_COMPLETE → VALIDATED → COMPLETED
                          ↓ (failure)
                  FAILED / ROLLEDBACK
```

**Usage Example:**

```bash
source "$SCRIPT_DIR/lib/zfs-transactions.sh"

# Start transaction
tx_id=$(transaction_start "convert" "tank/dataset" "/mnt/tank/data" "/mnt/tank/data_temp")

# Update state at each step
transaction_update_state "$tx_id" "RENAMED"
# ... perform rename ...

transaction_update_state "$tx_id" "DATASET_CREATED"
# ... create dataset ...

# On success
transaction_complete "$tx_id"

# On failure
transaction_rollback "$tx_id"
```

**Documentation:** See `lib/TRANSACTIONS.md`, `TRANSACTION_QUICKREF.md`, and `STREAM_7_COMPLETION_REPORT.md`

## Integration Guide

### Migrating Existing Scripts

To migrate existing scripts to use the libraries:

1. **Source the libraries** at the top of your script:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

   # Core libraries
   source "$SCRIPT_DIR/lib/zfs-common.sh"
   source "$SCRIPT_DIR/lib/zfs-validation.sh"
   source "$SCRIPT_DIR/lib/zfs-error-handling.sh"

   # Optional: concurrency and transactions
   [[ -f "$SCRIPT_DIR/lib/zfs-locking.sh" ]] && source "$SCRIPT_DIR/lib/zfs-locking.sh"
   [[ -f "$SCRIPT_DIR/lib/zfs-transactions.sh" ]] && source "$SCRIPT_DIR/lib/zfs-transactions.sh"
   ```

2. **Remove duplicated functions** from your script

3. **Add input validation** to user-facing parameters

4. **Wrap operations** with error handling and locking

5. **Test thoroughly** to ensure no regressions

### Configuration Variables

Global variables respected by the libraries:

| Variable | Purpose | Default |
|----------|---------|---------|
| `LOG_FILE` | Path to log file | None (stdout only) |
| `LOG_MAX_SIZE` | Max log size before rotation | "10M" |
| `LOG_MAX_FILES` | Number of rotated logs to keep | 5 |
| `GOTIFY_SERVER_URL` | Gotify server URL | None |
| `GOTIFY_APP_TOKEN` | Gotify application token | None |
| `notification_type` | Notification level (all/error/none) | "all" |
| `DRY_RUN` | Dry run mode | "no" |
| `ZFS_ERROR_LOG` | Error log file path | "/var/log/zfs-errors.log" |

### Best Practices

1. **Always source libraries** before using their functions
2. **Set configuration variables** before calling functions
3. **Check return codes** for critical operations
4. **Use validation functions** for all user inputs
5. **Wrap operations** with error handling and locking
6. **Use transactions** for multi-step operations
7. **Test with DRY_RUN** before production use

## Testing

### Manual Testing

Run manual test scripts:

```bash
cd /home/user/zfs
./tests/manual-test-common.sh
```

### BATS Testing

Install BATS and run test suites:

```bash
# Install BATS
./tests/setup.sh

# Run all tests
bats tests/*.bats

# Run specific test suites
bats tests/test-common.bats
bats tests/test-validation.bats
bats tests/test-error-handling.bats
bats tests/test-race-conditions.bats
bats tests/test-transactions.bats
```

## Backward Compatibility

All libraries are designed to be backward compatible:

- Functions maintain the same signatures
- Libraries work independently (optional dependencies)
- No breaking changes to existing behavior
- Additional features are opt-in through configuration

## Troubleshooting

### Common Issues

**Issue:** Functions not available after sourcing

**Solution:** Ensure you're sourcing with `source` or `.`, not executing

```bash
# Correct
source lib/zfs-common.sh

# Incorrect
./lib/zfs-common.sh
```

**Issue:** Lock files not being created

**Solution:** Check that /var/run/zfs-locks directory exists and is writable

```bash
sudo mkdir -p /var/run/zfs-locks
sudo chmod 755 /var/run/zfs-locks
```

**Issue:** Transaction state files not persisting

**Solution:** Check that /var/lib/zfs-scripts/transactions directory exists

```bash
sudo mkdir -p /var/lib/zfs-scripts/transactions
sudo chmod 755 /var/lib/zfs-scripts/transactions
```

## Support

For issues, questions, or contributions:

1. Check the test suites for examples
2. Review implementation reports (STREAM_*_REPORT.md files)
3. See the code review: `CODE_REVIEW.md`
4. See the implementation plan: `IMPLEMENTATION_PLAN.md`

## License

These libraries are part of the ZFS management scripts collection and follow the same license as the parent project.
