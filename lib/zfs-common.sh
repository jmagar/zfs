#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   ZFS Common Function Library                                           # #
# #   Shared functions used across multiple ZFS management scripts         # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# This library provides common functions used by:
#   - zfs-auto-datasets-ubuntu.sh
#   - zfs-replications-ubuntu.sh
#
# Functions provided:
#   - log_message: Log messages with timestamp
#   - rotate_log: Rotate log files when size exceeds limit
#   - send_notification: Send Gotify notifications
#   - is_zfs_dataset: Check if path is a ZFS dataset
#   - get_dataset_for_path: Get dataset name for a given path
#   - normalize_name: Normalize German umlauts to ASCII
#   - format_bytes: Convert bytes to human-readable format
#   - parse_size_to_bytes: Parse size string to bytes
#   - require_root: Check if running as root
#   - ensure_directory: Create directory with parents if needed
#   - get_dataset_available_space: Get available space for dataset
#   - get_dataset_used_space: Get used space for dataset

# Get the directory where this library is located
ZFS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies if available
# Note: These may not exist yet in Phase 1, so we check first
if [[ -f "$ZFS_LIB_DIR/zfs-validation.sh" ]]; then
    source "$ZFS_LIB_DIR/zfs-validation.sh"
fi

if [[ -f "$ZFS_LIB_DIR/zfs-error-handling.sh" ]]; then
    source "$ZFS_LIB_DIR/zfs-error-handling.sh"
fi

#######################################
# Log message with timestamp
# Logs to both file and stdout
# Globals:
#   LOG_FILE - Path to log file (optional)
# Arguments:
#   $1 - Level (INFO, WARNING, ERROR, SUCCESS)
#   $2 - Message
# Outputs:
#   Writes to log file and stdout
# Returns:
#   0 on success
#######################################
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Validate log file
    if [[ -n "${LOG_FILE:-}" ]]; then
        # Ensure log directory exists
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" 2>/dev/null || true
        fi

        # Write to log file
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Also print to stdout
    echo "[$level] $message"
}

#######################################
# Rotate log file if it exceeds max size
# Maintains multiple rotated log files
# Globals:
#   LOG_FILE - Path to log file
#   LOG_MAX_SIZE - Maximum size before rotation (default: 10M)
#   LOG_MAX_FILES - Number of rotated files to keep (default: 5)
# Returns:
#   0 on success, 1 on error
#######################################
rotate_log() {
    if [[ -z "${LOG_FILE:-}" || ! -f "$LOG_FILE" ]]; then
        return 0
    fi

    # Get file size
    local file_size
    if command -v stat >/dev/null 2>&1; then
        file_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    else
        file_size=$(ls -la "$LOG_FILE" 2>/dev/null | awk '{print $5}' || echo 0)
    fi

    # Convert LOG_MAX_SIZE to bytes (handles M, K, G suffixes)
    local max_bytes
    case "${LOG_MAX_SIZE:-10M}" in
        *M|*m) max_bytes=$((${LOG_MAX_SIZE%[Mm]} * 1024 * 1024)) ;;
        *K|*k) max_bytes=$((${LOG_MAX_SIZE%[Kk]} * 1024)) ;;
        *G|*g) max_bytes=$((${LOG_MAX_SIZE%[Gg]} * 1024 * 1024 * 1024)) ;;
        *) max_bytes="${LOG_MAX_SIZE:-10485760}" ;;
    esac

    # Check if rotation needed
    if [[ "$file_size" -le "$max_bytes" ]]; then
        return 0
    fi

    log_message "INFO" "Log file size ($file_size bytes) exceeds limit ($max_bytes bytes), rotating logs"

    # Validate we can rotate the log
    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    # Check if we have write permission to log directory
    if [[ ! -w "$log_dir" ]]; then
        echo "ERROR: No write permission to log directory: $log_dir" >&2
        return 1
    fi

    # Check if we have write permission to log file
    if [[ ! -w "$LOG_FILE" ]]; then
        echo "ERROR: No write permission to log file: $LOG_FILE" >&2
        return 1
    fi

    # Check available disk space (need at least 2x current log size)
    local required_space=$((file_size * 2))
    local available_space
    available_space=$(df -B1 "$log_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)

    if [[ "$available_space" -lt "$required_space" ]]; then
        echo "ERROR: Insufficient disk space for log rotation. Need: $required_space bytes, Available: $available_space bytes" >&2
        return 1
    fi

    # Rotate existing log files
    local max_files="${LOG_MAX_FILES:-5}"
    for ((i=max_files-1; i>=1; i--)); do
        if [[ -f "${LOG_FILE}.$i" ]]; then
            mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i+1))" 2>/dev/null || true
        fi
    done

    # Rotate current log
    if mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null; then
        touch "$LOG_FILE"
        chmod 640 "$LOG_FILE" 2>/dev/null || true
        log_message "INFO" "Log rotated - previous log saved as ${LOG_FILE}.1"
        return 0
    else
        echo "ERROR: Failed to rotate log file" >&2
        return 1
    fi
}

