# ZFS Error Handling Library

## Overview

The `zfs-error-handling.sh` library provides comprehensive error handling and recovery functions for ZFS management scripts. It implements robust error tracking, automatic retry logic with exponential backoff, dry-run mode support, and cleanup mechanisms.

## Features

- **Global Error Tracking**: Automatically counts and tracks all errors
- **Automatic Error Logging**: Logs errors to a separate error log file
- **Exponential Backoff Retry Logic**: Automatically retries failed commands with increasing delays
- **Dry-Run Mode Support**: Test commands without executing them
- **Exit Trap for Cleanup**: Automatically logs error summary on script exit
- **Comprehensive Error Context**: Provides detailed error messages with timestamps and error codes

## Installation

```bash
# Source the library in your script
source /path/to/lib/zfs-error-handling.sh
```

## Configuration

### Environment Variables

- `ZFS_ERROR_LOG` - Path to error log file (default: `/var/log/zfs-errors.log`)
- `DRY_RUN` - Set to "yes" to enable dry-run mode (default: "no")

## Functions

### Core Error Functions

#### `error()`

Logs an error message, increments error counter, and returns an error code.

```bash
error "Failed to create dataset" [error_code]
```

**Parameters:**
- `$1` - Error message (required)
- `$2` - Error code (optional, default: 1)

**Returns:** Error code

**Example:**
```bash
error "Failed to mount dataset" 2
# Returns: 2
# Logs: [2025-11-03 14:00:00] [ERROR 2] Failed to mount dataset
```

#### `safe_execute()`

Executes a command with error handling and logging.

```bash
safe_execute command [args...]
```

**Parameters:**
- `$@` - Command and arguments

**Returns:** Command exit code

**Example:**
```bash
if safe_execute zfs create tank/data; then
    echo "Dataset created successfully"
else
    echo "Failed to create dataset"
fi
```

#### `retry_execute()`

Executes a command with automatic retry and exponential backoff.

```bash
retry_execute max_attempts command [args...]
```

**Parameters:**
- `$1` - Maximum retry attempts (must be positive integer)
- `$2+` - Command and arguments

**Returns:** 0 on success, last exit code on failure

**Retry Schedule:**
- Attempt 1: Execute immediately
- Attempt 2: Wait 1 second
- Attempt 3: Wait 2 seconds
- Attempt 4: Wait 4 seconds
- Attempt 5: Wait 8 seconds
- etc. (2^(attempt-1) seconds)

**Example:**
```bash
# Retry up to 5 times
if retry_execute 5 curl https://api.example.com/status; then
    echo "API call succeeded"
else
    echo "API call failed after 5 attempts"
fi
```

#### `check_exit_code()`

Checks if a command succeeded and logs error if it failed.

```bash
check_exit_code exit_code "error message"
```

**Parameters:**
- `$1` - Exit code to check
- `$2` - Error message if failed

**Returns:** 0 if exit code is 0, 1 otherwise

**Example:**
```bash
some_command
exit_code=$?
if ! check_exit_code $exit_code "Command failed"; then
    # Handle error
    exit 1
fi
```

#### `require()`

Executes a command and exits the script if it fails.

```bash
require command [args...]
```

**Parameters:**
- `$@` - Command and arguments

**Returns:** Never returns on failure (exits script)

**Example:**
```bash
# Script will exit if this fails
require zpool import tank
# Continue only if successful
```

### Validation Functions

#### `require_file()`

Verifies that a file exists and is readable.

```bash
require_file "/path/to/file"
```

**Parameters:**
- `$1` - File path

**Returns:** 0 if valid, 1 otherwise

**Example:**
```bash
if require_file "/etc/zfs/zpool.cache"; then
    echo "Cache file found"
fi
```

#### `require_directory()`

Verifies that a directory exists and is writable.

```bash
require_directory "/path/to/directory"
```

**Parameters:**
- `$1` - Directory path

**Returns:** 0 if valid, 1 otherwise

**Example:**
```bash
if require_directory "/var/log"; then
    echo "Log directory is writable"
fi
```

#### `require_command()`

Verifies that a command exists in PATH.

```bash
require_command "command_name"
```

**Parameters:**
- `$1` - Command name

**Returns:** 0 if exists, 1 otherwise

**Example:**
```bash
require_command "zfs" || exit 1
require_command "zpool" || exit 1
echo "ZFS tools are available"
```

### Dry-Run Functions

#### `dry_run_execute()`

Executes a command or logs what would be executed in dry-run mode.

