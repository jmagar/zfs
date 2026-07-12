# Quick Start Guide: ZFS Common Library

## For Script Developers

### Basic Usage

```bash
#!/bin/bash

# 1. Source the library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/zfs-common.sh"

# 2. Configure logging
export LOG_FILE="/var/log/my-script.log"
export LOG_MAX_SIZE="10M"
export LOG_MAX_FILES=5

# 3. Use the functions!
log_message "INFO" "Script started"

# Check if running as root
if ! require_root; then
    log_message "ERROR" "Must run as root"
    exit 1
fi

# Work with datasets
if is_zfs_dataset "/mnt/tank/data"; then
    log_message "INFO" "Path is a ZFS dataset"

    avail=$(get_dataset_available_space "tank/data")
    used=$(get_dataset_used_space "tank/data")

    log_message "INFO" "Available: $(format_bytes $avail)"
    log_message "INFO" "Used: $(format_bytes $used)"
fi

# Send notification
send_notification "Script completed successfully" "success"
```

## Available Functions

### Logging Functions

```bash
# Log a message
log_message "INFO" "This is an info message"
log_message "WARNING" "This is a warning"
log_message "ERROR" "This is an error"
log_message "SUCCESS" "Operation succeeded"

# Rotate logs (automatic when sourcing)
rotate_log

# Send Gotify notification
send_notification "Message text" "success"  # or "error"
```

### ZFS Functions

```bash
# Check if path is a ZFS dataset
if is_zfs_dataset "/mnt/tank/data"; then
    echo "It's a dataset!"
fi

# Get dataset name for a path
dataset=$(get_dataset_for_path "/mnt/tank/data")
echo "Dataset: $dataset"

# Get dataset space
avail=$(get_dataset_available_space "tank/data")
used=$(get_dataset_used_space "tank/data")
echo "Available: $avail bytes"
echo "Used: $used bytes"
```

### Utility Functions

```bash
# Normalize German umlauts
normalized=$(normalize_name "Größe")
echo "$normalized"  # Output: Groesse

# Format bytes to human-readable
size=$(format_bytes "2147483648")
echo "$size"  # Output: 2G

# Parse size string to bytes
bytes=$(parse_size_to_bytes "10M")
echo "$bytes"  # Output: 10485760

# Check if running as root
if require_root; then
    echo "Running as root"
fi

# Ensure directory exists
ensure_directory "/var/lib/myapp" "755"
```

## Configuration Variables

Set these before calling functions:

```bash
# Logging
export LOG_FILE="/var/log/zfs-scripts.log"
export LOG_MAX_SIZE="10M"         # 10 megabytes
export LOG_MAX_FILES=5            # Keep 5 rotated logs

# Gotify notifications
export GOTIFY_SERVER_URL="http://localhost:8080"
export GOTIFY_APP_TOKEN="your_token_here"
export notification_type="all"    # all, error, or none

# General
export DRY_RUN="no"               # yes or no
```

## Testing Your Script

```bash
# Enable dry run mode
export DRY_RUN="yes"

# Run your script
./your-script.sh

# Check the log
tail -f /var/log/zfs-scripts.log
```

## Common Patterns

### Error Handling

```bash
if ! some_operation; then
    log_message "ERROR" "Operation failed"
    send_notification "Critical error in script" "error"
    exit 1
fi
```

### Progress Logging

```bash
log_message "INFO" "Starting backup..."
# ... backup code ...
log_message "SUCCESS" "Backup completed"
send_notification "Backup finished successfully" "success"
```

### Space Checking

```bash
dataset="tank/data"
avail=$(get_dataset_available_space "$dataset")
required=$(parse_size_to_bytes "10G")

if [ "$avail" -lt "$required" ]; then
    log_message "ERROR" "Insufficient space. Need $(format_bytes $required), have $(format_bytes $avail)"
    exit 1
fi
```

## Troubleshooting

**Issue:** Functions not found
```bash
# Make sure you sourced, not executed
source lib/zfs-common.sh    # Correct
./lib/zfs-common.sh         # Wrong
```

**Issue:** Log file not created
```bash
# Check directory exists and is writable
mkdir -p $(dirname "$LOG_FILE")
chmod 755 $(dirname "$LOG_FILE")
```

**Issue:** Notifications not sending
```bash
# Test Gotify connection
curl -X POST "$GOTIFY_SERVER_URL/message" \
  -H "Content-Type: application/json" \
  -H "X-Gotify-Key: $GOTIFY_APP_TOKEN" \
  -d '{"title":"Test","message":"Test"}'
```

## Next Steps

- Read `lib/README.md` for complete documentation
- Review `STREAM_4_REPORT.md` for implementation details
- Check `tests/test-common.bats` for usage examples

## Quick Test

Run the manual test suite:
```bash
./tests/manual-test-common.sh
```

Expected output: All tests passing (17/17)