#######################################
# Send notification via Gotify
# Also logs the message via log_message
# Globals:
#   GOTIFY_SERVER_URL - Gotify server URL
#   GOTIFY_APP_TOKEN - Gotify application token
#   notification_type - Notification level (all/error/none)
# Arguments:
#   $1 - Message
#   $2 - Level (success|error|info)
# Returns:
#   0 on success, 1 on error
#######################################
send_notification() {
    local message="$1"
    local level="${2:-info}"

    # Log the message first
    case "$level" in
        "success") log_message "SUCCESS" "$message" ;;
        "error") log_message "ERROR" "$message" ;;
        *) log_message "INFO" "$message" ;;
    esac

    # Check notification settings
    local notif_type="${notification_type:-all}"
    if [[ "$notif_type" == "none" ]]; then
        return 0
    fi

    if [[ "$notif_type" == "error" && "$level" == "success" ]]; then
        return 0
    fi

    # Check if Gotify is configured
    if [[ -z "${GOTIFY_SERVER_URL:-}" || -z "${GOTIFY_APP_TOKEN:-}" ]]; then
        return 0
    fi

    # Validate Gotify URL (basic check - full validation requires zfs-validation.sh)
    if [[ ! "$GOTIFY_SERVER_URL" =~ ^https?:// ]]; then
        log_message "WARNING" "Invalid Gotify URL format, skipping notification"
        return 1
    fi

    # Determine priority
    local priority=5
    local title="ZFS Management"
    case "$level" in
        "success") priority=1 ;;
        "error") priority=8 ;;
    esac

    # Send notification
    # Use jq for safe JSON encoding to prevent injection
    if ! command -v jq >/dev/null 2>&1; then
        echo "WARNING: jq is required for safe notification delivery but is not installed" >&2
        echo "         Skipping notification. Install with: sudo apt install jq" >&2
        return 0  # Not a fatal error, just skip notification
    fi

    # Build JSON payload safely with jq
    local json_payload
    json_payload=$(jq -n \
        --arg title "$title" \
        --arg message "$message" \
        --argjson priority "$priority" \
        '{title: $title, message: $message, priority: $priority}') || {
        echo "ERROR: Failed to encode notification JSON" >&2
        return 1
    }

    if ! curl -s -S -X POST "$GOTIFY_SERVER_URL/message" \
            -H "Content-Type: application/json" \
            -H "X-Gotify-Key: $GOTIFY_APP_TOKEN" \
            -d "$json_payload" \
            >/dev/null 2>&1; then
        log_message "WARNING" "Failed to send Gotify notification"
        return 1
    fi

    return 0
}

#######################################
# Check if location is a mounted ZFS dataset
# Uses ZFS native commands to verify
# Arguments:
#   $1 - Mount point path
# Returns:
#   0 if ZFS dataset, 1 if not
#######################################
is_zfs_dataset() {
    local location="$1"

    # Validate input (basic check - full validation requires zfs-validation.sh)
    if [[ -z "$location" ]]; then
        return 1
    fi

    # Check if it's a ZFS dataset mountpoint
    # Using awk to avoid grep regex issues
    if zfs list -H -o name,mountpoint 2>/dev/null | awk -v loc="$location" '$2 == loc {exit 0} END {exit 1}'; then
        return 0
    else
        return 1
    fi
}

