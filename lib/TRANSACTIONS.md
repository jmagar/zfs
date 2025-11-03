# ZFS Transaction Management Library

**Version:** 1.0.0
**Author:** Stream 7 - Transaction Specialist
**Date:** 2025-11-03

## Overview

The ZFS Transaction Management Library provides robust state tracking and rollback capabilities for non-atomic dataset conversion operations. It ensures data integrity by tracking each step of the conversion process and enabling recovery from failures at any point.

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Architecture](#solution-architecture)
3. [Transaction States](#transaction-states)
4. [API Reference](#api-reference)
5. [Usage Examples](#usage-examples)
6. [Recovery Procedures](#recovery-procedures)
7. [Testing](#testing)
8. [Troubleshooting](#troubleshooting)
9. [Performance Considerations](#performance-considerations)

---

## Problem Statement

Dataset conversion in `zfs-auto-datasets-ubuntu.sh` involves multiple steps:

1. Rename directory to `_temp`
2. Create ZFS dataset
3. Rsync data to dataset
4. Validate data integrity
5. Delete temporary directory

If the system crashes, loses power, or the script is terminated between any of these steps, data can be left in an inconsistent state with no automatic recovery mechanism.

### Risk Scenarios

- **Power Loss During Rsync:** Original data is in `_temp`, new dataset partially populated
- **Script Termination After Dataset Creation:** Dataset exists but is empty, data in `_temp`
- **Crash After Validation:** Data is safe but temp directory remains, wasting space
- **Multiple Failures:** Previous partial conversions prevent new conversions

---

## Solution Architecture

### Core Components

1. **State Files:** JSON files tracking transaction progress
2. **Atomic Writes:** All state updates use atomic rename operations
3. **Lock Files:** Prevent concurrent modifications to same transaction
4. **Recovery Engine:** Automatic detection and recovery of partial conversions

### State File Location

```
/var/lib/zfs-scripts/transactions/
├── tx_20251103_143022_12345.json
├── tx_20251103_143045_67890.json
└── ...
```

### Lock File Location

```
/var/run/zfs-scripts/locks/
├── tx_20251103_143022_12345.lock
└── ...
```

---

## Transaction States

### State Diagram

```
INITIATED → RENAMED → DATASET_CREATED → RSYNC_STARTED →
RSYNC_COMPLETE → VALIDATED → COMPLETED
                                   ↓
                            (any failure)
                                   ↓
                           FAILED / ROLLEDBACK
```

### State Descriptions

| State | Description | Rollback Action |
|-------|-------------|-----------------|
| `INITIATED` | Transaction created, no filesystem changes | None needed |
| `RENAMED` | Directory renamed to `_temp` | Restore original name |
| `DATASET_CREATED` | ZFS dataset created | Destroy dataset, restore directory |
| `RSYNC_STARTED` | Data copy initiated | Destroy dataset, restore directory |
| `RSYNC_COMPLETE` | Data copy finished, not yet validated | Destroy dataset, restore directory |
| `VALIDATED` | Data verified, ready for cleanup | Forward recovery - complete cleanup |
| `COMPLETED` | Transaction finished successfully | No action |
| `FAILED` | Transaction failed, needs attention | Attempt cleanup |
| `ROLLEDBACK` | Transaction rolled back successfully | No action |

### State File Format

```json
{
  "transaction_id": "tx_20251103_143022_12345",
  "operation": "convert",
  "dataset_name": "tank/data/appdata",
  "source_path": "/mnt/tank/data/appdata",
  "temp_path": "/mnt/tank/data/appdata_temp",
  "state": "RSYNC_COMPLETE",
  "created_at": "2025-11-03T14:30:22.123Z",
  "updated_at": "2025-11-03T14:35:18.456Z",
  "pid": 12345,
  "hostname": "zfs-server",
  "dry_run": "no",
  "error_message": ""
}
```

---

## API Reference

### transaction_start

Start a new transaction.

**Syntax:**
```bash
transaction_start <operation> <dataset_name> <source_path> <temp_path>
```

**Parameters:**
- `operation` - Operation type (e.g., "convert")
- `dataset_name` - Full ZFS dataset name (e.g., "tank/data/appdata")
- `source_path` - Original directory path
- `temp_path` - Temporary directory path (with `_temp` suffix)

**Returns:**
- Transaction ID on success
- Empty string and exit code 1 on failure

**Example:**
```bash
tx_id=$(transaction_start "convert" "tank/data/appdata" \
    "/mnt/tank/data/appdata" "/mnt/tank/data/appdata_temp")

if [[ -z "$tx_id" ]]; then
    echo "Failed to start transaction"
    exit 1
fi
```

---

### transaction_update_state

Update transaction state.

**Syntax:**
```bash
transaction_update_state <tx_id> <new_state> [error_message]
```

**Parameters:**
- `tx_id` - Transaction ID
- `new_state` - New state (see [Transaction States](#transaction-states))
- `error_message` - Optional error message (for FAILED state)

**Returns:**
- Exit code 0 on success, 1 on failure

**Example:**
```bash
if ! transaction_update_state "$tx_id" "RENAMED"; then
    echo "Failed to update transaction state"
    transaction_fail "$tx_id" "State update failed"
    exit 1
fi
```

---

### transaction_complete

Mark transaction as completed.

**Syntax:**
```bash
transaction_complete <tx_id>
```

**Parameters:**
- `tx_id` - Transaction ID

**Returns:**
- Exit code 0 on success, 1 on failure

**Example:**
```bash
transaction_complete "$tx_id"
log_message "SUCCESS" "Transaction $tx_id completed successfully"
```

---

### transaction_fail

Mark transaction as failed.

**Syntax:**
```bash
transaction_fail <tx_id> <error_message>
```

**Parameters:**
- `tx_id` - Transaction ID
- `error_message` - Description of the failure

**Returns:**
- Exit code 0 on success, 1 on failure

**Example:**
```bash
if ! zfs create "$dataset_name"; then
    transaction_fail "$tx_id" "Failed to create ZFS dataset"
    return 1
fi
```

---

### transaction_rollback

Rollback a transaction to its original state.

**Syntax:**
```bash
transaction_rollback <tx_id>
```

**Parameters:**
- `tx_id` - Transaction ID

**Returns:**
- Exit code 0 on success, 1 on failure

**Behavior:**
- Automatically determines appropriate rollback action based on current state
- For `VALIDATED` state, performs forward recovery instead of rollback
- Skips rollback for already completed or rolled back transactions

**Example:**
```bash
if ! rsync -a "$source/" "$dest/"; then
    transaction_fail "$tx_id" "Rsync failed"
    transaction_rollback "$tx_id"
    exit 1
fi
```

---

### transaction_get_info

Get transaction information.

**Syntax:**
```bash
transaction_get_info <tx_id> [field]
```

**Parameters:**
- `tx_id` - Transaction ID
- `field` - Optional field name (returns full JSON if omitted)

**Returns:**
- Field value or full JSON on success
- Exit code 1 on failure

**Example:**
```bash
# Get full transaction info
info=$(transaction_get_info "$tx_id")

# Get specific field
state=$(transaction_get_info "$tx_id" "state")
dataset=$(transaction_get_info "$tx_id" "dataset_name")
```

---

### transaction_list_pending

List all pending transactions.

**Syntax:**
```bash
transaction_list_pending
```

**Parameters:**
- None

**Returns:**
- List of pending transactions (one per line)
- Message if no pending transactions found

**Output Format:**
```
tx_20251103_143022_12345 | State: RENAMED | Dataset: tank/data/appdata | Created: 2025-11-03T14:30:22.123Z
tx_20251103_143045_67890 | State: RSYNC_COMPLETE | Dataset: tank/data/vms | Created: 2025-11-03T14:30:45.456Z
```

**Example:**
```bash
echo "Pending transactions:"
transaction_list_pending
```

---

### transaction_recover_all

Recover all pending transactions.

**Syntax:**
```bash
transaction_recover_all
```

**Parameters:**
- None

**Returns:**
- Exit code 0 on success

**Behavior:**
- Scans all transaction state files
- Skips already completed or rolled back transactions
- Performs forward recovery for `VALIDATED` state
- Performs rollback for all other pending states
- Logs recovery actions and results

**Example:**
```bash
echo "Scanning for partial conversions..."
transaction_recover_all
```

---

### transaction_cleanup

Clean up old transaction files.

**Syntax:**
```bash
transaction_cleanup [age_days]
```

**Parameters:**
- `age_days` - Age in days (default: 30)

**Returns:**
- Exit code 0 on success

**Behavior:**
- Removes transaction state files older than specified age
- Only removes files in `COMPLETED` or `ROLLEDBACK` state
- Preserves all pending transactions regardless of age

**Example:**
```bash
# Clean up transactions older than 30 days (default)
transaction_cleanup

# Clean up transactions older than 7 days
transaction_cleanup 7
```

---

## Usage Examples

### Basic Usage in create_datasets Function

```bash
create_dataset_with_transaction() {
    local dataset_name="$1"
    local source_path="$2"
    local temp_path="${source_path}_temp"

    # Start transaction
    local tx_id=$(transaction_start "convert" "$dataset_name" "$source_path" "$temp_path")
    if [[ -z "$tx_id" ]]; then
        log_message "ERROR" "Failed to start transaction"
        return 1
    fi

    # Step 1: Rename directory
    if ! mv "$source_path" "$temp_path"; then
        transaction_fail "$tx_id" "Failed to rename directory"
        return 1
    fi
    transaction_update_state "$tx_id" "RENAMED"

    # Step 2: Create dataset
    if ! zfs create "$dataset_name"; then
        transaction_fail "$tx_id" "Failed to create dataset"
        transaction_rollback "$tx_id"
        return 1
    fi
    transaction_update_state "$tx_id" "DATASET_CREATED"

    # Step 3: Copy data
    transaction_update_state "$tx_id" "RSYNC_STARTED"
    if ! rsync -a "$temp_path/" "$source_path/"; then
        transaction_fail "$tx_id" "Rsync failed"
        transaction_rollback "$tx_id"
        return 1
    fi
    transaction_update_state "$tx_id" "RSYNC_COMPLETE"

    # Step 4: Validate
    if validate_data "$temp_path" "$source_path"; then
        transaction_update_state "$tx_id" "VALIDATED"

        # Step 5: Cleanup
        rm -rf "$temp_path"
        transaction_complete "$tx_id"
        return 0
    else
        transaction_fail "$tx_id" "Validation failed"
        transaction_rollback "$tx_id"
        return 1
    fi
}
```

### Recovery on Script Startup

```bash
#!/bin/bash

# Source transaction library
source lib/zfs-transactions.sh

# Recover partial conversions before starting new work
recover_partial_conversions() {
    log_message "INFO" "Checking for partial conversions..."

    transaction_recover_all

    log_message "INFO" "Recovery check completed"
}

# Main execution
main() {
    recover_partial_conversions

    # Continue with normal operations
    perform_conversions
}

main "$@"
```

### Manual Recovery

```bash
#!/bin/bash
# manual-recovery.sh - Manually recover specific transaction

source lib/zfs-transactions.sh

if [[ -z "$1" ]]; then
    echo "Usage: $0 <transaction_id>"
    echo ""
    echo "Available pending transactions:"
    transaction_list_pending
    exit 1
fi

tx_id="$1"

echo "Transaction info:"
transaction_get_info "$tx_id"
echo ""

read -p "Rollback this transaction? (y/n): " answer
if [[ "$answer" == "y" ]]; then
    echo "Rolling back transaction $tx_id..."
    if transaction_rollback "$tx_id"; then
        echo "Rollback successful"
    else
        echo "Rollback failed - check logs"
        exit 1
    fi
fi
```

---

## Recovery Procedures

### Automatic Recovery

Automatic recovery is performed on script startup via the `recover_partial_conversions()` function. This scans all transaction state files and takes appropriate action:

1. **VALIDATED state** - Forward recovery (complete cleanup)
2. **Other pending states** - Rollback to original state
3. **Final states** - Skip (already completed or rolled back)

### Manual Recovery Scenarios

#### Scenario 1: Power Loss During Conversion

**Symptoms:**
- Directory exists with `_temp` suffix
- New dataset may or may not exist
- Data may be partially copied

**Recovery Steps:**

```bash
# List pending transactions
transaction_list_pending

# Get transaction details
transaction_get_info <tx_id>

# Check filesystem state
ls -la /mnt/tank/data/
zfs list | grep <dataset_name>

# Rollback transaction
transaction_rollback <tx_id>

# Verify recovery
ls -la /mnt/tank/data/
```

#### Scenario 2: Validation Failure

**Symptoms:**
- Transaction in `RSYNC_COMPLETE` or `VALIDATED` state
- Both dataset and temp directory exist
- Data counts don't match

**Recovery Steps:**

```bash
# Get transaction info
transaction_get_info <tx_id>

# Manual verification
diff -r <temp_path> <dataset_path>

# If data is bad, rollback
transaction_rollback <tx_id>

# If data is good, complete manually
transaction_update_state <tx_id> "VALIDATED"
transaction_complete <tx_id>
rm -rf <temp_path>
```

#### Scenario 3: Multiple Failed Conversions

**Symptoms:**
- Many pending transactions
- Disk space issues from temp directories
- Can't determine which are safe to rollback

**Recovery Steps:**

```bash
# List all pending transactions
transaction_list_pending > pending.txt

# Review each transaction
while read line; do
    tx_id=$(echo "$line" | awk '{print $1}')

    echo "=== Transaction: $tx_id ==="
    transaction_get_info "$tx_id"

    # Check filesystem state
    source_path=$(transaction_get_info "$tx_id" "source_path")
    temp_path=$(transaction_get_info "$tx_id" "temp_path")

    echo "Source: $source_path"
    ls -ld "$source_path" 2>/dev/null || echo "Not found"

    echo "Temp: $temp_path"
    ls -ld "$temp_path" 2>/dev/null || echo "Not found"

    echo ""
done < pending.txt

# Recover all automatically
transaction_recover_all
```

#### Scenario 4: Corrupted State File

**Symptoms:**
- Transaction functions fail with JSON errors
- State file unreadable
- Transaction appears stuck

**Recovery Steps:**

```bash
# Backup the corrupted file
cp /var/lib/zfs-scripts/transactions/<tx_id>.json \
   /root/backup-<tx_id>.json

# Manually inspect filesystem
tx_id="<tx_id>"
# Extract paths from backup if possible, or determine manually
source_path="/mnt/tank/data/appdata"
temp_path="/mnt/tank/data/appdata_temp"
dataset_name="tank/data/appdata"

# Manual recovery based on filesystem state
if [[ -d "$temp_path" && ! -d "$source_path" ]]; then
    # Rollback: restore original name
    mv "$temp_path" "$source_path"
elif [[ -d "$temp_path" && -d "$source_path" ]]; then
    # Dataset exists, check which has data
    source_size=$(du -sb "$source_path" | cut -f1)
    temp_size=$(du -sb "$temp_path" | cut -f1)

    if [[ $source_size -gt 0 ]]; then
        # Data in dataset, safe to remove temp
        rm -rf "$temp_path"
    else
        # Data in temp, rollback
        zfs destroy "$dataset_name"
        rm -rf "$source_path"
        mv "$temp_path" "$source_path"
    fi
fi

# Remove corrupted state file
rm /var/lib/zfs-scripts/transactions/<tx_id>.json
```

---

## Testing

### Running Tests

```bash
# Install BATS if not already installed
sudo apt-get install bats

# Run transaction tests
bats tests/test-transactions.bats

# Run specific test
bats tests/test-transactions.bats -f "rollback from RENAMED"

# Run with verbose output
bats tests/test-transactions.bats --verbose
```

### Test Coverage

The test suite covers:

- ✅ Transaction creation and validation
- ✅ State updates and tracking
- ✅ Completion and failure marking
- ✅ Info retrieval
- ✅ Rollback from each state
- ✅ Forward recovery from VALIDATED state
- ✅ Pending transaction listing
- ✅ Automatic recovery
- ✅ Cleanup of old transactions
- ✅ Concurrent transaction handling
- ✅ Dry run mode
- ✅ Atomic state file updates
- ✅ Error handling
- ✅ Complete workflow scenarios

### Manual Testing

```bash
# Test transaction creation
tx_id=$(transaction_start "test" "tank/test" "/mnt/tank/test" "/mnt/tank/test_temp")
echo "Created: $tx_id"

# Test state updates
transaction_update_state "$tx_id" "RENAMED"
transaction_update_state "$tx_id" "DATASET_CREATED"
transaction_get_info "$tx_id" "state"

# Test rollback
transaction_rollback "$tx_id"
transaction_get_info "$tx_id" "state"

# Test listing
transaction_list_pending

# Test cleanup
transaction_cleanup 0  # Clean up all completed transactions
```

---

## Troubleshooting

### Common Issues

#### Issue: Transaction functions not found

**Symptoms:**
```
bash: transaction_start: command not found
```

**Solution:**
```bash
# Ensure transaction library is sourced
source /path/to/lib/zfs-transactions.sh

# Or add to script header
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/zfs-transactions.sh"
```

#### Issue: State directory not writable

**Symptoms:**
```
ERROR: Failed to create transaction state directory: /var/lib/zfs-scripts/transactions
```

**Solution:**
```bash
# Create directory with proper permissions
sudo mkdir -p /var/lib/zfs-scripts/transactions
sudo chmod 700 /var/lib/zfs-scripts/transactions
sudo chown $USER:$USER /var/lib/zfs-scripts/transactions

# Or run script as root
sudo ./zfs-auto-datasets-ubuntu.sh
```

#### Issue: Lock timeout

**Symptoms:**
```
ERROR: Failed to acquire lock for transaction tx_XXX (timeout)
```

**Solution:**
```bash
# Check for stale locks
ls -la /var/run/zfs-scripts/locks/

# Remove stale locks (check PID first)
lock_file="/var/run/zfs-scripts/locks/tx_XXX.lock"
pid=$(cat "$lock_file")
if ! ps -p "$pid" > /dev/null; then
    rm "$lock_file"
fi

# Or clear all locks (if no scripts running)
rm -rf /var/run/zfs-scripts/locks/*.lock
```

#### Issue: jq not found (JSON parsing)

**Symptoms:**
Library works but with warnings about jq not being available.

**Solution:**
```bash
# Install jq for better JSON parsing
sudo apt-get install jq

# Or library will fall back to sed/grep (less reliable)
```

### Debug Mode

Enable debug logging:

```bash
# Set before sourcing library
export TX_DEBUG=1
source lib/zfs-transactions.sh

# Or add to library temporarily
set -x  # Enable bash tracing
```

### Log Files

Check log files for transaction operations:

```bash
# Main script log
tail -f /var/log/zfs-scripts.log

# Error log (if using error handling library)
tail -f /var/log/zfs-errors.log

# Transaction-specific logs
grep "Transaction" /var/log/zfs-scripts.log
```

---

## Performance Considerations

### State File I/O

- State files are small (typically < 1KB)
- Atomic writes use temporary file + rename
- Minimal overhead: ~1-2ms per state update
- Lock acquisition typically < 10ms

### Recovery Performance

- Recovery scans all state files in `TX_STATE_DIR`
- With 100 pending transactions: ~1-2 seconds
- With 1000 pending transactions: ~5-10 seconds
- Recommendation: Run cleanup regularly to limit state files

### Optimization Tips

1. **Cleanup Schedule:** Run `transaction_cleanup` daily to remove old completed transactions

```bash
# Add to cron
0 2 * * * /path/to/cleanup-script.sh
```

```bash
#!/bin/bash
# cleanup-script.sh
source /path/to/lib/zfs-transactions.sh
transaction_cleanup 30
```

2. **State Directory Location:** Use fast storage (SSD) for state directory
3. **Lock Directory:** Lock directory should be on fast local filesystem (not NFS)

4. **Parallel Operations:** Avoid running multiple conversion scripts simultaneously

---

## Security Considerations

### State File Permissions

State files are created with mode 600 (owner read/write only):

```bash
-rw------- 1 root root 512 Nov 3 14:30 tx_20251103_143022_12345.json
```

### Sensitive Information

State files contain:
- Dataset names
- File paths
- Hostnames
- Process IDs

**Do not expose state directory to untrusted users.**

### Lock File Security

Lock files contain only the PID of the owning process. However, ensure lock directory permissions prevent unauthorized modifications:

```bash
chmod 700 /var/run/zfs-scripts/locks
```

---

## Future Enhancements

Potential improvements for future versions:

1. **Transaction Journal:** Write-ahead log for additional safety
2. **Distributed Locking:** Support for distributed/cluster setups
3. **Retry Logic:** Automatic retry with exponential backoff
4. **Notification Integration:** Alert on failed transactions
5. **Metrics Export:** Prometheus-compatible metrics
6. **Transaction History:** Archive completed transactions for audit
7. **Compression Support:** Compress old state files
8. **Remote State Storage:** Store state files on remote server

---

## Support and Contributing

### Getting Help

- Check troubleshooting section above
- Review test suite for usage examples
- Check main script logs for error details

### Reporting Issues

When reporting issues, include:

1. Transaction ID (if applicable)
2. Current state: `transaction_get_info <tx_id>`
3. Filesystem state: `ls -la <paths>`
4. ZFS state: `zfs list` output
5. Log excerpts
6. Steps to reproduce

### Contributing

To contribute improvements:

1. Add tests for new functionality
2. Update documentation
3. Ensure backward compatibility
4. Test rollback scenarios
5. Submit patch with detailed description

---

## References

- ZFS Documentation: https://openzfs.github.io/openzfs-docs/
- Bash Best Practices: https://mywiki.wooledge.org/BashGuide
- Atomic Operations: https://en.wikipedia.org/wiki/Atomicity_(database_systems)

---

**Last Updated:** 2025-11-03
**Version:** 1.0.0
**Maintainer:** Stream 7 - Transaction Specialist