```bash
dry_run_execute command [args...]
```

**Parameters:**
- `$@` - Command and arguments

**Returns:** 0 in dry-run mode, command exit code otherwise

**Example:**
```bash
export DRY_RUN="yes"
dry_run_execute zfs destroy tank/data
# Output: DRY RUN: Would execute: zfs destroy tank/data
# Actual command is NOT executed

export DRY_RUN="no"
dry_run_execute zfs destroy tank/data
# Command IS executed
```

### Error Tracking Functions

#### `reset_error_count()`

Resets the error counter and clears last error message.

```bash
reset_error_count
```

**Example:**
```bash
reset_error_count
echo "Error count: $(get_error_count)"  # Output: 0
```

#### `get_error_count()`

Returns the current error count.

```bash
count=$(get_error_count)
```

**Returns:** Integer count

**Example:**
```bash
if [ "$(get_error_count)" -gt 0 ]; then
    echo "Errors occurred during execution"
fi
```

#### `get_last_error()`

Returns the last error message.

```bash
last_error=$(get_last_error)
```

**Returns:** Last error message string

**Example:**
```bash
if [ "$(get_error_count)" -gt 0 ]; then
    echo "Last error: $(get_last_error)"
fi
```

### Cleanup Functions

#### `cleanup_on_exit()`

Cleanup function that logs error summary on script exit.

```bash
# Automatically called via EXIT trap
# Can also define custom cleanup:
user_cleanup() {
    echo "Performing custom cleanup..."
    # Your cleanup code here
}
```

**Example:**
```bash
# The library automatically sets up EXIT trap
# Define custom cleanup if needed:
user_cleanup() {
    # Unmount temporary filesystems
    umount /mnt/temp 2>/dev/null || true
    # Remove temporary files
    rm -f /tmp/myapp-*
}
```

## Usage Examples

### Basic Error Handling

```bash
#!/bin/bash
source lib/zfs-error-handling.sh

# Set error log location
export ZFS_ERROR_LOG="/var/log/myscript-errors.log"

# Check for required commands
require_command "zfs" || exit 1
require_command "zpool" || exit 1

# Execute with error handling
if safe_execute zfs create tank/mydata; then
    echo "Dataset created"
else
    echo "Failed to create dataset"
    exit 1
fi

# Check error count at the end
if [ "$(get_error_count)" -gt 0 ]; then
    echo "Script completed with $(get_error_count) errors"
    exit 1
fi
```

### Retry with Exponential Backoff

```bash
#!/bin/bash
source lib/zfs-error-handling.sh

# Retry network operations
if retry_execute 5 curl -f https://example.com/config.json -o /tmp/config.json; then
    echo "Configuration downloaded"
else
    echo "Failed to download configuration after 5 attempts"
    exit 1
fi

# Retry ZFS operations
if retry_execute 3 zfs snapshot tank/data@backup-$(date +%Y%m%d); then
    echo "Snapshot created"
else
    echo "Failed to create snapshot after 3 attempts"
    exit 1
fi
```

### Dry-Run Mode

```bash
#!/bin/bash
source lib/zfs-error-handling.sh

# Enable dry-run mode
export DRY_RUN="yes"

# These commands will be logged but not executed
dry_run_execute zfs create tank/test
dry_run_execute zfs set compression=lz4 tank/test
dry_run_execute zfs snapshot tank/test@initial

echo "Dry-run completed. Set DRY_RUN=no to execute commands."
```

### Comprehensive Script Example

```bash
#!/bin/bash
set -euo pipefail

# Source error handling library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/zfs-error-handling.sh"

# Configuration
export ZFS_ERROR_LOG="/var/log/zfs-backup-errors.log"
export DRY_RUN="${DRY_RUN:-no}"

# Define custom cleanup
user_cleanup() {
    if [ -n "${TEMP_MOUNT:-}" ] && mountpoint -q "$TEMP_MOUNT"; then
        umount "$TEMP_MOUNT" 2>/dev/null || true
    fi
}

# Validate prerequisites
require_command "zfs" || exit 1
require_command "zpool" || exit 1
require_directory "/mnt/backup" || exit 1

# Reset error counter
reset_error_count

# Perform backup with error handling
echo "Starting ZFS backup..."

# Create snapshot with retry
if retry_execute 3 zfs snapshot tank/data@backup-$(date +%Y%m%d-%H%M%S); then
    echo "Snapshot created successfully"
else
    error "Failed to create snapshot"
    exit 1
fi

# Send snapshot to backup pool
if dry_run_execute zfs send tank/data@latest | \
   dry_run_execute zfs receive backup/data; then
    echo "Backup completed successfully"
else
    error "Backup failed"
    exit 1
fi

# Check for errors
if [ "$(get_error_count)" -gt 0 ]; then
    echo "ERROR: Backup completed with $(get_error_count) errors"
    echo "Last error: $(get_last_error)"
    exit 1
else
    echo "Backup completed successfully with no errors"
fi
```