#######################################
# Get ZFS dataset for a given path
# Finds the dataset mounted at the specified path
# Arguments:
#   $1 - Path
# Outputs:
#   Dataset name if found
# Returns:
#   0 if found, 1 if not
#######################################
get_dataset_for_path() {
    local path="$1"

    # Validate input
    if [[ -z "$path" ]]; then
        return 1
    fi

    # Find matching dataset
    local dataset
    dataset=$(zfs list -H -o name,mountpoint 2>/dev/null | awk -v path="$path" '$2 == path {print $1; exit}')

    if [[ -n "$dataset" ]]; then
        echo "$dataset"
        return 0
    else
        return 1
    fi
}

#######################################
# Normalize German umlauts to ASCII
# Converts ä->ae, ö->oe, ü->ue, ß->ss
# Arguments:
#   $1 - String to normalize
# Outputs:
#   Normalized string
#######################################
normalize_name() {
    local original_name="$1"
    local normalized_name

    normalized_name=$(echo "$original_name" |
                     sed 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g;
                          s/Ä/AE/g; s/Ö/OE/g; s/Ü/UE/g;
                          s/ß/ss/g')

    echo "$normalized_name"
}

#######################################
# Format bytes to human-readable size
# Converts byte count to K, M, G, T, P
# Arguments:
#   $1 - Size in bytes
# Outputs:
#   Human-readable size (e.g., "1.5G")
#######################################
format_bytes() {
    local bytes="$1"

    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0B"
        return
    fi

    # Guard against values that would overflow bash arithmetic (signed 64-bit max)
    local max_bytes=9223372036854775807
    if (( bytes > max_bytes )); then
        bytes=$max_bytes
    fi

    local units=("B" "K" "M" "G" "T" "P")
    local unit=0
    local size=$bytes

    while (( size >= 1024 && unit < 5 )); do
        size=$((size / 1024))
        unit=$((unit + 1))
    done

    echo "${size}${units[$unit]}"
}

#######################################
# Parse size string to bytes
# Converts size with suffix to byte count
# Arguments:
#   $1 - Size string (e.g., "10M", "1G", "512K")
# Outputs:
#   Size in bytes
#######################################
parse_size_to_bytes() {
    local size_str="$1"

    # Extract the numeric prefix and validate it
    local num
    case "$size_str" in
        *B|*b) num="${size_str%[Bb]}" ;;
        *K|*k) num="${size_str%[Kk]}" ;;
        *M|*m) num="${size_str%[Mm]}" ;;
        *G|*g) num="${size_str%[Gg]}" ;;
        *T|*t) num="${size_str%[Tt]}" ;;
        *) num="$size_str" ;;
    esac

    # Validate that num is a non-negative integer
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Invalid size string '$size_str'" >&2
        echo 0
        return 1
    fi

    case "$size_str" in
        *B|*b) echo "$num" ;;
        *K|*k) echo "$((num * 1024))" ;;
        *M|*m) echo "$((num * 1024 * 1024))" ;;
        *G|*g) echo "$((num * 1024 * 1024 * 1024))" ;;
        *T|*t) echo "$((num * 1024 * 1024 * 1024 * 1024))" ;;
        *) echo "$num" ;;
    esac
}

#######################################
# Check if running as root
# Verifies EUID is 0
# Returns:
#   0 if root, 1 if not
#######################################
require_root() {
    if [[ $EUID -ne 0 ]]; then
        # Use error function if available from zfs-error-handling.sh
        if declare -F error >/dev/null 2>&1; then
            error "This script must be run as root"
        else
            echo "ERROR: This script must be run as root" >&2
        fi
        return 1
    fi
    return 0
}

#######################################
# Create directory with parents if needed
# Creates directory and sets permissions
# Arguments:
#   $1 - Directory path
#   $2 - Permissions (optional, default 755)
# Returns:
#   0 on success, 1 on error
#######################################
ensure_directory() {
    local dir="$1"
    local perms="${2:-755}"

    if [[ -d "$dir" ]]; then
        return 0
    fi

    if mkdir -p "$dir" 2>/dev/null; then
        chmod "$perms" "$dir" 2>/dev/null || true
        log_message "INFO" "Created directory: $dir"
        return 0
    else
        # Use error function if available
        if declare -F error >/dev/null 2>&1; then
            error "Failed to create directory: $dir"
        else
            log_message "ERROR" "Failed to create directory: $dir"
        fi
        return 1
    fi
}

