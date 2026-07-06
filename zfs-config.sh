#!/bin/bash
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# #   Shared configuration file for ZFS management scripts                                                                              # #
# #   Source this file in both zfs-auto-datasets.sh and zfs-replications.sh                                                          # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# ---------------------------------------
# LIBRARY DEPENDENCIES
# ---------------------------------------

# Get the directory where this config file is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source validation library
if [[ -f "$SCRIPT_DIR/lib/zfs-validation.sh" ]]; then
    source "$SCRIPT_DIR/lib/zfs-validation.sh"
else
    echo "WARNING: Cannot find lib/zfs-validation.sh - validation will be limited" >&2
    # Define minimal fallback validation to prevent script failure
    validate_dataset_name() { [[ -n "$1" ]]; }
    validate_path() { [[ -n "$1" ]]; }
    validate_positive_integer() { [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]; }
    validate_non_negative_integer() { [[ "$1" =~ ^[0-9]+$ ]]; }
    validate_integer_range() { validate_non_negative_integer "$1" && [[ "$1" -ge "$2" ]] && [[ "$1" -le "$3" ]]; }
    validate_url() { [[ "$1" =~ ^https?:// ]]; }
    validate_host() { [[ -n "$1" ]]; }
    validate_boolean() { [[ "$1" == "yes" || "$1" == "no" ]]; }
    validate_choice() { local v="$1"; shift 2; for c in "$@"; do [[ "$v" == "$c" ]] && return 0; done; return 1; }
fi

# ---------------------------------------
# CORE ZFS SETTINGS
# ---------------------------------------

# Mount point base (where ZFS datasets are mounted)
MOUNT_POINT="/mnt"                         # Base mount point for ZFS datasets

# Dry run setting (applies to both scripts)
DRY_RUN="no"                              # Set to "yes" for testing, "no" for actual execution

# Primary ZFS pools and datasets
SOURCE_POOL="tank"                        # ZFS pool containing source datasets
SOURCE_DATASET="data"                     # Primary dataset to snapshot/replicate

# ---------------------------------------
# AUTO DATASET CONVERTER SETTINGS
# ---------------------------------------

# Docker Container Processing
SHOULD_PROCESS_CONTAINERS="no"            # Set to "yes" to process Docker appdata
SOURCE_POOL_APPDATA="tank"                # ZFS pool containing Docker appdata
SOURCE_DATASET_APPDATA="appdata"          # Dataset name for Docker appdata

# Virtual Machine Processing
SHOULD_PROCESS_VMS="no"                   # Set to "yes" to process VM vdisks
SOURCE_POOL_VMS="tank"                    # ZFS pool containing VM domains
SOURCE_DATASET_VMS="domains"              # Dataset name for VM domains
# VM shutdown timeout: 90 seconds provides enough time for graceful OS shutdown
# while preventing indefinite waits. Typical OS shutdown: 30-60s. Allows buffer
# for slow services. Adjust higher for systems with many services or slow storage.
VM_FORCE_SHUTDOWN_WAIT="90"               # Seconds to wait before force stopping VM

# Additional User-Defined Datasets
# Add datasets in format "pool/dataset", one per line
SOURCE_DATASETS_ARRAY=(
    # Example: "tank/data"
    # Example: "backup/important"
)

# Dataset Converter Options
CLEANUP_TEMP_DIRS="yes"                   # Remove temporary directories after successful conversion
REPLACE_SPACES="no"                       # Replace spaces in dataset names with underscores
# Buffer zone: 11% extra space requirement provides safety margin for:
# - ZFS metadata overhead (~1-2%)
# - Temporary snapshot/clone overhead (~3-5%)
# - File system metadata growth (~2-3%)
# - Safety buffer for unexpected growth (~3-5%)
# Total ~11% ensures conversion completes without running out of space.
# Reduce to 5% for space-constrained systems (higher risk).
BUFFER_ZONE=11                           # Percentage of extra space required before conversion

# ---------------------------------------
# SNAPSHOT & REPLICATION SETTINGS  
# ---------------------------------------

# Dataset Selection
SOURCE_DATASET_AUTO_SELECT="no"          # "yes" to auto-select all datasets in pool
SOURCE_DATASET_AUTO_SELECT_EXCLUDE_PREFIX="backup_"  # Exclude datasets with this prefix
SOURCE_DATASET_AUTO_SELECT_EXCLUDES=(
    # List dataset names to exclude from auto-selection
    "temp"
    "scratch"
)

# Snapshot Settings
AUTO_SNAPSHOTS="yes"                      # Enable automatic snapshots via Sanoid
SNAPSHOT_HOURS="0"                        # Number of hourly snapshots to retain
SNAPSHOT_DAYS="7"                         # Number of daily snapshots to retain  
SNAPSHOT_WEEKS="4"                        # Number of weekly snapshots to retain
SNAPSHOT_MONTHS="3"                       # Number of monthly snapshots to retain
SNAPSHOT_YEARS="0"                        # Number of yearly snapshots to retain

# Replication Method
REPLICATION="zfs"                         # "zfs", "rsync", or "none"

# ZFS Replication Settings (only needed if REPLICATION="zfs")
DESTINATION_POOL="backup"                 # Destination ZFS pool
PARENT_DESTINATION_DATASET="replicas"     # Parent dataset for replicated data
SYNCOID_MODE="strict-mirror"              # "strict-mirror" or "basic"

# Rsync Replication Settings (only needed if REPLICATION="rsync")
PARENT_DESTINATION_FOLDER="/backup"       # Parent directory for rsync backups
RSYNC_TYPE="incremental"                  # "incremental" or "mirror"

# Remote Server Configuration
DESTINATION_REMOTE="no"                   # "yes" for remote replication, "no" for local
REMOTE_USER="root"                        # Username for remote server
REMOTE_SERVER="192.168.1.100"            # Remote server hostname or IP
# SSH Host Key Fingerprint for security (optional but recommended)
# Get fingerprint with: ssh-keyscan -H SERVER | ssh-keygen -lf -
# Example: "SHA256:abcd1234efgh5678ijkl9012mnop3456qrst7890uvwx1234yzab5678"
# Leave empty to skip verification (less secure)
REMOTE_SSH_FINGERPRINT=""                 # SSH host key fingerprint for REMOTE_SERVER

# ---------------------------------------
# SCHEDULING SETTINGS
# ---------------------------------------

# Enable automatic cron job setup
ENABLE_SCHEDULING="no"                     # Set to "yes" to automatically setup cron jobs

# Schedule for auto dataset converter (cron format: minute hour day month weekday)
# Examples: "0 2 * * *" = daily at 2 AM, "0 */6 * * *" = every 6 hours
DATASET_CONVERTER_SCHEDULE="0 2 * * *"    # Daily at 2 AM

# Schedule for snapshot & replication (cron format)
REPLICATION_SCHEDULE="0 3 * * *"          # Daily at 3 AM (after dataset conversion)

# ---------------------------------------
# NOTIFICATION & LOGGING SETTINGS
# ---------------------------------------

# Gotify Configuration
GOTIFY_SERVER_URL="http://localhost:8080"  # Your Gotify server URL (no trailing slash)
GOTIFY_APP_TOKEN=""                        # Your Gotify application token
notification_type="all"                    # "all" for both success & failure, "error" for only failure, "none" for no notifications

# Logging Configuration
LOG_FILE="/var/log/zfs-scripts.log"       # Path to log file
# Log max size: 10M chosen to balance between:
# - Sufficient history for troubleshooting (typical daily run ~100-500KB)
# - Manageable file size for viewing/parsing
# - Preventing runaway disk usage (~50M max with 5 rotations)
# Increase to 50M for verbose logging or frequent runs.
LOG_MAX_SIZE="10M"                         # Max log file size before rotation (e.g., 10M, 100K)
# Log rotation count: 5 files preserves ~5-15 days of history (depending on activity)
# while limiting disk usage to ~50MB. Increase for longer retention.
LOG_MAX_FILES=5                            # Number of rotated log files to keep

# ---------------------------------------
# SYSTEM PATHS & DEPENDENCIES
# ---------------------------------------

# Sanoid Configuration
SANOID_CONFIG_DIR="/etc/sanoid/"          # Directory for Sanoid configuration files
SANOID_BINARY="/usr/sbin/sanoid"          # Path to Sanoid binary
SYNCOID_BINARY="/usr/sbin/syncoid"        # Path to Syncoid binary

# ---------------------------------------
# INTERNAL VARIABLES (DO NOT MODIFY)
# ---------------------------------------

# These are set dynamically by the scripts
stopped_containers=()
stopped_vms=()
converted_folders=()

#######################################
# Validate configuration
#
# Performs comprehensive validation of all configuration values using
# the validation library. Checks include:
# - Dataset name format validation
# - Path validation with traversal protection
# - Integer range validation
# - URL and host validation
# - Boolean value validation
# - Choice validation
#
# Globals:
#   All configuration variables
# Arguments:
#   None
# Returns:
#   0 if all valid, number of errors otherwise
# Outputs:
#   Error messages to stderr for each validation failure
#######################################
validate_config() {
    local errors=0

    echo "Validating ZFS configuration..." >&2

    # ---------------------------------------
    # Core Settings Validation
    # ---------------------------------------

    # Validate pool and dataset names
    if ! validate_dataset_name "$SOURCE_POOL" 2>/dev/null; then
        echo "ERROR: Invalid SOURCE_POOL: $SOURCE_POOL" >&2
        errors=$((errors + 1))
    fi

    if ! validate_dataset_name "$SOURCE_DATASET" 2>/dev/null; then
        echo "ERROR: Invalid SOURCE_DATASET: $SOURCE_DATASET" >&2
        errors=$((errors + 1))
    fi

    # Validate paths
    if ! validate_path "$MOUNT_POINT" 2>/dev/null; then
        echo "ERROR: Invalid MOUNT_POINT: $MOUNT_POINT" >&2
        errors=$((errors + 1))
    fi

    # Check mount point exists
    if [[ ! -d "$MOUNT_POINT" ]]; then
        echo "ERROR: Mount point does not exist: $MOUNT_POINT" >&2
        errors=$((errors + 1))
    fi

    # Validate DRY_RUN setting
    if ! validate_boolean "$DRY_RUN" "DRY_RUN" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    # ---------------------------------------
    # Container Processing Validation
    # ---------------------------------------

    if ! validate_boolean "$SHOULD_PROCESS_CONTAINERS" "SHOULD_PROCESS_CONTAINERS" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if [[ "$SHOULD_PROCESS_CONTAINERS" == "yes" ]]; then
        if ! validate_dataset_name "$SOURCE_POOL_APPDATA" 2>/dev/null; then
            echo "ERROR: Invalid SOURCE_POOL_APPDATA: $SOURCE_POOL_APPDATA" >&2
            errors=$((errors + 1))
        fi
        if ! validate_dataset_name "$SOURCE_DATASET_APPDATA" 2>/dev/null; then
            echo "ERROR: Invalid SOURCE_DATASET_APPDATA: $SOURCE_DATASET_APPDATA" >&2
            errors=$((errors + 1))
        fi
    fi

    # ---------------------------------------
    # VM Processing Validation
    # ---------------------------------------

    if ! validate_boolean "$SHOULD_PROCESS_VMS" "SHOULD_PROCESS_VMS" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if [[ "$SHOULD_PROCESS_VMS" == "yes" ]]; then
        if ! validate_dataset_name "$SOURCE_POOL_VMS" 2>/dev/null; then
            echo "ERROR: Invalid SOURCE_POOL_VMS: $SOURCE_POOL_VMS" >&2
            errors=$((errors + 1))
        fi
        if ! validate_dataset_name "$SOURCE_DATASET_VMS" 2>/dev/null; then
            echo "ERROR: Invalid SOURCE_DATASET_VMS: $SOURCE_DATASET_VMS" >&2
            errors=$((errors + 1))
        fi
        if ! validate_positive_integer "$VM_FORCE_SHUTDOWN_WAIT" "VM_FORCE_SHUTDOWN_WAIT" 2>/dev/null; then
            errors=$((errors + 1))
        fi
    fi

    # ---------------------------------------
    # Dataset Array Validation
    # ---------------------------------------

    for dataset in "${SOURCE_DATASETS_ARRAY[@]}"; do
        if [[ -n "$dataset" ]]; then
            if ! validate_dataset_name "$dataset" 2>/dev/null; then
                echo "ERROR: Invalid dataset in SOURCE_DATASETS_ARRAY: $dataset" >&2
                errors=$((errors + 1))
            fi
        fi
    done

    # ---------------------------------------
    # Dataset Converter Options Validation
    # ---------------------------------------

    if ! validate_boolean "$CLEANUP_TEMP_DIRS" "CLEANUP_TEMP_DIRS" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if ! validate_boolean "$REPLACE_SPACES" "REPLACE_SPACES" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if ! validate_integer_range "$BUFFER_ZONE" "0" "100" "BUFFER_ZONE" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    # ---------------------------------------
    # Snapshot Settings Validation
    # ---------------------------------------

    if ! validate_boolean "$SOURCE_DATASET_AUTO_SELECT" "SOURCE_DATASET_AUTO_SELECT" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if ! validate_boolean "$AUTO_SNAPSHOTS" "AUTO_SNAPSHOTS" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if ! validate_non_negative_integer "$SNAPSHOT_HOURS" "SNAPSHOT_HOURS" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if ! validate_non_negative_integer "$SNAPSHOT_DAYS" "SNAPSHOT_DAYS" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if ! validate_non_negative_integer "$SNAPSHOT_WEEKS" "SNAPSHOT_WEEKS" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if ! validate_non_negative_integer "$SNAPSHOT_MONTHS" "SNAPSHOT_MONTHS" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if ! validate_non_negative_integer "$SNAPSHOT_YEARS" "SNAPSHOT_YEARS" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    # ---------------------------------------
    # Replication Settings Validation
    # ---------------------------------------

    if ! validate_choice "$REPLICATION" "REPLICATION" "zfs" "rsync" "none" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    # ZFS replication settings
    if [[ "$REPLICATION" == "zfs" ]]; then
        if ! validate_dataset_name "$DESTINATION_POOL" 2>/dev/null; then
            echo "ERROR: Invalid DESTINATION_POOL: $DESTINATION_POOL" >&2
            errors=$((errors + 1))
        fi
        if ! validate_dataset_name "$PARENT_DESTINATION_DATASET" 2>/dev/null; then
            echo "ERROR: Invalid PARENT_DESTINATION_DATASET: $PARENT_DESTINATION_DATASET" >&2
            errors=$((errors + 1))
        fi
        if ! validate_choice "$SYNCOID_MODE" "SYNCOID_MODE" "strict-mirror" "basic" 2>/dev/null; then
            errors=$((errors + 1))
        fi
    fi

    # Rsync replication settings
    if [[ "$REPLICATION" == "rsync" ]]; then
        if ! validate_path "$PARENT_DESTINATION_FOLDER" 2>/dev/null; then
            echo "ERROR: Invalid PARENT_DESTINATION_FOLDER: $PARENT_DESTINATION_FOLDER" >&2
            errors=$((errors + 1))
        fi
        if ! validate_choice "$RSYNC_TYPE" "RSYNC_TYPE" "incremental" "mirror" 2>/dev/null; then
            errors=$((errors + 1))
        fi
    fi

    # Remote server validation
    if ! validate_boolean "$DESTINATION_REMOTE" "DESTINATION_REMOTE" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if [[ "$DESTINATION_REMOTE" == "yes" ]]; then
        if [[ -z "$REMOTE_USER" ]]; then
            echo "ERROR: REMOTE_USER must be set when remote destination is enabled" >&2
            errors=$((errors + 1))
        fi

        if [[ -z "$REMOTE_SERVER" ]]; then
            echo "ERROR: REMOTE_SERVER must be set when remote destination is enabled" >&2
            errors=$((errors + 1))
        elif ! validate_host "$REMOTE_SERVER" 2>/dev/null; then
            errors=$((errors + 1))
        fi
    fi

    # ---------------------------------------
    # Notification Settings Validation
    # ---------------------------------------

    if ! validate_choice "$notification_type" "notification_type" "all" "error" "none" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    # Validate Gotify settings if notifications enabled
    if [[ "$notification_type" != "none" ]]; then
        if [[ -z "$GOTIFY_SERVER_URL" ]]; then
            echo "ERROR: GOTIFY_SERVER_URL must be set when notifications are enabled" >&2
            errors=$((errors + 1))
        elif ! validate_url "$GOTIFY_SERVER_URL" 2>/dev/null; then
            errors=$((errors + 1))
        fi

        if [[ -z "$GOTIFY_APP_TOKEN" ]]; then
            echo "ERROR: GOTIFY_APP_TOKEN must be set when notifications are enabled" >&2
            errors=$((errors + 1))
        fi
    fi

    # ---------------------------------------
    # Logging Settings Validation
    # ---------------------------------------

    if ! validate_path "$LOG_FILE" 2>/dev/null; then
        echo "ERROR: Invalid LOG_FILE path: $LOG_FILE" >&2
        errors=$((errors + 1))
    fi

    # Check log directory exists and is writable
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if ! validate_path "$log_dir" 2>/dev/null; then
        echo "ERROR: Invalid log directory path: $log_dir" >&2
        errors=$((errors + 1))
    elif [[ ! -d "$log_dir" ]]; then
        echo "ERROR: Log directory does not exist: $log_dir" >&2
        errors=$((errors + 1))
    elif [[ ! -w "$log_dir" ]]; then
        echo "ERROR: Log directory is not writable: $log_dir" >&2
        errors=$((errors + 1))
    fi

    # Validate LOG_MAX_FILES
    if ! validate_positive_integer "$LOG_MAX_FILES" "LOG_MAX_FILES" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    # ---------------------------------------
    # Scheduling Settings Validation
    # ---------------------------------------

    if ! validate_boolean "$ENABLE_SCHEDULING" "ENABLE_SCHEDULING" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    # ---------------------------------------
    # Summary
    # ---------------------------------------

    if [[ $errors -gt 0 ]]; then
        echo "ERROR: Configuration validation failed with $errors error(s)" >&2
        return 1
    else
        echo "Configuration validation passed successfully" >&2
        return 0
    fi
}

#######################################
# Validate cron schedule format
# Arguments:
#   $1 - Cron schedule string
# Returns:
#   0 on valid, 1 on invalid
#######################################
validate_cron_schedule() {
    local schedule="$1"

    # Basic validation: should have 5 fields (minute hour day month weekday)
    local field_count
    field_count=$(echo "$schedule" | awk '{print NF}')
    if [[ "$field_count" -ne 5 ]]; then
        echo "ERROR: Cron schedule must have 5 fields, got $field_count" >&2
        return 1
    fi

    # Each field should only contain valid cron characters
    if [[ ! "$schedule" =~ ^[0-9*/,-\ ]+$ ]]; then
        echo "ERROR: Cron schedule contains invalid characters" >&2
        return 1
    fi

    return 0
}

#######################################
# Safely remove cron entries for specific scripts
# Arguments:
#   $1 - First script path
#   $2 - Second script path
#   $3 - Temp crontab file
# Returns:
#   0 on success, 1 on error
#######################################
remove_cron_entries() {
    local script1="$1"
    local script2="$2"
    local temp_crontab="$3"

    # Validate inputs
    if [[ -z "$script1" || -z "$script2" || -z "$temp_crontab" ]]; then
        echo "ERROR: remove_cron_entries: missing required parameters" >&2
        return 1
    fi

    if [[ ! -f "$temp_crontab" ]]; then
        echo "ERROR: Crontab file does not exist: $temp_crontab" >&2
        return 1
    fi

    # Use fixed string matching with separate -e options (safe alternative to pipe)
    if ! grep -vF -e "$script1" -e "$script2" "$temp_crontab" > "${temp_crontab}.new" 2>/dev/null; then
        # grep -v returns 1 if no lines matched (all lines filtered out)
        # Create empty file in this case
        touch "${temp_crontab}.new"
    fi

    # Verify the new file was created
    if [[ ! -f "${temp_crontab}.new" ]]; then
        echo "ERROR: Failed to create new crontab file" >&2
        return 1
    fi

    return 0
}

# Function to setup cron jobs
setup_cron_jobs() {
    if [[ "$ENABLE_SCHEDULING" != "yes" ]]; then
        echo "Scheduling disabled - skipping cron job setup"
        return 0
    fi

    # Validate cron schedules first
    if ! validate_cron_schedule "$DATASET_CONVERTER_SCHEDULE"; then
        echo "ERROR: Invalid cron schedule for dataset converter: $DATASET_CONVERTER_SCHEDULE" >&2
        return 1
    fi

    if ! validate_cron_schedule "$REPLICATION_SCHEDULE"; then
        echo "ERROR: Invalid cron schedule for replication: $REPLICATION_SCHEDULE" >&2
        return 1
    fi

    # Get the directory where the config file is located
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dataset_script="$script_dir/zfs-auto-datasets-ubuntu.sh"
    local replication_script="$script_dir/zfs-replications-ubuntu.sh"

    # Check if scripts exist
    if [[ ! -f "$dataset_script" ]]; then
        echo "ERROR: Dataset converter script not found: $dataset_script" >&2
        return 1
    fi

    if [[ ! -f "$replication_script" ]]; then
        echo "ERROR: Replication script not found: $replication_script" >&2
        return 1
    fi

    # Make scripts executable
    chmod +x "$dataset_script" "$replication_script"

    # Create temporary crontab file
    local temp_crontab=$(mktemp)

    # Get existing crontab (ignore errors if no crontab exists)
    crontab -l 2>/dev/null > "$temp_crontab" || true

    # Remove any existing entries for these scripts using safe function
    if ! remove_cron_entries "$dataset_script" "$replication_script" "$temp_crontab"; then
        echo "ERROR: Failed to remove existing cron entries" >&2
        rm -f "$temp_crontab" "${temp_crontab}.new"
        return 1
    fi
    mv "${temp_crontab}.new" "$temp_crontab"

    # Add new cron entries with properly escaped paths
    echo "# ZFS Auto Dataset Converter - Generated by zfs-config.sh" >> "$temp_crontab"
    echo "$DATASET_CONVERTER_SCHEDULE $(printf '%q' "$dataset_script") >/dev/null 2>&1" >> "$temp_crontab"
    echo "" >> "$temp_crontab"
    echo "# ZFS Snapshot & Replication - Generated by zfs-config.sh" >> "$temp_crontab"
    echo "$REPLICATION_SCHEDULE $(printf '%q' "$replication_script") >/dev/null 2>&1" >> "$temp_crontab"
    echo "" >> "$temp_crontab"

    # Install the new crontab
    if crontab "$temp_crontab"; then
        echo "SUCCESS: Cron jobs installed successfully"
        echo "  Dataset Converter: $DATASET_CONVERTER_SCHEDULE"
        echo "  Snapshot & Replication: $REPLICATION_SCHEDULE"
        echo ""
        echo "View scheduled jobs with: crontab -l"
        echo "Remove jobs with: crontab -e"
    else
        echo "ERROR: Failed to install cron jobs" >&2
        rm -f "$temp_crontab"
        return 1
    fi

    # Clean up
    rm -f "$temp_crontab" "${temp_crontab}.new"
}

# Function to remove cron jobs
remove_cron_jobs() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dataset_script="$script_dir/zfs-auto-datasets-ubuntu.sh"
    local replication_script="$script_dir/zfs-replications-ubuntu.sh"

    # Create temporary crontab file
    local temp_crontab=$(mktemp)

    # Get existing crontab (ignore errors if no crontab exists)
    if crontab -l 2>/dev/null > "$temp_crontab"; then
        # Remove entries for these scripts using safe function
        if ! remove_cron_entries "$dataset_script" "$replication_script" "$temp_crontab"; then
            echo "ERROR: Failed to remove cron entries" >&2
            rm -f "$temp_crontab" "${temp_crontab}.new"
            return 1
        fi

        # Also remove comment lines (safe, fixed strings)
        if ! grep -vF -e "# ZFS Auto Dataset Converter" -e "# ZFS Snapshot & Replication" "${temp_crontab}.new" > "${temp_crontab}.filtered" 2>/dev/null; then
            touch "${temp_crontab}.filtered"
        fi
        mv "${temp_crontab}.filtered" "${temp_crontab}.new"

        # Remove empty lines at the end
        sed -i '/^$/N;/^\n$/d' "${temp_crontab}.new" 2>/dev/null || true

        # Install the cleaned crontab
        if crontab "${temp_crontab}.new"; then
            echo "SUCCESS: ZFS cron jobs removed"
        else
            echo "ERROR: Failed to update crontab" >&2
            rm -f "$temp_crontab" "${temp_crontab}.new"
            return 1
        fi

        rm -f "${temp_crontab}.new"
    else
        echo "No existing crontab found"
    fi

    # Clean up
    rm -f "$temp_crontab"
}

# Function to show current cron schedule
show_cron_schedule() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dataset_script="$script_dir/zfs-auto-datasets-ubuntu.sh"
    local replication_script="$script_dir/zfs-replications-ubuntu.sh"
    
    echo "Current ZFS script schedule:"
    echo "=========================="
    
    if crontab -l 2>/dev/null | grep -q "$dataset_script\|$replication_script"; then
        echo "Scheduled jobs found:"
        crontab -l 2>/dev/null | grep -A1 -B1 "$dataset_script\|$replication_script"
    else
        echo "No ZFS scripts currently scheduled"
        if [[ "$ENABLE_SCHEDULING" == "yes" ]]; then
            echo ""
            echo "Scheduling is enabled in config but not installed."
            echo "Run: source zfs-config.sh && setup_cron_jobs"
        fi
    fi
    
    echo ""
    echo "Current configuration:"
    echo "  ENABLE_SCHEDULING: $ENABLE_SCHEDULING"
    echo "  Dataset Converter: $DATASET_CONVERTER_SCHEDULE"
    echo "  Snapshot & Replication: $REPLICATION_SCHEDULE"
}

# Export all configuration variables
export GOTIFY_SERVER_URL GOTIFY_APP_TOKEN notification_type
export LOG_FILE LOG_MAX_SIZE LOG_MAX_FILES
export MOUNT_POINT DRY_RUN
export SHOULD_PROCESS_CONTAINERS SOURCE_POOL_APPDATA SOURCE_DATASET_APPDATA
export SHOULD_PROCESS_VMS SOURCE_POOL_VMS SOURCE_DATASET_VMS VM_FORCE_SHUTDOWN_WAIT
export SOURCE_DATASETS_ARRAY CLEANUP_TEMP_DIRS REPLACE_SPACES BUFFER_ZONE
export SOURCE_POOL SOURCE_DATASET SOURCE_DATASET_AUTO_SELECT 
export SOURCE_DATASET_AUTO_SELECT_EXCLUDE_PREFIX SOURCE_DATASET_AUTO_SELECT_EXCLUDES
export AUTO_SNAPSHOTS SNAPSHOT_HOURS SNAPSHOT_DAYS SNAPSHOT_WEEKS SNAPSHOT_MONTHS SNAPSHOT_YEARS
export DESTINATION_REMOTE REMOTE_USER REMOTE_SERVER REMOTE_SSH_FINGERPRINT REPLICATION
export DESTINATION_POOL PARENT_DESTINATION_DATASET SYNCOID_MODE
export PARENT_DESTINATION_FOLDER RSYNC_TYPE
export SANOID_CONFIG_DIR SANOID_BINARY SYNCOID_BINARY
export ENABLE_SCHEDULING DATASET_CONVERTER_SCHEDULE REPLICATION_SCHEDULE
export stopped_containers stopped_vms converted_folders

# Auto-setup cron jobs if enabled and this script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-setup}" in
        "setup")
            echo "Setting up ZFS script scheduling..."
            setup_cron_jobs
            ;;
        "remove")
            echo "Removing ZFS script scheduling..."
            remove_cron_jobs
            ;;
        "show"|"status")
            show_cron_schedule
            ;;
        "help"|"-h"|"--help")
            echo "ZFS Config Scheduling Management"
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  setup    - Install cron jobs (default)"
            echo "  remove   - Remove cron jobs"
            echo "  show     - Show current schedule"
            echo "  help     - Show this help"
            echo ""
            echo "Before running setup, edit this file and set:"
            echo "  ENABLE_SCHEDULING=\"yes\""
            echo "  Configure your desired schedules"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
fi