## Error Log Format

The error log uses the following format:

```
[YYYY-MM-DD HH:MM:SS] [ERROR code] message
```

**Example:**
```
[2025-11-03 14:23:45] [ERROR 1] Failed to create dataset tank/data
[2025-11-03 14:23:50] [ERROR 2] Command failed after 5 attempts: curl https://api.example.com
[2025-11-03 14:24:00] [ERROR 1] Required file does not exist: /etc/config.conf
```

## Testing

The library includes a comprehensive test suite using BATS (Bash Automated Testing System).

### Running Tests

```bash
# Run all tests
bats tests/test-error-handling.bats

# Run specific test
bats --filter "retry_execute" tests/test-error-handling.bats
```

### Test Coverage

- ✅ Error function logs and increments counter
- ✅ Error function respects custom exit codes
- ✅ Error function creates log directory if missing
- ✅ Safe execute succeeds and fails appropriately
- ✅ Retry execute with exponential backoff
- ✅ Retry execute validates parameters
- ✅ Check exit code validation
- ✅ Command requirement validation
- ✅ File requirement validation
- ✅ Directory requirement validation
- ✅ Dry-run mode functionality
- ✅ Error counter reset and tracking
- ✅ Last error message tracking
- ✅ Error log timestamp and code format
- ✅ Multiple error sources tracking
- ✅ Pipefail setting compatibility

## Best Practices

1. **Always source the library at the beginning of your script**
   ```bash
   source lib/zfs-error-handling.sh
   ```

2. **Set error log location explicitly**
   ```bash
   export ZFS_ERROR_LOG="/var/log/myapp-errors.log"
   ```

3. **Check for required commands early**
   ```bash
   require_command "zfs" || exit 1
   require_command "zpool" || exit 1
   ```

4. **Use retry_execute for network operations**
   ```bash
   retry_execute 5 curl -f https://example.com/file
   ```

5. **Use dry_run_execute for destructive operations**
   ```bash
   dry_run_execute zfs destroy tank/old-data
   ```

6. **Always check error count at the end**
   ```bash
   if [ "$(get_error_count)" -gt 0 ]; then
       echo "Script failed with errors"
       exit 1
   fi
   ```

7. **Define custom cleanup if needed**
   ```bash
   user_cleanup() {
       # Your cleanup code
   }
   ```

8. **Use require() for critical operations**
   ```bash
   require zpool import tank
   ```

## Compatibility

- **Shell**: Bash 4.0+
- **Testing**: BATS 1.0+
- **OS**: Linux (Ubuntu, RHEL, etc.), FreeBSD, Solaris
- **ZFS**: OpenZFS 0.8+

## Integration with Other Libraries

The error handling library integrates seamlessly with other ZFS libraries:

```bash
# Load error handling first
source lib/zfs-error-handling.sh

# Then load other libraries
source lib/zfs-validation.sh
source lib/zfs-common.sh

# Error handling is automatically available to all functions
```

## Troubleshooting

### Error Log Not Created

**Problem:** Error log file is not being created.

**Solution:** Check that the parent directory exists and is writable:
```bash
export ZFS_ERROR_LOG="/var/log/app/errors.log"
mkdir -p /var/log/app
chmod 755 /var/log/app
```

### Errors Not Counted

**Problem:** Error count remains 0 even when errors occur.

**Solution:** Make sure to call error functions that increment the counter:
```bash
# This increments error count:
error "Something failed"

# This does NOT increment error count:
echo "ERROR: Something failed" >&2
```

### Retry Not Working

**Problem:** retry_execute doesn't retry commands.

**Solution:** Ensure max_attempts is a positive integer:
```bash
# Correct:
retry_execute 5 my_command

# Incorrect:
retry_execute "5" my_command  # String instead of integer
retry_execute 0 my_command    # Must be >= 1
```

## License

This library is part of the ZFS Management Scripts project. See the main README for license information.

## Support

For issues, questions, or contributions, please refer to the main project repository.