#######################################
# Get available space for ZFS dataset
# Queries ZFS for available space in bytes
# Arguments:
#   $1 - Dataset name
# Outputs:
#   Available space in bytes
# Returns:
#   0 on success, 1 on error
#######################################
get_dataset_available_space() {
    local dataset="$1"

    # Basic validation
    if [[ -z "$dataset" ]]; then
        return 1
    fi

    # Check if dataset exists
    if ! zfs list -H "$dataset" &>/dev/null; then
        return 1
    fi

    local avail
    avail=$(zfs list -H -o avail -p "$dataset" 2>/dev/null)

    if [[ -n "$avail" ]]; then
        echo "$avail"
        return 0
    else
        return 1
    fi
}

#######################################
# Get used space for ZFS dataset
# Queries ZFS for used space in bytes
# Arguments:
#   $1 - Dataset name
# Outputs:
#   Used space in bytes
# Returns:
#   0 on success, 1 on error
#######################################
get_dataset_used_space() {
    local dataset="$1"

    # Basic validation
    if [[ -z "$dataset" ]]; then
        return 1
    fi

    # Check if dataset exists
    if ! zfs list -H "$dataset" &>/dev/null; then
        return 1
    fi

    local used
    used=$(zfs list -H -o used -p "$dataset" 2>/dev/null)

    if [[ -n "$used" ]]; then
        echo "$used"
        return 0
    else
        return 1
    fi
}

#######################################
# Verify SSH host key fingerprint for secure remote connections
# Globals:
#   None
# Arguments:
#   $1 - Server hostname or IP (may include port, e.g. "host:2222")
#   $2 - Expected fingerprint (e.g., "SHA256:...")
#   $3 - SSH port (optional, default 22; overridden by host:port in $1)
# Returns:
#   0 if fingerprint matches or verification skipped (empty expected)
#   1 on mismatch or error
# Outputs:
#   Error messages to stderr
#######################################
verify_ssh_fingerprint() {
    local server="$1"
    local expected_fingerprint="$2"
    local port="${3:-22}"

    # Extract port from server if specified as host:port
    if [[ "$server" == *:* ]]; then
        port="${server##*:}"
        server="${server%:*}"
    fi

    # Skip verification if no fingerprint provided
    if [[ -z "$expected_fingerprint" ]]; then
        return 0
    fi

    # Validate expected fingerprint format
    if [[ "$expected_fingerprint" != SHA256:* && "$expected_fingerprint" != MD5:* ]]; then
        echo "ERROR: Invalid fingerprint format '$expected_fingerprint' (expected SHA256:... or MD5:...)" >&2
        return 1
    fi

    # Check if ssh-keyscan and ssh-keygen are available
    if ! command -v ssh-keyscan >/dev/null 2>&1 || ! command -v ssh-keygen >/dev/null 2>&1; then
        echo "WARNING: ssh-keyscan or ssh-keygen not available, skipping fingerprint verification" >&2
        return 0
    fi

    # Get actual fingerprint (use -p for non-standard ports, -t to limit key types)
    local actual_fingerprint
    actual_fingerprint=$(ssh-keyscan -p "$port" -t rsa,ed25519 -H "$server" 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' | head -n1)

    if [[ -z "$actual_fingerprint" ]]; then
        echo "ERROR: Failed to retrieve SSH fingerprint from $server:$port" >&2
        echo "  Check that the server is reachable and SSH is running on port $port" >&2
        return 1
    fi

    if [[ "$actual_fingerprint" != "$expected_fingerprint" ]]; then
        echo "ERROR: SSH host key fingerprint mismatch for $server:$port" >&2
        echo "  Expected: $expected_fingerprint" >&2
        echo "  Actual:   $actual_fingerprint" >&2
        echo "  This could indicate a man-in-the-middle attack or server reinstallation" >&2
        echo "  Update REMOTE_SSH_FINGERPRINT in config if server was legitimately changed" >&2
        return 1
    fi

    log_message "INFO" "SSH host key fingerprint verified for $server:$port"
    return 0
}

# Export common functions for use by sourcing scripts
export -f log_message
export -f rotate_log
export -f send_notification
export -f is_zfs_dataset
export -f get_dataset_for_path
export -f normalize_name
export -f format_bytes
export -f parse_size_to_bytes
export -f require_root
export -f ensure_directory
export -f get_dataset_available_space
export -f get_dataset_used_space
export -f verify_ssh_fingerprint
