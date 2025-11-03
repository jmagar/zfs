# ZFS Common Libraries

This directory contains shared libraries used by the ZFS management scripts.

## Libraries

### zfs-common.sh

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

### zfs-validation.sh

**Primary Owner:** Stream 2 - Validation Specialist

**Purpose:** Input validation functions for ZFS scripts

### zfs-error-handling.sh

**Primary Owner:** Stream 3 - Reliability Specialist

**Purpose:** Error handling and recovery functions

## Integration Guide

### Migrating Existing Scripts

To migrate existing scripts to use the common library:

1. **Source the library** at the top of your script:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "$SCRIPT_DIR/lib/zfs-common.sh"
   ```

2. **Remove duplicated functions** from your script:
   - `log_message()`
   - `rotate_log()`
   - `send_notification()`
   - `is_zfs_dataset()`
   - `normalize_name()`

3. **Update function calls** if needed (most should work as-is)

4. **Test thoroughly** to ensure no regressions

### Configuration Variables

The common library respects these global variables:

| Variable | Purpose | Default |
|----------|---------|---------|
| `LOG_FILE` | Path to log file | None (stdout only) |
| `LOG_MAX_SIZE` | Max log size before rotation | "10M" |
| `LOG_MAX_FILES` | Number of rotated logs to keep | 5 |
| `GOTIFY_SERVER_URL` | Gotify server URL | None |
| `GOTIFY_APP_TOKEN` | Gotify application token | None |
| `notification_type` | Notification level (all/error/none) | "all" |
| `DRY_RUN` | Dry run mode | "no" |

### Error Handling

Functions in the common library follow these conventions:

- **Return codes:** 0 for success, 1 for error
- **Output:** Error messages go to stderr, data output to stdout
- **Logging:** All functions that can log will use `log_message` if available
- **Graceful degradation:** Functions work even if optional dependencies are missing

### Best Practices

1. **Always source the library** before using its functions
2. **Set configuration variables** before calling functions that depend on them
3. **Check return codes** for critical operations
4. **Use log_message** consistently throughout your scripts
5. **Export functions** if you need them available in subshells

### Testing

#### Manual Testing

Run the manual test script:

```bash
cd /home/user/zfs
./tests/manual-test-common.sh
```

#### BATS Testing

Install BATS and run the test suite:

```bash
# Install BATS
sudo apt install bats

# Run tests
bats tests/test-common.bats
```

#### Integration Testing

Test with actual ZFS operations:

```bash
# Create a test pool (requires root)
sudo truncate -s 1G /tmp/test-pool.img
sudo zpool create test-pool /tmp/test-pool.img
sudo zfs create test-pool/data

# Source library and test functions
source lib/zfs-common.sh
is_zfs_dataset "/test-pool"
get_dataset_available_space "test-pool/data"

# Cleanup
sudo zpool destroy test-pool
sudo rm /tmp/test-pool.img
```

## Backward Compatibility

The common library is designed to be backward compatible with existing scripts:

- All functions maintain the same signatures as the original implementations
- Functions work without dependencies (graceful degradation)
- No breaking changes to existing behavior
- Additional features are opt-in through configuration variables

## Future Enhancements

Planned improvements for the common library:

1. **Enhanced error handling** - Integration with zfs-error-handling.sh for retry logic
2. **Input validation** - Integration with zfs-validation.sh for parameter validation
3. **Performance monitoring** - Add timing and performance metrics
4. **Structured logging** - Support for JSON log format
5. **Remote logging** - Support for sending logs to remote syslog servers

## Troubleshooting

### Common Issues

**Issue:** Functions not available after sourcing

**Solution:** Ensure you're sourcing with `source` or `.`, not executing the script

```bash
# Correct
source lib/zfs-common.sh

# Incorrect
./lib/zfs-common.sh
```

**Issue:** Log file not being created

**Solution:** Check that LOG_FILE is set and the directory exists and is writable

```bash
export LOG_FILE="/var/log/zfs-scripts.log"
mkdir -p $(dirname "$LOG_FILE")
chmod 755 $(dirname "$LOG_FILE")
```

**Issue:** Notifications not being sent

**Solution:** Check Gotify configuration and network connectivity

```bash
# Test Gotify connection
curl -X POST "$GOTIFY_SERVER_URL/message" \
  -H "Content-Type: application/json" \
  -H "X-Gotify-Key: $GOTIFY_APP_TOKEN" \
  -d '{"title":"Test","message":"Test message","priority":5}'
```

## Support

For issues, questions, or contributions related to the common library:

1. Check the test suite for examples: `tests/test-common.bats`
2. Review the implementation plan: `IMPLEMENTATION_PLAN.md`
3. See the code review: `CODE_REVIEW.md`

## License

This library is part of the ZFS management scripts collection and follows the same license as the parent project.
